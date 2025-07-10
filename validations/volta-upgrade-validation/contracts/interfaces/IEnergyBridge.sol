// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IEnergyBridge {
  event LogAuthorsEnabled(bool indexed state);
  event LogLiftingEnabled(bool indexed state);
  event LogLoweringEnabled(bool indexed state);
  event LogMinimumLiftAmount(address indexed token, uint256 amount);
  event LogDefaultMinimumLift(uint256 denominator);
  event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

  event LogAuthorAdded(address indexed t1Address, bytes32 indexed t2PubKey, uint32 indexed t2TxId);
  event LogAuthorRemoved(address indexed t1Address, bytes32 indexed t2PubKey, uint32 indexed t2TxId);
  event LogRootPublished(bytes32 indexed rootHash, uint32 indexed t2TxId);

  event LogLifted(address indexed token, bytes32 indexed t2PubKey, uint256 amount);
  event LogLegacyLowered(address indexed token, address indexed t1Address, bytes32 indexed t2PubKey, uint256 amount);
  event LogLowerClaimed(uint32 indexed lowerId);
  event LogLowered(uint32 indexed lowerId, address indexed token, address indexed recipient, uint256 amount);

  // Owner only
  function toggleAuthors(bool state) external;
  function toggleLifting(bool state) external;
  function toggleLowering(bool state) external;
  function setMinimumLiftAmount(address token, uint256 amount) external;
  function setDefaultMinimumLift(uint256 denominator) external;

  // Authors only
  function addAuthor(
    bytes calldata t1PubKey,
    bytes32 t2PubKey,
    uint256 expiry,
    uint32 t2TxId,
    bytes calldata confirmations
  ) external;
  function removeAuthor(
    bytes32 t2PubKey,
    bytes calldata t1PubKey,
    uint256 expiry,
    uint32 t2TxId,
    bytes calldata confirmations
  ) external;
  function publishRoot(bytes32 rootHash, uint256 expiry, uint32 t2TxId, bytes calldata confirmations) external;

  // Public
  function lift(address token, bytes calldata t2PubKey, uint256 amount) external;
  function liftEWT(bytes calldata t2PubKey) external payable;
  function legacyLower(bytes calldata leaf, bytes32[] calldata merklePath) external;
  function claimLower(bytes calldata proof) external;
  function checkLower(
    bytes calldata proof
  )
    external
    view
    returns (
      address token,
      uint256 amount,
      address recipient,
      uint32 lowerId,
      uint256 confirmationsRequired,
      uint256 confirmationsProvided,
      bool proofIsValid,
      bool lowerIsClaimed
    );
  function confirmTransaction(bytes32 leafHash, bytes32[] calldata merklePath) external view returns (bool);
  function corroborate(uint32 t2TxId, uint256 expiry) external view returns (int8);
}