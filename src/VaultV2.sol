// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IVaultV2, IERC20} from "./interfaces/IVaultV2.sol";
import {IAdapter} from "./interfaces/IAdapter.sol";
import {IVic} from "./interfaces/IVic.sol";

import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {EventsLib} from "./libraries/EventsLib.sol";
import "./libraries/ConstantsLib.sol";
import {MathLib} from "./libraries/MathLib.sol";
import {SafeERC20Lib} from "./libraries/SafeERC20Lib.sol";
import {FixedPointMathLib} from "../lib/solady/src/utils/FixedPointMathLib.sol";
import {LibBit} from "../lib/solady/src/utils/LibBit.sol";

/// @dev Zero checks are not performed.
/// @dev No-ops are allowed.
contract VaultV2 is IVaultV2 {
    using MathLib for uint256;

    /* IMMUTABLE */
    address public immutable asset;

    /* ROLES STORAGE */
    address public owner;
    address public curator;
    mapping(address => bool) public isSentinel;
    mapping(address => bool) public isAllocator;

    /* TOKEN STORAGE */
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public nonces;

    /* VAULT STORAGE */
    uint256 public totalAssets;
    uint256 public lastUpdate;

    /* CURATION AND ALLOCATION STORAGE */
    address public vic;
    uint256 public forceReallocateToIdlePenalty;
    /// @dev Adapter is trusted to pass the expected ids when supplying assets.
    mapping(address => bool) public isAdapter;
    /// @dev Key is an abstract id, which can represent a protocol, a collateral, a duration etc.
    mapping(bytes32 => uint256) public absoluteCap;
    /// @dev Key is an abstract id, which can represent a protocol, a collateral, a duration etc.
    /// @dev The relative cap is relative to `totalAssets`.
    /// @dev Units are in WAD.
    /// @dev A relative cap of 1 WAD means no relative cap.
    mapping(bytes32 => uint256) internal oneMinusRelativeCap;
    /// @dev Interests are not counted in the allocation.
    mapping(bytes32 => uint256) public allocation;
    /// @dev calldata => executable at
    mapping(bytes => uint256) public validAt;
    /// @dev function selector => timelock duration
    mapping(bytes4 => uint256) public timelock;
    address public liquidityAdapter;
    bytes public liquidityData;

    uint256 root;
    mapping(uint256 => uint256) leafBitmap;

    /* FEES STORAGE */
    /// @dev invariant: performanceFee != 0 => performanceFeeRecipient != address(0)
    uint256 public performanceFee;
    address public performanceFeeRecipient;
    /// @dev invariant: managementFee != 0 => managementFeeRecipient != address(0)
    uint256 public managementFee;
    address public managementFeeRecipient;

    /* GETTERS */

    function relativeCap(bytes32 id) public view returns (uint256) {
        return WAD - oneMinusRelativeCap[id];
    }

    /* MULTICALL */

    function multicall(bytes[] calldata data) external {
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory returnData) = address(this).delegatecall(data[i]);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(32, returnData), mload(returnData))
                }
            }
        }
    }

    /* CONSTRUCTOR */

    constructor(address _owner, address _asset) {
        asset = _asset;
        owner = _owner;
        lastUpdate = block.timestamp;
        timelock[IVaultV2.decreaseTimelock.selector] = TIMELOCK_CAP;
        emit EventsLib.Constructor(_owner, _asset);
    }

    /* OWNER ACTIONS */

    function setOwner(address newOwner) external {
        require(msg.sender == owner, ErrorsLib.Unauthorized());
        owner = newOwner;
        emit EventsLib.SetOwner(newOwner);
    }

    function setCurator(address newCurator) external {
        require(msg.sender == owner, ErrorsLib.Unauthorized());
        curator = newCurator;
        emit EventsLib.SetCurator(newCurator);
    }

    function setIsSentinel(address account, bool newIsSentinel) external {
        require(msg.sender == owner, ErrorsLib.Unauthorized());
        isSentinel[account] = newIsSentinel;
        emit EventsLib.SetIsSentinel(account, newIsSentinel);
    }

    /* CURATOR ACTIONS */

    function setIsAllocator(address account, bool newIsAllocator) external timelocked {
        isAllocator[account] = newIsAllocator;
        emit EventsLib.SetIsAllocator(account, newIsAllocator);
    }

    function setVic(address newVic) external timelocked {
        accrueInterest();
        vic = newVic;
        emit EventsLib.SetVic(newVic);
    }

    function setIsAdapter(address account, bool newIsAdapter) external timelocked {
        require(account != liquidityAdapter, ErrorsLib.LiquidityAdapterInvariantBroken());
        isAdapter[account] = newIsAdapter;
        emit EventsLib.SetIsAdapter(account, newIsAdapter);
    }

    function increaseTimelock(bytes4 selector, uint256 newDuration) external {
        require(msg.sender == curator, ErrorsLib.Unauthorized());
        require(selector != IVaultV2.decreaseTimelock.selector, ErrorsLib.TimelockCapIsFixed());
        require(newDuration <= TIMELOCK_CAP, ErrorsLib.TimelockDurationTooHigh());
        require(newDuration >= timelock[selector], ErrorsLib.TimelockNotIncreasing());

        timelock[selector] = newDuration;
        emit EventsLib.IncreaseTimelock(selector, newDuration);
    }

    function decreaseTimelock(bytes4 selector, uint256 newDuration) external timelocked {
        require(selector != IVaultV2.decreaseTimelock.selector, ErrorsLib.TimelockCapIsFixed());
        require(newDuration <= timelock[selector], ErrorsLib.TimelockNotDecreasing());

        timelock[selector] = newDuration;
        emit EventsLib.DecreaseTimelock(selector, newDuration);
    }

    function setPerformanceFee(uint256 newPerformanceFee) external timelocked {
        require(newPerformanceFee <= MAX_PERFORMANCE_FEE, ErrorsLib.FeeTooHigh());
        require(performanceFeeRecipient != address(0) || newPerformanceFee == 0, ErrorsLib.FeeInvariantBroken());

        accrueInterest();

        performanceFee = newPerformanceFee;
        emit EventsLib.SetPerformanceFee(newPerformanceFee);
    }

    function setManagementFee(uint256 newManagementFee) external timelocked {
        require(newManagementFee <= MAX_MANAGEMENT_FEE, ErrorsLib.FeeTooHigh());
        require(managementFeeRecipient != address(0) || newManagementFee == 0, ErrorsLib.FeeInvariantBroken());

        accrueInterest();

        managementFee = newManagementFee;
        emit EventsLib.SetManagementFee(newManagementFee);
    }

    function setPerformanceFeeRecipient(address newPerformanceFeeRecipient) external timelocked {
        require(newPerformanceFeeRecipient != address(0) || performanceFee == 0, ErrorsLib.FeeInvariantBroken());

        accrueInterest();

        performanceFeeRecipient = newPerformanceFeeRecipient;
        emit EventsLib.SetPerformanceFeeRecipient(newPerformanceFeeRecipient);
    }

    function setManagementFeeRecipient(address newManagementFeeRecipient) external timelocked {
        require(newManagementFeeRecipient != address(0) || managementFee == 0, ErrorsLib.FeeInvariantBroken());

        accrueInterest();

        managementFeeRecipient = newManagementFeeRecipient;
        emit EventsLib.SetManagementFeeRecipient(newManagementFeeRecipient);
    }

    function increaseAbsoluteCap(bytes memory idData, uint256 newAbsoluteCap) external timelocked {
        bytes32 id = keccak256(idData);
        require(newAbsoluteCap >= absoluteCap[id], ErrorsLib.AbsoluteCapNotIncreasing());

        absoluteCap[id] = newAbsoluteCap;
        emit EventsLib.IncreaseAbsoluteCap(id, idData, newAbsoluteCap);
    }

    function decreaseAbsoluteCap(bytes memory idData, uint256 newAbsoluteCap) external {
        require(msg.sender == curator || isSentinel[msg.sender], ErrorsLib.Unauthorized());
        bytes32 id = keccak256(idData);
        require(newAbsoluteCap <= absoluteCap[id], ErrorsLib.AbsoluteCapNotDecreasing());

        absoluteCap[id] = newAbsoluteCap;
        emit EventsLib.DecreaseAbsoluteCap(id, idData, newAbsoluteCap);
    }

    function increaseRelativeCap(bytes memory idData, uint256 newRelativeCap) external timelocked {
        bytes32 id = keccak256(idData);
        require(newRelativeCap <= WAD, ErrorsLib.RelativeCapAboveOne());
        require(newRelativeCap >= relativeCap(id), ErrorsLib.RelativeCapNotIncreasing());

        if (newRelativeCap > relativeCap(id)) {
            removeFloorIfNeeded(allocation[id], relativeCap(id));
            oneMinusRelativeCap[id] = WAD - newRelativeCap;
            addFloorIfNeeded(allocation[id], relativeCap(id));
        }

        emit EventsLib.IncreaseRelativeCap(id, idData, newRelativeCap);
    }

    function decreaseRelativeCap(bytes memory idData, uint256 newRelativeCap) external timelocked {
        bytes32 id = keccak256(idData);
        // To set a cap to 0, use `decreaseAbsoluteCap`.
        require(newRelativeCap > 0, ErrorsLib.RelativeCapZero());
        require(newRelativeCap <= relativeCap(id), ErrorsLib.RelativeCapNotDecreasing());

        if (newRelativeCap < relativeCap(id)) {
            require(allocation[id] <= totalAssets.mulDivDown(newRelativeCap, WAD), ErrorsLib.RelativeCapExceeded());

            removeFloorIfNeeded(allocation[id], relativeCap(id));
            oneMinusRelativeCap[id] = WAD - newRelativeCap;
            addFloorIfNeeded(allocation[id], relativeCap(id));
        }

        emit EventsLib.DecreaseRelativeCap(id, idData, newRelativeCap);
    }

    function setForceReallocateToIdlePenalty(uint256 newForceReallocateToIdlePenalty) external timelocked {
        require(newForceReallocateToIdlePenalty <= MAX_FORCE_REALLOCATE_TO_IDLE_PENALTY, ErrorsLib.PenaltyTooHigh());
        forceReallocateToIdlePenalty = newForceReallocateToIdlePenalty;
        emit EventsLib.SetForceReallocateToIdlePenalty(newForceReallocateToIdlePenalty);
    }

    /* ALLOCATOR ACTIONS */

    function reallocateFromIdle(address adapter, bytes memory data, uint256 assets) external {
        require(isAllocator[msg.sender] || msg.sender == address(this), ErrorsLib.NotAllocator());
        require(isAdapter[adapter], ErrorsLib.NotAdapter());

        SafeERC20Lib.safeTransfer(asset, adapter, assets);
        bytes32[] memory ids = IAdapter(adapter).allocate(data, assets);

        for (uint256 i; i < ids.length; i++) {
            removeFloorIfNeeded(allocation[ids[i]], relativeCap(ids[i]));
            allocation[ids[i]] += assets;
            addFloorIfNeeded(allocation[ids[i]], relativeCap(ids[i]));

            require(allocation[ids[i]] <= absoluteCap[ids[i]], ErrorsLib.AbsoluteCapExceeded());
        }
        require(noRelativeCapExceeded(), ErrorsLib.RelativeCapExceeded());

        emit EventsLib.ReallocateFromIdle(msg.sender, adapter, assets, ids);
    }

    function reallocateToIdle(address adapter, bytes memory data, uint256 assets) external {
        require(
            isAllocator[msg.sender] || isSentinel[msg.sender] || msg.sender == address(this), ErrorsLib.NotAllocator()
        );
        require(isAdapter[adapter], ErrorsLib.NotAdapter());

        bytes32[] memory ids = IAdapter(adapter).deallocate(data, assets);

        for (uint256 i; i < ids.length; i++) {
            removeFloorIfNeeded(allocation[ids[i]], relativeCap(ids[i]));
            allocation[ids[i]] = allocation[ids[i]].zeroFloorSub(assets);
            addFloorIfNeeded(allocation[ids[i]], relativeCap(ids[i]));
        }

        SafeERC20Lib.safeTransferFrom(asset, adapter, address(this), assets);
        emit EventsLib.ReallocateToIdle(msg.sender, adapter, assets, ids);
    }

    function setLiquidityAdapter(address newLiquidityAdapter) external {
        require(isAllocator[msg.sender], ErrorsLib.Unauthorized());
        require(
            newLiquidityAdapter == address(0) || isAdapter[newLiquidityAdapter],
            ErrorsLib.LiquidityAdapterInvariantBroken()
        );
        liquidityAdapter = newLiquidityAdapter;
        emit EventsLib.SetLiquidityAdapter(msg.sender, newLiquidityAdapter);
    }

    function setLiquidityData(bytes memory newLiquidityData) external {
        require(isAllocator[msg.sender], ErrorsLib.Unauthorized());
        liquidityData = newLiquidityData;
        emit EventsLib.SetLiquidityData(msg.sender, newLiquidityData);
    }

    /* TIMELOCKS */

    function submit(bytes calldata data) external {
        require(msg.sender == curator, ErrorsLib.Unauthorized());
        require(validAt[data] == 0, ErrorsLib.DataAlreadyPending());

        bytes4 selector = bytes4(data);
        validAt[data] = block.timestamp + timelock[selector];
        emit EventsLib.Submit(msg.sender, selector, data, validAt[data]);
    }

    modifier timelocked() {
        require(validAt[msg.data] != 0, ErrorsLib.DataNotTimelocked());
        require(block.timestamp >= validAt[msg.data], ErrorsLib.TimelockNotExpired());
        validAt[msg.data] = 0;
        _;
    }

    function revoke(bytes calldata data) external {
        require(msg.sender == curator || isSentinel[msg.sender], ErrorsLib.Unauthorized());
        require(validAt[data] != 0, ErrorsLib.DataNotTimelocked());
        validAt[data] = 0;
        emit EventsLib.Revoke(msg.sender, bytes4(data), data);
    }

    /* EXCHANGE RATE */

    function accrueInterest() public {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = accrueInterestView();
        emit EventsLib.AccrueInterest(totalAssets, newTotalAssets, performanceFeeShares, managementFeeShares);
        totalAssets = newTotalAssets;
        if (performanceFeeShares != 0) createShares(performanceFeeRecipient, performanceFeeShares);
        if (managementFeeShares != 0) createShares(managementFeeRecipient, managementFeeShares);
        lastUpdate = block.timestamp;
    }

    function accrueInterestView() public view returns (uint256, uint256, uint256) {
        uint256 elapsed = block.timestamp - lastUpdate;
        if (elapsed == 0) return (totalAssets, 0, 0);
        uint256 interestPerSecond;
        try IVic(vic).interestPerSecond(totalAssets, elapsed) returns (uint256 output) {
            if (output <= totalAssets.mulDivDown(MAX_RATE_PER_SECOND, WAD)) interestPerSecond = output;
            else interestPerSecond = 0;
        } catch {
            interestPerSecond = 0;
        }
        uint256 interest = interestPerSecond * elapsed;
        uint256 newTotalAssets = totalAssets + interest;

        uint256 performanceFeeShares;
        uint256 managementFeeShares;
        // Note: the fee assets is subtracted from the total assets in the fee shares calculation to compensate for the
        // fact that total assets is already increased by the total interest (including the fee assets).
        // Note: `feeAssets` may be rounded down to 0 if `totalInterest * fee < WAD`.
        if (interest > 0 && performanceFee != 0) {
            // Note: the accrued performance fee might be smaller than this because of the management fee.
            uint256 performanceFeeAssets = interest.mulDivDown(performanceFee, WAD);
            performanceFeeShares =
                performanceFeeAssets.mulDivDown(totalSupply + 1, newTotalAssets + 1 - performanceFeeAssets);
        }
        if (managementFee != 0) {
            // Note: The vault must be pinged at least once every 20 years to avoid management fees exceeding total
            // assets and revert forever.
            // Note: The management fee is taken on newTotalAssets to make all approximations consistent (interacting
            // less increases management fees).
            uint256 managementFeeAssets = (newTotalAssets * elapsed).mulDivDown(managementFee, WAD);
            managementFeeShares = managementFeeAssets.mulDivDown(
                totalSupply + 1 + performanceFeeShares, newTotalAssets + 1 - managementFeeAssets
            );
        }
        return (newTotalAssets, performanceFeeShares, managementFeeShares);
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = accrueInterestView();
        uint256 newTotalSupply = totalSupply + performanceFeeShares + managementFeeShares;
        return assets.mulDivDown(newTotalSupply + 1, newTotalAssets + 1);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = accrueInterestView();
        uint256 newTotalSupply = totalSupply + performanceFeeShares + managementFeeShares;
        return assets.mulDivUp(newTotalSupply + 1, newTotalAssets + 1);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = accrueInterestView();
        uint256 newTotalSupply = totalSupply + performanceFeeShares + managementFeeShares;
        return shares.mulDivUp(newTotalAssets + 1, newTotalSupply + 1);
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = accrueInterestView();
        uint256 newTotalSupply = totalSupply + performanceFeeShares + managementFeeShares;
        return shares.mulDivDown(newTotalAssets + 1, newTotalSupply + 1);
    }

    /* USER VAULT INTERACTIONS */

    function deposit(uint256 assets, address receiver) external returns (uint256) {
        accrueInterest();
        uint256 shares = previewDeposit(assets);
        enter(assets, shares, receiver);
        return shares;
    }

    function mint(uint256 shares, address receiver) external returns (uint256) {
        accrueInterest();
        uint256 assets = previewMint(shares);
        enter(assets, shares, receiver);
        return assets;
    }

    function enter(uint256 assets, uint256 shares, address receiver) internal {
        SafeERC20Lib.safeTransferFrom(asset, msg.sender, address(this), assets);
        createShares(receiver, shares);
        totalAssets += assets;
        if (liquidityAdapter != address(0)) {
            try this.reallocateFromIdle(liquidityAdapter, liquidityData, assets) {} catch {}
        }
        emit EventsLib.Deposit(msg.sender, receiver, assets, shares);
    }

    function withdraw(uint256 assets, address receiver, address onBehalf) public returns (uint256) {
        accrueInterest();
        uint256 shares = previewWithdraw(assets);
        exit(assets, shares, receiver, onBehalf);
        return shares;
    }

    function redeem(uint256 shares, address receiver, address onBehalf) external returns (uint256) {
        accrueInterest();
        uint256 assets = previewRedeem(shares);
        exit(assets, shares, receiver, onBehalf);
        return assets;
    }

    function exit(uint256 assets, uint256 shares, address receiver, address onBehalf) internal {
        uint256 idleAssets = IERC20(asset).balanceOf(address(this));
        if (assets > idleAssets && liquidityAdapter != address(0)) {
            this.reallocateToIdle(liquidityAdapter, liquidityData, assets - idleAssets);
        }

        if (msg.sender != onBehalf) {
            uint256 _allowance = allowance[onBehalf][msg.sender];
            if (_allowance != type(uint256).max) allowance[onBehalf][msg.sender] = _allowance - shares;
        }

        deleteShares(onBehalf, shares);
        totalAssets -= assets;

        require(noRelativeCapExceeded(), ErrorsLib.RelativeCapExceeded());

        SafeERC20Lib.safeTransfer(asset, receiver, assets);
        emit EventsLib.Withdraw(msg.sender, receiver, onBehalf, assets, shares);
    }

    /// @dev Loop to make the relative cap check at the end.
    function forceReallocateToIdle(
        address[] memory adapters,
        bytes[] memory data,
        uint256[] memory assets,
        address onBehalf
    ) external returns (uint256) {
        require(adapters.length == data.length && adapters.length == assets.length, ErrorsLib.InvalidInputLength());
        uint256 total;
        for (uint256 i; i < adapters.length; i++) {
            this.reallocateToIdle(adapters[i], data[i], assets[i]);
            total += assets[i];
        }

        // The penalty is taken as a withdrawal that is donated to the vault.
        uint256 shares = withdraw(total.mulDivDown(forceReallocateToIdlePenalty, WAD), address(this), onBehalf);
        emit EventsLib.ForceReallocateToIdle(msg.sender, onBehalf, total);
        return shares;
    }

    /* ERC20 */

    function transfer(address to, uint256 shares) external returns (bool) {
        require(to != address(0), ErrorsLib.ZeroAddress());
        balanceOf[msg.sender] -= shares;
        balanceOf[to] += shares;
        emit EventsLib.Transfer(msg.sender, to, shares);
        return true;
    }

    function transferFrom(address from, address to, uint256 shares) external returns (bool) {
        require(from != address(0), ErrorsLib.ZeroAddress());
        require(to != address(0), ErrorsLib.ZeroAddress());

        if (msg.sender != from) {
            uint256 _allowance = allowance[from][msg.sender];
            if (_allowance != type(uint256).max) {
                allowance[from][msg.sender] = _allowance - shares;
                emit EventsLib.AllowanceUpdatedByTransferFrom(from, msg.sender, _allowance - shares);
            }
        }

        balanceOf[from] -= shares;
        balanceOf[to] += shares;
        emit EventsLib.Transfer(from, to, shares);
        return true;
    }

    function approve(address spender, uint256 shares) external returns (bool) {
        allowance[msg.sender][spender] = shares;
        emit EventsLib.Approval(msg.sender, spender, shares);
        return true;
    }

    function permit(address _owner, address spender, uint256 shares, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
    {
        require(deadline >= block.timestamp, ErrorsLib.PermitDeadlineExpired());

        uint256 nonce = nonces[_owner]++;
        bytes32 hashStruct = keccak256(abi.encode(PERMIT_TYPEHASH, _owner, spender, shares, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), hashStruct));
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == _owner, ErrorsLib.InvalidSigner());

        allowance[_owner][spender] = shares;
        emit EventsLib.Approval(_owner, spender, shares);
        emit EventsLib.Permit(_owner, spender, shares, nonce, deadline);
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
    }

    function createShares(address to, uint256 shares) internal {
        require(to != address(0), ErrorsLib.ZeroAddress());
        balanceOf[to] += shares;
        totalSupply += shares;
        emit EventsLib.Transfer(address(0), to, shares);
    }

    function deleteShares(address from, uint256 shares) internal {
        require(from != address(0), ErrorsLib.ZeroAddress());
        balanceOf[from] -= shares;
        totalSupply -= shares;
        emit EventsLib.Transfer(from, address(0), shares);
    }

    // Assumes floor > 0
    // Compute ln_base(floor).
    function getIndex(uint256 floor) internal pure returns (uint256) {
        // Safe to convert from uint because floor < 2**255-1/1e18.
        // Safe to convert to uint because the input is at least WAD.
        return uint256(FixedPointMathLib.lnWad(int256(floor * WAD))) / LN_BASE_E18;
    }

    function noRelativeCapExceeded() internal view returns (bool) {
        if (root == 0) {
            return true;
        } else {
            // index of leaf with highest nonempty cap
            uint256 maxIndexInRoot = 255 - LibBit.ffs(root);

            // Cannot be 0 by invariant
            // leaves[p] == 0 iff 255-pth bit of root == 0
            uint256 leaf = leafBitmap[maxIndexInRoot];
            uint256 maxIndexInLeaf = 31 - (LibBit.ffs(leaf) / 8);

            uint256 maxIndex = (32 * maxIndexInRoot) + maxIndexInLeaf;
            uint256 totalAssetsIndex = getIndex(totalAssets);

            return maxIndex < totalAssetsIndex;
        }
    }

    function removeFloorIfNeeded(uint256 _allocation, uint256 _relativeCap) internal {
        if (_allocation > 0 && _relativeCap < WAD) {
            uint256 index = getIndex(_allocation * WAD / _relativeCap);
            uint256 indexInRoot = index / 32;
            uint256 indexInLeaf = index % 32;
            uint256 leaf = leafBitmap[indexInRoot];
            uint256 oldNumCaps = byteAt(indexInLeaf, leaf);

            if (oldNumCaps == 1) root &= ~(TOP >> indexInRoot);

            uint256 decrement = TOP >> (8 * indexInLeaf + 7);
            leafBitmap[indexInRoot] = leaf - decrement;
        }
    }

    function addFloorIfNeeded(uint256 _allocation, uint256 _relativeCap) internal {
        if (_allocation > 0 && _relativeCap < WAD) {
            uint256 index = getIndex(_allocation * WAD / _relativeCap);
            uint256 indexInRoot = index / 32;
            uint256 indexInLeaf = index % 32;
            uint256 leaf = leafBitmap[indexInRoot];
            uint256 oldNumCaps = byteAt(indexInLeaf, leaf);

            require(oldNumCaps < 255, ErrorsLib.MaximumRelativeCapsAtFloor());

            if (oldNumCaps == 0) root |= TOP >> indexInRoot;

            uint256 increment = TOP >> (8 * indexInLeaf + 7);
            leafBitmap[indexInRoot] = leaf + increment;
        }
    }

    function byteAt(uint256 pos, uint256 word) internal pure returns (uint256 b) {
        assembly {
            b := byte(pos, word)
        }
    }
}
