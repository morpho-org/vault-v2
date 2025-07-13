# PR: Document incentive rounding behavior in realizeLoss function

## Summary

This PR documents the fact that the incentive calculation in the `realizeLoss` function may result in zero incentive shares due to rounding down behavior.

## Problem

In the `realizeLoss` function in `VaultV2.sol`, the incentive calculation uses `mulDivDown` which rounds down to the nearest integer. This can result in zero incentive shares being awarded even when there is a loss to realize.

## Technical Details

### Current Implementation

The incentive calculation in `realizeLoss` (lines 727-730 in `VaultV2.sol`):

```solidity
uint256 tentativeIncentive = loss.mulDivDown(LOSS_REALIZATION_INCENTIVE_RATIO, WAD);
incentiveShares = tentativeIncentive.mulDivDown(
    totalSupply + virtualShares, uint256(_totalAssets).zeroFloorSub(tentativeIncentive) + 1
);
```

Where:
- `LOSS_REALIZATION_INCENTIVE_RATIO = 0.01e18` (1%)
- `WAD = 1e18`
- `mulDivDown` rounds down to the nearest integer

### Rounding Scenarios

1. **Small Loss Amounts**: When `loss * LOSS_REALIZATION_INCENTIVE_RATIO < WAD`, the first `mulDivDown` will round down to 0, resulting in zero incentive.

2. **Example**: For a loss of 1e16 (0.01 tokens), the calculation would be:
   - `tentativeIncentive = 1e16 * 0.01e18 / 1e18 = 1e14`
   - If this is less than 1, it rounds down to 0

3. **Second Rounding**: Even if the first calculation produces a non-zero result, the second `mulDivDown` operation can also round down to zero if the calculated shares are less than 1.

## Impact

- Users calling `realizeLoss` may receive no incentive shares despite successfully realizing a loss
- This behavior is deterministic and expected due to the use of `mulDivDown`
- The rounding behavior is consistent with other fee calculations in the codebase

## Recommendation

This is documented behavior and not a bug. The rounding down ensures that:
1. No more incentive shares are distributed than mathematically justified
2. The calculation remains gas-efficient
3. The behavior is consistent with other mathematical operations in the codebase

## Testing

The existing test suite covers various loss scenarios, but specific tests for edge cases with very small losses could be added to verify the rounding behavior.

## Related Code

- `src/VaultV2.sol`: Lines 714-741 (realizeLoss function)
- `src/libraries/MathLib.sol`: Lines 8-11 (mulDivDown implementation)
- `src/libraries/ConstantsLib.sol`: Lines 4, 13 (WAD and LOSS_REALIZATION_INCENTIVE_RATIO constants)