// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { ScriptTools }       from "lib/dss-test/src/ScriptTools.sol";
import { MainnetController } from "lib/spark-alm-controller/src/MainnetController.sol";
import { IERC20 }            from "lib/forge-std/src/interfaces/IERC20.sol";
import { Usds }              from "lib/usds/src/Usds.sol";
import { ALMProxy }          from "lib/spark-alm-controller/src/ALMProxy.sol";


contract SetupAllMainetTest is Test {
    MainnetController mainnetController;
    ALMProxy almProxy;
    Usds usds;
    address safe;

    function setUp() public {
        vm.setEnv("FOUNDRY_ROOT_CHAINID", "1");

        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        string memory output = ScriptTools.readOutput("mainnet");
        
        mainnetController = MainnetController(stdJson.readAddress(output, ".almController"));
        almProxy = ALMProxy(stdJson.readAddress(output, ".almProxy"));
        usds = Usds(stdJson.readAddress(output, ".usds"));
        safe = stdJson.readAddress(output, ".safe");
    }

    function test_permissions() view public {
        assertTrue(mainnetController.hasRole(mainnetController.RELAYER(), safe));
    }

    function test_swap_usdc() public {
        IERC20 usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        address usdc_whale = 0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa;
        uint256 usdcValue = 1_000_000;
        uint256 expectedUsdsValue = 1e18;

        vm.prank(usdc_whale);
        usdc.transfer(address(almProxy), usdcValue);

        vm.prank(safe);
        mainnetController.swapUSDCToUSDS(usdcValue);

        assertEq(usdc.balanceOf(address(almProxy)), 0);
        assertEq(usds.balanceOf(address(almProxy)), expectedUsdsValue);
    }

    function test_mintUSDS() public {
        uint256 usdsValue = 1e18;

        vm.prank(safe);
        mainnetController.mintUSDS(usdsValue);

        assertEq(usds.balanceOf(address(almProxy)), usdsValue);
    }

    function test_burn_usds() public {
        uint256 usdsValue = 1e18;
        vm.prank(safe);
        mainnetController.mintUSDS(usdsValue);
        
        vm.prank(safe);
        mainnetController.burnUSDS(usdsValue);

        assertEq(usds.balanceOf(address(almProxy)), 0);
    }
}