// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { ScriptTools } from "lib/dss-test/src/ScriptTools.sol";

import { Bridge }                from "xchain-helpers/testing/Bridge.sol";
import { Domain, DomainHelpers } from "xchain-helpers/testing/Domain.sol";
import { OptimismBridgeTesting } from "xchain-helpers/testing/bridges/OptimismBridgeTesting.sol";
import { CCTPBridgeTesting }     from "xchain-helpers/testing/bridges/CCTPBridgeTesting.sol";
import { CCTPForwarder }         from "xchain-helpers/forwarders/CCTPForwarder.sol";

import { Ethereum } from "lib/spark-address-registry/src/Ethereum.sol";

import { Usds }  from "lib/usds/src/Usds.sol";
import { SUsds } from "lib/sdai/src/SUsds.sol";
import { Sky }   from "lib/sky/src/Sky.sol";
import { SDAO }  from "lib/endgame-toolkit/src/SDAO.sol";

import { AllocatorVault }  from "lib/dss-allocator/src/AllocatorVault.sol";
import { AllocatorBuffer } from "lib/dss-allocator/src/AllocatorBuffer.sol";

import { MainnetController } from "lib/spark-alm-controller/src/MainnetController.sol";
import { ForeignController } from "lib/spark-alm-controller/src/ForeignController.sol";
import { ALMProxy }          from "lib/spark-alm-controller/src/ALMProxy.sol";
import { RateLimits }        from "lib/spark-alm-controller/src/RateLimits.sol";

import { DssVest } from "src/DssVest.sol";

import { L1TokenBridge } from "lib/op-token-bridge/src/L1TokenBridge.sol";
import { L2TokenBridge } from "lib/op-token-bridge/src/L2TokenBridge.sol";

import { VestedRewardsDistribution } from "lib/endgame-toolkit/src/VestedRewardsDistribution.sol";
import { StakingRewards }            from "lib/endgame-toolkit/src/synthetix/StakingRewards.sol";

import { PSM3, IERC20 } from "lib/spark-psm/src/PSM3.sol";

interface AuthLike {
    function rely(address usr) external;
}

contract SetupAllTest is Test {

    using stdJson for *;
    using DomainHelpers for *;

    string outputMainnet;
    string inputBase;
    string outputBase;

    Domain mainnet;
    Domain base;
    Bridge bridge;
    Bridge cctpBridge;

    // Mainnet contracts
    Usds   usds;
    SUsds  susds;
    Sky    sky;
    SDAO   spk;
    IERC20 usdc;

    address safe;

    AllocatorVault allocatorVault;
    AllocatorBuffer allocatorBuffer;

    MainnetController mainnetController;
    ALMProxy almProxy;
    RateLimits rateLimits;

    DssVest skyVest;
    DssVest spkVest;

    L1TokenBridge l1TokenBridge;

    // Base contracts
    L2TokenBridge l2TokenBridge;
    address govRelayBase;

    address safeBase;

    PSM3 psm;

    IERC20 usdsBase;
    IERC20 susdsBase;
    IERC20 usdcBase;

    ForeignController foreignController;
    ALMProxy almProxyBase;

    function setUp() public {
        vm.setEnv("FOUNDRY_ROOT_CHAINID", "1");

        mainnet    = getChain("mainnet").createSelectFork();
        base       = getChain("base").createFork();
        bridge     = OptimismBridgeTesting.createNativeBridge(mainnet, base);
        cctpBridge = CCTPBridgeTesting.createCircleBridge(mainnet, base);
        
        outputMainnet = ScriptTools.readOutput("mainnet");
        inputBase = ScriptTools.readInput("base");
        outputBase = ScriptTools.readOutput("base");

        usds  = Usds(outputMainnet.readAddress(".usds"));
        susds = SUsds(outputMainnet.readAddress(".sUsds"));
        sky   = Sky(outputMainnet.readAddress(".sky"));
        spk   = SDAO(outputMainnet.readAddress(".spk"));
        usdc  = IERC20(Ethereum.USDC);

        safe = outputMainnet.readAddress(".safe");

        allocatorVault = AllocatorVault(outputMainnet.readAddress(".allocatorVault"));
        allocatorBuffer = AllocatorBuffer(outputMainnet.readAddress(".allocatorBuffer"));
        
        mainnetController = MainnetController(outputMainnet.readAddress(".almController"));
        almProxy          = ALMProxy(outputMainnet.readAddress(".almProxy"));
        rateLimits        = RateLimits(outputMainnet.readAddress(".rateLimits"));

        skyVest = DssVest(outputMainnet.readAddress(".skyVest"));
        spkVest = DssVest(outputMainnet.readAddress(".spkVest"));

        l1TokenBridge = L1TokenBridge(outputBase.readAddress(".l1TokenBridge"));

        usdsBase  = IERC20(outputBase.readAddress(".usds"));
        susdsBase = IERC20(outputBase.readAddress(".sUsds"));
        usdcBase  = IERC20(inputBase.readAddress(".usdc"));

        l2TokenBridge = L2TokenBridge(outputBase.readAddress(".tokenBridge"));
        govRelayBase = outputBase.readAddress(".govRelay");

        safeBase = outputBase.readAddress(".safe");

        psm = PSM3(outputBase.readAddress(".psm"));
        
        foreignController = ForeignController(outputBase.readAddress(".almController"));
        almProxyBase      = ALMProxy(outputBase.readAddress(".almProxy"));

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
        uint256 usdsValue = 1_000_000e18;

        assertEq(rateLimits.getCurrentRateLimit(mainnetController.LIMIT_USDS_MINT()), 5_000_000e18);

        vm.prank(safe);
        mainnetController.mintUSDS(usdsValue);

        assertEq(rateLimits.getCurrentRateLimit(mainnetController.LIMIT_USDS_MINT()), 4_000_000e18);

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

        deal(address(usdcBase), address(this), 1e6);
        usdcBase.approve(address(psm), 1e6);
        psm.deposit(address(usdcBase), address(this), 1e6);
    }

    function test_full_psm_setup() public {
        // Finish the L2 setup for the token bridge (spell is not yet executed)
        base.selectFork();

        vm.startPrank(govRelayBase);

        l2TokenBridge.registerToken(address(usds), address(usdsBase));
        l2TokenBridge.registerToken(address(susds), address(susdsBase));
        AuthLike(address(usdsBase)).rely(address(l2TokenBridge));
        AuthLike(address(susdsBase)).rely(address(l2TokenBridge));

        vm.stopPrank();

        mainnet.selectFork();

        // Example spell which will supply USDS and sUSDS to the L2 PSM
        vm.startPrank(Ethereum.SPARK_PROXY);

        allocatorVault.draw(2_000_000e18);
        allocatorBuffer.approve(address(usds), Ethereum.SPARK_PROXY, 2_000_000e18);
        usds.transferFrom(address(allocatorBuffer), Ethereum.SPARK_PROXY, 2_000_000e18);
        usds.approve(address(susds), 1_000_000e18);
        uint256 susdsShares = susds.deposit(1_000_000e18, Ethereum.SPARK_PROXY);

        // Bridge to L2
        // FIXME: This should bridge to Spark Governance which needs to be deployed
        usds.approve(address(l1TokenBridge), 1_000_000e18);
        susds.approve(address(l1TokenBridge), susdsShares);
        l1TokenBridge.bridgeERC20To(address(usds), address(usdsBase), address(almProxyBase), 1_000_000e18, 5e6, "");
        l1TokenBridge.bridgeERC20To(address(susds), address(susdsBase), address(almProxyBase), susdsShares, 5e6, "");

        vm.stopPrank();

        vm.startPrank(safe);

        mainnetController.mintUSDS(1_000_000e18);
        mainnetController.swapUSDSToUSDC(1_000_000e6);
        mainnetController.transferUSDCToCCTP(1_000_000e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);

        vm.stopPrank();

        OptimismBridgeTesting.relayMessagesToDestination(bridge, true);
        CCTPBridgeTesting.relayMessagesToDestination(cctpBridge, true);

        assertEq(usdcBase.balanceOf(address(almProxyBase)), 1_000_000e6);
        assertEq(usdsBase.balanceOf(address(almProxyBase)), 1_000_000e18);
        assertEq(susdsBase.balanceOf(address(almProxyBase)), susdsShares);

        // FIXME: this will be replaced by a spell and not done through the ALM Proxy
        vm.startPrank(address(almProxyBase));

        usdsBase.approve(address(psm), 1_000_000e18);
        susdsBase.approve(address(psm), susdsShares);
        psm.deposit(address(usdsBase), address(almProxyBase), 1_000_000e18);
        psm.deposit(address(susdsBase), address(almProxyBase), susdsShares);

        vm.stopPrank();

        vm.startPrank(safeBase);

        foreignController.depositPSM(address(usdcBase), 1_000_000e6);

        vm.stopPrank();

        assertEq(usdcBase.balanceOf(address(psm)), 1_000_000e6);
        assertEq(usdsBase.balanceOf(address(psm)), 1_000_000e18);
        assertEq(susdsBase.balanceOf(address(psm)), susdsShares);
    }

}
