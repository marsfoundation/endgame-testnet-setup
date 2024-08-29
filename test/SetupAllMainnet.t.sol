// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { MainnetController } from "lib/spark-alm-controller/src/MainnetController.sol";

contract SetupAllMainetTest is Test {
    MainnetController mainnetController;

    // @todo: automatically read from script output
    address public constant MAINNET_CONTROLLER_ADDRESS = 0x271647acC35113e9FEFbDcb230d8aCf4453FF876;
    address public constant SAFE_ADDRESS = 0x42dDF1269E1E1eA5D3549296B9f9A9AFcFd2bc68;

    function setUp() public {
        mainnetController = MainnetController(MAINNET_CONTROLLER_ADDRESS);
    }

    function test_permissions() view public {
        assertTrue(mainnetController.hasRole(mainnetController.RELAYER(), SAFE_ADDRESS));
    }

    function test_swap_usdc() public {
        vm.prank(SAFE_ADDRESS);

        // @todo: will require USDC balance first
        mainnetController.swapUSDCToNST(10);
    }
}