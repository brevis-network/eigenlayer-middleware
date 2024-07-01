// SPDX-License-Identifier: MIT
pragma solidity =0.8.12;

import {BLSSignatureChecker, IRegistryCoordinator, IStakeRegistry} from "./BLSSignatureChecker.sol";
import {ServiceManagerBase, IAVSDirectory} from "./ServiceManagerBase.sol";

// simple contract to verify via eigenlayer BLS
contract BrevisEigen is BLSSignatureChecker, ServiceManagerBase {
    // admin configs
    bytes public quorumNumbers = hex"00_01"; // 2 quorums, value to be determined

    // if request has been verified, will save reqKey -> true, reqKey = keccak256(abi.encodePacked(_proofId, _nonce));
    mapping(bytes32 => bool) public records;
    // this reqid has been verified by agg bls sig
    event Verified(bytes32 requestId, bytes32[] proofIds, uint64[] nonces);

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
        bytes32[] calldata _proofIds,
        uint64[] calldata _nonces,
        NonSignerStakesAndSignature memory nonSignerStakesAndSignature
    ) external {
        require(_proofIds.length == _nonces.length, "length not match");
        bytes32 msghash = keccak256(abi.encodePacked(block.chainid, address(this), "BrevisEigen", reqid, blockNum));
        bytes memory memQ = quorumNumbers;
        (
            QuorumStakeTotals memory quorumStakeTotals,
            bytes32 hashOfNonSigners
        ) = checkSignatures(
                msghash,
                memQ,
                uint32(blockNum),
                nonSignerStakesAndSignature
            );
        for (uint i = 0; i < quorumNumbers.length; i++) {
            // must over 2/3
            require(quorumStakeTotals.signedStakeForQuorum[i] >= (quorumStakeTotals.totalStakeForQuorum[i]*2)/3+1);
        }
        require(reqid == keccak256(abi.encodePacked(_proofIds, _nonces)), "invalid _proofIds and _nonces");
        for (uint i = 0; i < _proofIds.length; i++) {
            records[keccak256(abi.encodePacked(_proofIds[i], _nonces[i]))] = true;
        }
        emit Verified(reqid, _proofIds, _nonces);
    }

    // require all reqIds have been verified
    function mustVerified(bytes32[] calldata _proofIds, uint64[] calldata _nonces) public view {
        require(_proofIds.length == _nonces.length, "length not match");
        for (uint256 i = 0; i < _proofIds.length; i++) {
            require(records[keccak256(abi.encodePacked(_proofIds[i], _nonces[i]))] == true);
        }
    }

    // admin only
    function setQuorums(bytes calldata newQ) external onlyOwner() {
        quorumNumbers = newQ;
    }
}