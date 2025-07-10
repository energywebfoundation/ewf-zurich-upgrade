// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/**
 * @dev Bridging contract between Energy Web Chain tier 1 (T1) and Energy Web X tier 2 (T2) blockchains.
 * Enables POS "author" nodes to periodically publish the transactional state of T2 to T1.
 * Enables authors to be added and removed from participation in consensus.
 * Enables the "lifting" of any EWT or ERC20 tokens from T1 to the specified account on T2.
 * Enables the "lowering" of EWT and ERC20 tokens from T2 to the T1 account specified in the T2 proof.
 * Proxy upgradeable implementation utilising EIP-1822
 */

import './interfaces/IEnergyBridge.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/interfaces/IERC20.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';

contract EnergyBridge is IEnergyBridge, Initializable, UUPSUpgradeable, OwnableUpgradeable {
  using SafeERC20 for IERC20;

  string private constant ESM_PREFIX = '\x19Ethereum Signed Message:\n32';
  address private constant PSEUDO_EWT_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
  uint256 private constant LIFT_LIMIT = type(uint128).max;
  uint256 private constant MINIMUM_NUMBER_OF_AUTHORS = 4;
  uint256 private constant LOWER_DATA_LENGTH = 20 + 32 + 20 + 4; // token address + amount + recipient address + lower ID
  uint256 private constant SIGNATURE_LENGTH = 65;
  uint256 private constant MINIMUM_PROOF_LENGTH = LOWER_DATA_LENGTH + SIGNATURE_LENGTH * 2;
  uint256 private constant UNLOCKED = 1;
  uint256 private constant LOCKED = 2;
  int8 private constant TX_SUCCEEDED = 1;
  int8 private constant TX_PENDING = 0;
  int8 private constant TX_FAILED = -1;

  /// @custom:oz-renamed-from isRegisteredCollator
  mapping(uint256 => bool) public isAuthor;
  /// @custom:oz-renamed-from isActiveCollator
  mapping(uint256 => bool) public authorIsActive;
  mapping(address => uint256) public t1AddressToId;
  /// @custom:oz-renamed-from t2PublicKeyToId
  mapping(bytes32 => uint256) public t2PubKeyToId;
  mapping(uint256 => address) public idToT1Address;
  /// @custom:oz-renamed-from idToT2PublicKey
  mapping(uint256 => bytes32) public idToT2PubKey;
  mapping(bytes2 => uint256) public numBytesToLowerData;
  mapping(bytes32 => bool) public isPublishedRootHash;
  /// @custom:oz-renamed-from isUsedT2TransactionId
  mapping(uint256 => bool) public isUsedT2TxId;
  mapping(bytes32 => bool) public hasLowered;

  /// @custom:oz-renamed-from quorum
  uint256[2] public _unused1_;
  /// @custom:oz-renamed-from numActiveCollators
  uint256 public numActiveAuthors;
  /// @custom:oz-renamed-from nextCollatorId
  uint256 public nextAuthorId;
  /// @custom:oz-renamed-from collatorFunctionsAreEnabled
  bool public authorsEnabled;
  /// @custom:oz-renamed-from liftingIsEnabled
  bool public liftingEnabled;
  /// @custom:oz-renamed-from loweringIsEnabled
  bool public loweringEnabled;
  address public pendingOwner;
  uint256 private _lock;

  mapping(address => uint256) public minimumLiftAmount;
  uint256 public defaultMinimumLiftDenominator;

  error AddressMismatch();
  error AlreadyAdded();
  error AuthorsDisabled();
  error BelowMinimumLift();
  error BadConfirmations();
  error CannotChangeT2Key(bytes32 existingT2PubKey);
  error InvalidProof();
  error InvalidT1Key();
  error InvalidT2Key();
  error InvalidTxData();
  error LiftDisabled();
  error LiftFailed();
  error LiftLimitHit();
  error Locked();
  error LowerDisabled();
  error LowerIsUsed();
  error MissingKeys();
  error NotALowerTx();
  error NotAnAuthor();
  error NotEnoughAuthors();
  error PaymentFailed();
  error PendingOwnerOnly();
  error RenounceOwnershipDisabled();
  error RootHashIsUsed();
  error T1AddressInUse(address t1Address);
  error T2KeyInUse(bytes32 t2PubKey);
  error TxIdIsUsed();
  error UnsignedTx();
  error WindowExpired();

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    address[] calldata t1Addresses,
    bytes32[] calldata t1PubKeysLHS,
    bytes32[] calldata t1PubKeysRHS,
    bytes32[] calldata t2PubKeys
  ) public initializer {
    __Ownable_init(msg.sender);
    __UUPSUpgradeable_init();
    numBytesToLowerData[0x5900] = 133; // callID (2 bytes) + proof (2 prefix + 32 relayer + 32 signer + 1 prefix + 64 signature)
    numBytesToLowerData[0x5700] = 133; // callID (2 bytes) + proof (2 prefix + 32 relayer + 32 signer + 1 prefix + 64 signature)
    numBytesToLowerData[0x5702] = 2; // callID (2 bytes)
    authorsEnabled = true;
    liftingEnabled = true;
    loweringEnabled = true;
    nextAuthorId = 1;
    _initialiseAuthors(t1Addresses, t1PubKeysLHS, t1PubKeysRHS, t2PubKeys);
  }

  modifier onlyWhenLiftingEnabled() {
    if (!liftingEnabled) revert LiftDisabled();
    _;
  }

  modifier onlyWhenLoweringEnabled() {
    if (!loweringEnabled) revert LowerDisabled();
    _;
  }

  modifier onlyWhenAuthorsEnabled() {
    if (!authorsEnabled) revert AuthorsDisabled();
    _;
  }

  modifier onlyIfLiftMinimumIsReached(address token, uint256 amount) {
    uint256 minimumAmount = minimumLiftAmount[token];

    if (minimumAmount == 0 && token != PSEUDO_EWT_ADDRESS && defaultMinimumLiftDenominator != 0) {
      minimumAmount = IERC20(token).totalSupply() / defaultMinimumLiftDenominator;
    }

    if (amount == 0 || amount < minimumAmount) revert BelowMinimumLift();
    _;
  }

  modifier onlyWithinCallWindow(uint256 expiry) {
    if (block.timestamp > expiry) revert WindowExpired();
    _;
  }

  modifier lock() {
    if (_lock == LOCKED) revert Locked();
    _lock = LOCKED;
    _;
    _lock = UNLOCKED;
  }

  /**
   * @dev Allows the owner to enable/disable author functionality.
   */
  function toggleAuthors(bool state) external onlyOwner {
    authorsEnabled = state;
    emit LogAuthorsEnabled(state);
  }

  /**
   * @dev Allows the owner to enable/disable lifting.
   */
  function toggleLifting(bool state) external onlyOwner {
    liftingEnabled = state;
    emit LogLiftingEnabled(state);
  }

  /**
   * @dev Allows the owner to enable/disable lowering.
   */
  function toggleLowering(bool state) external onlyOwner {
    loweringEnabled = state;
    emit LogLoweringEnabled(state);
  }

  /**
   * @dev Allows the owner to set the minimum amount of a token the bridge will lift.
   */
  function setMinimumLiftAmount(address token, uint256 amount) external onlyOwner {
    minimumLiftAmount[token] = amount;
    emit LogMinimumLiftAmount(token, amount);
  }

  /**
   * @dev Allows the owner to set the value required to calculate the default minimum lift amount for any token.
   */
  function setDefaultMinimumLift(uint256 denominator) external onlyOwner {
    defaultMinimumLiftDenominator = denominator;
    emit LogDefaultMinimumLift(denominator);
  }

  /**
   * @dev Enables T2 to add a new author, permanently associating their T1 and T2 accounts and enabling
   * them to take part in consensus. Can also be used to reactivate an author, provided their details
   * have not changed. Activation of the author occurs on the first confirmation received from them.
   */
  function addAuthor(
    bytes calldata t1PubKey,
    bytes32 t2PubKey,
    uint256 expiry,
    uint32 t2TxId,
    bytes calldata confirmations
  ) external onlyWhenAuthorsEnabled onlyWithinCallWindow(expiry) {
    if (t1PubKey.length != 64) revert InvalidT1Key();
    address t1Address = address(uint160(uint256(keccak256(t1PubKey))));
    uint256 id = t1AddressToId[t1Address];
    if (isAuthor[id]) revert AlreadyAdded();

    _verifyConfirmations(false, keccak256(abi.encode(t1PubKey, t2PubKey, expiry, t2TxId)), confirmations);
    _storeT2TxId(t2TxId);

    if (id == 0) {
      _addNewAuthor(t1Address, t2PubKey);
    } else {
      if (t2PubKey != idToT2PubKey[id]) revert CannotChangeT2Key(idToT2PubKey[id]);
      isAuthor[id] = true;
    }

    emit LogAuthorAdded(t1Address, t2PubKey, t2TxId);
  }

  /**
   * @dev Enables T2 to remove an author, immediately revoking their authority on T1.
   */
  function removeAuthor(
    bytes32 t2PubKey,
    bytes calldata t1PubKey,
    uint256 expiry,
    uint32 t2TxId,
    bytes calldata confirmations
  ) external onlyWhenAuthorsEnabled onlyWithinCallWindow(expiry) {
    if (t1PubKey.length != 64) revert InvalidT1Key();
    uint256 id = t2PubKeyToId[t2PubKey];
    if (!isAuthor[id]) revert NotAnAuthor();

    isAuthor[id] = false;

    if (numActiveAuthors <= MINIMUM_NUMBER_OF_AUTHORS) revert NotEnoughAuthors();

    if (authorIsActive[id]) {
      authorIsActive[id] = false;
      unchecked {
        --numActiveAuthors;
      }
    }

    _verifyConfirmations(false, keccak256(abi.encode(t2PubKey, t1PubKey, expiry, t2TxId)), confirmations);
    _storeT2TxId(t2TxId);

    emit LogAuthorRemoved(idToT1Address[id], t2PubKey, t2TxId);
  }

  /**
   * @dev Enables T2 to publish a Merkle tree root hash representing the latest set of calls to have been made on T2.
   */
  function publishRoot(
    bytes32 rootHash,
    uint256 expiry,
    uint32 t2TxId,
    bytes calldata confirmations
  ) external onlyWhenAuthorsEnabled onlyWithinCallWindow(expiry) {
    if (isPublishedRootHash[rootHash]) revert RootHashIsUsed();
    _verifyConfirmations(false, keccak256(abi.encode(rootHash, expiry, t2TxId)), confirmations);
    _storeT2TxId(t2TxId);
    isPublishedRootHash[rootHash] = true;
    emit LogRootPublished(rootHash, t2TxId);
  }

  /**
   * @dev Enables anyone to move an amount of ERC20 tokens to the specified 32 byte public key of the recipient on T2.
   * Tokens must first be approved for use by this contract.
   * Fails if it will cause the total amount of the tokens currently lifted to exceed 340282366920938463463374607431768211455.
   * Fails if the amount falls below the minimum lifting threshold for the token.
   */
  function lift(
    address token,
    bytes calldata t2PubKey,
    uint256 amount
  ) external onlyWhenLiftingEnabled onlyIfLiftMinimumIsReached(token, amount) lock {
    uint256 existingBalance = IERC20(token).balanceOf(address(this));
    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    uint256 newBalance = IERC20(token).balanceOf(address(this));
    if (newBalance <= existingBalance) revert LiftFailed();
    if (newBalance > LIFT_LIMIT) revert LiftLimitHit();
    emit LogLifted(token, _checkT2PubKey(t2PubKey), newBalance - existingBalance);
  }

  /**
   * @dev Enables anyone to lift an amount of EWT to the specified 32 byte public key of the T2 recipient.
   */
  function liftEWT(
    bytes calldata t2PubKey
  ) external payable onlyWhenLiftingEnabled onlyIfLiftMinimumIsReached(PSEUDO_EWT_ADDRESS, msg.value) lock {
    emit LogLifted(PSEUDO_EWT_ADDRESS, _checkT2PubKey(t2PubKey), msg.value);
  }

  /**
   * @dev Method deprecated - please use claimLower() instead.
   */
  function legacyLower(bytes calldata leaf, bytes32[] calldata merklePath) external onlyWhenLoweringEnabled lock {
    bytes32 leafHash = keccak256(leaf);
    if (!confirmTransaction(leafHash, merklePath)) revert InvalidTxData();
    if (hasLowered[leafHash]) revert LowerIsUsed();
    hasLowered[leafHash] = true;

    uint256 ptr;

    // Determine the position of the Call ID in the leaf:
    unchecked {
      ptr += _getCompactIntegerByteSize(leaf[0]); // add number of bytes encoding the leaf length
      if (leaf[ptr] & 0x80 == 0x0) revert UnsignedTx(); // bitwise version check to ensure leaf is a signed tx
      // add version(1) + multiAddress type(1) + sender(32) + curve type(1) + signature(64) = 99 bytes to check era bytes:
      ptr += leaf[ptr + 99] == 0x0 ? 100 : 101; // add 99 + number of era bytes (immortal is 1, otherwise 2)
      ptr += _getCompactIntegerByteSize(leaf[ptr]); // add number of bytes encoding the nonce
      ptr += _getCompactIntegerByteSize(leaf[ptr]); // add number of bytes encoding the tip
    }

    bytes2 callId;

    // Retrieve the Call ID from the leaf:
    assembly {
      ptr := add(ptr, leaf.offset)
      callId := calldataload(ptr)
    }

    uint256 numBytesToSkip = numBytesToLowerData[callId]; // get the number of bytes between the pointer and the lower arguments
    if (numBytesToSkip == 0) revert NotALowerTx(); // we don't recognise this Call ID as a lower so revert

    bytes32 t2PubKey;
    address token;
    uint128 amount;
    address recipient;

    assembly {
      ptr := add(ptr, numBytesToSkip) // skip the required number of bytes to point to the start of lower transaction arguments
      t2PubKey := calldataload(ptr) // load next 32 bytes into 32 byte type starting at ptr
      token := calldataload(add(ptr, 20)) // load leftmost 20 of next 32 bytes into 20 byte type starting at ptr + 20
      amount := calldataload(add(ptr, 36)) // load leftmost 16 of next 32 bytes into 16 byte type starting at ptr + 20 + 16
      recipient := calldataload(add(ptr, 56)) // load leftmost 20 of next 32 bytes type starting at ptr + 20 + 16 + 20

      // the amount was encoded in little endian so reverse it to big endian:
      amount := or(
        shr(8, and(amount, 0xFF00FF00FF00FF00FF00FF00FF00FF00)),
        shl(8, and(amount, 0x00FF00FF00FF00FF00FF00FF00FF00FF))
      )
      amount := or(
        shr(16, and(amount, 0xFFFF0000FFFF0000FFFF0000FFFF0000)),
        shl(16, and(amount, 0x0000FFFF0000FFFF0000FFFF0000FFFF))
      )
      amount := or(
        shr(32, and(amount, 0xFFFFFFFF00000000FFFFFFFF00000000)),
        shl(32, and(amount, 0x00000000FFFFFFFF00000000FFFFFFFF))
      )
      amount := or(shr(64, amount), shl(64, amount))
    }

    _releaseFunds(token, amount, recipient);
    emit LogLegacyLowered(token, recipient, t2PubKey, amount);
  }

  /**
   * @dev Enables anyone to claim the amount of funds specified in the T2-supplied proof, for the intended recipient.
   */
  function claimLower(bytes calldata proof) external onlyWhenLoweringEnabled lock {
    if (proof.length < MINIMUM_PROOF_LENGTH) revert InvalidProof();

    address token;
    uint256 amount;
    address recipient;
    uint32 lowerId;

    assembly {
      token := shr(96, calldataload(proof.offset))
      amount := calldataload(add(proof.offset, 20))
      recipient := shr(96, calldataload(add(proof.offset, 52)))
      lowerId := shr(224, calldataload(add(proof.offset, 72)))
    }

    bytes32 lowerHash = keccak256(abi.encodePacked(token, amount, recipient, lowerId));
    if (hasLowered[lowerHash]) revert LowerIsUsed();
    hasLowered[lowerHash] = true;

    _verifyConfirmations(true, lowerHash, proof[LOWER_DATA_LENGTH:]);
    _releaseFunds(token, amount, recipient);

    emit LogLowerClaimed(lowerId);
    emit LogLowered(lowerId, token, recipient, amount);
  }

  /** @dev Check a lower proof. Returns the details, proof validity, and whether or not the lower has been claimed.
   * For unclaimed lowers, if the confirmations required exceed those provided then the proof must be regenerated
   * by T2 before claiming.
   */
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
    )
  {
    if (proof.length < MINIMUM_PROOF_LENGTH) return (address(0), 0, address(0), 0, 0, 0, false, false);

    token = address(bytes20(proof[0:20]));
    amount = uint256(bytes32(proof[20:52]));
    recipient = address(bytes20(proof[52:72]));
    lowerId = uint32(bytes4(proof[72:LOWER_DATA_LENGTH]));
    bytes32 lowerHash = keccak256(abi.encodePacked(token, amount, recipient, lowerId));
    uint256 numConfirmations = (proof.length - LOWER_DATA_LENGTH) / SIGNATURE_LENGTH;
    bool[] memory confirmed = new bool[](nextAuthorId);
    bytes32 ethSignedPrefixMsgHash = keccak256(abi.encodePacked(ESM_PREFIX, lowerHash));
    uint256 confirmationsOffset;

    lowerIsClaimed = hasLowered[lowerHash];
    confirmationsProvided = numConfirmations;
    confirmationsRequired = _requiredConfirmations();
    assembly {
      confirmationsOffset := add(proof.offset, LOWER_DATA_LENGTH)
    }

    for (uint256 i = 0; i < numConfirmations; ++i) {
      uint256 id = _recoverAuthorId(ethSignedPrefixMsgHash, confirmationsOffset, i);
      if (authorIsActive[id] && !confirmed[id]) confirmed[id] = true;
      else confirmationsProvided--;
    }

    proofIsValid = confirmationsProvided >= confirmationsRequired;
  }

  /**
   * @dev Enables anyone to check the current status of any author transaction. Helper function, intended for use by T2 authors.
   */
  function corroborate(uint32 t2TxId, uint256 expiry) external view returns (int8) {
    if (isUsedT2TxId[t2TxId]) return TX_SUCCEEDED;
    else if (block.timestamp > expiry) return TX_FAILED;
    else return TX_PENDING;
  }

  /**
   * @dev The new owner accepts the ownership transfer.
   */
  function acceptOwnership() external {
    if (msg.sender != pendingOwner) revert PendingOwnerOnly();
    delete pendingOwner;
    _transferOwnership(msg.sender);
  }

  /**
   * @dev Confirm the existence of a T2 extrinsic call within a published root.
   */
  function confirmTransaction(bytes32 leafHash, bytes32[] calldata merklePath) public view returns (bool) {
    bytes32 node;
    uint256 i;

    do {
      node = merklePath[i];
      leafHash = leafHash < node ? keccak256(abi.encode(leafHash, node)) : keccak256(abi.encode(node, leafHash));
      unchecked {
        ++i;
      }
    } while (i < merklePath.length);

    return isPublishedRootHash[leafHash];
  }

  /** @dev Starts the ownership transfer of the contract to a new account. Replaces the pending transfer if there is one.
   *  Can only be called by the current owner.
   */
  function transferOwnership(address newOwner) public override onlyOwner {
    pendingOwner = newOwner;
    emit OwnershipTransferStarted(owner(), newOwner);
  }

  /**
   * @dev Disables the renounceOwnership function to prevent relinquishing ownership.
   */
  function renounceOwnership() public view override onlyOwner {
    revert RenounceOwnershipDisabled();
  }

  function _authorizeUpgrade(address) internal override onlyOwner {}

  function _initialiseAuthors(
    address[] calldata t1Addresses,
    bytes32[] calldata t1PubKeysLHS,
    bytes32[] calldata t1PubKeysRHS,
    bytes32[] calldata t2PubKeys
  ) private {
    uint256 numAuth = t1Addresses.length;
    if (numAuth < MINIMUM_NUMBER_OF_AUTHORS) revert NotEnoughAuthors();
    if (t1PubKeysLHS.length != numAuth || t1PubKeysRHS.length != numAuth || t2PubKeys.length != numAuth) revert MissingKeys();

    bytes memory t1PubKey;
    address t1Address;
    uint256 i;

    do {
      t1Address = t1Addresses[i];
      t1PubKey = abi.encode(t1PubKeysLHS[i], t1PubKeysRHS[i]);
      if (address(uint160(uint256(keccak256(t1PubKey)))) != t1Address) revert AddressMismatch();
      if (t1AddressToId[t1Address] != 0) revert T1AddressInUse(t1Address);
      _activateAuthor(_addNewAuthor(t1Address, t2PubKeys[i]));
      unchecked {
        ++i;
      }
    } while (i < numAuth);
  }

  function _addNewAuthor(address t1Address, bytes32 t2PubKey) private returns (uint256 id) {
    unchecked {
      id = nextAuthorId++;
    }
    if (t2PubKeyToId[t2PubKey] != 0) revert T2KeyInUse(t2PubKey);
    idToT1Address[id] = t1Address;
    idToT2PubKey[id] = t2PubKey;
    t1AddressToId[t1Address] = id;
    t2PubKeyToId[t2PubKey] = id;
    isAuthor[id] = true;
  }

  function _activateAuthor(uint256 id) private {
    authorIsActive[id] = true;
    unchecked {
      ++numActiveAuthors;
    }
  }

  function _releaseFunds(address token, uint256 amount, address recipient) private {
    if (token == PSEUDO_EWT_ADDRESS) {
      (bool success, ) = payable(recipient).call{ value: amount }('');
      if (!success) revert PaymentFailed();
    } else IERC20(token).safeTransfer(recipient, amount);
  }

  // reference: https://docs.substrate.io/reference/scale-codec/#fn-1
  function _getCompactIntegerByteSize(bytes1 checkByte) private pure returns (uint8 result) {
    result = uint8(checkByte);
    assembly {
      switch and(result, 3)
      case 0 {
        result := 1
      } // single-byte mode
      case 1 {
        result := 2
      } // two-byte mode
      case 2 {
        result := 4
      } // four-byte mode
      default {
        result := add(shr(2, result), 5)
      } // upper 6 bits + 4 = number of bytes to follow + 1 for checkbyte
    }
  }

  function _requiredConfirmations() private view returns (uint256 required) {
    required = numActiveAuthors;
    unchecked {
      required -= (required * 2) / 3;
    }
  }

  function _verifyConfirmations(bool isLower, bytes32 msgHash, bytes calldata confirmations) private {
    uint256[] memory confirmed = new uint256[](nextAuthorId);
    bytes32 ethSignedPrefixMsgHash = keccak256(abi.encodePacked(ESM_PREFIX, msgHash));
    uint256 requiredConfirmations = _requiredConfirmations();
    uint256 numConfirmations = confirmations.length / SIGNATURE_LENGTH;
    uint256 confirmationsOffset;
    uint256 confirmationsIndex;
    uint256 validConfirmations;
    uint256 authorId;

    assembly {
      confirmationsOffset := confirmations.offset
    }

    // Setup the first iteration of the do-while loop:
    if (isLower) {
      // For lowers all confirmations are explicit so the first authorId is extracted from the first confirmation
      authorId = _recoverAuthorId(ethSignedPrefixMsgHash, confirmationsOffset, confirmationsIndex);
      confirmationsIndex = 1;
    } else {
      // For non-lowers there is a high likelihood the sender is an author, so their confirmation is taken to be implicit
      authorId = t1AddressToId[msg.sender];
      unchecked {
        ++numConfirmations;
      }
    }

    do {
      if (!authorIsActive[authorId]) {
        if (isAuthor[authorId]) {
          _activateAuthor(authorId);
          unchecked {
            ++validConfirmations;
          }
          requiredConfirmations = _requiredConfirmations();
          if (validConfirmations == requiredConfirmations) return; // success
          confirmed[authorId] = 1;
        }
      } else if (confirmed[authorId] == 0) {
        unchecked {
          ++validConfirmations;
        }
        if (validConfirmations == requiredConfirmations) return; // success
        confirmed[authorId] = 1;
      }

      // Setup the next iteration of the loop:
      authorId = _recoverAuthorId(ethSignedPrefixMsgHash, confirmationsOffset, confirmationsIndex);
      unchecked {
        ++confirmationsIndex;
      }
    } while (confirmationsIndex <= numConfirmations);

    revert BadConfirmations();
  }

  function _recoverAuthorId(
    bytes32 ethSignedPrefixMsgHash,
    uint256 confirmationsOffset,
    uint256 confirmationsIndex
  ) private view returns (uint256 id) {
    bytes32 r;
    bytes32 s;
    uint8 v;

    assembly {
      let sig := add(confirmationsOffset, mul(confirmationsIndex, SIGNATURE_LENGTH))
      r := calldataload(sig)
      s := calldataload(add(sig, 32))
      v := byte(0, calldataload(add(sig, 64)))
    }

    if (v < 27) {
      unchecked {
        v += 27;
      }
    }

    id = v < 29 && uint256(s) <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0
      ? t1AddressToId[ecrecover(ethSignedPrefixMsgHash, v, r, s)]
      : 0;
  }

  function _storeT2TxId(uint256 t2TxId) private {
    if (isUsedT2TxId[t2TxId]) revert TxIdIsUsed();
    isUsedT2TxId[t2TxId] = true;
  }

  function _checkT2PubKey(bytes calldata t2PubKey) private pure returns (bytes32 checkedT2PubKey) {
    if (t2PubKey.length != 32) revert InvalidT2Key();
    checkedT2PubKey = bytes32(t2PubKey);
  }
}