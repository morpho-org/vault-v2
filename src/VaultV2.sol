// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {IVaultV2, IERC20, Caps} from "./interfaces/IVaultV2.sol";
import {IAdapter} from "./interfaces/IAdapter.sol";
import {IAdapterRegistry} from "./interfaces/IAdapterRegistry.sol";

import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {EventsLib} from "./libraries/EventsLib.sol";
import "./libraries/ConstantsLib.sol";
import {MathLib} from "./libraries/MathLib.sol";
import {SafeERC20Lib} from "./libraries/SafeERC20Lib.sol";
import {IReceiveSharesGate, ISendSharesGate, IReceiveAssetsGate, ISendAssetsGate} from "./interfaces/IGate.sol";

/// ERC4626
/// @dev The vault is compliant with ERC-4626 and with ERC-2612 (permit extension). Though the vault has a
/// non-conventional behaviour on max functions: they always return zero.
/// @dev totalSupply is not updated to include shares minted to fee recipients. One can call accrueInterestView to
/// compute the updated totalSupply.
///
/// TOTAL ASSETS
/// @dev Adapters are responsible for reporting to the vault how much their investments are worth at any time, so that
/// the vault can accrue interest or realize losses.
/// @dev _totalAssets stores the last recorded total assets. Use totalAssets() for the updated total assets.
/// @dev Upon interest accrual, the vault loops through adapters' realAssets(). If there are too many adapters and/or
/// they consume too much gas on realAssets(), it could cause issues such as expensive interactions, even DOS.
///
/// LOSS REALIZATION
/// @dev Loss realization occurs in accrueInterest and decreases the total assets, causing shares to lose value.
/// @dev Vault shares should not be loanable to prevent shares shorting on loss realization. Shares can be flashloanable
/// because flashloan-based shorting is prevented as interests and losses are only accounted once per transaction.
///
/// SHARE PRICE
/// @dev The share price can go down if the vault incurs some losses. Users might want to perform slippage checks upon
/// withdraw/redeem via an other contract.
/// @dev Interest/loss are accounted only once per transaction (at the first interaction with the vault).
/// @dev Donations increase the share price but not faster than the maxRate.
/// @dev The vault has 1 virtual asset and a decimal offset of max(0, 18 - assetDecimals). In order to protect against
/// inflation attacks, the vault might need to be seeded with an initial deposit. See
/// https://docs.openzeppelin.com/contracts/5.x/erc4626#inflation-attack
/// @dev If they make the rate increase by a large factor, donations and forceDeallocate penalties can be in part stolen
/// by opportunistic depositors. Setting a low maxRate prevents that by making the donation/penalty distributed over a
/// long period.
///
/// CAPS
/// @dev Ids have an asset allocation, and can be absolutely capped and/or relatively capped.
/// @dev The allocation is not always up to date, because interest and losses are accounted only when (de)allocating in
/// the corresponding markets.
/// @dev The caps are checked on allocate (where allocations can increase) for the ids returned by the adapter.
/// @dev Relative caps are "soft" in the sense that they are not checked on exit.
/// @dev Caps can be exceeded because of interest.
/// @dev The relative cap is relative to firstTotalAssets, not realAssets.
/// @dev The relative cap unit is WAD.
/// @dev To track allocations using events, use the Allocate and Deallocate events only.
///
/// FIRST TOTAL ASSETS
/// @dev The variable firstTotalAssets tracks the total assets after the first interest accrual of the transaction.
/// @dev Used to implement a mechanism that prevents bypassing relative caps with flashloans. This mechanism makes the
/// caps conservative and can generate false positives, notably for big deposits that go through the liquidity adapter.
/// @dev Relative caps can still be manipulated by allocators (with short-term deposits), but it requires capital.
/// @dev The behavior of firstTotalAssets is different when the vault has totalAssets=0, but it does not matter
/// internally because in this case there are no investments to cap.
///
/// ADAPTERS
/// @dev Loose specification of adapters:
/// - They must enforce that only the vault can call allocate/deallocate.
/// - They must enter/exit markets only in allocate/deallocate.
/// - They must return the right ids on allocate/deallocate. Returned ids must not repeat.
/// - After a call to deallocate, the vault must have an approval to transfer at least `assets` from the adapter.
/// - They must make it possible to make deallocate possible (for in-kind redemptions).
/// - The totalAssets() calculation ignores markets for which the vault has no allocation.
/// - They must not re-enter (directly or indirectly) the vault. They might not statically prevent it, but the curator
/// must not interact with markets that can re-enter the vault.
/// - After an update, the sum of the changes returned after interactions with a given market must be exactly the
/// current estimate position.
/// @dev Ids being reused are useful to cap multiple investments that have a common property.
/// @dev Allocating is prevented if one of the ids' absolute cap is zero and deallocating is prevented if the id's
/// allocation is zero. This prevents interactions with zero assets with unknown markets. For markets that share all
/// their ids, it will be impossible to "disable" them (preventing any interaction) without disabling the others using
/// the same ids.
/// @dev On allocate or deallocate, the adapters might lose some assets (total realAssets decreases), for instance due
/// to roundings or entry/exit fees. This loss should stay negligible compared to gas. Adapters might not statically
/// ensure this, but the curators should not interact with markets that can create big entry/exit losses.
/// @dev Except particular scenarios, adapters should be removed only if they have no assets. In order to ensure no
/// allocator can allocate some assets in an adapter being removed, there should be an id exclusive to the adapter with
/// its cap set to zero.
///
/// ADAPTER REGISTRY
/// @dev An adapter registry can be added to restrict the adapters. This is useful to commit to using only a certain
/// type of adapters for example.
/// @dev If adapterRegistry is set to address(0), the vault can have any adapters.
/// @dev When an adapterRegistry is set, it retroactively checks already added adapters.
/// @dev If the adapterRegistry now returns false for an already added adapter, it doesn't impact the vault's
/// functioning.
/// @dev The invariant that adapters of the vault are all in the registry holds only if the registry cannot remove
/// adapters (is "add only").
///
/// LIQUIDITY ADAPTER
/// @dev Liquidity is allocated to the liquidityAdapter on deposit/mint, and deallocated from the liquidityAdapter on
/// withdraw/redeem if idle assets don't cover the withdrawal.
/// @dev The liquidity adapter is useful on exit, so that exit liquidity is available in addition to the idle assets. But
/// the same adapter/data is used for both entry and exit to have the property that in the general case looping
/// supply-withdraw or withdraw-supply should not change the allocation.
/// @dev If a cap (absolute or relative) associated with the ids returned by the liquidity adapter on the liquidity data
/// is reached, deposit/mint will revert.
///
/// TOKEN REQUIREMENTS
/// @dev List of assumptions on the token that guarantees that the vault behaves as expected:
/// - It should be ERC-20 compliant, except that it can omit return values on transfer and transferFrom.
/// - The balance of the vault should only decrease on transfer and transferFrom.
/// - It should not re-enter the vault on transfer or transferFrom.
/// - The balance of the sender (resp. receiver) should decrease (resp. increase) by exactly the given amount on
/// transfer and transferFrom. In particular, tokens with fees on transfer are not supported.
///
/// LIVENESS REQUIREMENTS
/// @dev List of assumptions that guarantees the vault's liveness properties:
/// - Adapters should not revert on realAssets.
/// - The token should not revert on transfer and transferFrom if balances and approvals are right.
/// - The token should not revert on transfer to self.
/// - totalAssets and totalSupply must stay below ~10^35. Initially there are min(1, 10^(18-decimals)) shares per asset.
/// - The vault is pinged at least every 10 years.
/// - Adapters must not revert on deallocate if the underlying markets are liquid.
///
/// TIMELOCKS
/// @dev The timelock of decreaseTimelock is initially set to TIMELOCK_CAP, and can only be changed to type(uint256).max
/// through abdicateSubmit.
/// @dev Multiple clashing data can be pending, for example increaseCap and decreaseCap, which can make so accepted
/// timelocked data can potentially be changed shortly afterwards.
/// @dev The minimum time in which a function can be called is the following:
/// min(
///     timelock[selector],
///     executableAt[selector::_],
///     executableAt[decreaseTimelock::selector::newTimelock] + newTimelock
/// ).
/// @dev Nothing is checked on the timelocked data, so it could be not executable (function does not exist, argument
/// encoding is wrong, function' conditions are not met, etc.).
///
/// GATES
/// @dev Set to 0 to disable a gate.
/// @dev Gates must never revert, nor consume too much gas.
/// @dev receiveSharesGate:
///     - Gates receiving shares.
///     - Can lock users out of getting back their shares deposited on an other contract.
/// @dev sendSharesGate:
///     - Gates sending shares.
///     - Can lock users out of exiting the vault.
/// @dev receiveAssetsGate:
///     - Gates withdrawing assets from the vault.
///     - The vault itself (address(this)) is always allowed to receive assets, regardless of the gate configuration.
///     - Can lock users out of exiting the vault.
/// @dev sendAssetsGate:
///     - Gates depositing assets to the vault.
///     - This gate is not critical (cannot block users' funds), while still being able to gate supplies.
///
/// FEES
/// @dev Fees unit is WAD.
/// @dev This invariant holds for both fees: fee != 0 => recipient != address(0).
///
/// ROLES
/// @dev The owner cannot do actions that can directly hurt depositors. Though it can set the curator and sentinels.
/// @dev The curator cannot do actions that can directly hurt depositors without going through a timelock.
/// @dev Allocators can move funds between markets in the boundaries set by caps without going through timelocks. They
/// can also set the liquidity adapter and data, which can prevent deposits and/or withdrawals (it cannot prevent
/// "in-kind redemptions" with forceDeallocate though). Allocators also set the maxRate.
/// @dev Warning: if setIsAllocator is timelocked, removing an allocator will take time.
/// @dev Roles are not "two-step", so anyone can give a role to anyone, but it does not mean that they will exercise it.
///
/// MISC
/// @dev Zero checks are not systematically performed.
/// @dev No-ops are allowed.
/// @dev NatSpec comments are included only when they bring clarity.
/// @dev The contract uses transient storage.
/// @dev At creation, all settings are set to their default values. Notably, timelocks are zero (except the
/// decreaseTimelock timelock) which is useful to set up the vault quickly. Also, there are no gates so anybody can
/// interact with the vault. To prevent that, the gates configuration can be batched with the vault creation.
contract VaultV2 is IVaultV2 {
    using MathLib for uint256;
    using MathLib for uint128;
    using MathLib for int256;

    /* IMMUTABLE */

    address public immutable asset;
    uint8 public immutable decimals;
    uint256 public immutable virtualShares;

    /* ROLES STORAGE */

    address public owner;
    address public curator;
    address public receiveSharesGate;
    address public sendSharesGate;
    address public receiveAssetsGate;
    address public sendAssetsGate;
    address public adapterRegistry;
    mapping(address account => bool) public isSentinel;
    mapping(address account => bool) public isAllocator;

    /* TOKEN STORAGE */

    string public name;
    string public symbol;
    uint256 public totalSupply;
    mapping(address account => uint256) public balanceOf;
    mapping(address owner => mapping(address spender => uint256)) public allowance;
    mapping(address account => uint256) public nonces;

    /* INTEREST STORAGE */

    uint256 public transient firstTotalAssets;
    uint128 public _totalAssets;
    uint64 public lastUpdate;
    uint64 public maxRate;

    /* CURATION STORAGE */

    mapping(address account => bool) public isAdapter;
    address[] public adapters;
    mapping(bytes32 id => Caps) internal caps;
    mapping(address adapter => uint256) public forceDeallocatePenalty;

    /* LIQUIDITY ADAPTER STORAGE */

    address public liquidityAdapter;
    bytes public liquidityData;

    /* TIMELOCKS STORAGE */

    mapping(bytes4 selector => uint256) public timelock;
    mapping(bytes data => uint256) public executableAt;

    /* FEES STORAGE */

    uint96 public performanceFee;
    address public performanceFeeRecipient;
    uint96 public managementFee;
    address public managementFeeRecipient;

    /* GETTERS */

    function adaptersLength() external view returns (uint256) {
        return adapters.length;
    }

    function totalAssets() external view returns (uint256) {
        (uint256 newTotalAssets,,) = accrueInterestView();
        return newTotalAssets;
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
    }

    function absoluteCap(bytes32 id) external view returns (uint256) {
        return caps[id].absoluteCap;
    }

    function relativeCap(bytes32 id) external view returns (uint256) {
        return caps[id].relativeCap;
    }

    function allocation(bytes32 id) external view returns (uint256) {
        return caps[id].allocation;
    }

    /* MULTICALL */

    /// @dev Useful for EOAs to batch admin calls.
    /// @dev Does not return anything, because accounts who would use the return data would be contracts, which can do
    /// the multicall themselves.
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
        lastUpdate = uint64(block.timestamp);
        uint256 assetDecimals = IERC20(_asset).decimals();
        uint256 decimalOffset = uint256(18).zeroFloorSub(assetDecimals);
        decimals = uint8(assetDecimals + decimalOffset);
        virtualShares = 10 ** decimalOffset;
        timelock[IVaultV2.decreaseTimelock.selector] = TIMELOCK_CAP;
        emit EventsLib.Constructor(_owner, _asset);
    }

    /* OWNER FUNCTIONS */

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

    function setName(string memory newName) external {
        require(msg.sender == owner, ErrorsLib.Unauthorized());
        name = newName;
        emit EventsLib.SetName(newName);
    }

    function setSymbol(string memory newSymbol) external {
        require(msg.sender == owner, ErrorsLib.Unauthorized());
        symbol = newSymbol;
        emit EventsLib.SetSymbol(newSymbol);
    }

    /* TIMELOCKS FOR CURATOR FUNCTIONS */

    function submit(bytes calldata data) external {
        bytes4 selector = bytes4(data);
        require(msg.sender == curator, ErrorsLib.Unauthorized());
        require(executableAt[data] == 0, ErrorsLib.DataAlreadyPending());
        require(timelock[selector] != type(uint256).max, ErrorsLib.Abdicated());

        executableAt[data] = block.timestamp + timelock[selector];
        emit EventsLib.Submit(selector, data, executableAt[data]);
    }

    function timelocked() internal {
        require(executableAt[msg.data] != 0, ErrorsLib.DataNotTimelocked());
        require(block.timestamp >= executableAt[msg.data], ErrorsLib.TimelockNotExpired());
        executableAt[msg.data] = 0;
        emit EventsLib.Accept(bytes4(msg.data), msg.data);
    }

    function revoke(bytes calldata data) external {
        require(msg.sender == curator || isSentinel[msg.sender], ErrorsLib.Unauthorized());
        require(executableAt[data] != 0, ErrorsLib.DataNotTimelocked());
        executableAt[data] = 0;
        emit EventsLib.Revoke(msg.sender, bytes4(data), data);
    }

    /* CURATOR FUNCTIONS */

    function setIsAllocator(address account, bool newIsAllocator) external {
        timelocked();
        isAllocator[account] = newIsAllocator;
        emit EventsLib.SetIsAllocator(account, newIsAllocator);
    }

    function setReceiveSharesGate(address newReceiveSharesGate) external {
        timelocked();
        receiveSharesGate = newReceiveSharesGate;
        emit EventsLib.SetReceiveSharesGate(newReceiveSharesGate);
    }

    function setSendSharesGate(address newSendSharesGate) external {
        timelocked();
        sendSharesGate = newSendSharesGate;
        emit EventsLib.SetSendSharesGate(newSendSharesGate);
    }

    function setReceiveAssetsGate(address newReceiveAssetsGate) external {
        timelocked();
        receiveAssetsGate = newReceiveAssetsGate;
        emit EventsLib.SetReceiveAssetsGate(newReceiveAssetsGate);
    }

    function setSendAssetsGate(address newSendAssetsGate) external {
        timelocked();
        sendAssetsGate = newSendAssetsGate;
        emit EventsLib.SetSendAssetsGate(newSendAssetsGate);
    }

    /// @dev The no-op will revert if the registry now returns false for an already added adapter.
    function setAdapterRegistry(address newAdapterRegistry) external {
        timelocked();

        if (newAdapterRegistry != address(0)) {
            for (uint256 i = 0; i < adapters.length; i++) {
                require(
                    IAdapterRegistry(newAdapterRegistry).isInRegistry(adapters[i]), ErrorsLib.NotInAdapterRegistry()
                );
            }
        }

        adapterRegistry = newAdapterRegistry;
        emit EventsLib.SetAdapterRegistry(newAdapterRegistry);
    }

    function addAdapter(address account) external {
        timelocked();
        require(
            adapterRegistry == address(0) || IAdapterRegistry(adapterRegistry).isInRegistry(account),
            ErrorsLib.NotInAdapterRegistry()
        );
        if (!isAdapter[account]) {
            adapters.push(account);
            isAdapter[account] = true;
        }
        emit EventsLib.AddAdapter(account);
    }

    function removeAdapter(address account) external {
        timelocked();
        if (isAdapter[account]) {
            for (uint256 i = 0; i < adapters.length; i++) {
                if (adapters[i] == account) {
                    adapters[i] = adapters[adapters.length - 1];
                    adapters.pop();
                    break;
                }
            }
            isAdapter[account] = false;
        }
        emit EventsLib.RemoveAdapter(account);
    }

    function increaseTimelock(bytes4 selector, uint256 newDuration) external {
        require(msg.sender == curator, ErrorsLib.Unauthorized());
        require(newDuration <= TIMELOCK_CAP, ErrorsLib.TimelockDurationTooHigh());
        require(newDuration >= timelock[selector], ErrorsLib.TimelockNotIncreasing());

        timelock[selector] = newDuration;
        emit EventsLib.IncreaseTimelock(selector, newDuration);
    }

    /// @dev Irreversibly disable submit for a selector.
    /// @dev Be particularly careful as this action is not reversible.
    /// @dev Existing timelocked operations submitted before abdicating the selector can still be executed. The
    /// abdication of a selector only prevents future operations to be submitted.
    function abdicateSubmit(bytes4 selector) external {
        timelocked();
        timelock[selector] = type(uint256).max;
        emit EventsLib.AbdicateSubmit(selector);
    }

    function decreaseTimelock(bytes4 selector, uint256 newDuration) external {
        timelocked();
        require(selector != IVaultV2.decreaseTimelock.selector, ErrorsLib.TimelockCapIsFixed());
        require(timelock[selector] != type(uint256).max, ErrorsLib.Abdicated());
        require(newDuration <= timelock[selector], ErrorsLib.TimelockNotDecreasing());

        timelock[selector] = newDuration;
        emit EventsLib.DecreaseTimelock(selector, newDuration);
    }

    function setPerformanceFee(uint256 newPerformanceFee) external {
        timelocked();
        require(newPerformanceFee <= MAX_PERFORMANCE_FEE, ErrorsLib.FeeTooHigh());
        require(performanceFeeRecipient != address(0) || newPerformanceFee == 0, ErrorsLib.FeeInvariantBroken());

        accrueInterest();

        // Safe because 2**96 > MAX_PERFORMANCE_FEE.
        performanceFee = uint96(newPerformanceFee);
        emit EventsLib.SetPerformanceFee(newPerformanceFee);
    }

    function setManagementFee(uint256 newManagementFee) external {
        timelocked();
        require(newManagementFee <= MAX_MANAGEMENT_FEE, ErrorsLib.FeeTooHigh());
        require(managementFeeRecipient != address(0) || newManagementFee == 0, ErrorsLib.FeeInvariantBroken());

        accrueInterest();

        // Safe because 2**96 > MAX_MANAGEMENT_FEE.
        managementFee = uint96(newManagementFee);
        emit EventsLib.SetManagementFee(newManagementFee);
    }

    function setPerformanceFeeRecipient(address newPerformanceFeeRecipient) external {
        timelocked();
        require(newPerformanceFeeRecipient != address(0) || performanceFee == 0, ErrorsLib.FeeInvariantBroken());

        accrueInterest();

        performanceFeeRecipient = newPerformanceFeeRecipient;
        emit EventsLib.SetPerformanceFeeRecipient(newPerformanceFeeRecipient);
    }

    function setManagementFeeRecipient(address newManagementFeeRecipient) external {
        timelocked();
        require(newManagementFeeRecipient != address(0) || managementFee == 0, ErrorsLib.FeeInvariantBroken());

        accrueInterest();

        managementFeeRecipient = newManagementFeeRecipient;
        emit EventsLib.SetManagementFeeRecipient(newManagementFeeRecipient);
    }

    function increaseAbsoluteCap(bytes memory idData, uint256 newAbsoluteCap) external {
        timelocked();
        bytes32 id = keccak256(idData);
        require(newAbsoluteCap >= caps[id].absoluteCap, ErrorsLib.AbsoluteCapNotIncreasing());

        caps[id].absoluteCap = newAbsoluteCap.toUint128();
        emit EventsLib.IncreaseAbsoluteCap(id, idData, newAbsoluteCap);
    }

    function decreaseAbsoluteCap(bytes memory idData, uint256 newAbsoluteCap) external {
        bytes32 id = keccak256(idData);
        require(msg.sender == curator || isSentinel[msg.sender], ErrorsLib.Unauthorized());
        require(newAbsoluteCap <= caps[id].absoluteCap, ErrorsLib.AbsoluteCapNotDecreasing());

        // Safe because newAbsoluteCap <= absoluteCap < 2**128.
        caps[id].absoluteCap = uint128(newAbsoluteCap);
        emit EventsLib.DecreaseAbsoluteCap(msg.sender, id, idData, newAbsoluteCap);
    }

    function increaseRelativeCap(bytes memory idData, uint256 newRelativeCap) external {
        timelocked();
        bytes32 id = keccak256(idData);
        require(newRelativeCap <= WAD, ErrorsLib.RelativeCapAboveOne());
        require(newRelativeCap >= caps[id].relativeCap, ErrorsLib.RelativeCapNotIncreasing());

        // Safe because WAD < 2**128.
        caps[id].relativeCap = uint128(newRelativeCap);
        emit EventsLib.IncreaseRelativeCap(id, idData, newRelativeCap);
    }

    function decreaseRelativeCap(bytes memory idData, uint256 newRelativeCap) external {
        bytes32 id = keccak256(idData);
        require(msg.sender == curator || isSentinel[msg.sender], ErrorsLib.Unauthorized());
        require(newRelativeCap <= caps[id].relativeCap, ErrorsLib.RelativeCapNotDecreasing());

        // Safe because WAD < 2**128.
        caps[id].relativeCap = uint128(newRelativeCap);
        emit EventsLib.DecreaseRelativeCap(msg.sender, id, idData, newRelativeCap);
    }

    function setForceDeallocatePenalty(address adapter, uint256 newForceDeallocatePenalty) external {
        timelocked();
        require(newForceDeallocatePenalty <= MAX_FORCE_DEALLOCATE_PENALTY, ErrorsLib.PenaltyTooHigh());
        forceDeallocatePenalty[adapter] = newForceDeallocatePenalty;
        emit EventsLib.SetForceDeallocatePenalty(adapter, newForceDeallocatePenalty);
    }

    /* ALLOCATOR FUNCTIONS */

    function allocate(address adapter, bytes memory data, uint256 assets) external {
        require(isAllocator[msg.sender], ErrorsLib.Unauthorized());
        allocateInternal(adapter, data, assets);
    }

    function allocateInternal(address adapter, bytes memory data, uint256 assets) internal {
        require(isAdapter[adapter], ErrorsLib.NotAdapter());

        accrueInterest();

        SafeERC20Lib.safeTransfer(asset, adapter, assets);
        (bytes32[] memory ids, int256 change) = IAdapter(adapter).allocate(data, assets, msg.sig, msg.sender);

        for (uint256 i; i < ids.length; i++) {
            Caps storage _caps = caps[ids[i]];
            _caps.allocation = (int256(_caps.allocation) + change).toUint256();

            require(_caps.absoluteCap > 0, ErrorsLib.ZeroAbsoluteCap());
            require(_caps.allocation <= _caps.absoluteCap, ErrorsLib.AbsoluteCapExceeded());
            require(
                _caps.relativeCap == WAD || _caps.allocation <= firstTotalAssets.mulDivDown(_caps.relativeCap, WAD),
                ErrorsLib.RelativeCapExceeded()
            );
        }
        emit EventsLib.Allocate(msg.sender, adapter, assets, ids, change);
    }

    function deallocate(address adapter, bytes memory data, uint256 assets) external {
        require(isAllocator[msg.sender] || isSentinel[msg.sender], ErrorsLib.Unauthorized());
        deallocateInternal(adapter, data, assets);
    }

    function deallocateInternal(address adapter, bytes memory data, uint256 assets)
        internal
        returns (bytes32[] memory)
    {
        require(isAdapter[adapter], ErrorsLib.NotAdapter());

        (bytes32[] memory ids, int256 change) = IAdapter(adapter).deallocate(data, assets, msg.sig, msg.sender);

        for (uint256 i; i < ids.length; i++) {
            Caps storage _caps = caps[ids[i]];
            require(_caps.allocation > 0, ErrorsLib.ZeroAllocation());
            _caps.allocation = (int256(_caps.allocation) + change).toUint256();
        }

        SafeERC20Lib.safeTransferFrom(asset, adapter, address(this), assets);
        emit EventsLib.Deallocate(msg.sender, adapter, assets, ids, change);
        return ids;
    }

    /// @dev Whether newLiquidityAdapter is an adapter is checked in allocate/deallocate.
    function setLiquidityAdapterAndData(address newLiquidityAdapter, bytes memory newLiquidityData) external {
        require(isAllocator[msg.sender], ErrorsLib.Unauthorized());
        liquidityAdapter = newLiquidityAdapter;
        liquidityData = newLiquidityData;
        emit EventsLib.SetLiquidityAdapterAndData(msg.sender, newLiquidityAdapter, newLiquidityData);
    }

    function setMaxRate(uint256 newMaxRate) external {
        require(isAllocator[msg.sender], ErrorsLib.Unauthorized());
        require(newMaxRate <= MAX_MAX_RATE, ErrorsLib.MaxRateTooHigh());

        accrueInterest();

        // Safe because newMaxRate <= MAX_MAX_RATE < 2**64-1.
        maxRate = uint64(newMaxRate);
        emit EventsLib.SetMaxRate(newMaxRate);
    }

    /* EXCHANGE RATE FUNCTIONS */

    function accrueInterest() public {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = accrueInterestView();
        emit EventsLib.AccrueInterest(_totalAssets, newTotalAssets, performanceFeeShares, managementFeeShares);
        _totalAssets = newTotalAssets.toUint128();
        if (firstTotalAssets == 0) firstTotalAssets = newTotalAssets;
        if (performanceFeeShares != 0) createShares(performanceFeeRecipient, performanceFeeShares);
        if (managementFeeShares != 0) createShares(managementFeeRecipient, managementFeeShares);
        lastUpdate = uint64(block.timestamp);
    }

    /// @dev Returns newTotalAssets, performanceFeeShares, managementFeeShares.
    /// @dev The management fee is not bound to the interest, so it can make the share price go down.
    /// @dev The management fees is taken even if the vault incurs some losses.
    /// @dev Both fees are rounded down, so fee recipients could receive less than expected.
    /// @dev The performance fee is taken on the "distributed interest" (which differs from the "real interest" because
    /// of the max rate).
    function accrueInterestView() public view returns (uint256, uint256, uint256) {
        if (firstTotalAssets != 0) return (_totalAssets, 0, 0);
        uint256 elapsed = block.timestamp - lastUpdate;
        uint256 realAssets = IERC20(asset).balanceOf(address(this));
        for (uint256 i = 0; i < adapters.length; i++) {
            realAssets += IAdapter(adapters[i]).realAssets();
        }
        uint256 maxTotalAssets = _totalAssets + (_totalAssets * elapsed).mulDivDown(maxRate, WAD);
        uint256 newTotalAssets = MathLib.min(realAssets, maxTotalAssets);
        uint256 interest = newTotalAssets.zeroFloorSub(_totalAssets);

        // The performance fee assets may be rounded down to 0 if interest * fee < WAD.
        uint256 performanceFeeAssets = interest > 0 && performanceFee > 0 && canReceiveShares(performanceFeeRecipient)
            ? interest.mulDivDown(performanceFee, WAD)
            : 0;
        // The management fee is taken on newTotalAssets to make all approximations consistent (interacting less
        // increases fees).
        uint256 managementFeeAssets = elapsed > 0 && managementFee > 0 && canReceiveShares(managementFeeRecipient)
            ? (newTotalAssets * elapsed).mulDivDown(managementFee, WAD)
            : 0;

        // Interest should be accrued at least every 10 years to avoid fees exceeding total assets.
        uint256 newTotalAssetsWithoutFees = newTotalAssets - performanceFeeAssets - managementFeeAssets;
        uint256 performanceFeeShares =
            performanceFeeAssets.mulDivDown(totalSupply + virtualShares, newTotalAssetsWithoutFees + 1);
        uint256 managementFeeShares =
            managementFeeAssets.mulDivDown(totalSupply + virtualShares, newTotalAssetsWithoutFees + 1);

        return (newTotalAssets, performanceFeeShares, managementFeeShares);
    }

    /// @dev Returns previewed minted shares.
    function previewDeposit(uint256 assets) public view returns (uint256) {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = accrueInterestView();
        uint256 newTotalSupply = totalSupply + performanceFeeShares + managementFeeShares;
        return assets.mulDivDown(newTotalSupply + virtualShares, newTotalAssets + 1);
    }

    /// @dev Returns previewed deposited assets.
    function previewMint(uint256 shares) public view returns (uint256) {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = accrueInterestView();
        uint256 newTotalSupply = totalSupply + performanceFeeShares + managementFeeShares;
        return shares.mulDivUp(newTotalAssets + 1, newTotalSupply + virtualShares);
    }

    /// @dev Returns previewed redeemed shares.
    function previewWithdraw(uint256 assets) public view returns (uint256) {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = accrueInterestView();
        uint256 newTotalSupply = totalSupply + performanceFeeShares + managementFeeShares;
        return assets.mulDivUp(newTotalSupply + virtualShares, newTotalAssets + 1);
    }

    /// @dev Returns previewed withdrawn assets.
    function previewRedeem(uint256 shares) public view returns (uint256) {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = accrueInterestView();
        uint256 newTotalSupply = totalSupply + performanceFeeShares + managementFeeShares;
        return shares.mulDivDown(newTotalAssets + 1, newTotalSupply + virtualShares);
    }

    /// @dev Returns corresponding shares (rounded down).
    /// @dev Takes into account performance and management fees.
    function convertToShares(uint256 assets) external view returns (uint256) {
        return previewDeposit(assets);
    }

    /// @dev Returns corresponding assets (rounded down).
    /// @dev Takes into account performance and management fees.
    function convertToAssets(uint256 shares) external view returns (uint256) {
        return previewRedeem(shares);
    }

    /* MAX FUNCTIONS */

    /// @dev Gross underestimation because being revert-free cannot be guaranteed when calling the gate.
    function maxDeposit(address) external pure returns (uint256) {
        return 0;
    }

    /// @dev Gross underestimation because being revert-free cannot be guaranteed when calling the gate.
    function maxMint(address) external pure returns (uint256) {
        return 0;
    }

    /// @dev Gross underestimation because being revert-free cannot be guaranteed when calling the gate.
    function maxWithdraw(address) external pure returns (uint256) {
        return 0;
    }

    /// @dev Gross underestimation because being revert-free cannot be guaranteed when calling the gate.
    function maxRedeem(address) external pure returns (uint256) {
        return 0;
    }

    /* USER MAIN FUNCTIONS */

    /// @dev Returns minted shares.
    function deposit(uint256 assets, address onBehalf) external returns (uint256) {
        accrueInterest();
        uint256 shares = previewDeposit(assets);
        enter(assets, shares, onBehalf);
        return shares;
    }

    /// @dev Returns deposited assets.
    function mint(uint256 shares, address onBehalf) external returns (uint256) {
        accrueInterest();
        uint256 assets = previewMint(shares);
        enter(assets, shares, onBehalf);
        return assets;
    }

    /// @dev Internal function for deposit and mint.
    function enter(uint256 assets, uint256 shares, address onBehalf) internal {
        require(canReceiveShares(onBehalf), ErrorsLib.CannotReceiveShares());
        require(canSendAssets(msg.sender), ErrorsLib.CannotSendAssets());

        SafeERC20Lib.safeTransferFrom(asset, msg.sender, address(this), assets);
        createShares(onBehalf, shares);
        _totalAssets += assets.toUint128();
        emit EventsLib.Deposit(msg.sender, onBehalf, assets, shares);

        if (liquidityAdapter != address(0)) allocateInternal(liquidityAdapter, liquidityData, assets);
    }

    /// @dev Returns redeemed shares.
    function withdraw(uint256 assets, address receiver, address onBehalf) public returns (uint256) {
        accrueInterest();
        uint256 shares = previewWithdraw(assets);
        exit(assets, shares, receiver, onBehalf);
        return shares;
    }

    /// @dev Returns withdrawn assets.
    function redeem(uint256 shares, address receiver, address onBehalf) external returns (uint256) {
        accrueInterest();
        uint256 assets = previewRedeem(shares);
        exit(assets, shares, receiver, onBehalf);
        return assets;
    }

    /// @dev Internal function for withdraw and redeem.
    function exit(uint256 assets, uint256 shares, address receiver, address onBehalf) internal {
        require(canSendShares(onBehalf), ErrorsLib.CannotSendShares());
        require(canReceiveAssets(receiver), ErrorsLib.CannotReceiveAssets());

        uint256 idleAssets = IERC20(asset).balanceOf(address(this));
        if (assets > idleAssets && liquidityAdapter != address(0)) {
            deallocateInternal(liquidityAdapter, liquidityData, assets - idleAssets);
        }

        if (msg.sender != onBehalf) {
            uint256 _allowance = allowance[onBehalf][msg.sender];
            if (_allowance != type(uint256).max) allowance[onBehalf][msg.sender] = _allowance - shares;
        }

        deleteShares(onBehalf, shares);
        _totalAssets -= assets.toUint128();
        SafeERC20Lib.safeTransfer(asset, receiver, assets);
        emit EventsLib.Withdraw(msg.sender, receiver, onBehalf, assets, shares);
    }

    /// @dev Returns shares withdrawn as penalty.
    /// @dev When calling this function, a penalty is taken from onBehalf, in order to discourage allocation
    /// manipulations.
    /// @dev The penalty is taken as a withdrawal for which assets are returned to the vault. In consequence,
    /// totalAssets is decreased normally along with totalSupply (the share price doesn't change except because of
    /// rounding errors), but the amount of assets actually controlled by the vault is not decreased.
    /// @dev If a user has A assets in the vault, and that the vault is already fully illiquid, the optimal amount to
    /// force deallocate in order to exit the vault is min(liquidity_of_market, A / (1 + penalty)).
    /// This ensures that either the market is empty or that it leaves no shares nor liquidity after exiting.
    function forceDeallocate(address adapter, bytes memory data, uint256 assets, address onBehalf)
        external
        returns (uint256)
    {
        bytes32[] memory ids = deallocateInternal(adapter, data, assets);
        uint256 penaltyAssets = assets.mulDivUp(forceDeallocatePenalty[adapter], WAD);
        uint256 penaltyShares = withdraw(penaltyAssets, address(this), onBehalf);
        emit EventsLib.ForceDeallocate(msg.sender, adapter, assets, onBehalf, ids, penaltyAssets);
        return penaltyShares;
    }

    /* ERC20 FUNCTIONS */

    /// @dev Returns success (always true because reverts on failure).
    function transfer(address to, uint256 shares) external returns (bool) {
        require(to != address(0), ErrorsLib.ZeroAddress());

        require(canSendShares(msg.sender), ErrorsLib.CannotSendShares());
        require(canReceiveShares(to), ErrorsLib.CannotReceiveShares());

        balanceOf[msg.sender] -= shares;
        balanceOf[to] += shares;
        emit EventsLib.Transfer(msg.sender, to, shares);
        return true;
    }

    /// @dev Returns success (always true because reverts on failure).
    function transferFrom(address from, address to, uint256 shares) external returns (bool) {
        require(from != address(0), ErrorsLib.ZeroAddress());
        require(to != address(0), ErrorsLib.ZeroAddress());

        require(canSendShares(from), ErrorsLib.CannotSendShares());
        require(canReceiveShares(to), ErrorsLib.CannotReceiveShares());

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

    /// @dev Returns success (always true because reverts on failure).
    function approve(address spender, uint256 shares) external returns (bool) {
        allowance[msg.sender][spender] = shares;
        emit EventsLib.Approval(msg.sender, spender, shares);
        return true;
    }

    /// @dev Signature malleability is not explicitly prevented but it is not a problem thanks to the nonce.
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

    /* PERMISSIONED TOKEN FUNCTIONS */

    function canReceiveShares(address account) public view returns (bool) {
        return receiveSharesGate == address(0) || IReceiveSharesGate(receiveSharesGate).canReceiveShares(account);
    }

    function canSendShares(address account) public view returns (bool) {
        return sendSharesGate == address(0) || ISendSharesGate(sendSharesGate).canSendShares(account);
    }

    function canReceiveAssets(address account) public view returns (bool) {
        return account == address(this) || receiveAssetsGate == address(0)
            || IReceiveAssetsGate(receiveAssetsGate).canReceiveAssets(account);
    }

    function canSendAssets(address account) public view returns (bool) {
        return sendAssetsGate == address(0) || ISendAssetsGate(sendAssetsGate).canSendAssets(account);
    }
}
