// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script }  from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";

import { Safe }             from "lib/safe-smart-account/contracts/Safe.sol";
import { SafeProxyFactory } from "lib/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";

import { MCD, DssInstance } from "lib/dss-test/src/DssTest.sol";
import { ScriptTools }      from "lib/dss-test/src/ScriptTools.sol";

import { ChainlogAbstract, DSPauseProxyAbstract, WardsAbstract } from "lib/dss-interfaces/src/Interfaces.sol";

import { Ethereum } from "lib/spark-address-registry/src/Ethereum.sol";

import { Usds }                         from "lib/usds/src/Usds.sol";
import { UsdsInstance, UsdsL2Instance } from "lib/usds/deploy/UsdsInstance.sol";
import { UsdsDeploy }                   from "lib/usds/deploy/UsdsDeploy.sol";

import { SUsds }                      from "lib/sdai/src/SUsds.sol";
import { SUsdsDeploy, SUsdsInstance } from "lib/sdai/deploy/l2/SUsdsDeploy.sol";

import {
    AllocatorDeploy,
    AllocatorSharedInstance,
    AllocatorIlkInstance
} from "lib/dss-allocator/deploy/AllocatorDeploy.sol";
import {
    AllocatorInit,
    AllocatorIlkConfig,
    VaultLike
} from "lib/dss-allocator/deploy/AllocatorInit.sol";
import { AllocatorBuffer } from "lib/dss-allocator/src/AllocatorBuffer.sol";
import { AllocatorVault }  from "lib/dss-allocator/src/AllocatorVault.sol";

import { ALMProxy }          from "lib/spark-alm-controller/src/ALMProxy.sol";
import { ForeignController } from "lib/spark-alm-controller/src/ForeignController.sol";
import { MainnetController } from "lib/spark-alm-controller/src/MainnetController.sol";
import { RateLimits }        from "lib/spark-alm-controller/src/RateLimits.sol";
import { RateLimitHelpers }  from "lib/spark-alm-controller/src/RateLimitHelpers.sol";

import { OptimismForwarder } from "lib/xchain-helpers/src/forwarders/OptimismForwarder.sol";
import { CCTPForwarder }     from "lib/xchain-helpers/src/forwarders/CCTPForwarder.sol";

import { L1TokenBridgeInstance }          from "lib/op-token-bridge/deploy/L1TokenBridgeInstance.sol";
import { L2TokenBridgeInstance }          from "lib/op-token-bridge/deploy/L2TokenBridgeInstance.sol";
import { TokenBridgeDeploy }              from "lib/op-token-bridge/deploy/TokenBridgeDeploy.sol";
import { TokenBridgeInit, BridgesConfig } from "lib/op-token-bridge/deploy/TokenBridgeInit.sol";

import { PSM3 } from "lib/spark-psm/src/PSM3.sol";

import { Sky }         from "lib/sky/src/Sky.sol";
import { SkyInstance } from "lib/sky/deploy/SkyInstance.sol";
import { SkyDeploy }   from "lib/sky/deploy/SkyDeploy.sol";

import { DssVest, DssVestMintable } from "src/DssVest.sol";

import { VestedRewardsDistribution } from "lib/endgame-toolkit/src/VestedRewardsDistribution.sol";
import { StakingRewards }            from "lib/endgame-toolkit/src/synthetix/StakingRewards.sol";
import { SDAO }                      from "lib/endgame-toolkit/src/SDAO.sol";

import { FarmProxyDeploy }                from "lib/op-farms/deploy/FarmProxyDeploy.sol";
import { FarmProxyInit, ProxiesConfig }   from "lib/op-farms/deploy/FarmProxyInit.sol";
import { L1FarmProxy }                    from "lib/op-farms/src/L1FarmProxy.sol";
import { L2FarmProxy }                    from "lib/op-farms/src/L2FarmProxy.sol";

interface ISparkProxy {
    function exec(address target, bytes calldata data) external;
}

interface ILitePSM {
    function kiss(address usr) external;
}

struct EthereumDomain {
    string  name;
    string  config;
    uint256 forkId;
    address admin;

    // MCD
    ChainlogAbstract chainlog;
    DssInstance      dss;

    // Init spell
    SetupMainnetSpell spell;

    // New tokens
    UsdsInstance  usdsInstance;
    SUsdsInstance susdsInstance;
    SkyInstance   skyInstance;
    SDAO          spk;

    // Allocation system
    AllocatorSharedInstance allocatorSharedInstance;
    AllocatorIlkInstance    allocatorIlkInstance;

    // ALM Controller
    address           safe;
    MainnetController almController;
    ALMProxy          almProxy;
    RateLimits        rateLimits;

    // Farms
    DssVest skyVest;
    DssVest spkVest;
    Farm    skyUsdsFarm;
    Farm    spkUsdsFarm;
    Farm    skySpkFarm;
    Farm    spkSkyFarm;
}

struct OpStackForeignDomain {
    string  name;
    string  config;
    uint256 forkId;
    address admin;

    // L2 versions of the tokens
    UsdsL2Instance usdsInstance;
    SUsdsInstance  susdsInstance;
    address        sky;
    address        spk;

    // Token Bridge
    L1TokenBridgeInstance l1BridgeInstance;
    L2TokenBridgeInstance l2BridgeInstance;

    // ALM Controller
    address           safe;
    ForeignController almController;
    ALMProxy          almProxy;
    RateLimits        rateLimits;

    // PSM
    PSM3 psm;

    // Farms
    OpStackFarm skyUsdsFarm;
    OpStackFarm spkUsdsFarm;
    OpStackFarm skySpkFarm;
    OpStackFarm spkSkyFarm;
}

struct Farm {
    DssVest                   vest;
    StakingRewards            rewards;
    VestedRewardsDistribution distribution;
}

struct OpStackFarm {
    DssVest                   vest;
    StakingRewards            rewards;
    VestedRewardsDistribution distribution;
    L1FarmProxy               l1Proxy;
    L2FarmProxy               l2Proxy;
    address                   l2Spell;
}

contract SetupMainnetSpell {

    uint256 constant ALLOCATOR_VAULT_RATE = 1000000001547125957863212448;  // 5% APY

    uint256 constant RATE_LIMIT_MAX = 5_000_000e18;
    uint256 constant RATE_LIMIT_SLOPE = uint256(1_000_000e18) / 4 hours;

    function initAllocator(
        DssInstance memory dss,
        AllocatorSharedInstance memory allocatorSharedInstance,
        AllocatorIlkInstance memory allocatorIlkInstance,
        uint256 maxLine,
        uint256 gap,
        uint256 ttl
    ) external {
        AllocatorInit.initShared(dss, allocatorSharedInstance);
        AllocatorInit.initIlk(
            dss,
            allocatorSharedInstance,
            allocatorIlkInstance,
            AllocatorIlkConfig({
                ilk            : VaultLike(allocatorIlkInstance.vault).ilk(),
                duty           : ALLOCATOR_VAULT_RATE,
                gap            : gap,
                maxLine        : maxLine,
                ttl            : ttl,
                allocatorProxy : Ethereum.SPARK_PROXY,
                ilkRegistry    : dss.chainlog.getAddress("ILK_REGISTRY")
            })
        );
    }

    function initALMController(
        address spell,
        UsdsInstance memory usdsInstance,
        AllocatorIlkInstance memory allocatorIlkInstance,
        ALMProxy almProxy,
        MainnetController mainnetController,
        RateLimits rateLimits,
        address freezer,
        address relayer,
        bytes32 baseMintRecipient
    ) external {
        // Whitelist the proxy on the Lite PSM
        ILitePSM(address(mainnetController.psm())).kiss(address(almProxy));

        // Need to execute as the Spark Proxy
        ISparkProxy(Ethereum.SPARK_PROXY).exec(spell, abi.encodeCall(
            this.sparkProxy_initALMController,
            (
                usdsInstance,
                allocatorIlkInstance,
                almProxy,
                mainnetController,
                rateLimits,
                freezer,
                relayer,
                baseMintRecipient
            )
        ));
    }

    function sparkProxy_initALMController(
        UsdsInstance memory usdsInstance,
        AllocatorIlkInstance memory allocatorIlkInstance,
        ALMProxy almProxy,
        MainnetController mainnetController,
        RateLimits rateLimits,
        address freezer,
        address relayer,
        bytes32 baseMintRecipient
    ) external {
        AllocatorVault(allocatorIlkInstance.vault).rely(address(almProxy));

        mainnetController.grantRole(mainnetController.FREEZER(), freezer);
        mainnetController.grantRole(mainnetController.RELAYER(), relayer);
        mainnetController.setMintRecipient(6, baseMintRecipient);

        almProxy.grantRole(almProxy.CONTROLLER(), address(mainnetController));
        rateLimits.grantRole(rateLimits.CONTROLLER(), address(mainnetController));

        AllocatorBuffer(allocatorIlkInstance.buffer).approve(
            usdsInstance.usds,
            address(almProxy),
            type(uint256).max
        );

        bytes32 domainKeyBase = RateLimitHelpers.makeDomainKey(
            mainnetController.LIMIT_USDC_TO_DOMAIN(),
            CCTPForwarder.DOMAIN_ID_CIRCLE_BASE
        );
        rateLimits.setUnlimitedRateLimitData(mainnetController.LIMIT_USDC_TO_CCTP());
        rateLimits.setRateLimitData(mainnetController.LIMIT_USDS_MINT(),    RATE_LIMIT_MAX, RATE_LIMIT_SLOPE);
        rateLimits.setRateLimitData(mainnetController.LIMIT_USDS_TO_USDC(), RATE_LIMIT_MAX / 1e12, RATE_LIMIT_SLOPE / 1e12);
        rateLimits.setRateLimitData(domainKeyBase,                          RATE_LIMIT_MAX / 1e12, RATE_LIMIT_SLOPE / 1e12);
    }

    function initVest(
        DssVest vest,
        address token
    ) external {
        vest.file("cap", type(uint256).max);
        WardsAbstract(token).rely(address(vest));
    }

    function initFarm(
        Farm memory farm,
        uint256 total,
        uint256 duration
    ) external {
        uint256 vestId = farm.vest.create({
            _usr: address(farm.distribution),
            _tot: total,
            _bgn: block.timestamp,
            _tau: duration,
            _eta: 0,
            _mgr: address(0)
        });
        farm.vest.restrict(vestId);
        farm.distribution.file("vestId", vestId);
    }

    function initOpStackTokenBridge(
        DssInstance memory           dss,
        L1TokenBridgeInstance memory l1BridgeInstance,
        L2TokenBridgeInstance memory l2BridgeInstance,
        BridgesConfig memory         cfg
    ) external {
        TokenBridgeInit.initBridges(dss, l1BridgeInstance, l2BridgeInstance, cfg);
    }

    function initOpStackFarm(
        DssInstance memory dss,
        OpStackForeignDomain memory domain,
        OpStackFarm memory farm,
        ProxiesConfig memory cfg
    ) external {
        FarmProxyInit.initProxies(
            dss,
            domain.l1BridgeInstance.govRelay,
            address(farm.l1Proxy),
            address(farm.l2Proxy),
            farm.l2Spell,
            cfg
        );
    }

}

contract SetupAll is Script {

    using stdJson for string;
    using ScriptTools for string;

    uint256 constant RATE_LIMIT_MAX = 5_000_000e18;
    uint256 constant RATE_LIMIT_SLOPE = uint256(1_000_000e18) / 4 hours;

    EthereumDomain mainnet;

    OpStackForeignDomain base;

    address deployer;

    function createEthereumDomain() internal returns (EthereumDomain memory domain) {
        domain.name     = "mainnet";
        domain.config   = ScriptTools.loadConfig(domain.name);
        domain.chainlog = ChainlogAbstract(domain.config.readAddress(".chainlog"));
        // Note we are selecting the fork here because we need to load from the chainlog
        domain.forkId   = vm.createSelectFork(getChain(domain.name).rpcUrl);
        domain.admin    = domain.chainlog.getAddress("MCD_PAUSE_PROXY");
        domain.dss      = MCD.loadFromChainlog(address(domain.chainlog));

        vm.broadcast();
        domain.spell    = new SetupMainnetSpell();

        ScriptTools.exportContract(domain.name, "spell", address(domain.spell));
    }

    function createOpStackForeignDomain(string memory name) internal returns (OpStackForeignDomain memory domain) {
        domain.name   = name;
        domain.config = ScriptTools.loadConfig(name);
        domain.forkId = vm.createFork(getChain(name).rpcUrl);
    }

    function setupNewTokens() internal {
        vm.selectFork(mainnet.forkId);

        vm.startBroadcast();

        // Deploy phase
        mainnet.usdsInstance = UsdsInstance({
            usds:     mainnet.chainlog.getAddress("USDS"),
            usdsImp:  mainnet.chainlog.getAddress("USDS_IMP"),
            usdsJoin: mainnet.chainlog.getAddress("USDS_JOIN"),
            daiUsds:  mainnet.chainlog.getAddress("DAI_USDS")
        });
        mainnet.susdsInstance = SUsdsInstance({
            sUsds:    mainnet.chainlog.getAddress("SUSDS"),
            sUsdsImp: mainnet.chainlog.getAddress("SUSDS_IMP")
        });
        mainnet.skyInstance = SkyInstance({
            sky:    mainnet.chainlog.getAddress("SKY"),
            mkrSky: mainnet.chainlog.getAddress("MKR_SKY")
        });
        mainnet.spk = new SDAO("Spark", "SPK");
        ScriptTools.switchOwner(address(mainnet.spk), deployer, mainnet.admin);

        vm.stopBroadcast();

        ScriptTools.exportContract(mainnet.name, "usds",     mainnet.usdsInstance.usds);
        ScriptTools.exportContract(mainnet.name, "usdsImp",  mainnet.usdsInstance.usdsImp);
        ScriptTools.exportContract(mainnet.name, "usdsJoin", mainnet.usdsInstance.usdsJoin);
        ScriptTools.exportContract(mainnet.name, "daiUsds",  mainnet.usdsInstance.daiUsds);
        ScriptTools.exportContract(mainnet.name, "sUsds",    mainnet.susdsInstance.sUsds);
        ScriptTools.exportContract(mainnet.name, "sUsdsImp", mainnet.susdsInstance.sUsdsImp);
        ScriptTools.exportContract(mainnet.name, "sky",      mainnet.skyInstance.sky);
        ScriptTools.exportContract(mainnet.name, "mkrSky",   mainnet.skyInstance.mkrSky);
        ScriptTools.exportContract(mainnet.name, "spk",      address(mainnet.spk));
    }

    function setupAllocationSystem() internal {
        vm.selectFork(mainnet.forkId);

        vm.startBroadcast();

        mainnet.allocatorSharedInstance = AllocatorDeploy.deployShared(deployer, mainnet.admin);
        mainnet.allocatorIlkInstance    = AllocatorDeploy.deployIlk(
            deployer,
            mainnet.admin,
            mainnet.allocatorSharedInstance.roles,
            mainnet.config.readString(".ilk").stringToBytes32(),
            mainnet.usdsInstance.usdsJoin
        );

        DSPauseProxyAbstract(mainnet.admin).exec(address(mainnet.spell),
            abi.encodeCall(mainnet.spell.initAllocator, (
                mainnet.dss,
                mainnet.allocatorSharedInstance,
                mainnet.allocatorIlkInstance,
                mainnet.config.readUint(".maxLine") * 1e45,
                mainnet.config.readUint(".gap") * 1e45,
                mainnet.config.readUint(".ttl")
            ))
        );

        vm.stopBroadcast();

        ScriptTools.exportContract(mainnet.name, "allocatorOracle",   mainnet.allocatorSharedInstance.oracle);
        ScriptTools.exportContract(mainnet.name, "allocatorRoles",    mainnet.allocatorSharedInstance.roles);
        ScriptTools.exportContract(mainnet.name, "allocatorRegistry", mainnet.allocatorSharedInstance.registry);
        ScriptTools.exportContract(mainnet.name, "allocatorVault",    mainnet.allocatorIlkInstance.vault);
        ScriptTools.exportContract(mainnet.name, "allocatorBuffer",   mainnet.allocatorIlkInstance.buffer);
    }

    function _setupSafe(
        address safeProxyFactoryAddress,
        address safeSingletonAddress,
        address relayerAddress
    ) internal returns (address) {
        SafeProxyFactory factory = SafeProxyFactory(safeProxyFactoryAddress);

        address[] memory owners = new address[](1);
        owners[0] = relayerAddress;

        bytes memory initData = abi.encodeCall(Safe.setup, (
            owners,
            1,
            address(0),
            "",
            address(0),
            address(0),
            0,
            payable(address(0))));
        return address(factory.createProxyWithNonce(safeSingletonAddress, initData, 0));
    }

    function setupSafe() internal {
        vm.selectFork(mainnet.forkId);

        vm.startBroadcast();

        mainnet.safe = _setupSafe(
            mainnet.config.readAddress(".safeProxyFactory"),
            mainnet.config.readAddress(".safeSingleton"),
            mainnet.config.readAddress(".relayer")
        );

        vm.stopBroadcast();

        ScriptTools.exportContract(mainnet.name, "safe", mainnet.safe);
    }

    function predeployALMDependencies() internal {
        vm.selectFork(mainnet.forkId);

        vm.startBroadcast();

        mainnet.almProxy   = new ALMProxy(Ethereum.SPARK_PROXY);
        mainnet.rateLimits = new RateLimits(Ethereum.SPARK_PROXY);

        vm.stopBroadcast();

        ScriptTools.exportContract(mainnet.name, "almProxy", address(mainnet.almProxy));
        ScriptTools.exportContract(mainnet.name, "rateLimits", address(mainnet.rateLimits));
    }

    function setupALMController() internal {
        vm.selectFork(mainnet.forkId);

        vm.startBroadcast();

        mainnet.almController = new MainnetController({
            admin_      : Ethereum.SPARK_PROXY,
            proxy_      : payable(address(mainnet.almProxy)),
            rateLimits_ : address(mainnet.rateLimits),
            vault_      : mainnet.allocatorIlkInstance.vault,
            psm_        : mainnet.chainlog.getAddress("MCD_LITE_PSM_USDC_A"),
            daiUsds_    : mainnet.usdsInstance.daiUsds,
            cctp_       : mainnet.config.readAddress(".cctpTokenMessenger"),
            susds_      : mainnet.susdsInstance.sUsds
        });

        DSPauseProxyAbstract(mainnet.admin).exec(address(mainnet.spell),
            abi.encodeCall(mainnet.spell.initALMController, (
                address(mainnet.spell),
                mainnet.usdsInstance,
                mainnet.allocatorIlkInstance,
                mainnet.almProxy,
                mainnet.almController,
                mainnet.rateLimits,
                mainnet.config.readAddress(".freezer"),
                mainnet.safe,
                bytes32(uint256(uint160(address(base.almProxy))))
            ))
        );

        vm.stopBroadcast();

        ScriptTools.exportContract(mainnet.name, "almController", address(mainnet.almController));
    }

    function _createFarm(
        DssVest vest,
        address stakingToken,
        uint256 total,
        uint256 duration
    ) internal returns (Farm memory farm) {
        address distributionExpectedAddress = _getDeploymentAddress(1);

        // Deploy
        farm.vest = vest;
        farm.rewards = new StakingRewards(
            mainnet.admin,
            distributionExpectedAddress,
            address(DssVestMintable(address(vest)).gem()),
            stakingToken
        );
        farm.distribution = new VestedRewardsDistribution(address(vest), address(farm.rewards));
        require(address(farm.distribution) == distributionExpectedAddress, "addr mismatch");
        ScriptTools.switchOwner(address(farm.distribution), deployer, mainnet.admin);

        // Init
        DSPauseProxyAbstract(mainnet.admin).exec(address(mainnet.spell),
            abi.encodeCall(mainnet.spell.initFarm, (
                farm,
                total,
                duration
            ))
        );
    }

    function setupFarms() internal {
        vm.selectFork(mainnet.forkId);

        vm.startBroadcast();

        // SKY Vest
        mainnet.skyVest = DssVest(mainnet.chainlog.getAddress("MCD_VEST_SKY"));

        // SPK Vest
        mainnet.spkVest = new DssVestMintable(address(mainnet.spk));
        ScriptTools.switchOwner(address(mainnet.spkVest), deployer, mainnet.admin);
        DSPauseProxyAbstract(mainnet.admin).exec(address(mainnet.spell),
            abi.encodeCall(mainnet.spell.initVest, (
                mainnet.spkVest,
                address(mainnet.spk)
            ))
        );

        // Farms
        mainnet.skyUsdsFarm = Farm({
            vest:         DssVest(mainnet.chainlog.getAddress("MCD_VEST_SKY")),
            rewards:      StakingRewards(mainnet.chainlog.getAddress("REWARDS_USDS_SKY")),
            distribution: VestedRewardsDistribution(mainnet.chainlog.getAddress("REWARDS_DIST_USDS_SKY"))
        });
        mainnet.spkUsdsFarm = _createFarm(
            mainnet.spkVest,
            address(mainnet.usdsInstance.usds),
            mainnet.config.readUint(".farms.spkUsds.total") * 1e18,
            mainnet.config.readUint(".farms.spkUsds.duration")
        );
        mainnet.skySpkFarm = _createFarm(
            mainnet.skyVest,
            address(mainnet.spk),
            mainnet.config.readUint(".farms.skySpk.total") * 1e18,
            mainnet.config.readUint(".farms.skySpk.duration")
        );
        mainnet.spkSkyFarm = _createFarm(
            mainnet.spkVest,
            address(mainnet.skyInstance.sky),
            mainnet.config.readUint(".farms.spkSky.total") * 1e18,
            mainnet.config.readUint(".farms.spkSky.duration")
        );

        vm.stopBroadcast();

        ScriptTools.exportContract(mainnet.name, "skyVest", address(mainnet.skyVest));
        ScriptTools.exportContract(mainnet.name, "spkVest", address(mainnet.spkVest));

        ScriptTools.exportContract(mainnet.name, "skyUsdsFarmDistribution", address(mainnet.skyUsdsFarm.distribution));
        ScriptTools.exportContract(mainnet.name, "skyUsdsFarmRewards",      address(mainnet.skyUsdsFarm.rewards));

        ScriptTools.exportContract(mainnet.name, "spkUsdsFarmDistribution", address(mainnet.spkUsdsFarm.distribution));
        ScriptTools.exportContract(mainnet.name, "spkUsdsFarmRewards",      address(mainnet.spkUsdsFarm.rewards));

        ScriptTools.exportContract(mainnet.name, "skySpkFarmDistribution", address(mainnet.skySpkFarm.distribution));
        ScriptTools.exportContract(mainnet.name, "skySpkFarmRewards",      address(mainnet.skySpkFarm.rewards));

        ScriptTools.exportContract(mainnet.name, "spkSkyFarmDistribution", address(mainnet.spkSkyFarm.distribution));
        ScriptTools.exportContract(mainnet.name, "spkSkyFarmRewards",      address(mainnet.spkSkyFarm.rewards));
    }

    function setupOpStackTokenBridge(OpStackForeignDomain storage domain) internal {
        address l1CrossDomain;
        if (domain.name.eq("base")) {
            l1CrossDomain = OptimismForwarder.L1_CROSS_DOMAIN_BASE;
        } else {
            revert("Unsupported domain");
        }
        address l2CrossDomain = OptimismForwarder.L2_CROSS_DOMAIN;  // Always the same

        vm.selectFork(domain.forkId);

        // Pre-compute L2 deployment addresses
        uint256 nonce = vm.getNonce(deployer);

        // Mainnet deploy

        vm.selectFork(mainnet.forkId);

        vm.startBroadcast();

        domain.l1BridgeInstance = TokenBridgeDeploy.deployL1(
            deployer,
            mainnet.admin,
            vm.computeCreateAddress(deployer, nonce),
            vm.computeCreateAddress(deployer, nonce + 1),
            l1CrossDomain
        );

        vm.stopBroadcast();

        // L2 deploy

        vm.selectFork(domain.forkId);

        vm.startBroadcast();

        domain.l2BridgeInstance = TokenBridgeDeploy.deployL2(
            deployer,
            domain.l1BridgeInstance.govRelay,
            domain.l1BridgeInstance.bridge,
            l2CrossDomain
        );

        domain.usdsInstance = UsdsDeploy.deployL2(deployer, domain.l2BridgeInstance.govRelay);
        domain.susdsInstance = SUsdsDeploy.deploy(deployer, domain.l2BridgeInstance.govRelay);
        domain.sky = SkyDeploy.deployL2(deployer, domain.l2BridgeInstance.govRelay);
        domain.spk = address(new SDAO("Spark", "SPK"));
        ScriptTools.switchOwner(domain.spk, deployer, domain.l2BridgeInstance.govRelay);

        vm.stopBroadcast();

        // Initialization spell

        vm.selectFork(mainnet.forkId);

        vm.startBroadcast();

        address[] memory l1Tokens = new address[](4);
        l1Tokens[0] = mainnet.usdsInstance.usds;
        l1Tokens[1] = mainnet.susdsInstance.sUsds;
        l1Tokens[2] = mainnet.skyInstance.sky;
        l1Tokens[3] = address(mainnet.spk);

        address[] memory l2Tokens = new address[](4);
        l2Tokens[0] = address(domain.usdsInstance.usds);
        l2Tokens[1] = address(domain.susdsInstance.sUsds);
        l2Tokens[2] = address(domain.sky);
        l2Tokens[3] = address(domain.spk);

        string memory clPrefix = domain.config.readString(".chainlogPrefix");

        DSPauseProxyAbstract(mainnet.admin).exec(address(mainnet.spell),
            abi.encodeCall(mainnet.spell.initOpStackTokenBridge, (
                mainnet.dss,
                domain.l1BridgeInstance,
                domain.l2BridgeInstance,
                BridgesConfig({
                    l1Messenger    : l1CrossDomain,
                    l2Messenger    : l2CrossDomain,
                    l1Tokens       : l1Tokens,
                    l2Tokens       : l2Tokens,
                    minGasLimit    : 5_000_000,  // Should be enough gas to execute the l2 spell
                    govRelayCLKey  : string.concat(clPrefix, "_GOV_RELAY").stringToBytes32(),
                    escrowCLKey    : string.concat(clPrefix, "_ESCROW").stringToBytes32(),
                    l1BridgeCLKey  : string.concat(clPrefix, "_TOKEN_BRIDGE").stringToBytes32()
                })
            ))
        );

        vm.stopBroadcast();

        ScriptTools.exportContract(domain.name, "usds",          domain.usdsInstance.usds);
        ScriptTools.exportContract(domain.name, "usdsImp",       domain.usdsInstance.usdsImp);
        ScriptTools.exportContract(domain.name, "sUsds",         domain.susdsInstance.sUsds);
        ScriptTools.exportContract(domain.name, "sUsdsImp",      domain.susdsInstance.sUsdsImp);
        ScriptTools.exportContract(domain.name, "sky",           domain.sky);
        ScriptTools.exportContract(domain.name, "spk",           domain.spk);
        ScriptTools.exportContract(domain.name, "l1GovRelay",    domain.l1BridgeInstance.govRelay);
        ScriptTools.exportContract(domain.name, "l1Escrow",      domain.l1BridgeInstance.escrow);
        ScriptTools.exportContract(domain.name, "l1TokenBridge", domain.l1BridgeInstance.bridge);
        ScriptTools.exportContract(domain.name, "govRelay",      domain.l2BridgeInstance.govRelay);
        ScriptTools.exportContract(domain.name, "tokenBridge",   domain.l2BridgeInstance.bridge);
    }

    function setupOpStackForeignPSM(OpStackForeignDomain storage domain) internal {
        vm.selectFork(domain.forkId);

        vm.startBroadcast();

        domain.psm = new PSM3(
            domain.l2BridgeInstance.govRelay,
            domain.config.readAddress(".usdc"),
            domain.usdsInstance.usds,
            domain.susdsInstance.sUsds,
            domain.config.readAddress(".ssrOracle")
        );

        vm.stopBroadcast();

        ScriptTools.exportContract(domain.name, "psm", address(domain.psm));
    }

    function setupOpStackSafe(OpStackForeignDomain storage domain) internal {
        vm.selectFork(domain.forkId);

        vm.startBroadcast();

        domain.safe = _setupSafe(
            domain.config.readAddress(".safeProxyFactory"),
            domain.config.readAddress(".safeSingleton"),
            domain.config.readAddress(".relayer")
        );

        vm.stopBroadcast();

        ScriptTools.exportContract(domain.name, "safe", domain.safe);
    }

    function predeployOpStackALMDependencies(OpStackForeignDomain storage domain) internal {
        vm.selectFork(domain.forkId);

        vm.startBroadcast();

        // Temporarily granting admin role to the deployer for straightforward configuration
        domain.almProxy   = new ALMProxy(msg.sender);
        domain.rateLimits = new RateLimits(msg.sender);

        vm.stopBroadcast();

        ScriptTools.exportContract(domain.name, "almProxy", address(domain.almProxy));
        ScriptTools.exportContract(domain.name, "rateLimits", address(domain.rateLimits));
    }

    function setupOpStackALMController(OpStackForeignDomain storage domain) internal {
        vm.selectFork(domain.forkId);
        address usdc = domain.config.readAddress(".usdc");

        vm.startBroadcast();

        // Temporarily granting admin role to the deployer for straightforward configuration
        domain.almController = new ForeignController({
            admin_      : msg.sender,
            proxy_      : address(domain.almProxy),
            rateLimits_ : address(domain.rateLimits),
            psm_        : address(domain.psm),
            usdc_       : usdc,
            cctp_       : domain.config.readAddress(".cctpTokenMessenger")
        });

        domain.almController.grantRole(domain.almController.FREEZER(),            domain.config.readAddress(".freezer"));
        domain.almController.grantRole(domain.almController.RELAYER(),            domain.safe);
        domain.almController.grantRole(domain.almController.DEFAULT_ADMIN_ROLE(), domain.l2BridgeInstance.govRelay);
        domain.almController.setMintRecipient(0, bytes32(uint256(uint160(address(mainnet.almProxy)))));

        domain.almController.revokeRole(domain.almController.DEFAULT_ADMIN_ROLE(), msg.sender);

        domain.almProxy.grantRole(domain.almProxy.CONTROLLER(),         address(domain.almController));
        domain.almProxy.grantRole(domain.almProxy.DEFAULT_ADMIN_ROLE(), domain.l2BridgeInstance.govRelay);
        domain.almProxy.revokeRole(domain.almProxy.DEFAULT_ADMIN_ROLE(), msg.sender);

        domain.rateLimits.setRateLimitData(_makeForeignPSMDepositKey(domain.almController, usdc),  RATE_LIMIT_MAX / 1e12, RATE_LIMIT_SLOPE / 1e12);
        domain.rateLimits.setRateLimitData(_makeForeignPSMWithdrawKey(domain.almController, usdc), RATE_LIMIT_MAX / 1e12, RATE_LIMIT_SLOPE / 1e12);
        domain.rateLimits.setRateLimitData(_makeForeignCCTPDomainKey(domain.almController, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM), RATE_LIMIT_MAX / 1e12, RATE_LIMIT_SLOPE / 1e12);
        domain.rateLimits.setUnlimitedRateLimitData(domain.almController.LIMIT_USDC_TO_CCTP());

        domain.rateLimits.grantRole(domain.almProxy.CONTROLLER(),          address(domain.almController));
        domain.rateLimits.grantRole(domain.almProxy.DEFAULT_ADMIN_ROLE(),  domain.l2BridgeInstance.govRelay);
        domain.rateLimits.revokeRole(domain.almProxy.DEFAULT_ADMIN_ROLE(), msg.sender);

        vm.stopBroadcast();

        ScriptTools.exportContract(domain.name, "almController", address(domain.almController));
    }

    function _makeForeignCCTPDomainKey(ForeignController controller, uint32 domainId) internal view returns (bytes32) {
        return RateLimitHelpers.makeDomainKey(controller.LIMIT_USDC_TO_DOMAIN(), domainId);
    }

    function _makeForeignPSMDepositKey(ForeignController controller, address asset) internal view returns (bytes32) {
        return RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_DEPOSIT(), asset);
    }

    function _makeForeignPSMWithdrawKey(ForeignController controller, address asset) internal view returns (bytes32) {
        return RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_WITHDRAW(), asset);
    }

    struct OpStackFarmVars {
        address rewardsTokenL1;
        address l2ProxyExpectedAddress;
        ProxiesConfig cfg;
    }

    function _createOpStackFarm(
        OpStackForeignDomain storage domain,
        DssVest vest,
        address stakingTokenL2,
        address rewardsTokenL2,
        uint256 total,
        uint256 duration,
        string memory farmName
    ) internal returns (OpStackFarm memory farm) {
        vm.selectFork(mainnet.forkId);

        OpStackFarmVars memory vars = OpStackFarmVars({
            rewardsTokenL1: address(DssVestMintable(address(vest)).gem()),
            l2ProxyExpectedAddress: _getDeploymentAddress(domain.forkId, 1),
            cfg: ProxiesConfig({
                vest: address(vest),
                vestTot: total,
                vestBgn: block.timestamp,
                vestTau: duration,
                vestedRewardsDistribution: address(0),
                l1RewardsToken: address(0),  // Can't reference vars.rewardsTokenL1 before vars is initialized
                l2RewardsToken: rewardsTokenL2,
                l2StakingToken: stakingTokenL2,
                l1Bridge: domain.l1BridgeInstance.bridge,
                minGasLimit: 1_000_000,
                rewardThreshold: 0,
                farm: address(0),
                rewardsDuration: 7 days,
                initMinGasLimit: 1_000_000,
                proxyChainlogKey: string.concat(farmName, "_PROXY").stringToBytes32(),
                distrChainlogKey: string.concat(farmName, "_DISTRIBUTION").stringToBytes32()
            })
        });
        vars.cfg.l1RewardsToken = vars.rewardsTokenL1;

        vm.startBroadcast();

        // Deploy
        farm.l1Proxy = L1FarmProxy(FarmProxyDeploy.deployL1Proxy(
            deployer,
            mainnet.admin,
            vars.rewardsTokenL1,
            rewardsTokenL2,
            vars.l2ProxyExpectedAddress,
            domain.l1BridgeInstance.bridge
        ));
        farm.vest = vest;
        farm.distribution = new VestedRewardsDistribution(address(vest), address(farm.l1Proxy));
        ScriptTools.switchOwner(address(farm.distribution), deployer, mainnet.admin);
        vars.cfg.vestedRewardsDistribution = address(farm.distribution);

        vm.stopBroadcast();
        vm.selectFork(domain.forkId);
        vm.startBroadcast();

        farm.rewards = new StakingRewards(
            mainnet.admin,
            vars.l2ProxyExpectedAddress,
            rewardsTokenL2,
            stakingTokenL2
        );
        vars.cfg.farm = address(farm.rewards);
        farm.l2Proxy = L2FarmProxy(FarmProxyDeploy.deployL2Proxy(
            deployer,
            domain.l2BridgeInstance.govRelay,
            address(farm.rewards)
        ));
        require(address(farm.l2Proxy) == vars.l2ProxyExpectedAddress, "addr mismatch");
        farm.l2Spell = FarmProxyDeploy.deployL2ProxySpell();

        vm.stopBroadcast();
        vm.selectFork(mainnet.forkId);
        vm.startBroadcast();

        // Init
        DSPauseProxyAbstract(mainnet.admin).exec(address(mainnet.spell),
            abi.encodeCall(mainnet.spell.initOpStackFarm, (
                mainnet.dss,
                domain,
                farm,
                vars.cfg
            ))
        );

        vm.stopBroadcast();
    }

    function setupOpStackFarms(OpStackForeignDomain storage domain) internal {
        // SKY-USDS Farm
        domain.skyUsdsFarm = _createOpStackFarm(
            domain,
            mainnet.skyVest,
            domain.usdsInstance.usds,
            domain.sky,
            domain.config.readUint(".farms.skyUsds.total") * 1e18,
            domain.config.readUint(".farms.skyUsds.duration"),
            "SKY-USDS"
        );

        // SPK-USDS Farm
        domain.spkUsdsFarm = _createOpStackFarm(
            domain,
            mainnet.spkVest,
            domain.usdsInstance.usds,
            domain.spk,
            domain.config.readUint(".farms.spkUsds.total") * 1e18,
            domain.config.readUint(".farms.spkUsds.duration"),
            "SPK-USDS"
        );

        // SKY-SPK Farm
        domain.skySpkFarm = _createOpStackFarm(
            domain,
            mainnet.skyVest,
            domain.spk,
            domain.sky,
            domain.config.readUint(".farms.skySpk.total") * 1e18,
            domain.config.readUint(".farms.skySpk.duration"),
            "SKY-SPK"
        );

        // SPK-SKY Farm
        domain.spkSkyFarm = _createOpStackFarm(
            domain,
            mainnet.spkVest,
            domain.sky,
            domain.spk,
            domain.config.readUint(".farms.spkSky.total") * 1e18,
            domain.config.readUint(".farms.spkSky.duration"),
            "SPK-SKY"
        );

        ScriptTools.exportContract(domain.name, "skyUsdsFarmDistribution", address(domain.skyUsdsFarm.distribution));
        ScriptTools.exportContract(domain.name, "skyUsdsFarmRewards",      address(domain.skyUsdsFarm.rewards));
        ScriptTools.exportContract(domain.name, "skyUsdsFarmL1Proxy",      address(domain.skyUsdsFarm.l1Proxy));
        ScriptTools.exportContract(domain.name, "skyUsdsFarmL2Proxy",      address(domain.skyUsdsFarm.l2Proxy));
        ScriptTools.exportContract(domain.name, "skyUsdsFarmL2Spell",      domain.skyUsdsFarm.l2Spell);

        ScriptTools.exportContract(domain.name, "spkUsdsFarmDistribution", address(domain.spkUsdsFarm.distribution));
        ScriptTools.exportContract(domain.name, "spkUsdsFarmRewards",      address(domain.spkUsdsFarm.rewards));
        ScriptTools.exportContract(domain.name, "spkUsdsFarmL1Proxy",      address(domain.spkUsdsFarm.l1Proxy));
        ScriptTools.exportContract(domain.name, "spkUsdsFarmL2Proxy",      address(domain.spkUsdsFarm.l2Proxy));
        ScriptTools.exportContract(domain.name, "spkUsdsFarmL2Spell",      domain.spkUsdsFarm.l2Spell);

        ScriptTools.exportContract(domain.name, "skySpkFarmDistribution", address(domain.skySpkFarm.distribution));
        ScriptTools.exportContract(domain.name, "skySpkFarmRewards",      address(domain.skySpkFarm.rewards));
        ScriptTools.exportContract(domain.name, "skySpkFarmL1Proxy",      address(domain.skySpkFarm.l1Proxy));
        ScriptTools.exportContract(domain.name, "skySpkFarmL2Proxy",      address(domain.skySpkFarm.l2Proxy));
        ScriptTools.exportContract(domain.name, "skySpkFarmL2Spell",      domain.skySpkFarm.l2Spell);

        ScriptTools.exportContract(domain.name, "spkSkyFarmDistribution", address(domain.spkSkyFarm.distribution));
        ScriptTools.exportContract(domain.name, "spkSkyFarmRewards",      address(domain.spkSkyFarm.rewards));
        ScriptTools.exportContract(domain.name, "spkSkyFarmL1Proxy",      address(domain.spkSkyFarm.l1Proxy));
        ScriptTools.exportContract(domain.name, "spkSkyFarmL2Proxy",      address(domain.spkSkyFarm.l2Proxy));
        ScriptTools.exportContract(domain.name, "spkSkyFarmL2Spell",      domain.spkSkyFarm.l2Spell);
    }

    function run() public {
        vm.setEnv("FOUNDRY_ROOT_CHAINID", "1");
        vm.setEnv("FOUNDRY_EXPORTS_OVERWRITE_LATEST", "true");

        deployer = msg.sender;

        mainnet = createEthereumDomain();
        base    = createOpStackForeignDomain("base");

        predeployALMDependencies();
        predeployOpStackALMDependencies(base);

        setupNewTokens();
        setupAllocationSystem();
        setupSafe();
        setupALMController();
        setupFarms();

        setupOpStackTokenBridge(base);
        setupOpStackForeignPSM(base);
        setupOpStackSafe(base);
        setupOpStackALMController(base);
        setupOpStackFarms(base);
    }

    function _getDeploymentAddress(uint256 forkId, uint256 delta) internal returns (address addr) {
        uint256 currentFork = vm.activeFork();
        vm.selectFork(forkId);

        addr = _getDeploymentAddress(delta);

        vm.selectFork(currentFork);
    }

    function _getDeploymentAddress(uint256 delta) internal view returns (address addr) {
        addr = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + delta);
    }

}
