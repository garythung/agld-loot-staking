// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "abdk-libraries-solidity/ABDKMathQuad.sol";

library Math {
  // Source: https://medium.com/coinmonks/math-in-solidity-part-3-percents-and-proportions-4db014e080b1
  // Calculates x * y / z. Useful for doing percentages like Amount * Percent numerator / Percent denominator
  // Example: Calculate 1.25% of 100 ETH (aka 125 basis points): mulDiv(100e18, 125, 10000)
  function mulDiv(uint256 x, uint256 y, uint256 z) internal pure returns (uint256) {
    return ABDKMathQuad.toUInt(
      ABDKMathQuad.div(
        ABDKMathQuad.mul(
          ABDKMathQuad.fromUInt(x),
          ABDKMathQuad.fromUInt(y)
        ),
        ABDKMathQuad.fromUInt(z)
      )
    );
  }
}
