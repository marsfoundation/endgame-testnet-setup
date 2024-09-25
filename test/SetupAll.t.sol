// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { ScriptTools } from "lib/dss-test/src/ScriptTools.sol";

import { Bridge }                from "xchain-helpers/testing/Bridge.sol";
import { Domain, DomainHelpers } from "xchain-helpers/testing/Domain.sol";
import { OptimismBridgeTesting } from "xchain-helpers/testing/bridges/OptimismBridgeTesting.sol";

import { Ethereum } from "lib/spark-address-registry/src/Ethereum.sol";

import { Usds } from "lib/usds/src/Usds.sol";
import { Sky }  from "lib/sky/src/Sky.sol";
import { SDAO } from "lib/endgame-toolkit/src/SDAO.sol";

import { MainnetController } from "lib/spark-alm-controller/src/MainnetController.sol";
import { ALMProxy }          from "lib/spark-alm-controller/src/ALMProxy.sol";

import { DssVest } from "src/DssVest.sol";

import { VestedRewardsDistribution } from "lib/endgame-toolkit/src/VestedRewardsDistribution.sol";
import { StakingRewards }            from "lib/endgame-toolkit/src/synthetix/StakingRewards.sol";

import { PSM3, IERC20 } from "lib/spark-psm/src/PSM3.sol";

contract SetupAllTest is Test {

    using stdJson for *;
    using DomainHelpers for *;

    string outputMainnet;
    string outputBase;

    Domain mainnet;
    Domain base;
    Bridge bridge;

    // Mainnet contracts
    Usds   usds;
    Sky    sky;
    SDAO   spk;
    IERC20 usdc;

    address safe;

    MainnetController mainnetController;
    ALMProxy almProxy;

    DssVest skyVest;
    DssVest spkVest;

    // Base contracts
    PSM3 psm;

    function setUp() public {
        vm.setEnv("FOUNDRY_ROOT_CHAINID", "1");

        mainnet = getChain("mainnet").createSelectFork();
        base    = getChain("base").createFork();
        bridge  = OptimismBridgeTesting.createNativeBridge(mainnet, base);
        
        outputMainnet = ScriptTools.readOutput("mainnet");
        outputBase = ScriptTools.readOutput("base");

        usds = Usds(outputMainnet.readAddress(".usds"));
        sky  = Sky(outputMainnet.readAddress(".sky"));
        spk  = SDAO(outputMainnet.readAddress(".spk"));
        usdc = IERC20(Ethereum.USDC);

        safe = outputMainnet.readAddress(".safe");
        
        mainnetController = MainnetController(outputMainnet.readAddress(".almController"));
        almProxy          = ALMProxy(outputMainnet.readAddress(".almProxy"));

        skyVest = DssVest(outputMainnet.readAddress(".skyVest"));
        spkVest = DssVest(outputMainnet.readAddress(".spkVest"));

        psm = PSM3(outputBase.readAddress(".psm"));

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

    function test_spk_usds_farm() public {
        VestedRewardsDistribution distribution = VestedRewardsDistribution(outputMainnet.readAddress(".spkUsdsFarmDistribution"));
        StakingRewards rewards = StakingRewards(outputMainnet.readAddress(".spkUsdsFarmRewards"));

        deal(address(usds), address(this), 300e18);
        usds.approve(address(rewards), 300e18);

        // Accrue a bunch of rewards (numbers dont matter that much)
        vm.warp(spkVest.bgn(1));
        rewards.stake(100e18);
        skip(7 days);
        distribution.distribute();
        skip(7 days);
        rewards.stake(100e18);
        distribution.distribute();
        skip(7 days);
        rewards.stake(100e18);
        distribution.distribute();
        skip(7 days);
        distribution.distribute();
        
        uint256 amountEarned = 2_876_712.328767123287280000e18;

        assertEq(rewards.earned(address(this)), amountEarned);
        assertEq(spk.totalSupply(),             3_835_616.438356164383561643e18);
        assertEq(usds.balanceOf(address(this)), 0);
        assertEq(spk.balanceOf(address(this)),  0);

        // Pull my rewards
        rewards.exit();
        
        assertEq(usds.balanceOf(address(this)), 300e18);
        assertEq(spk.balanceOf(address(this)),  amountEarned);
    }

    function test_base_psm() public {
        base.selectFork();

        psm = PSM3(outputBase.readAddress(".psm"));

        IERC20 usdcBase = psm.asset0();
        deal(address(usdcBase), address(this), 1e6);
        usdcBase.approve(address(psm), 1e6);
        psm.deposit(address(usdcBase), address(this), 1e6);
    }

}
