// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {ERC20, IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Math} from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IVaultV2, IAdapter} from "./interfaces/IVaultV2.sol";
import {IIRM} from "./interfaces/IIRM.sol";
import {ProtocolFee, IVaultV2Factory} from "./interfaces/IVaultV2Factory.sol";

import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {WAD} from "./libraries/ConstantsLib.sol";
import {MathLib} from "./libraries/MathLib.sol";

// forgefmt: disable-start
bytes32 constant ONE            = bytes32(uint256(1));

bytes32 constant SENTINEL_ROLE  = ONE << 0;
bytes32 constant TREASURER_ROLE = ONE << 2;
bytes32 constant CURATOR_ROLE   = ONE << 3;
bytes32 constant ALLOCATOR_ROLE = ONE << 4;
bytes32 constant OWNER_ROLE     = ONE << 5;
bytes32 constant ADAPTER_ROLE   = ONE << 6;
// forgefmt: disable-end

contract VaultV2 is ERC20, IVaultV2 {
    using Math for uint256;
    using MathLib for uint256;

    /* CONSTANT */
    uint64 public constant TIMELOCK_CAP = 2 weeks;

    /* IMMUTABLE */

    address public immutable factory;
    IERC20 public immutable asset;

    /* TRANSIENT */

    // TODO: make this actually transient.
    bool public unlocked;
    bool willRevoke;

    /* STORAGE */
    address public irm;

    uint256 public performanceFee;
    address public performanceFeeRecipient;
    uint256 public managementFee;
    address public managementFeeRecipient;

    uint256 public lastUpdate;
    uint256 public totalAssets;

    /// @dev Key is an abstract id, which can represent a protocol, a collateral, a duration etc.
    mapping(bytes32 => uint256) public absoluteCap;

    /// @dev Key is an abstract id, which can represent a protocol, a collateral, a duration etc.
    /// @dev Relative cap = 0 is interpreted as no relative cap.
    mapping(bytes32 => uint256) public relativeCap;

    /// @dev Useful to iterate over all ids with relative cap in withdrawals.
    bytes32[] public idsWithRelativeCap;

    /// @dev Interests are not counted in the allocation.
    /// @dev By design, double counting some stuff.
    mapping(bytes32 => uint256) public allocation;

    address public depositAdapter;
    bytes public depositData;
    address public withdrawAdapter;
    bytes public withdrawData;

    mapping(address account => bytes32) internal roles;
    mapping(string roleName => bytes32) internal roleIds;

    mapping(bytes => uint256) public validAt;
    mapping(bytes4 => uint64) public timelockDuration;

    /* CONSTRUCTOR */

    constructor(address _owner, address _asset, string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        factory = msg.sender;
        asset = IERC20(_asset);
        lastUpdate = block.timestamp;
        timelockDuration[IVaultV2.decreaseTimelock.selector] = TIMELOCK_CAP;

        roleIds["sentinel"] = SENTINEL_ROLE;
        roleIds["treasurer"] = TREASURER_ROLE;
        roleIds["curator"] = CURATOR_ROLE;
        roleIds["allocator"] = ALLOCATOR_ROLE;
        roleIds["owner"] = OWNER_ROLE;
        roleIds["adapter"] = ADAPTER_ROLE;

        _setRole(_owner, OWNER_ROLE, true);
        // The vault starts with no IRM, no markets and no assets. To be configured afterwards.
    }

    /* OWNER ACTIONS */

    function setPerformanceFeeRecipient(address newPerformanceFeeRecipient) external {
        if (timelock(hasRole(OWNER_ROLE))) performanceFeeRecipient = newPerformanceFeeRecipient;
    }

    function setManagementFeeRecipient(address newManagementFeeRecipient) external {
        if (timelock(hasRole(OWNER_ROLE))) managementFeeRecipient = newManagementFeeRecipient;
    }

    function increaseTimelock(bytes4 functionSelector, uint64 newDuration) external {
        require(functionSelector != IVaultV2.decreaseTimelock.selector, ErrorsLib.TimelockCapIsFixed());
        require(newDuration <= TIMELOCK_CAP, ErrorsLib.TimelockDurationTooHigh());

        if (timelock(hasRole(OWNER_ROLE))) {
            require(newDuration > timelockDuration[functionSelector],ErrorsLib.TimelockNotIncreasing());
            timelockDuration[functionSelector] = newDuration;
        }
    }

    function decreaseTimelock(bytes4 functionSelector, uint64 newDuration) external {
        require(functionSelector != IVaultV2.decreaseTimelock.selector, ErrorsLib.TimelockCapIsFixed());
        require(newDuration <= TIMELOCK_CAP, ErrorsLib.TimelockDurationTooHigh());

        if (timelock(hasRole(OWNER_ROLE))) {
            require(newDuration < timelockDuration[functionSelector],ErrorsLib.TimelockNotDecreasing());
            timelockDuration[functionSelector] = newDuration;
        }
    }

    /* ROLE MANAGEMENT */

    function setRole(address account, string calldata roleName, bool on) external {
        bytes32 role = roleIds[roleName];
        require(role != bytes32(0), ErrorsLib.InvalidRole());

        // forgefmt: disable-start
        bool canSubmit = hasRole(OWNER_ROLE)
                   || (hasRole(CURATOR_ROLE) && role == ADAPTER_ROLE)
                   || (hasRole(SENTINEL_ROLE) && role == ALLOCATOR_ROLE);
        bool canRevoke = canSubmit
                     || (hasRole(SENTINEL_ROLE) && role != SENTINEL_ROLE);
        // forgefmt: disable-end

        if (timelock(canSubmit, canRevoke)) _setRole(account, role, on);
    }

    function _setRole(address account, bytes32 role, bool on) internal {
        if (on) roles[account] |= role;
        else roles[account] &= ~role;
    }

    function hasRole(bytes32 role) internal view returns (bool) {
        return hasRole(msg.sender, role);
    }

    function hasRole(address account, bytes32 role) internal view returns (bool) {
        return roles[account] & role != 0;
    }

    function hasRole(address account, string calldata roleName) external view returns (bool) {
        bytes32 role = roleIds[roleName];
        require(role != bytes32(0), ErrorsLib.InvalidRole());
        return hasRole(account, role);
    }

    /* TREASURER ACTIONS */

    function setPerformanceFee(uint256 newPerformanceFee) external {
        require(newPerformanceFee < WAD, ErrorsLib.FeeTooHigh());

        if (timelock(hasRole(TREASURER_ROLE))) performanceFee = newPerformanceFee;
    }

    function setManagementFee(uint256 newManagementFee) external {
        require(newManagementFee < WAD, ErrorsLib.FeeTooHigh());

        if (timelock(hasRole(TREASURER_ROLE))) managementFee = newManagementFee;
    }

    /* CURATOR ACTIONS */

    function setIRM(address newIRM) external {
        if (timelock(hasRole(CURATOR_ROLE))) irm = newIRM;
    }

    /* CAP MANAGEMENT */

    function setAbsoluteCap(bytes32 id, uint256 newCap) external {
        bool canSubmit = hasRole(CURATOR_ROLE) || (hasRole(SENTINEL_ROLE) && newCap < absoluteCap[id]);
        if (timelock(canSubmit)) absoluteCap[id] = newCap;
    }

    function setRelativeCap(bytes32 id, uint256 newRelativeCap, uint256 index) external {
        uint256 currentRelativeCap = relativeCap[id];
        bool canSubmit = hasRole(CURATOR_ROLE) || (hasRole(SENTINEL_ROLE) && newRelativeCap < currentRelativeCap);
        if (timelock(canSubmit)) {
            if (newRelativeCap > currentRelativeCap) {
                if (relativeCap[id] == 0) idsWithRelativeCap.push(id);
                relativeCap[id] = newRelativeCap;
            } else if (newRelativeCap < currentRelativeCap) {
                require(idsWithRelativeCap[index] == id, ErrorsLib.IdNotFound());
                require(
                    allocation[id] <= totalAssets.mulDiv(newRelativeCap, WAD, Math.Rounding.Floor),
                    ErrorsLib.RelativeCapExceeded()
                );

                if (newRelativeCap == 0) {
                    idsWithRelativeCap[index] = idsWithRelativeCap[idsWithRelativeCap.length - 1];
                    idsWithRelativeCap.pop();
                }
                relativeCap[id] = newRelativeCap;
            }
        }
    }

    /* ALLOCATION ACTIONS */

    // Note how the discrepancy between transferred amount and increase in market.totalAssets() is handled:
    // it is not reflected in vault.totalAssets() but will have an impact on interest.
    function reallocateFromIdle(address adapter, bytes memory data, uint256 amount) external {
        require(hasRole(ALLOCATOR_ROLE | SENTINEL_ROLE) || msg.sender == address(this), ErrorsLib.NotAllocator());
        require(hasRole(adapter, ADAPTER_ROLE), ErrorsLib.NotAdapter());

        asset.transfer(adapter, amount);
        bytes32[] memory ids = IAdapter(adapter).allocateIn(data, amount);

        for (uint256 i; i < ids.length; i++) {
            allocation[ids[i]] += amount;

            require(allocation[ids[i]] <= absoluteCap[ids[i]], ErrorsLib.AbsoluteCapExceeded());
            require(
                allocation[ids[i]] <= totalAssets.mulDiv(relativeCap[ids[i]], WAD, Math.Rounding.Floor),
                ErrorsLib.RelativeCapExceeded()
            );
        }
    }

    // Note how the discrepancy between transferred amount and decrease in market.totalAssets() is handled:
    // it is not reflected in vault.totalAssets() but will have an impact on interest.
    function reallocateToIdle(address adapter, bytes memory data, uint256 amount) external {
        require(hasRole(ALLOCATOR_ROLE | SENTINEL_ROLE) || msg.sender == address(this), ErrorsLib.NotAllocator());
        require(hasRole(adapter, ADAPTER_ROLE), ErrorsLib.NotAdapter());

        bytes32[] memory ids = IAdapter(adapter).allocateOut(data, amount);

        for (uint256 i; i < ids.length; i++) {
            allocation[ids[i]] = allocation[ids[i]].zeroFloorSub(amount);
        }

        asset.transferFrom(adapter, address(this), amount);
    }

    function setDepositData(address newDepositAdapter, bytes memory newDepositData) external {
        if (timelock(hasRole(ALLOCATOR_ROLE))) {
            depositAdapter = newDepositAdapter;
            depositData = newDepositData;
        }
    }

    function setWithdrawData(address newWithdrawAdapter, bytes memory newWithdrawData) external {
        if (timelock(hasRole(ALLOCATOR_ROLE))) {
            withdrawAdapter = newWithdrawAdapter;
            withdrawData = newWithdrawData;
        }
    }

    /* EXCHANGE RATE */

    function accrueInterest() public {
        (uint256 performanceFeeShares, uint256 managementFeeShares, uint256 protocolFeeShares, uint256 newTotalAssets) =
            accruedFeeShares();

        totalAssets = newTotalAssets;

        address protocolFeeRecipient = IVaultV2Factory(factory).protocolFeeRecipient();
        if (performanceFeeShares != 0) _mint(performanceFeeRecipient, performanceFeeShares);
        if (managementFeeShares != 0) _mint(managementFeeRecipient, managementFeeShares);
        if (protocolFeeShares != 0) _mint(protocolFeeRecipient, protocolFeeShares);

        lastUpdate = block.timestamp;
    }

    function accruedFeeShares() public view returns (uint256, uint256, uint256, uint256) {
        uint256 elapsed = block.timestamp - lastUpdate;
        uint256 interest = IIRM(irm).interestPerSecond() * elapsed;
        uint256 newTotalAssets = totalAssets + interest;

        uint256 protocolFee = IVaultV2Factory(factory).protocolFee();

        uint256 performanceFeeShares;
        uint256 managementFeeShares;
        uint256 protocolPerformanceFeeShares;
        uint256 protocolManagementFeeShares;
        // Note that the fee assets is subtracted from the total assets in the fee shares calculation to compensate for
        // the fact that total assets is already increased by the total interest (including the fee assets).
        // Note that `feeAssets` may be rounded down to 0 if `totalInterest * fee < WAD`.
        uint256 totalPerformanceFeeShares;
        if (interest > 0 && performanceFee != 0) {
            uint256 performanceFeeAssets = interest.mulDiv(performanceFee, WAD, Math.Rounding.Floor);
            totalPerformanceFeeShares = performanceFeeAssets.mulDiv(
                totalSupply() + 1, newTotalAssets + 1 - performanceFeeAssets, Math.Rounding.Floor
            );
            protocolPerformanceFeeShares = totalPerformanceFeeShares.mulDiv(protocolFee, WAD, Math.Rounding.Floor);
            performanceFeeShares = totalPerformanceFeeShares - protocolPerformanceFeeShares;
        }
        if (managementFee != 0) {
            // Using newTotalAssets to make all approximations consistent.
            uint256 managementFeeAssets = (newTotalAssets * elapsed).mulDiv(managementFee, WAD, Math.Rounding.Floor);
            uint256 totalManagementFeeShares = managementFeeAssets.mulDiv(
                totalSupply() + 1 + totalPerformanceFeeShares,
                newTotalAssets + 1 - managementFeeAssets,
                Math.Rounding.Floor
            );
            protocolManagementFeeShares = totalManagementFeeShares.mulDiv(protocolFee, WAD, Math.Rounding.Floor);
            managementFeeShares = totalManagementFeeShares - protocolManagementFeeShares;
        }
        uint256 protocolFeeShares = protocolPerformanceFeeShares + protocolManagementFeeShares;
        return (performanceFeeShares, managementFeeShares, protocolFeeShares, newTotalAssets);
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

        try this.reallocateFromIdle(depositAdapter, depositData, assets) {} catch {}
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
        assets = convertToAssets(shares, Math.Rounding.Ceil);
        _deposit(assets, shares, receiver);
    }

    function _withdraw(uint256 assets, uint256 shares, address receiver, address supplier) internal virtual {
        try this.reallocateToIdle(withdrawAdapter, withdrawData, assets) {} catch {}

        if (msg.sender != supplier) _spendAllowance(supplier, msg.sender, shares);
        _burn(supplier, shares);
        SafeERC20.safeTransfer(asset, receiver, assets);
        totalAssets -= assets;

        for (uint256 i; i < idsWithRelativeCap.length; i++) {
            bytes32 id = idsWithRelativeCap[i];
            require(
                allocation[id] <= totalAssets.mulDiv(relativeCap[id], WAD, Math.Rounding.Floor),
                ErrorsLib.RelativeCapExceeded()
            );
        }
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
        assets = convertToAssets(shares, Math.Rounding.Floor);
        _withdraw(assets, shares, receiver, supplier);
    }

    /* TIMELOCKS */

    function timelock(bool canSubmit) internal returns (bool) {
        return timelock(canSubmit, canSubmit);
    }

    function timelock(bool canSubmit, bool canRevoke) internal returns (bool immediatelyCallable) {
        if (willRevoke == true) {
            require(canRevoke, ErrorsLib.Unauthorized());
            require(validAt[msg.data] != 0);
            validAt[msg.data] = 0;
            return false;
        } else {
            if (validAt[msg.data] != 0) {
                require(block.timestamp >= validAt[msg.data], ErrorsLib.DataAlreadyPending());
                validAt[msg.data] = 0;
                return true;
            } else {
                require(canSubmit, ErrorsLib.Unauthorized());
                validAt[msg.data] = block.timestamp + timelockDuration[msg.sig];
                return false;
            }
        }
    }

    function revoke(bytes calldata data) external {
        willRevoke = true;
        address(this).delegatecall(data);
        willRevoke = false;
    }

    /* INTERFACE */

    function maxWithdraw(address) external view returns (uint256) {
        return asset.balanceOf(address(this));
    }
}
