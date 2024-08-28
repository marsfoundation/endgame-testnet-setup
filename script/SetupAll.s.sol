// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script }  from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";

import { Safe }                        from "lib/safe-smart-account/contracts/Safe.sol";
import { SafeProxyFactory, SafeProxy } from "lib/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";

import { MCD, DssInstance } from "lib/dss-test/src/DssTest.sol";
import { ScriptTools }      from "lib/dss-test/src/ScriptTools.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { ChainlogAbstract, DSPauseProxyAbstract } from "lib/dss-interfaces/src/Interfaces.sol";

import { Ethereum } from "lib/spark-address-registry/src/Ethereum.sol";

import { Usds }                     from "lib/usds/src/Usds.sol";
import { UsdsDeploy, UsdsInstance } from "lib/usds/deploy/UsdsDeploy.sol";
import { UsdsInit }                 from "lib/usds/deploy/UsdsInit.sol";

import { SUsdsDeploy, SUsdsInstance } from "lib/sdai/deploy/SUsdsDeploy.sol";
import { SUsdsInit, SUsdsConfig }     from "lib/sdai/deploy/SUsdsInit.sol";

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

import { DSROracleForwarderBaseChain } from "lib/xchain-dsr-oracle/src/forwarders/DSROracleForwarderBaseChain.sol";
import { OptimismReceiver }            from "lib/xchain-helpers/src/receivers/OptimismReceiver.sol";
import { DSRAuthOracle }               from "lib/xchain-dsr-oracle/src/DSRAuthOracle.sol";

import { OptimismForwarder } from "lib/xchain-helpers/src/forwarders/OptimismForwarder.sol";

import { L1TokenBridgeInstance }          from "lib/op-token-bridge/deploy/L1TokenBridgeInstance.sol";
import { L2TokenBridgeInstance }          from "lib/op-token-bridge/deploy/L2TokenBridgeInstance.sol";
import { TokenBridgeDeploy }              from "lib/op-token-bridge/deploy/TokenBridgeDeploy.sol";
import { TokenBridgeInit, BridgesConfig } from "lib/op-token-bridge/deploy/TokenBridgeInit.sol";

import { PSM3 } from "lib/spark-psm/src/PSM3.sol";

interface ISparkProxy {
    function exec(address target, bytes calldata data) external;
}

contract SetupMainnetSpell {

    uint256 constant DSR_INITIAL_RATE     = 1000000001847694957439350562;  // 6% APY
    uint256 constant ALLOCATOR_VAULT_RATE = 1000000001547125957863212448;  // 5% APY

    function initTokens(
        DssInstance memory dss,
        UsdsInstance memory usdsInstance,
        SUsdsInstance memory susdsInstance
    ) external {
        UsdsInit.init(dss, usdsInstance);
        SUsdsInit.init(dss, susdsInstance, SUsdsConfig({
            usdsJoin: usdsInstance.usdsJoin,
            usds:     usdsInstance.usds,
            ssr:      DSR_INITIAL_RATE
        }));
    }

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
                duty           : DSR_INITIAL_RATE,
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
        address freezer,
        address relayer
    ) external {
        // Need to execute as the Spark Proxy
        ISparkProxy(Ethereum.SPARK_PROXY).exec(spell, abi.encodeCall(
            this.sparkProxy_initALMController,
            (
                usdsInstance,
                allocatorIlkInstance,
                almProxy,
                mainnetController,
                freezer,
                relayer
            )
        ));
    }

    function sparkProxy_initALMController(
        UsdsInstance memory usdsInstance,
        AllocatorIlkInstance memory allocatorIlkInstance,
        ALMProxy almProxy,
        MainnetController mainnetController,
        address freezer,
        address relayer
    ) external {
        AllocatorVault(allocatorIlkInstance.vault).rely(address(almProxy));

        mainnetController.grantRole(mainnetController.FREEZER(), freezer);
        mainnetController.grantRole(mainnetController.RELAYER(), relayer);

        almProxy.grantRole(almProxy.CONTROLLER(), address(mainnetController));

        AllocatorBuffer(allocatorIlkInstance.buffer).approve(
            usdsInstance.usds,
            address(almProxy),
            type(uint256).max
        );
    }

    function initOpStackTokenBridge(
        DssInstance memory           dss,
        L1TokenBridgeInstance memory l1BridgeInstance,
        L2TokenBridgeInstance memory l2BridgeInstance,
        BridgesConfig memory         cfg
    ) external {
        TokenBridgeInit.initBridges(dss, l1BridgeInstance, l2BridgeInstance, cfg);
    }

}

contract SetupAll is Script {

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

        // Allocation system
        AllocatorSharedInstance allocatorSharedInstance;
        AllocatorIlkInstance    allocatorIlkInstance;

        // ALM Controller
        address           safe;
        MainnetController almController;
        ALMProxy          almProxy;
    }

    struct OpStackForeignDomain {
        string  name;
        string  config;
        uint256 forkId;
        address admin;

        // L2 versions of the tokens
        Usds usds;
        Usds susds;

        // Token Bridge
        L1TokenBridgeInstance l1BridgeInstance;
        L2TokenBridgeInstance l2BridgeInstance;

        // ALM Controller
        address           safe;
        ForeignController almController;
        ALMProxy          almProxy;

        // PSM
        PSM3 psm;

        // XChain DSR Oracle
        address          dsrForwarder;  // On Mainnet
        OptimismReceiver dsrReceiver;
        DSRAuthOracle    dsrOracle;
    }

    using stdJson for string;
    using ScriptTools for string;

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

        ScriptTools.exportContract(mainnet.name, "spell", address(domain.spell));
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
        mainnet.usdsInstance  = UsdsDeploy.deploy(deployer, mainnet.admin, address(mainnet.dss.daiJoin));
        mainnet.susdsInstance = SUsdsDeploy.deploy(deployer, mainnet.admin, mainnet.usdsInstance.usdsJoin);

        // Initialization phase (needs executing as pause proxy owner)
        DSPauseProxyAbstract(mainnet.admin).exec(address(mainnet.spell),
            abi.encodeCall(mainnet.spell.initTokens, (
                mainnet.dss,
                mainnet.usdsInstance,
                mainnet.susdsInstance
            ))
        );

        vm.stopBroadcast();

        ScriptTools.exportContract(mainnet.name, "usds",     mainnet.usdsInstance.usds);
        ScriptTools.exportContract(mainnet.name, "usdsImp",  mainnet.usdsInstance.usdsImp);
        ScriptTools.exportContract(mainnet.name, "usdsJoin", mainnet.usdsInstance.usdsJoin);
        ScriptTools.exportContract(mainnet.name, "daiUsds",  mainnet.usdsInstance.daiUsds);
        ScriptTools.exportContract(mainnet.name, "sUsds",    mainnet.susdsInstance.sUsds);
        ScriptTools.exportContract(mainnet.name, "sUsdsImp", mainnet.susdsInstance.sUsdsImp);
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

    function setupALMController() internal {
        vm.selectFork(mainnet.forkId);

        vm.startBroadcast();

        mainnet.almProxy = new ALMProxy(Ethereum.SPARK_PROXY);
        mainnet.almController = new MainnetController({
            admin_   : Ethereum.SPARK_PROXY,
            proxy_   : address(mainnet.almProxy),
            vault_   : mainnet.allocatorIlkInstance.vault,
            buffer_  : mainnet.allocatorIlkInstance.buffer,
            psm_     : mainnet.chainlog.getAddress("MCD_LITE_PSM_USDC_A"),
            daiUsds_ : mainnet.usdsInstance.daiUsds,
            cctp_    : mainnet.config.readAddress(".cctpTokenMessenger"),
            susds_   : mainnet.susdsInstance.sUsds
        });

        DSPauseProxyAbstract(mainnet.admin).exec(address(mainnet.spell),
            abi.encodeCall(mainnet.spell.initALMController, (
                address(mainnet.spell),
                mainnet.usdsInstance,
                mainnet.allocatorIlkInstance,
                mainnet.almProxy,
                mainnet.almController,
                mainnet.config.readAddress(".freezer"),
                mainnet.safe
            ))
        );

        vm.stopBroadcast();

        ScriptTools.exportContract(mainnet.name, "almProxy",      address(mainnet.almProxy));
        ScriptTools.exportContract(mainnet.name, "almController", address(mainnet.almController));
    }

    // Deploy an instance of USDS which will closely resemble the L2 versions of the tokens
    // TODO: This should be replaced by the actual tokens when they are available
    function deployUsdsInstance(
        address _deployer,
        address _owner
    ) internal returns (Usds instance) {
        address _usdsImp = address(new Usds());
        address _usds = address((new ERC1967Proxy(_usdsImp, abi.encodeCall(Usds.initialize, ()))));
        ScriptTools.switchOwner(_usds, _deployer, _owner);

        return Usds(_usds);
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

        domain.usds  = deployUsdsInstance(deployer, domain.l2BridgeInstance.govRelay);
        domain.susds = deployUsdsInstance(deployer, domain.l2BridgeInstance.govRelay);

        vm.stopBroadcast();

        // Initialization spell

        vm.selectFork(mainnet.forkId);

        vm.startBroadcast();

        address[] memory l1Tokens = new address[](2);
        l1Tokens[0] = mainnet.usdsInstance.usds;
        l1Tokens[1] = mainnet.susdsInstance.sUsds;

        address[] memory l2Tokens = new address[](2);
        l2Tokens[0] = address(domain.usds);
        l2Tokens[1] = address(domain.susds);

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

        ScriptTools.exportContract(domain.name, "usds",          address(domain.usds));
        ScriptTools.exportContract(domain.name, "sUsds",         address(domain.susds));
        ScriptTools.exportContract(domain.name, "l1GovRelay",    domain.l1BridgeInstance.govRelay);
        ScriptTools.exportContract(domain.name, "l1Escrow",      domain.l1BridgeInstance.escrow);
        ScriptTools.exportContract(domain.name, "l1TokenBridge", domain.l1BridgeInstance.bridge);
        ScriptTools.exportContract(domain.name, "govRelay",      domain.l2BridgeInstance.govRelay);
        ScriptTools.exportContract(domain.name, "tokenBridge",   domain.l2BridgeInstance.bridge);
    }

    function setupOpStackCrossChainDSROracle(OpStackForeignDomain storage domain) internal {
        vm.selectFork(mainnet.forkId);

        address expectedReceiver = vm.computeCreateAddress(deployer, 2);
        if (domain.name.eq("base")) {
            domain.dsrForwarder = address(new DSROracleForwarderBaseChain(address(mainnet.susdsInstance.sUsds), expectedReceiver));
        } else {
            revert("Unsupported domain");
        }

        vm.selectFork(domain.forkId);

        domain.dsrOracle   = new DSRAuthOracle();
        domain.dsrReceiver = new OptimismReceiver(domain.dsrForwarder, address(domain.dsrOracle));
        domain.dsrOracle.grantRole(domain.dsrOracle.DATA_PROVIDER_ROLE(), address(domain.dsrReceiver));

        ScriptTools.exportContract(domain.name, "l1DSRForwarder", domain.dsrForwarder);
        ScriptTools.exportContract(domain.name, "dsrReceiver",    address(domain.dsrReceiver));
        ScriptTools.exportContract(domain.name, "dsrOracle",      address(domain.dsrOracle));
    }

    function setupOpStackForeignPSM(OpStackForeignDomain storage domain) internal {
        vm.selectFork(domain.forkId);

        vm.startBroadcast();

        domain.psm = new PSM3(
            domain.config.readAddress(".usdc"),
            address(domain.usds),
            address(domain.susds),
            address(domain.dsrOracle)
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

    function setupOpStackALMController(OpStackForeignDomain storage domain) internal {
        vm.selectFork(domain.forkId);

        vm.startBroadcast();

        // Temporarily granting admin role to the deployer for straightforward configuration
        domain.almProxy = new ALMProxy(msg.sender);
        domain.almController = new ForeignController({
            admin_ : msg.sender,
            proxy_ : address(domain.almProxy),
            psm_   : address(domain.psm),
            usds_  : address(domain.usds),
            usdc_  : domain.config.readAddress(".usdc"),
            susds_ : address(domain.susds),
            cctp_  : domain.config.readAddress(".cctpTokenMessenger")
        });

        domain.almController.grantRole(domain.almController.FREEZER(),            domain.config.readAddress(".freezer"));
        domain.almController.grantRole(domain.almController.RELAYER(),            domain.safe);
        domain.almController.grantRole(domain.almController.DEFAULT_ADMIN_ROLE(), domain.l2BridgeInstance.govRelay);

        domain.almController.revokeRole(domain.almController.DEFAULT_ADMIN_ROLE(), msg.sender);

        domain.almProxy.grantRole(domain.almProxy.CONTROLLER(),         address(domain.almController));
        domain.almProxy.grantRole(domain.almProxy.DEFAULT_ADMIN_ROLE(), domain.l2BridgeInstance.govRelay);

        domain.almProxy.revokeRole(domain.almProxy.DEFAULT_ADMIN_ROLE(), msg.sender);

        vm.stopBroadcast();

        ScriptTools.exportContract(domain.name, "almProxy",      address(domain.almProxy));
        ScriptTools.exportContract(domain.name, "almController", address(domain.almController));
    }

    function run() public {
        vm.setEnv("FOUNDRY_ROOT_CHAINID", "1");
        vm.setEnv("FOUNDRY_EXPORTS_OVERWRITE_LATEST", "true");

        deployer = msg.sender;

        mainnet = createEthereumDomain();
        base    = createOpStackForeignDomain("base");

        setupNewTokens();
        setupAllocationSystem();
        setupSafe();
        setupALMController();

        setupOpStackTokenBridge(base);
        setupOpStackCrossChainDSROracle(base);
        setupOpStackForeignPSM(base);
        setupOpStackSafe(base);
        setupOpStackALMController(base);
    }

}
