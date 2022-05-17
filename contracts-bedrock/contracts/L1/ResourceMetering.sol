// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SignedMath } from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import { SlotPacking128x64x64 } from "../libraries/SlotPacking128x64x64.sol";
import { Burn } from "../libraries/Burn.sol";

/**
 * @title ResourceMetering
 * @notice ResourceMetering implements an EIP-1559 style resource metering system where pricing
 * updates automatically based on current demand.
 */
contract ResourceMetering {
    /**
     * Along with the resource limit, determines the target resource limit.
     */
    int256 public constant ELASTICITY_MULTIPLIER = 2;

    /**
     * Denominator that determines max change on fee per block.
     */
    int256 public constant BASE_FEE_MAX_CHANGE_DENOMINATOR = 8;

    /**
     * Maximum amount of deposit gas that can be used within this block.
     */
    int256 public constant MAX_RESOURCE_LIMIT = 30000000;

    /**
     * Target amount of deposit gas that should be used within this block.
     */
    int256 public constant TARGET_RESOURCE_LIMIT = MAX_RESOURCE_LIMIT / ELASTICITY_MULTIPLIER;

    /**
     * Minimum base fee value, cannot go lower than this.
     */
    int256 public constant MINIMUM_BASE_FEE = 10000;

    /**
     * Initial base fee value.
     */
    uint128 public constant INITIAL_BASE_FEE = 1000000000;

    /**
     * EIP-1559 style gas parameters packed as follows:
     * 128 bits: prev base fee
     * 64 bits:  prev bought gas
     * 64 bits:  prev block num
     */
    bytes32 internal resources;

    /**
     * Sets the initial resource values.
     */
    constructor() {
        resources = SlotPacking128x64x64.set(INITIAL_BASE_FEE, 0, uint64(block.number));
    }

    /**
     * Meters access to a function based an amount of a requested resource.
     *
     * @param _amount Amount of the resource requested.
     */
    modifier metered(uint64 _amount) {
        // Record initial gas amount so we can refund for it later.
        uint256 initialGas = gasleft();

        // Run the underlying function.
        _;

        // Retrieve resource parameters.
        (uint128 prevBaseFee, uint64 prevBoughtGas, uint64 prevBlockNum) = getResourceParams();

        // Update block number and base fee if necessary.
        uint256 blockDiff = block.number - prevBlockNum;
        if (blockDiff > 0) {
            // Handle updating EIP-1559 style gas parameters. We use EIP-1559 to restrict the rate
            // at which deposits can be created and therefore limit the potential for deposits to
            // spam the L2 system. Fee scheme is very similar to EIP-1559 with minor changes.
            int256 gasUsedDelta = int256(uint256(prevBoughtGas)) - TARGET_RESOURCE_LIMIT;
            int256 baseFeeDelta = (int256(uint256(prevBaseFee)) * gasUsedDelta) /
                TARGET_RESOURCE_LIMIT /
                BASE_FEE_MAX_CHANGE_DENOMINATOR;

            // Clamp the value of the base fee between the minimum and maximum values.
            uint128 newBaseFee = uint128(
                uint256(
                    SignedMath.min(
                        SignedMath.max(
                            int256(uint256(prevBaseFee)) + baseFeeDelta,
                            int256(MINIMUM_BASE_FEE)
                        ),
                        int256(uint256(type(uint128).max))
                    )
                )
            );

            // If we skipped more than one block, we also need to account for every empty block.
            // Empty block means there was no demand for deposits in that block, so we should
            // reflect this lack of demand in the fee.
            if (blockDiff > 1) {
                // Repeatedly reduce newBaseFee by 7/8 of its value based on the number of skipped
                // blocks. We break this math into chunks of x=40 (at a maximum) to avoid an
                // overflow.
                // TODO: Replace with solmate's powWad when v7 is released, it's close to constant
                // gas for any value of n.
                uint256 n = blockDiff - 1;
                uint256 tempBaseFee = uint256(newBaseFee);
                for (uint256 i = 0; i < n; i += 40) {
                    // Execution is bounded by the fact that we'll eventually get down below the
                    // minimum base fee. We can stop early to avoid wasting gas.
                    if (tempBaseFee <= uint256(MINIMUM_BASE_FEE)) {
                        break;
                    }

                    uint256 x = Math.min(n - i, 40);
                    tempBaseFee = (tempBaseFee * (7**x)) / (8**x);
                }

                // Clamp new base fee value between min and max values.
                newBaseFee = uint128(
                    uint256(
                        SignedMath.min(
                            SignedMath.max(int256(tempBaseFee), int256(MINIMUM_BASE_FEE)),
                            int256(uint256(type(uint128).max))
                        )
                    )
                );
            }

            // Update new base fee, reset bought gas, and update block number.
            prevBaseFee = newBaseFee;
            prevBoughtGas = 0;
            prevBlockNum = uint64(block.number);
        }

        // Make sure we can actually buy the resource amount requested by the user.
        prevBoughtGas += _amount;
        require(
            prevBoughtGas <= uint64(uint256(MAX_RESOURCE_LIMIT)),
            "OptimismPortal: cannot buy more gas than available gas limit"
        );

        // Update resource parameters with the new amount of gas bought.
        resources = SlotPacking128x64x64.set(prevBaseFee, prevBoughtGas, prevBlockNum);

        // Determine the amount of ETH to be paid.
        uint256 resourceCost = _amount * prevBaseFee;

        // We currently charge for this ETH amount as an L1 gas burn, so we convert the ETH amount
        // into gas by dividing by the L1 base fee. We assume a minimum base fee of 1 gwei to avoid
        // division by zero for L1s that don't support 1559 or to avoid excessive gas burns during
        // periods of extremely low L1 demand. One-day average gas fee hasn't dipped below 1 gwei
        // during any 1 day period in the last 5 years, so should be fine.
        uint256 gasCost = resourceCost / Math.max(block.basefee, 1000000000);

        // Give the user a refund based on the amount of gas they used to do all of the work up to
        // this point. Since we're at the end of the modifier, this should be pretty accurate. Acts
        // effectively like a dynamic stipend (with a minimum value).
        uint256 usedGas = initialGas - gasleft();
        if (gasCost > usedGas) {
            Burn.gas(gasCost - usedGas);
        }
    }

    /**
     * Unpacks resource params.
     *
     * @return prevBaseFee
     * @return prevBoughtGas
     * @return prevBlockNum
     */
    function getResourceParams()
        public
        view
        returns (
            uint128,
            uint64,
            uint64
        )
    {
        return SlotPacking128x64x64.get(resources);
    }
}
