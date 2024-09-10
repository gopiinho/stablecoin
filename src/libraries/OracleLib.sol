// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author https://github.com/gopiinho
 * @notice This library is used to check stale data of chainlink oracles.
 * @notice If the oracle prices become stale, the function reverts and DSCEngine becomes unusable by design.
 */
library OracleLib {
    ///////////////
    /// Errors  ///
    ///////////////
    error OracleLib__StalePrice();

    ///////////////////////
    /// State Variables ///
    ///////////////////////
    uint256 private constant TIMEOUT = 3 hours;

    ///////////////
    // Functions //
    ///////////////
    function staleCheckLastRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIMEOUT) {
            revert OracleLib__StalePrice();
        }

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
