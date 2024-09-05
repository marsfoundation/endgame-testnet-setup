// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { ScriptTools } from "lib/dss-test/src/ScriptTools.sol";

import { Ethereum } from "lib/spark-address-registry/src/Ethereum.sol";

import { IERC20 }      from "lib/forge-std/src/interfaces/IERC20.sol";

import { Usds } from "lib/usds/src/Usds.sol";
import { Sky }  from "lib/sky/src/Sky.sol";
import { SDAO } from "lib/endgame-toolkit/src/SDAO.sol";

import { MainnetController } from "lib/spark-alm-controller/src/MainnetController.sol";
import { ALMProxy }          from "lib/spark-alm-controller/src/ALMProxy.sol";

import { DssVest } from "src/DssVest.sol";

import { VestedRewardsDistribution } from "lib/endgame-toolkit/src/VestedRewardsDistribution.sol";
import { StakingRewards }            from "lib/endgame-toolkit/src/synthetix/StakingRewards.sol";

contract SetupAllMainetTest is Test {

    using stdJson for *;

    string output;

    Usds   usds;
    Sky    sky;
    SDAO   spk;
    IERC20 usdc;

    address safe;

    MainnetController mainnetController;
    ALMProxy almProxy;

    DssVest skyVest;
    DssVest spkVest;

    function setUp() public {
        vm.setEnv("FOUNDRY_ROOT_CHAINID", "1");

        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        output = ScriptTools.readOutput("mainnet");

        usds = Usds(output.readAddress(".usds"));
        sky  = Sky(output.readAddress(".sky"));
        spk  = SDAO(output.readAddress(".spk"));
        usdc = IERC20(Ethereum.USDC);

        safe = output.readAddress(".safe");
        
        mainnetController = MainnetController(output.readAddress(".almController"));
        almProxy          = ALMProxy(output.readAddress(".almProxy"));

        skyVest = DssVest(output.readAddress(".skyVest"));
        spkVest = DssVest(output.readAddress(".spkVest"));

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

    function test_sky_usds_farm() public {
        VestedRewardsDistribution distribution = VestedRewardsDistribution(output.readAddress(".skyUsdsFarmDistribution"));
        StakingRewards rewards = StakingRewards(output.readAddress(".skyUsdsFarmRewards"));

        deal(address(usds), address(this), 300e18);
        usds.approve(address(rewards), 300e18);

        // Accrue a bunch of rewards (numbers dont matter that much)
        vm.warp(skyVest.bgn(1));
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
        
        uint256 amountEarned = 466_666.666666666665897600e18;

        assertEq(rewards.earned(address(this)), amountEarned);
        assertEq(sky.totalSupply(),             622_222.222222222222222222e18);
        assertEq(usds.balanceOf(address(this)), 0);
        assertEq(sky.balanceOf(address(this)),  0);

        // Pull my rewards
        rewards.exit();
        
        assertEq(usds.balanceOf(address(this)), 300e18);
        assertEq(sky.balanceOf(address(this)),  amountEarned);
    }

    function test_spk_usds_farm() public {
        VestedRewardsDistribution distribution = VestedRewardsDistribution(output.readAddress(".spkUsdsFarmDistribution"));
        StakingRewards rewards = StakingRewards(output.readAddress(".spkUsdsFarmRewards"));

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

}
