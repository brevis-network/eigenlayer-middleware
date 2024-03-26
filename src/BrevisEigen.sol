// SPDX-License-Identifier: MIT
pragma solidity =0.8.12;

import {BLSSignatureChecker, IRegistryCoordinator, IStakeRegistry} from "./BLSSignatureChecker.sol";
import {ServiceManagerBase, IAVSDirectory} from "./ServiceManagerBase.sol";

// simple contract to verify via eigenlayer BLS
contract BrevisEigen is BLSSignatureChecker, ServiceManagerBase {
    // admin configs
    bytes public quorumNumbers = hex"00_01"; // 2 quorums, value to be determined

    // if request has been verified, will save reqid -> true
    mapping(bytes32 => bool) public records;
    // this reqid has been verified by agg bls sig
    event Verified(bytes32 requestId);

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

    // verify sig
    function verifyRequest(
        bytes32 reqid,
        uint64 blockNum,
        NonSignerStakesAndSignature memory nonSignerStakesAndSignature
    ) external {
        bytes32 msghash = keccak256(abi.encodePacked(block.chainid, address(this), "BrevisEigen",reqid, blockNum));
        (
            QuorumStakeTotals memory quorumStakeTotals,
            bytes32 hashOfNonSigners
        ) = checkSignatures(
                msghash,
                quorumNumbers,
                uint32(blockNum),
                nonSignerStakesAndSignature
            );
        for (uint i = 0; i < quorumNumbers.length; i++) {
            // must over 2/3
            require(quorumStakeTotals.signedStakeForQuorum[i] >= (quorumStakeTotals.totalStakeForQuorum[i]*2)/3+1);
        }
        records[reqid] = true;
        emit Verified(reqid);
    }

    // require all reqIds have been verified
    function mustVerified(bytes32[] calldata reqIds) public view {
        for (uint256 i = 0; i < reqIds.length; i++) {
            require(records[reqIds[i]] == true);
        }
    }

    // admin only
    function setQuorums(bytes calldata newQ) external onlyOwner() {
        quorumNumbers = newQ;
    }
}