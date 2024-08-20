// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script }  from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";

import { MCD, DssInstance } from "lib/dss-test/src/DssTest.sol";
import { ScriptTools }      from "lib/dss-test/src/ScriptTools.sol";

import { ChainlogAbstract, DSPauseProxyAbstract } from "lib/dss-interfaces/src/Interfaces.sol";

import { Ethereum } from "lib/spark-address-registry/src/Ethereum.sol";

import { NstDeploy, NstInstance } from "lib/nst/deploy/NstDeploy.sol";
import { NstInit }                from "lib/nst/deploy/NstInit.sol";

import { SNstDeploy, SNstInstance } from "lib/sdai/deploy/SNstDeploy.sol";
import { SNstInit, SNstConfig }     from "lib/sdai/deploy/SNstInit.sol";

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
import { MainnetController } from "lib/spark-alm-controller/src/MainnetController.sol";

import { DSROracleForwarderBaseChain } from "lib/xchain-dsr-oracle/src/forwarders/DSROracleForwarderBaseChain.sol";
import { OptimismReceiver }            from "lib/xchain-helpers/src/receivers/OptimismReceiver.sol";
import { DSRAuthOracle }               from "lib/xchain-dsr-oracle/src/DSRAuthOracle.sol";

import { PSM3 } from "lib/spark-psm/src/PSM3.sol";

import { MockERC20 } from "lib/erc20-helpers/src/MockERC20.sol";

interface ISparkProxy {
    function exec(address target, bytes calldata data) external;
}

contract SetupMainnetSpell {

    uint256 constant DSR_INITIAL_RATE     = 1000000001847694957439350562;  // 6% APY
    uint256 constant ALLOCATOR_VAULT_RATE = 1000000001547125957863212448;  // 5% APY

    function initTokens(
        DssInstance memory dss,
        NstInstance memory nstInstance,
        SNstInstance memory snstInstance
    ) external {
        NstInit.init(dss, nstInstance);
        SNstInit.init(dss, snstInstance, SNstConfig({
            nstJoin: nstInstance.nstJoin,
            nst:     nstInstance.nst,
            nsr:     DSR_INITIAL_RATE
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
        NstInstance memory nstInstance,
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
                nstInstance,
                allocatorIlkInstance,
                almProxy,
                mainnetController,
                freezer,
                relayer
            )
        ));
    }

    function sparkProxy_initALMController(
        NstInstance memory nstInstance,
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
            nstInstance.nst,
            address(almProxy),
            type(uint256).max
        );
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
        NstInstance  nstInstance;
        SNstInstance snstInstance;

        // Allocation system
        AllocatorSharedInstance allocatorSharedInstance;
        AllocatorIlkInstance    allocatorIlkInstance;

        // ALM Controller
        MainnetController almController;
        ALMProxy           almProxy;
    }

    struct ForeignDomain {
        string  name;
        string  config;
        uint256 forkId;
        address admin;

        // ALM Controller
        address  almController;
        ALMProxy almProxy;

        // PSM
        PSM3 psm;

        // XChain DSR Oracle
        address       dsrForwarder;  // On Mainnet
        address       dsrReceiver;
        DSRAuthOracle dsrOracle;
    }

    using stdJson for string;
    using ScriptTools for string;
    
    EthereumDomain mainnet;
    ForeignDomain  base;

    address deployer;

    function createEthereumDomain() internal returns (EthereumDomain memory domain) {
        domain.name     = "mainnet";
        domain.config   = ScriptTools.loadConfig(domain.name);
        domain.chainlog = ChainlogAbstract(domain.config.readAddress(".chainlog"));
        // Note we are selecting the fork here because we need to load from the chainlog
        domain.forkId   = vm.createSelectFork(getChain(domain.name).rpcUrl);
        domain.admin    = domain.chainlog.getAddress("MCD_PAUSE_PROXY");
        domain.dss      = MCD.loadFromChainlog(address(domain.chainlog));
        domain.spell    = new SetupMainnetSpell();
    }

    function createForeignDomain(string memory name) internal returns (ForeignDomain memory domain) {
        domain.name   = name;
        domain.config = ScriptTools.loadConfig(name);
        domain.forkId = vm.createFork(getChain(name).rpcUrl);
    }

    function setupNewTokens() internal {
        vm.selectFork(mainnet.forkId);

        vm.startBroadcast();

        // Deploy phase
        mainnet.nstInstance  = NstDeploy.deploy(deployer, mainnet.admin, address(mainnet.dss.daiJoin));
        mainnet.snstInstance = SNstDeploy.deploy(deployer, mainnet.admin, mainnet.nstInstance.nstJoin);

        // Initialization phase (needs executing as pause proxy owner)
        DSPauseProxyAbstract(mainnet.admin).exec(address(mainnet.spell),
            abi.encodeCall(mainnet.spell.initTokens, (
                mainnet.dss,
                mainnet.nstInstance,
                mainnet.snstInstance
            ))
        );

        vm.stopBroadcast();

        ScriptTools.exportContract(mainnet.name, "nst",     mainnet.nstInstance.nst);
        ScriptTools.exportContract(mainnet.name, "nstImp",  mainnet.nstInstance.nstImp);
        ScriptTools.exportContract(mainnet.name, "nstJoin", mainnet.nstInstance.nstJoin);
        ScriptTools.exportContract(mainnet.name, "daiNst",  mainnet.nstInstance.daiNst);

        ScriptTools.exportContract(mainnet.name, "sNst",    mainnet.snstInstance.sNst);
        ScriptTools.exportContract(mainnet.name, "sNstImp", mainnet.snstInstance.sNstImp);
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
            mainnet.nstInstance.nstJoin
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

    function setupALMController() internal {
        vm.selectFork(mainnet.forkId);
        
        vm.startBroadcast();

        mainnet.almProxy = new ALMProxy(Ethereum.SPARK_PROXY);
        mainnet.almController = new MainnetController({
            admin_  : Ethereum.SPARK_PROXY,
            proxy_  : address(mainnet.almProxy),
            vault_  : mainnet.allocatorIlkInstance.vault,
            buffer_ : mainnet.allocatorIlkInstance.buffer,
            psm_    : mainnet.chainlog.getAddress("MCD_LITE_PSM_USDC_A"),
            daiNst_ : mainnet.nstInstance.daiNst,
            snst_   : mainnet.snstInstance.sNst
        });

        DSPauseProxyAbstract(mainnet.admin).exec(address(mainnet.spell),
            abi.encodeCall(mainnet.spell.initALMController, (
                address(mainnet.spell),
                mainnet.nstInstance,
                mainnet.allocatorIlkInstance,
                mainnet.almProxy,
                mainnet.almController,
                mainnet.config.readAddress(".freezer"),
                mainnet.config.readAddress(".relayer")
            ))
        );

        vm.stopBroadcast();

        ScriptTools.exportContract(mainnet.name, "almProxy",      address(mainnet.almProxy));
        ScriptTools.exportContract(mainnet.name, "almController", address(mainnet.almController));
    }

    function setupCrossChainDSROracle(ForeignDomain storage domain) internal {
        vm.selectFork(mainnet.forkId);
        
        address expectedReceiver = vm.computeCreateAddress(deployer, 2);
        if (domain.name.eq("base")) {
            domain.dsrForwarder = address(new DSROracleForwarderBaseChain(address(mainnet.snstInstance.sNst), expectedReceiver));
        }

        vm.selectFork(domain.forkId);

        domain.dsrOracle = new DSRAuthOracle();
        if (domain.name.eq("base")) {
            domain.dsrReceiver = address(new OptimismReceiver(domain.dsrForwarder, address(domain.dsrOracle)));
        }
        domain.dsrOracle.grantRole(domain.dsrOracle.DATA_PROVIDER_ROLE(), domain.dsrReceiver);

        ScriptTools.exportContract(domain.name, "dsrForwarder", domain.dsrForwarder);
        ScriptTools.exportContract(domain.name, "dsrReceiver",  domain.dsrReceiver);
        ScriptTools.exportContract(domain.name, "dsrOracle",    address(domain.dsrOracle));
    }

    function setupForeignPSM(ForeignDomain storage domain) internal {
        vm.selectFork(domain.forkId);
        
        vm.startBroadcast();

        // FIXME: Placeholder until https://github.com/makerdao/op-token-bridge is public
        MockERC20 nst  = new MockERC20("NST", "NST", 18);
        MockERC20 snst = new MockERC20("sNST", "sNST", 18);

        domain.psm = new PSM3(
            base.config.readAddress(".usdc"),
            address(nst),
            address(snst),
            address(domain.dsrOracle)
        );

        vm.stopBroadcast();

        ScriptTools.exportContract(domain.name, "psm", address(domain.psm));
    }

    function run() public {
        vm.setEnv("FOUNDRY_ROOT_CHAINID", "1");
        vm.setEnv("FOUNDRY_EXPORTS_OVERWRITE_LATEST", "true");

        deployer = msg.sender;

        mainnet = createEthereumDomain();
        base    = createForeignDomain("base");

        setupNewTokens();
        setupAllocationSystem();
        setupALMController();

        setupCrossChainDSROracle(base);
        setupForeignPSM(base);
    }

}
