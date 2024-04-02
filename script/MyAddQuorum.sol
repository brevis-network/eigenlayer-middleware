pragma solidity =0.8.12;

import {RegistryCoordinator, IRegistryCoordinator} from "src/RegistryCoordinator.sol";
import {IStakeRegistry} from "src/interfaces/IStakeRegistry.sol";
// import {BrevisEigen, IAVSDirectory} from "src/BrevisEigen.sol";

// forge utils
import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

contract Deployer {
    address constant private VM_ADDRESS =
        address(bytes20(uint160(uint256(keccak256('hevm cheat code')))));
    Vm public constant vm = Vm(VM_ADDRESS);
    string public deployConfigPath = string.concat("script/configs/addquorum.json");

    RegistryCoordinator public regCo;

    function run() external {
        string memory config_data = vm.readFile(deployConfigPath);
        (
            uint96[] memory minimumStakeForQuourm, 
            IStakeRegistry.StrategyParams[][] memory strategyParams
        ) = _parseStakeRegistryParams(config_data);
        
        IRegistryCoordinator.OperatorSetParam[] memory operatorSetParams
         = _parseRegistryCoordinatorParams(config_data);
    
        regCo = RegistryCoordinator(address(0x0dB4ceE042705d47Ef6C0818E82776359c3A80Ca));
        // vm.startPrank(msg.sender);
        vm.startBroadcast();
        regCo.createQuorum(operatorSetParams[0], minimumStakeForQuourm[0], strategyParams[0]);
        vm.stopBroadcast();
    }


    function _parseStakeRegistryParams(string memory config_data) internal pure returns (uint96[] memory minimumStakeForQuourm, IStakeRegistry.StrategyParams[][] memory strategyAndWeightingMultipliers) {
        bytes memory stakesConfigsRaw = stdJson.parseRaw(config_data, ".minimumStakes");
        minimumStakeForQuourm = abi.decode(stakesConfigsRaw, (uint96[]));
        
        bytes memory strategyConfigsRaw = stdJson.parseRaw(config_data, ".strategyWeights");
        strategyAndWeightingMultipliers = abi.decode(strategyConfigsRaw, (IStakeRegistry.StrategyParams[][]));
    }

    function _parseRegistryCoordinatorParams(string memory config_data) internal returns (IRegistryCoordinator.OperatorSetParam[] memory operatorSetParams) {
        bytes memory operatorConfigsRaw = stdJson.parseRaw(config_data, ".operatorSetParams");
        operatorSetParams = abi.decode(operatorConfigsRaw, (IRegistryCoordinator.OperatorSetParam[]));
    }
}