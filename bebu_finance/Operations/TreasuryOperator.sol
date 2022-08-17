// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../utils/interfaces/ITreasury.sol";

contract TreasuryOperator {

    function initialize(
        address treasury,
        address token,
        address share,
        address oracle,
        address boardroom,
        uint256 start_time
    ) internal {
        ITreasury(treasury).initialize(token, share, oracle, boardroom, start_time);
    }

    function doubleInitialize(
        address treasury1,
        address treasury2,

        address token1,
        address token2,

        address oracle1,
        address oracle2,

        address boardroom1,
        address boardroom2,

        address share,
        uint256 start_time
    ) external {
        initialize(treasury1, token1, share, oracle1, boardroom1, start_time);
        initialize(treasury2, token2, share, oracle2, boardroom2, start_time);
    }

    function allocate(address treasury1, address treasury2) external {
        for(int i = 0; i < 20; i++){
            ITreasury(treasury1).allocateSeigniorage();
            ITreasury(treasury2).allocateSeigniorage();
        }
    }

}