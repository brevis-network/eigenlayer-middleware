// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

// eigen core
import {PauserRegistry, IPauserRegistry} from "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";
import {EmptyContract} from "eigenlayer-contracts/src/test/mocks/EmptyContract.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

// eigen middleware
import {BLSApkRegistry} from "src/BLSApkRegistry.sol";
import {IBLSApkRegistry} from "src/interfaces/IBLSApkRegistry.sol";
import {RegistryCoordinator} from "src/RegistryCoordinator.sol";
import {IRegistryCoordinator} from "src/interfaces/IRegistryCoordinator.sol";
import {IndexRegistry} from "src/IndexRegistry.sol";
import {IIndexRegistry} from "src/interfaces/IIndexRegistry.sol";
import {StakeRegistry} from "src/StakeRegistry.sol";
import {IStakeRegistry} from "src/interfaces/IStakeRegistry.sol";
import {IServiceManager} from "src/interfaces/IServiceManager.sol";
// do we need these two?
// import {OperatorStateRetriever} from "src/OperatorStateRetriever.sol";
// import {ServiceManagerRouter} from "src/ServiceManagerRouter.sol";

// our own
import {BrevisEigen, IAVSDirectory} from "src/BrevisEigen.sol";

// forge utils
import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "forge-std/StdJson.sol";


//forge script script/MyDeploy.s.sol:Deployer --rpc-url $RPC_URL  --private-key $PRIVATE_KEY -vvvv //--broadcast 
contract Deployer {
    address constant private VM_ADDRESS =
        address(bytes20(uint160(uint256(keccak256('hevm cheat code')))));

    Vm public constant vm = Vm(VM_ADDRESS);
    string public deployConfigPath = string.concat("script/configs/mainnet.json");
    string public outputPath = string.concat("script/output/deploy_mainnet.json");

    ProxyAdmin public brevisProxyAdmin;
    address public brevisOwner;
    address public brevisUpgrader;

    PauserRegistry public pauser; // pauserRegistry contract
    uint256 public initalPausedStatus;

    address public avsDirectory; // deployed by eigen team, read from config
    address public delegationManager;
    EmptyContract public emptyContract;

    // middleware proxy and impl
    RegistryCoordinator public registryCoordinator;
    RegistryCoordinator public registryCoordinatorImplementation;
    BLSApkRegistry public apkRegistry;
    BLSApkRegistry public apkRegistryImplementation;
    IndexRegistry public indexRegistry;
    IndexRegistry public indexRegistryImplementation;
    StakeRegistry public stakeRegistry;
    StakeRegistry public stakeRegistryImplementation;
    // OperatorStateRetriever public operatorStateRetriever;
    // ServiceManagerRouter public serviceManagerRouter;
    // our own
    BrevisEigen public brevisEigen;
    BrevisEigen public brevisEigenImplementation;

    function run() external {
        // READ JSON CONFIG DATA
        string memory config_data = vm.readFile(deployConfigPath);

        // check that the chainID matches the one in the config
        uint256 currentChainId = block.chainid;
        uint256 configChainId = stdJson.readUint(config_data, ".chainId");
        // emit log_named_uint("You are deploying on ChainID", currentChainId);
        require(configChainId == currentChainId, "You are on the wrong chain for this config");

        avsDirectory = stdJson.readAddress(config_data, ".avsAddr");
        delegationManager = stdJson.readAddress(config_data, ".delegationMgr");
    
        // parse the addresses of permissioned roles
        brevisOwner = stdJson.readAddress(config_data, ".permissions.owner");
        brevisUpgrader = stdJson.readAddress(config_data, ".permissions.upgrader");
        
        vm.startBroadcast();

        // deploy our own pauser, if already deployed, read from config
        address[] memory pausers = new address[](1);
        pausers[0] = brevisOwner;
        pauser = new PauserRegistry(pausers, brevisOwner);
        // pauser = stdJson.readAddress(config_data, ".permissions.pauser");
        // unpause value is 0, uncomment next if we want to begin w/ paused
        // initalPausedStatus = stdJson.readUint(config_data, ".permissions.initalPausedStatus");

        

        // deploy proxy admin for ability to upgrade proxy contracts
        brevisProxyAdmin = new ProxyAdmin();
        emptyContract = new EmptyContract();

        /**
         * First, deploy upgradeable proxy contracts that **will point** to the implementations. Since the implementation contracts are
         * not yet deployed, we give these proxies an empty contract as the initial implementation, to act as if they have no code.
         */
        brevisEigen = BrevisEigen(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(brevisProxyAdmin), ""))
        );
        registryCoordinator = RegistryCoordinator(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(brevisProxyAdmin), ""))
        );
        indexRegistry = IndexRegistry(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(brevisProxyAdmin), ""))
        );
        stakeRegistry = StakeRegistry(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(brevisProxyAdmin), ""))
        );
        apkRegistry = BLSApkRegistry(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(brevisProxyAdmin), ""))
        );

        //deploy index registry implementation
        indexRegistryImplementation = new IndexRegistry(
            registryCoordinator
        );

        //upgrade index registry proxy to implementation
        brevisProxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(indexRegistry))),
            address(indexRegistryImplementation)
        );

        //deploy stake registry implementation
        stakeRegistryImplementation = new StakeRegistry(
            registryCoordinator,
            IDelegationManager(delegationManager)
        );

        //upgrade stake registry proxy to implementation
        brevisProxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(stakeRegistry))),
            address(stakeRegistryImplementation)
        );

        //deploy apk registry implementation
        apkRegistryImplementation = new BLSApkRegistry(
            registryCoordinator
        );

        //upgrade apk registry proxy to implementation
        brevisProxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(apkRegistry))),
            address(apkRegistryImplementation)
        );

        //deploy the registry coordinator implementation.
        registryCoordinatorImplementation = new RegistryCoordinator(
            IServiceManager(address(brevisEigen)),
            stakeRegistry,
            apkRegistry,
            indexRegistry
        );

        {
        // parse initalization params and permissions from config data
        (
            uint96[] memory minimumStakeForQuourm, 
            IStakeRegistry.StrategyParams[][] memory strategyAndWeightingMultipliers
        ) = _parseStakeRegistryParams(config_data);
        (
            IRegistryCoordinator.OperatorSetParam[] memory operatorSetParams, 
            address churner, 
            address ejector
        ) = _parseRegistryCoordinatorParams(config_data);

        //upgrade the registry coordinator proxy to implementation
        brevisProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(registryCoordinator))),
            address(registryCoordinatorImplementation),
            abi.encodeWithSelector(
                RegistryCoordinator.initialize.selector,
                brevisOwner,
                churner,
                ejector,
                pauser,
                initalPausedStatus, 
                operatorSetParams, 
                minimumStakeForQuourm,
                strategyAndWeightingMultipliers 
            )
        );
        }

        //deploy the brevis service manager implementation
        brevisEigenImplementation = new BrevisEigen(
            IAVSDirectory(avsDirectory),
            registryCoordinator,
            stakeRegistry
        );

        //upgrade the brevis service manager proxy to implementation
        brevisProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(brevisEigen))),
            address(brevisEigenImplementation),
            abi.encodeWithSelector(
                BrevisEigen.initialize.selector,
                brevisOwner
            )
        );

        //deploy the operator state retriever
        // operatorStateRetriever = new OperatorStateRetriever();

        //deploy service manager router
        // serviceManagerRouter = new ServiceManagerRouter();

        // transfer ownership of proxy admin to upgrader
        brevisProxyAdmin.transferOwnership(brevisUpgrader);

        vm.stopBroadcast();

        // sanity checks
        __verifyContractPointers(
            apkRegistry,
            brevisEigen,
            registryCoordinator,
            indexRegistry,
            stakeRegistry
        );

        __verifyContractPointers(
            apkRegistryImplementation,
            brevisEigenImplementation,
            registryCoordinatorImplementation,
            indexRegistryImplementation,
            stakeRegistryImplementation
        );

        __verifyImplementations();
        __verifyInitalizations(config_data);

        //write output
        _writeOutput(config_data);
    }

    function __verifyContractPointers(
        BLSApkRegistry _apkRegistry,
        BrevisEigen _brevisEigen,
        RegistryCoordinator _registryCoordinator,
        IndexRegistry _indexRegistry,
        StakeRegistry _stakeRegistry
    ) internal view {
        require(address(_apkRegistry.registryCoordinator()) == address(registryCoordinator), "blsApkRegistry.registryCoordinator() != registryCoordinator");

        require(address(_indexRegistry.registryCoordinator()) == address(registryCoordinator), "indexRegistry.registryCoordinator() != registryCoordinator");

        require(address(_stakeRegistry.registryCoordinator()) == address(registryCoordinator), "stakeRegistry.registryCoordinator() != registryCoordinator");
        require(address(_stakeRegistry.delegation()) == address(delegationManager), "stakeRegistry.delegationManager() != delegation");

        require(address(_brevisEigen.registryCoordinator()) == address(registryCoordinator), "brevisEigen.registryCoordinator() != registryCoordinator");
        require(address(_brevisEigen.stakeRegistry()) == address(stakeRegistry), "brevisEigen.stakeRegistry() != stakeRegistry");

        require(address(_registryCoordinator.serviceManager()) == address(brevisEigen), "registryCoordinator.brevisEigen() != brevisEigen");
        require(address(_registryCoordinator.stakeRegistry()) == address(stakeRegistry), "registryCoordinator.stakeRegistry() != stakeRegistry");
        require(address(_registryCoordinator.blsApkRegistry()) == address(apkRegistry), "registryCoordinator.blsApkRegistry() != blsPubkeyRegistry");
        require(address(_registryCoordinator.indexRegistry()) == address(indexRegistry), "registryCoordinator.indexRegistry() != indexRegistry");
    }

    function __verifyImplementations() internal view {
        require(brevisProxyAdmin.getProxyImplementation(
            TransparentUpgradeableProxy(payable(address(brevisEigen)))) == address(brevisEigenImplementation),
            "brevisEigen: implementation set incorrectly");
        require(brevisProxyAdmin.getProxyImplementation(
            TransparentUpgradeableProxy(payable(address(registryCoordinator)))) == address(registryCoordinatorImplementation),
            "registryCoordinator: implementation set incorrectly");
        require(brevisProxyAdmin.getProxyImplementation(
            TransparentUpgradeableProxy(payable(address(apkRegistry)))) == address(apkRegistryImplementation),
            "blsApkRegistry: implementation set incorrectly");
        require(brevisProxyAdmin.getProxyImplementation(
            TransparentUpgradeableProxy(payable(address(indexRegistry)))) == address(indexRegistryImplementation),
            "indexRegistry: implementation set incorrectly");
        require(brevisProxyAdmin.getProxyImplementation(
            TransparentUpgradeableProxy(payable(address(stakeRegistry)))) == address(stakeRegistryImplementation),
            "stakeRegistry: implementation set incorrectly");
    }

    function __verifyInitalizations(string memory config_data) internal {
        (
            uint96[] memory minimumStakeForQuourm, 
            IStakeRegistry.StrategyParams[][] memory strategyAndWeightingMultipliers
        ) = _parseStakeRegistryParams(config_data);
        (
            IRegistryCoordinator.OperatorSetParam[] memory operatorSetParams, 
            address churner, 
            address ejector
        ) = _parseRegistryCoordinatorParams(config_data);

        require(brevisEigen.owner() == brevisOwner, "brevisEigen.owner() != brevisOwner");

        require(registryCoordinator.owner() == brevisOwner, "registryCoordinator.owner() != brevisOwner");
        require(registryCoordinator.churnApprover() == churner, "registryCoordinator.churner() != churner");
        require(registryCoordinator.ejector() == ejector, "registryCoordinator.ejector() != ejector");
        require(registryCoordinator.pauserRegistry() == IPauserRegistry(pauser), "registryCoordinator: pauser registry not set correctly");
        require(registryCoordinator.paused() == initalPausedStatus, "registryCoordinator: init paused status set incorrectly");
        
        for (uint8 i = 0; i < operatorSetParams.length; ++i) {
            require(keccak256(abi.encode(registryCoordinator.getOperatorSetParams(i))) == keccak256(abi.encode(operatorSetParams[i])), "registryCoordinator.operatorSetParams != operatorSetParams");
        }

        for (uint8 i = 0; i < minimumStakeForQuourm.length; ++i) {
            require(stakeRegistry.minimumStakeForQuorum(i) == minimumStakeForQuourm[i], "stakeRegistry.minimumStakeForQuourm != minimumStakeForQuourm");
        }

        for (uint8 i = 0; i < strategyAndWeightingMultipliers.length; ++i) {
            for(uint8 j = 0; j < strategyAndWeightingMultipliers[i].length; ++j) {
                IStakeRegistry.StrategyParams memory strategyParams = stakeRegistry.strategyParamsByIndex(i, j);
                require(address(strategyParams.strategy) == address(strategyAndWeightingMultipliers[i][j].strategy), "stakeRegistry.strategyAndWeightingMultipliers != strategyAndWeightingMultipliers");
                require(strategyParams.multiplier == strategyAndWeightingMultipliers[i][j].multiplier, "stakeRegistry.strategyAndWeightingMultipliers != strategyAndWeightingMultipliers");
            }
        }

        require(operatorSetParams.length == strategyAndWeightingMultipliers.length && operatorSetParams.length == minimumStakeForQuourm.length, "operatorSetParams, strategyAndWeightingMultipliers, and minimumStakeForQuourm must be the same length");
    }

    function _writeOutput(string memory config_data) internal {
        string memory parent_object = "parent object";

        string memory deployed_addresses = "addresses";
        vm.serializeAddress(deployed_addresses, "brevisProxyAdmin", address(brevisProxyAdmin));
        // vm.serializeAddress(deployed_addresses, "operatorStateRetriever", address(operatorStateRetriever));
        vm.serializeAddress(deployed_addresses, "brevisEigen", address(brevisEigen));
        vm.serializeAddress(deployed_addresses, "brevisEigenImplementation", address(brevisEigenImplementation));
        vm.serializeAddress(deployed_addresses, "registryCoordinator", address(registryCoordinator));
        vm.serializeAddress(deployed_addresses, "registryCoordinatorImplementation", address(registryCoordinatorImplementation));
        vm.serializeAddress(deployed_addresses, "blsApkRegistry", address(apkRegistry));
        vm.serializeAddress(deployed_addresses, "blsApkRegistryImplementation", address(apkRegistryImplementation));
        vm.serializeAddress(deployed_addresses, "indexRegistry", address(indexRegistry));
        vm.serializeAddress(deployed_addresses, "indexRegistryImplementation", address(indexRegistryImplementation));
        vm.serializeAddress(deployed_addresses, "stakeRegistry", address(stakeRegistry));
        vm.serializeAddress(deployed_addresses, "stakeRegistryImplementation", address(stakeRegistryImplementation));
        string memory deployed_addresses_output = vm.serializeAddress(deployed_addresses, "stakeRegistryImplementation", address(stakeRegistryImplementation));

        string memory chain_info = "chainInfo";
        vm.serializeUint(chain_info, "deploymentBlock", block.number);
        string memory chain_info_output = vm.serializeUint(chain_info, "chainId", block.chainid);

        address churner = stdJson.readAddress(config_data, ".permissions.churner");
        address ejector = stdJson.readAddress(config_data, ".permissions.ejector");
        string memory permissions = "permissions";
        vm.serializeAddress(permissions, "brevisOwner", brevisOwner);
        vm.serializeAddress(permissions, "brevisUpgrader", brevisUpgrader);
        vm.serializeAddress(permissions, "brevisChurner", churner);
        vm.serializeAddress(permissions, "pauserRegistry", address(pauser));
        string memory permissions_output = vm.serializeAddress(permissions, "brevisEjector", ejector);
        
        vm.serializeString(parent_object, chain_info, chain_info_output);
        vm.serializeString(parent_object, deployed_addresses, deployed_addresses_output);
        string memory finalJson = vm.serializeString(parent_object, permissions, permissions_output);
        vm.writeJson(finalJson, outputPath);
    } 

    function _parseStakeRegistryParams(string memory config_data) internal pure returns (uint96[] memory minimumStakeForQuourm, IStakeRegistry.StrategyParams[][] memory strategyAndWeightingMultipliers) {
        bytes memory stakesConfigsRaw = stdJson.parseRaw(config_data, ".minimumStakes");
        minimumStakeForQuourm = abi.decode(stakesConfigsRaw, (uint96[]));
        
        bytes memory strategyConfigsRaw = stdJson.parseRaw(config_data, ".strategyWeights");
        strategyAndWeightingMultipliers = abi.decode(strategyConfigsRaw, (IStakeRegistry.StrategyParams[][]));
    }

    function _parseRegistryCoordinatorParams(string memory config_data) internal returns (IRegistryCoordinator.OperatorSetParam[] memory operatorSetParams, address churner, address ejector) {
        bytes memory operatorConfigsRaw = stdJson.parseRaw(config_data, ".operatorSetParams");
        operatorSetParams = abi.decode(operatorConfigsRaw, (IRegistryCoordinator.OperatorSetParam[]));

        churner = stdJson.readAddress(config_data, ".permissions.churner");
        ejector = stdJson.readAddress(config_data, ".permissions.ejector");
    }
}
