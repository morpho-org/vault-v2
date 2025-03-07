// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {ERC20, IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Math} from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {Pending, IMarket, IVaultV2} from "./interfaces/IVaultV2.sol";
import {IIRM} from "./interfaces/IIRM.sol";
import {IAllocator} from "./interfaces/IAllocator.sol";
import {ProtocolFee, IVaultV2Factory} from "./interfaces/IVaultV2Factory.sol";

import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {ConstantsLib} from "./libraries/ConstantsLib.sol";

contract VaultV2 is ERC20, IVaultV2 {
    using Math for uint256;

    /* CONSTANT */

    uint64 public constant TIMELOCKS_TIMELOCK = 2 weeks;
    address private constant CHANGE_OWNER_TIMELOCK_KEY = address(uint160(uint256(keccak256("change owner"))));
    address private constant CHANGE_CURATOR_TIMELOCK_KEY = address(uint160(uint256(keccak256("change curator"))));
    address private constant CHANGE_GUARDIAN_TIMELOCK_KEY = address(uint160(uint256(keccak256("change guardian"))));
    address private constant CHANGE_FEE_TIMELOCK_KEY = address(uint160(uint256(keccak256("change fee"))));
    address private constant CHANGE_FEE_RECIPIENT_TIMELOCK_KEY = address(uint160(uint256(keccak256("change fee recipient"))));
    address private constant CHANGE_ALLOCATOR_TIMELOCK_KEY = address(uint160(uint256(keccak256("change allocator"))));
    address private constant UNZERO_CAP_TIMELOCK_KEY = address(uint160(uint256(keccak256("unzero cap"))));
    address private constant INCREASE_CAP_TIMELOCK_KEY = address(uint160(uint256(keccak256("increase cap"))));
    address private constant CHANGE_IRM_TIMELOCK_KEY = address(uint160(uint256(keccak256("change irm"))));

    /* IMMUTABLE */

    address public immutable factory;
    IERC20 public immutable asset;

    /* TRANSIENT */

    // TODO: make this actually transient.
    bool public unlocked;

    /* STORAGE */

    // Note that each role could be a smart contract: the owner, curator and allocator.
    // This way, roles are modularized, and notably restricting their capabilities could be done on top.
    address public owner;
    address public curator;
    address public allocator;
    address public guardian;

    uint160 public fee;
    address public feeRecipient;

    address public irm;
    uint256 public lastUpdate;
    uint256 public totalAssets;

    IMarket[] public markets;
    mapping(address => uint160) public cap;

    mapping(bytes32 => Pending) public pending;
    mapping(address => uint64) public timelock;

    /* CONSTRUCTOR */

    constructor(
        address _factory,
        address _owner,
        address _curator,
        address _allocator,
        address _asset,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        factory = _factory;
        asset = IERC20(_asset);
        owner = _owner;
        curator = _curator;
        allocator = _allocator;
        lastUpdate = block.timestamp;
        // The vault starts with no IRM, no markets and no assets. To be configured afterwards.
    }

    /* AUTHORIZED MULTICALL */

    function multicall(bytes[] calldata bundle) external {
        IAllocator(allocator).authorizeMulticall(msg.sender, bundle);

        // The allocator is responsible for making sure that bundles cannot reenter.
        unlocked = true;

        for (uint256 i = 0; i < bundle.length; i++) {
            // Note: no need to check that address(this) has code.
            (bool success, bytes memory data) = address(this).delegatecall(bundle[i]);
            // Bubble up the revert message from the delegatecall
            if (!success) {
                assembly {
                    revert(add(data, 32), mload(data))
                }
            }
        }

        unlocked = false;
    }

    /* SUBMIT ACTIONS */

    function submit(bytes32 id, address key, uint160 value) external {
        if (id == "owner") {
            require(msg.sender == owner, ErrorsLib.Unauthorized());
            pending[id].value = value;
            pending[id].validAt = uint64(block.timestamp) + timelock[CHANGE_OWNER_TIMELOCK_KEY];
        } else if (id == "curator") {
            require(msg.sender == owner, ErrorsLib.Unauthorized());
            pending[id].value = value;
            pending[id].validAt = uint64(block.timestamp) + timelock[CHANGE_CURATOR_TIMELOCK_KEY];
        } else if (id == "guardian") {
            require(msg.sender == owner, ErrorsLib.Unauthorized());
            pending[id].value = value;
            pending[id].validAt = uint64(block.timestamp) + timelock[CHANGE_GUARDIAN_TIMELOCK_KEY];
        } else if (id == "fee") {
            require(msg.sender == owner, ErrorsLib.Unauthorized());
            pending[id].value = value;
            pending[id].validAt = uint64(block.timestamp) + timelock[CHANGE_GUARDIAN_TIMELOCK_KEY];
        } else if (id == "fee recipient") {
            require(msg.sender == owner, ErrorsLib.Unauthorized());
            pending[id].value = value;
            pending[id].validAt = uint64(block.timestamp) + timelock[CHANGE_GUARDIAN_TIMELOCK_KEY];
        } else if (id == "allocator") {
            require(msg.sender == curator, ErrorsLib.Unauthorized());
            pending[id].value = value;
            pending[id].validAt = uint64(block.timestamp) + timelock[CHANGE_ALLOCATOR_TIMELOCK_KEY];
        } else if (id == "irm") {
            require(msg.sender == curator, ErrorsLib.Unauthorized());
            pending[id].value = value;
            pending[id].validAt = uint64(block.timestamp) + timelock[CHANGE_IRM_TIMELOCK_KEY];
        } else if (keccak256(abi.encode("timelock", key)) == id) {
            require(msg.sender == owner, ErrorsLib.Unauthorized());
            require(uint64(value) <= TIMELOCKS_TIMELOCK, "Timelock too long");
            pending[id].value = value;
            pending[id].validAt = uint64(block.timestamp) + TIMELOCKS_TIMELOCK;
        } else if (keccak256(abi.encode("cap", key)) == id) {
            require(msg.sender == curator, ErrorsLib.Unauthorized());
            require(value != cap[key], "Cap unchanged");
            if (cap[key] == 0) {
                pending[id].validAt = uint64(block.timestamp) + timelock[UNZERO_CAP_TIMELOCK_KEY];
            } else if (value > cap[key]) {
                pending[id].validAt = uint64(block.timestamp) + timelock[INCREASE_CAP_TIMELOCK_KEY];
            } else {
                pending[id].validAt = uint64(block.timestamp);
            }
            pending[id].value = value;
        } else {
            revert("Invalid key");
        }
    }

    /* ACCEPT ACTIONS */

    function accept(bytes32 id, address key) external {
        require(pending[id].validAt != 0, "not pending");
        require(block.timestamp >= pending[id].validAt, "not valid");

        if (id == "owner") {
            owner = address(pending[id].value);
        } else if (id == "curator") {
            curator = address(pending[id].value);
        } else if (id == "guardian") {
            guardian = address(pending[id].value);
        } else if (id == "allocator") {
            allocator = address(pending[id].value);
        } else if (id == "irm") {
            irm = address(pending[id].value);
        } else if (keccak256(abi.encode("timelock", key)) == id) {
            timelock[key] = uint64(pending[id].value);
        } else if (keccak256(abi.encode("cap", key)) == id) {
            cap[key] = uint160(pending[id].value);
            markets.push(IMarket(key));
        } else {
            revert("Invalid key");
        }

        delete pending[id];
    }

    /* REVOKE ACTION */

    function revoke(bytes32 id) external {
        require(pending[id].validAt != 0, "not pending");

        if (id == "owner") {
            require(msg.sender == owner || msg.sender == guardian, ErrorsLib.Unauthorized());
        } else if (id == "curator") {
            require(msg.sender == owner || msg.sender == guardian, ErrorsLib.Unauthorized());
        } else if (id == "guardian") {
            require(msg.sender == owner || msg.sender == guardian, ErrorsLib.Unauthorized());
        } else if (keccak256(abi.encode("timelock", address(pending[id].value))) == id) {
            require(msg.sender == owner || msg.sender == guardian, ErrorsLib.Unauthorized());
        } else if (id == "allocator") {
            require(msg.sender == curator || msg.sender == owner || msg.sender == guardian, ErrorsLib.Unauthorized());
        } else if (id == "irm") {
            require(msg.sender == curator || msg.sender == owner || msg.sender == guardian, ErrorsLib.Unauthorized());
        } else if (keccak256(abi.encode("cap", address(pending[id].value))) == id) {
            require(msg.sender == curator || msg.sender == owner || msg.sender == guardian, ErrorsLib.Unauthorized());
        } else {
            revert("Invalid id");
        }

        delete pending[id];
    }

    /* ALLOCATOR ACTIONS */

    // Note how the discrepancy between transferred amount and increase in market.totalAssets() is handled:
    // it is not reflected in vault.totalAssets() but will have an impact on interest.
    function reallocateFromIdle(uint256 marketIndex, uint256 amount) external {
        require(unlocked, ErrorsLib.Locked());
        IMarket market = markets[marketIndex];
        // Interest accrual can make the supplied amount go over the cap.
        require(amount + market.balanceOf(address(this)) <= cap[address(market)], ErrorsLib.CapExceeded());
        asset.approve(address(market), amount);
        market.deposit(amount, address(this));
    }

    // Note how the discrepancy between transferred amount and decrease in market.totalAssets() is handled:
    // it is not reflected in vault.totalAssets() but will have an impact on interest.
    function reallocateToIdle(uint256 marketIndex, uint256 amount) external {
        require(unlocked, ErrorsLib.Locked());
        IMarket market = markets[marketIndex];
        market.withdraw(amount, address(this), address(this));
    }

    /* EXCHANGE RATE */

    // Vault managers would not use this function when taking full custody.
    // Note that donations would be smoothed, which is a nice feature to incentivize the vault directly.
    function realAssets() external view returns (uint256 aum) {
        aum = asset.balanceOf(address(this));
        for (uint256 i; i < markets.length; i++) {
            aum += markets[i].convertToAssets(markets[i].balanceOf(address(this)));
        }
    }

    function accrueInterest() public {
        (uint256 feeShares, uint256 newTotalAssets) = accruedFeeShares();

        totalAssets = newTotalAssets;

        if (feeShares != 0) {
            ProtocolFee memory protocolFee = IVaultV2Factory(factory).protocolFee();
            // Todo: verify that this computation can't return something greater than feeShares.
            uint256 protocolFeeShares = feeShares.mulDiv(protocolFee.fee, ConstantsLib.WAD, Math.Rounding.Ceil);
            _mint(protocolFee.feeRecipient, protocolFeeShares);
            _mint(feeRecipient, feeShares - protocolFeeShares);
        }

        lastUpdate = block.timestamp;
    }

    function accruedFeeShares() public view returns (uint256 feeShares, uint256 newTotalAssets) {
        uint256 elapsed = block.timestamp - lastUpdate;
        // Note that interest could be negative, but this is not always incentive compatible: users would want to leave.
        // But keeping this possible still, as it can make sense in the custody case when withdrawals are disabled.
        // Note that interestPerSecond should probably be bounded to give guarantees that it cannot rug users instantly.
        // Note that irm.interestPerSecond() reverts if the vault is not initialized and has irm == address(0).
        int256 interest = IIRM(irm).interestPerSecond() * int256(elapsed);
        int256 rawTotalAssets = int256(totalAssets) + interest;
        newTotalAssets = rawTotalAssets >= 0 ? uint256(rawTotalAssets) : 0;
        if (interest > 0 && fee != 0) {
            // It is acknowledged that `feeAssets` may be rounded down to 0 if `totalInterest * fee < WAD`.
            uint256 feeAssets = uint256(interest).mulDiv(fee, ConstantsLib.WAD, Math.Rounding.Floor);
            // The fee assets is subtracted from the total assets in this calculation to compensate for the fact
            // that total assets is already increased by the total interest (including the fee assets).
            feeShares = feeAssets.mulDiv(totalSupply() + 1, totalAssets + 1 - feeAssets, Math.Rounding.Floor);
        }
    }

    function convertToShares(uint256 assets) external view returns (uint256) {
        return convertToShares(assets, Math.Rounding.Floor);
    }

    // TODO: extract virtual shares and assets (= 1).
    function convertToShares(uint256 assets, Math.Rounding rounding) internal view returns (uint256 shares) {
        shares = assets.mulDiv(totalSupply() + 1, totalAssets + 1, rounding);
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        return convertToAssets(shares, Math.Rounding.Floor);
    }

    function convertToAssets(uint256 shares, Math.Rounding rounding) internal view returns (uint256 assets) {
        assets = shares.mulDiv(totalAssets + 1, totalSupply() + 1, rounding);
    }

    /* USER INTERACTION */

    function _deposit(uint256 assets, uint256 shares, address receiver) internal {
        SafeERC20.safeTransferFrom(asset, msg.sender, address(this), assets);
        _mint(receiver, shares);
        totalAssets += assets;
    }

    // TODO: how to hook on deposit so that assets are atomically allocated ?
    function deposit(uint256 assets, address receiver) public virtual returns (uint256 shares) {
        accrueInterest();
        // Note that it could be made more efficient by caching totalAssets.
        shares = convertToShares(assets, Math.Rounding.Floor);
        _deposit(assets, shares, receiver);
    }

    function mint(uint256 shares, address receiver) public virtual returns (uint256 assets) {
        accrueInterest();
        assets = convertToShares(shares, Math.Rounding.Ceil);
        _deposit(assets, shares, receiver);
    }

    function _withdraw(uint256 assets, uint256 shares, address receiver, address supplier) internal virtual {
        if (msg.sender != supplier) _spendAllowance(supplier, msg.sender, shares);
        _burn(supplier, shares);
        SafeERC20.safeTransfer(asset, receiver, assets);
        totalAssets -= assets;
    }

    // Note that it is not callable by default, if there is no liquidity.
    // This is actually a feature, so that the curator can pause withdrawals if necessary/wanted.
    function withdraw(uint256 assets, address receiver, address supplier) public virtual returns (uint256 shares) {
        accrueInterest();
        shares = convertToShares(assets, Math.Rounding.Ceil);
        _withdraw(assets, shares, receiver, supplier);
    }

    function redeem(uint256 shares, address receiver, address supplier) public virtual returns (uint256 assets) {
        accrueInterest();
        assets = convertToShares(shares, Math.Rounding.Floor);
        _withdraw(assets, shares, receiver, supplier);
    }

    /* INTERFACE */

    function balanceOf(address user) public view override(ERC20, IMarket) returns (uint256) {
        return super.balanceOf(user);
    }

    function maxWithdraw(address) external view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function marketsLength() external view returns (uint256) {
        return markets.length;
    }
}
