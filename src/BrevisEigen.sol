// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {BLSSignatureChecker, IRegistryCoordinator, IStakeRegistry} from "./BLSSignatureChecker.sol";
import {ServiceManagerBase, IAVSDirectory} from "./ServiceManagerBase.sol";

// simple contract to verify via eigenlayer BLS
contract BrevisEigen is BLSSignatureChecker, ServiceManagerBase {
    // admin configs
    bytes public quorumNumbers = hex"00_01"; // 2 quorums, value to be determined
    uint64 public blkNumTimeout = 20000; // only accept recent reference block number

    constructor(
        IAVSDirectory __avsDirectory,
        IRegistryCoordinator __registryCoordinator,
        IStakeRegistry __stakeRegistry
    ) 
        BLSSignatureChecker(__registryCoordinator)
        ServiceManagerBase(__avsDirectory, __registryCoordinator, __stakeRegistry) {
            _disableInitializers();
    }

    function initialize(
        address _initialOwner
    )
        public
        initializer
    {
        _transferOwnership(_initialOwner);
    }

    // verify sigs
    function verifySigs(
        bytes32 msgHash,
        uint64 blockNum,
        NonSignerStakesAndSignature memory nonSignerStakesAndSignature
    ) external view {
        require(blockNum > uint64(block.number) - blkNumTimeout, "not recent block number");
        bytes memory memQ = quorumNumbers;
        (
            QuorumStakeTotals memory quorumStakeTotals,
            bytes32 hashOfNonSigners
        ) = checkSignatures(
                msgHash,
                memQ,
                uint32(blockNum),
                nonSignerStakesAndSignature
            );
        for (uint i = 0; i < quorumNumbers.length; i++) {
            // must over 2/3
            require(quorumStakeTotals.signedStakeForQuorum[i] >= (quorumStakeTotals.totalStakeForQuorum[i]*2)/3+1);
        }
    }

    // admin only
    function setQuorums(bytes calldata newQ) external onlyOwner() {
        quorumNumbers = newQ;
    }

    function setBlkNumTimeout(uint64 timeout) external onlyOwner() {
        blkNumTimeout = blkNumTimeout;
    }
}