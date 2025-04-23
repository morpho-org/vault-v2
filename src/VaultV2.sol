// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IVaultV2, IERC20, IAdapter} from "./interfaces/IVaultV2.sol";
import {IIRM} from "./interfaces/IIRM.sol";
import {ProtocolFee, IVaultV2Factory} from "./interfaces/IVaultV2Factory.sol";

import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {EventsLib} from "./libraries/EventsLib.sol";
import "./libraries/ConstantsLib.sol";
import {MathLib} from "./libraries/MathLib.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";

// forgefmt: disable-start
bytes32 constant ONE            = bytes32(uint256(1));

bytes32 constant SENTINEL_ROLE  = ONE << 0;
bytes32 constant TREASURER_ROLE = ONE << 2;
bytes32 constant CURATOR_ROLE   = ONE << 3;
bytes32 constant ALLOCATOR_ROLE = ONE << 4;
bytes32 constant OWNER_ROLE     = ONE << 5;
bytes32 constant ADAPTER_ROLE   = ONE << 6;
// forgefmt: disable-end

contract VaultV2 is IVaultV2 {
    using MathLib for uint256;
    using SafeTransferLib for IERC20;

    /* IMMUTABLE */

    string public name;
    string public symbol;
    uint8 public immutable decimals;
    address public immutable factory;
    address public immutable asset;

    /* STORAGE */
    address public irm;
    bool willRevoke;

    /// @dev invariant: performanceFee != 0 => performanceFeeRecipient != address(0)
    uint256 public performanceFee;
    address public performanceFeeRecipient;
    /// @dev invariant: managementFee != 0 => managementFeeRecipient != address(0)
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

    address public liquidityAdapter;
    bytes public liquidityData;

    mapping(address account => bytes32) internal roles;
    mapping(string roleName => bytes32) internal roleIds;

    /// @dev calldata => executable at
    mapping(bytes => uint256) public validAt;
    /// @dev function selector => timelock duration
    mapping(bytes4 => uint256) public timelock;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public nonces;

    /* CONSTRUCTOR */

    constructor(address _owner, address _asset, string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
        decimals = IERC20(_asset).decimals();
        factory = msg.sender;
        asset = _asset;
        lastUpdate = block.timestamp;
        timelock[IVaultV2.decreaseTimelock.selector] = TIMELOCK_CAP;

        roleIds["sentinel"] = SENTINEL_ROLE;
        roleIds["treasurer"] = TREASURER_ROLE;
        roleIds["curator"] = CURATOR_ROLE;
        roleIds["allocator"] = ALLOCATOR_ROLE;
        roleIds["owner"] = OWNER_ROLE;
        roleIds["adapter"] = ADAPTER_ROLE;

        _setRole(_owner, OWNER_ROLE, true);
    }

    /* OWNER ACTIONS */

    function setPerformanceFeeRecipient(address newPerformanceFeeRecipient) external {
        if (_timelock(hasRole(OWNER_ROLE))) performanceFeeRecipient = newPerformanceFeeRecipient;
    }

    function setManagementFeeRecipient(address newManagementFeeRecipient) external {
        if (_timelock(hasRole(OWNER_ROLE))) managementFeeRecipient = newManagementFeeRecipient;
    }

    function increaseTimelock(bytes4 functionSelector, uint64 newDuration) external {
        require(functionSelector != IVaultV2.decreaseTimelock.selector, ErrorsLib.TimelockCapIsFixed());
        require(newDuration <= TIMELOCK_CAP, ErrorsLib.TimelockDurationTooHigh());

        if (_timelock(hasRole(OWNER_ROLE))) {
            require(newDuration > timelock[functionSelector], ErrorsLib.TimelockNotIncreasing());
            timelock[functionSelector] = newDuration;
        }
    }

    function decreaseTimelock(bytes4 functionSelector, uint64 newDuration) external {
        require(functionSelector != IVaultV2.decreaseTimelock.selector, ErrorsLib.TimelockCapIsFixed());
        require(newDuration <= TIMELOCK_CAP, ErrorsLib.TimelockDurationTooHigh());

        if (_timelock(hasRole(OWNER_ROLE))) {
            require(newDuration < timelock[functionSelector], ErrorsLib.TimelockNotDecreasing());
            timelock[functionSelector] = newDuration;
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

        if (_timelock(canSubmit, canRevoke)) _setRole(account, role, on);
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
        require(newPerformanceFee < MAX_PERFORMANCE_FEE, ErrorsLib.FeeTooHigh());
        require(performanceFeeRecipient != address(0), ErrorsLib.FeeInvariantBroken());

        if (_timelock(hasRole(TREASURER_ROLE))) performanceFee = newPerformanceFee;
    }

    function setManagementFee(uint256 newManagementFee) external {
        require(newManagementFee < WAD, ErrorsLib.FeeTooHigh());
        require(managementFeeRecipient != address(0), ErrorsLib.FeeInvariantBroken());

        if (_timelock(hasRole(TREASURER_ROLE))) managementFee = newManagementFee;
    }

    /* CURATOR ACTIONS */

    function setIRM(address newIRM) external {
        if (_timelock(hasRole(CURATOR_ROLE))) irm = newIRM;
    }

    /* CAP MANAGEMENT */

    function setAbsoluteCap(bytes32 id, uint256 newCap) external {
        bool canSubmit = hasRole(CURATOR_ROLE) || (hasRole(SENTINEL_ROLE) && newCap < absoluteCap[id]);
        if (_timelock(canSubmit)) absoluteCap[id] = newCap;
    }

    function setRelativeCap(bytes32 id, uint256 newRelativeCap, uint256 index) external {
        uint256 currentRelativeCap = relativeCap[id];
        bool canSubmit = hasRole(CURATOR_ROLE) || (hasRole(SENTINEL_ROLE) && newRelativeCap < currentRelativeCap);
        if (_timelock(canSubmit)) {
            if (newRelativeCap > currentRelativeCap) {
                if (relativeCap[id] == 0) idsWithRelativeCap.push(id);
                relativeCap[id] = newRelativeCap;
            } else if (newRelativeCap < currentRelativeCap) {
                require(idsWithRelativeCap[index] == id, ErrorsLib.IdNotFound());
                require(allocation[id] <= totalAssets.mulDivDown(newRelativeCap, WAD), ErrorsLib.RelativeCapExceeded());

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

        SafeTransferLib.safeTransfer(IERC20(asset), adapter, amount);
        bytes32[] memory ids = IAdapter(adapter).allocateIn(data, amount);

        for (uint256 i; i < ids.length; i++) {
            allocation[ids[i]] += amount;

            require(allocation[ids[i]] <= absoluteCap[ids[i]], ErrorsLib.AbsoluteCapExceeded());
            require(
                allocation[ids[i]] <= totalAssets.mulDivDown(relativeCap[ids[i]], WAD), ErrorsLib.RelativeCapExceeded()
            );
        }
    }

    // Note how the discrepancy between transferred amount and decrease in market.totalAssets() is handled:
    // it is not reflected in vault.totalAssets() but will have an impact on interest.
    function reallocateToIdle(address adapter, bytes memory data, uint256 amount) public {
        require(hasRole(ALLOCATOR_ROLE | SENTINEL_ROLE) || msg.sender == address(this), ErrorsLib.NotAllocator());
        require(hasRole(adapter, ADAPTER_ROLE), ErrorsLib.NotAdapter());

        bytes32[] memory ids = IAdapter(adapter).allocateOut(data, amount);

        for (uint256 i; i < ids.length; i++) {
            allocation[ids[i]] = allocation[ids[i]].zeroFloorSub(amount);
        }

        SafeTransferLib.safeTransferFrom(IERC20(asset), adapter, address(this), amount);
    }

    function setLiquidityMarket(address newLiquidityAdapter, bytes memory newLiquidityData) external {
        liquidityAdapter = newLiquidityAdapter;
        liquidityData = newLiquidityData;
    }

    /* EXCHANGE RATE */

    function accrueInterest() public {
        (uint256 performanceFeeShares, uint256 managementFeeShares, uint256 protocolFeeShares, uint256 newTotalAssets) =
            accrueInterestView();

        totalAssets = newTotalAssets;

        if (performanceFeeShares != 0) _mint(performanceFeeRecipient, performanceFeeShares);
        if (managementFeeShares != 0) _mint(managementFeeRecipient, managementFeeShares);
        if (protocolFeeShares != 0) _mint(IVaultV2Factory(factory).protocolFeeRecipient(), protocolFeeShares);

        lastUpdate = block.timestamp;
    }

    function accrueInterestView() public view returns (uint256, uint256, uint256, uint256) {
        uint256 elapsed = block.timestamp - lastUpdate;
        uint256 interestPerSecond = IIRM(irm).interestPerSecond(totalAssets, elapsed);
        require(interestPerSecond <= totalAssets.mulDivDown(MAX_RATE_PER_SECOND, WAD), ErrorsLib.InvalidRate());
        uint256 interest = interestPerSecond * elapsed;
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
            uint256 performanceFeeAssets = interest.mulDivDown(performanceFee, WAD);
            totalPerformanceFeeShares =
                performanceFeeAssets.mulDivDown(totalSupply + 1, newTotalAssets + 1 - performanceFeeAssets);
            protocolPerformanceFeeShares = totalPerformanceFeeShares.mulDivDown(protocolFee, WAD);
            performanceFeeShares = totalPerformanceFeeShares - protocolPerformanceFeeShares;
        }
        if (managementFee != 0) {
            // Using newTotalAssets to make all approximations consistent.
            uint256 managementFeeAssets = (newTotalAssets * elapsed).mulDivDown(managementFee, WAD);
            uint256 totalManagementFeeShares = managementFeeAssets.mulDivDown(
                totalSupply + 1 + totalPerformanceFeeShares, newTotalAssets + 1 - managementFeeAssets
            );
            protocolManagementFeeShares = totalManagementFeeShares.mulDivDown(protocolFee, WAD);
            managementFeeShares = totalManagementFeeShares - protocolManagementFeeShares;
        }
        uint256 protocolFeeShares = protocolPerformanceFeeShares + protocolManagementFeeShares;
        return (performanceFeeShares, managementFeeShares, protocolFeeShares, newTotalAssets);
    }

    function convertToShares(uint256 assets) external view returns (uint256) {
        (uint256 performanceFeeShares, uint256 managementFeeShares, uint256 protocolFeeShares, uint256 newTotalAssets) =
            accrueInterestView();
        uint256 newTotalSupply = totalSupply + performanceFeeShares + managementFeeShares + protocolFeeShares;
        return assets.mulDivDown(newTotalSupply + 1, newTotalAssets + 1);
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        (uint256 performanceFeeShares, uint256 managementFeeShares, uint256 protocolFeeShares, uint256 newTotalAssets) =
            accrueInterestView();
        uint256 newTotalSupply = totalSupply + performanceFeeShares + managementFeeShares + protocolFeeShares;
        return shares.mulDivDown(newTotalAssets + 1, newTotalSupply + 1);
    }

    /// @dev Use only once interest have been accrued.
    function convertToSharesDown(uint256 assets) internal view returns (uint256) {
        return assets.mulDivDown(totalSupply + 1, totalAssets + 1);
    }

    /// @dev Use only once interest have been accrued.
    function convertToSharesUp(uint256 assets) internal view returns (uint256) {
        return assets.mulDivUp(totalSupply + 1, totalAssets + 1);
    }

    /// @dev Use only once interest have been accrued.
    function convertToAssetsDown(uint256 shares) internal view returns (uint256) {
        return shares.mulDivDown(totalAssets + 1, totalSupply + 1);
    }

    /// @dev Use only once interest have been accrued.
    function convertToAssetsUp(uint256 shares) internal view returns (uint256) {
        return shares.mulDivUp(totalAssets + 1, totalSupply + 1);
    }

    /* USER INTERACTION */

    function _deposit(uint256 assets, uint256 shares, address receiver) internal {
        SafeTransferLib.safeTransferFrom(IERC20(asset), msg.sender, address(this), assets);
        _mint(receiver, shares);
        totalAssets += assets;

        try this.reallocateFromIdle(liquidityAdapter, liquidityData, assets) {} catch {}
    }

    // TODO: how to hook on deposit so that assets are atomically allocated ?
    function deposit(uint256 assets, address receiver) public returns (uint256 shares) {
        accrueInterest();
        // Note that it could be made more efficient by caching totalAssets.
        shares = convertToSharesDown(assets);
        _deposit(assets, shares, receiver);
    }

    function mint(uint256 shares, address receiver) public returns (uint256 assets) {
        accrueInterest();
        assets = convertToAssetsUp(shares);
        _deposit(assets, shares, receiver);
    }

    function _withdraw(uint256 assets, uint256 shares, address receiver, address supplier) internal {
        uint256 idleAssets = IERC20(asset).balanceOf(address(this));
        if (assets > idleAssets && liquidityAdapter != address(0)) {
            reallocateToIdle(liquidityAdapter, liquidityData, assets - idleAssets);
        }
        uint256 _allowance = allowance[supplier][msg.sender];
        if (msg.sender != supplier && _allowance != type(uint256).max) {
            allowance[supplier][msg.sender] = _allowance - shares;
        }
        _burn(supplier, shares);
        SafeTransferLib.safeTransfer(IERC20(asset), receiver, assets);
        totalAssets -= assets;

        for (uint256 i; i < idsWithRelativeCap.length; i++) {
            bytes32 id = idsWithRelativeCap[i];
            require(allocation[id] <= totalAssets.mulDivDown(relativeCap[id], WAD), ErrorsLib.RelativeCapExceeded());
        }
    }

    // Note that it is not callable by default, if there is no liquidity.
    // This is actually a feature, so that the curator can pause withdrawals if necessary/wanted.
    function withdraw(uint256 assets, address receiver, address supplier) public returns (uint256 shares) {
        accrueInterest();
        shares = convertToSharesUp(assets);
        _withdraw(assets, shares, receiver, supplier);
    }

    function redeem(uint256 shares, address receiver, address supplier) public returns (uint256 assets) {
        accrueInterest();
        assets = convertToAssetsDown(shares);
        _withdraw(assets, shares, receiver, supplier);
    }

    /* TIMELOCKS */

    function _timelock(bool canSubmit) internal returns (bool) {
        return _timelock(canSubmit, canSubmit);
    }

    function _timelock(bool canSubmit, bool canRevoke) internal returns (bool immediatelyCallable) {
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
                validAt[msg.data] = block.timestamp + timelock[msg.sig];
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

    function transfer(address to, uint256 amount) public returns (bool) {
        require(to != address(0), ErrorsLib.ZeroAddress());
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit EventsLib.Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        require(from != address(0), ErrorsLib.ZeroAddress());
        require(to != address(0), ErrorsLib.ZeroAddress());
        uint256 _allowance = allowance[from][msg.sender];

        if (_allowance < type(uint256).max) allowance[from][msg.sender] = _allowance - amount;

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit EventsLib.Transfer(from, to, amount);

        return true;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit EventsLib.Approval(msg.sender, spender, amount);
        return true;
    }

    function permit(address _owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
    {
        bytes32 hashStruct = keccak256(abi.encode(PERMIT_TYPEHASH, _owner, spender, value, nonces[_owner]++, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), hashStruct));
        address recoveredAddress = ecrecover(digest, v, r, s);

        require(deadline >= block.timestamp, ErrorsLib.PermitDeadlineExpired());
        require(recoveredAddress != address(0) && recoveredAddress == _owner, ErrorsLib.InvalidSigner());

        allowance[recoveredAddress][spender] = value;
        emit EventsLib.Approval(recoveredAddress, spender, value);
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
    }

    function maxWithdraw(address) external view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    /* ERC20 INTERNAL */

    function _mint(address to, uint256 amount) internal {
        require(to != address(0), ErrorsLib.ZeroAddress());
        balanceOf[to] += amount;
        totalSupply += amount;
        emit EventsLib.Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        require(from != address(0), ErrorsLib.ZeroAddress());
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit EventsLib.Transfer(from, address(0), amount);
    }
}
