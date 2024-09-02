// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { ScriptTools }       from "lib/dss-test/src/ScriptTools.sol";
import { MainnetController } from "lib/spark-alm-controller/src/MainnetController.sol";
import { IERC20 }            from "lib/forge-std/src/interfaces/IERC20.sol";
import { Usds }              from "lib/usds/src/Usds.sol";
import { ALMProxy }          from "lib/spark-alm-controller/src/ALMProxy.sol";
import { Ethereum } from "lib/spark-address-registry/src/Ethereum.sol";


contract SetupAllMainetTest is Test {
    MainnetController mainnetController;
    ALMProxy almProxy;
    Usds usds;
    IERC20 usdc;
    address safe;

    function setUp() public {
        vm.setEnv("FOUNDRY_ROOT_CHAINID", "1");

        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        string memory output = ScriptTools.readOutput("mainnet");
        
        mainnetController = MainnetController(stdJson.readAddress(output, ".almController"));
        almProxy = ALMProxy(stdJson.readAddress(output, ".almProxy"));
        usds = Usds(stdJson.readAddress(output, ".usds"));
        safe = stdJson.readAddress(output, ".safe");
        usdc = IERC20(Ethereum.USDC);

        assertEq(usds.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(address(almProxy)), 0);

    }

    function test_permissions() view public {
        assertTrue(mainnetController.hasRole(mainnetController.RELAYER(), safe));
    }

    function test_swap_usdc() public {
        uint256 usdcValue = 1_000_000;
        uint256 expectedUsdsValue = 1e18;

        deal(address(usdc), address(almProxy), usdcValue);

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