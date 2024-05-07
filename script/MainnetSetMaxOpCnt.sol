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

    RegistryCoordinator public regCo;

    function run() external {
        regCo = RegistryCoordinator(address(0x434621cfd8BcDbe8839a33c85aE2B2893a4d596C));
        vm.startBroadcast();
        IRegistryCoordinator.OperatorSetParam memory opSetParam = IRegistryCoordinator.OperatorSetParam(66, 11000, 50);
        regCo.setOperatorSetParams(1, opSetParam);
        vm.stopBroadcast();
    }
}
