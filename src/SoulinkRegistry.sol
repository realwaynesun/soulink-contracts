// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISoulinkRegistry} from "./interfaces/ISoulinkRegistry.sol";

/// @title SoulinkRegistry
/// @notice ERC-721 registry for .agent names on Base
/// @dev Each name is an NFT. Agents pay via x402 operator flow.
///      Deployed behind a UUPS proxy for upgradeability.
contract SoulinkRegistry is
    ISoulinkRegistry,
    Initializable,
    ERC721Upgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    // --- Constants ---

    uint256 public constant REGISTRATION_PERIOD = 365 days;
    uint256 public constant MIN_NAME_LENGTH = 3;
    uint256 public constant MAX_NAME_LENGTH = 32;

    // USDC pricing (6 decimals) — must match server/src/pricing.ts
    uint256 public constant PRICE_SHORT = 100e6;    // $100 for 3-4 character names
    uint256 public constant PRICE_STANDARD = 5e6;   // $5 for 5+ character names

    // --- Storage ---

    IERC20 public usdc;
    uint256 private _nextTokenId;

    /// @dev Authorized API server operators
    mapping(address => bool) public operators;

    /// @dev name hash => AgentIdentity
    mapping(bytes32 => AgentIdentity) private _identities;

    /// @dev name hash => original name string
    mapping(bytes32 => string) private _nameStrings;

    /// @dev token ID => name hash
    mapping(uint256 => bytes32) private _tokenToName;

    /// @dev name hash => encrypted soul data
    mapping(bytes32 => bytes) private _encryptedSouls;

    // --- Modifiers ---

    modifier onlyOperator() {
        require(operators[msg.sender], "Not authorized operator");
        _;
    }

    // --- Initializer ---

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address usdcAddress,
        address initialOwner
    ) external initializer {
        __ERC721_init("Soulink", "SOUL");
        __Ownable_init(initialOwner);
        __Pausable_init();

        usdc = IERC20(usdcAddress);
        _nextTokenId = 1;
    }

    // --- UUPS ---

    function _authorizeUpgrade(address) internal override onlyOwner {}

    // --- Registration ---

    /// @notice Register a name on behalf of an agent (called by API server after x402 payment)
    /// @dev Only callable by authorized operator. No USDC transfer -- payment handled off-chain via x402.
    function registerFor(
        string calldata name,
        address agentOwner,
        bytes32 soulHash,
        address paymentAddress
    ) external whenNotPaused onlyOperator {
        bytes32 nameHash = _validateAndHash(name);

        require(_isAvailableByHash(nameHash), "Name not available");
        require(agentOwner != address(0), "Invalid agent owner");
        require(paymentAddress != address(0), "Invalid payment address");
        require(soulHash != bytes32(0), "Invalid soul hash");

        // Clean up old registration if re-registering an expired name
        AgentIdentity storage existing = _identities[nameHash];
        if (existing.tokenId != 0 && block.timestamp > existing.expiresAt) {
            uint256 oldTokenId = existing.tokenId;
            delete _tokenToName[oldTokenId];
            delete _encryptedSouls[nameHash];
            _burn(oldTokenId);
        }

        uint256 tokenId = _nextTokenId++;
        uint256 expiresAt = block.timestamp + REGISTRATION_PERIOD;

        _identities[nameHash] = AgentIdentity({
            tokenId: tokenId,
            owner: agentOwner,
            soulHash: soulHash,
            paymentAddress: paymentAddress,
            registeredAt: block.timestamp,
            expiresAt: expiresAt
        });

        _nameStrings[nameHash] = name;
        _tokenToName[tokenId] = nameHash;

        _mint(agentOwner, tokenId);

        emit NameRegistered(name, name, agentOwner, tokenId, soulHash, paymentAddress, expiresAt);
    }

    // --- Resolution ---

    function resolve(string calldata name) external view returns (AgentIdentity memory) {
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        AgentIdentity storage identity = _identities[nameHash];
        require(identity.tokenId != 0 && block.timestamp <= identity.expiresAt, "Name not registered");
        return identity;
    }

    // --- Renewal ---

    /// @notice Renew a name on behalf of an agent (called by API server after x402 payment)
    /// @dev Only callable by authorized operator. No USDC transfer.
    function renewFor(string calldata name) external whenNotPaused onlyOperator {
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        AgentIdentity storage identity = _identities[nameHash];

        require(identity.tokenId != 0, "Name not registered");

        uint256 base = block.timestamp > identity.expiresAt
            ? block.timestamp
            : identity.expiresAt;
        identity.expiresAt = base + REGISTRATION_PERIOD;

        emit NameRenewed(name, name, identity.expiresAt);
    }

    // --- Updates ---

    /// @notice Update soul on behalf of an agent (called by API server)
    /// @dev Only callable by authorized operator.
    function updateSoulFor(
        string calldata name,
        bytes32 newSoulHash
    ) external whenNotPaused onlyOperator {
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        AgentIdentity storage identity = _identities[nameHash];

        require(identity.tokenId != 0, "Name not registered");
        require(newSoulHash != bytes32(0), "Invalid soul hash");

        identity.soulHash = newSoulHash;

        emit SoulUpdated(name, name, newSoulHash);
    }

    /// @notice Update the payment address on behalf of an agent (operator-only)
    /// @dev Only callable by authorized operator.
    function updatePaymentAddressFor(
        string calldata name,
        address newPaymentAddress
    ) external whenNotPaused onlyOperator {
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        AgentIdentity storage identity = _identities[nameHash];

        require(identity.tokenId != 0, "Name not registered");
        require(newPaymentAddress != address(0), "Invalid payment address");

        identity.paymentAddress = newPaymentAddress;

        emit PaymentAddressUpdated(name, name, newPaymentAddress);
    }

    // --- Encrypted Soul ---

    /// @notice Store encrypted soul data on behalf of an agent (operator-only)
    /// @dev Only callable by authorized operator.
    function storeEncryptedSoulFor(
        string calldata name,
        bytes calldata encryptedData
    ) external whenNotPaused onlyOperator {
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        AgentIdentity storage identity = _identities[nameHash];

        require(identity.tokenId != 0, "Name not registered");

        _encryptedSouls[nameHash] = encryptedData;

        emit EncryptedSoulStored(name, name);
    }

    function getEncryptedSoul(string calldata name) external view returns (bytes memory) {
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        return _encryptedSouls[nameHash];
    }

    // --- Queries ---

    function isAvailable(string calldata name) external view returns (bool) {
        bytes32 nameHash = _validateAndHash(name);
        return _isAvailableByHash(nameHash);
    }

    /// @notice On-chain price reference for .agent names.
    /// @dev Actual payment is enforced off-chain via x402. This function serves
    ///      as the canonical on-chain price lookup for transparency and verification.
    function getPrice(string calldata name) public pure returns (uint256) {
        uint256 len = bytes(name).length;
        require(len >= MIN_NAME_LENGTH && len <= MAX_NAME_LENGTH, "Invalid name length");
        if (len <= 4) return PRICE_SHORT;
        return PRICE_STANDARD;
    }

    function nameToTokenId(string calldata name) external view returns (uint256) {
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        uint256 tokenId = _identities[nameHash].tokenId;
        require(tokenId != 0, "Name not registered");
        return tokenId;
    }

    /// @notice Get the name string for a token ID
    function tokenToName(uint256 tokenId) external view returns (string memory) {
        bytes32 nameHash = _tokenToName[tokenId];
        require(nameHash != bytes32(0), "Token not found");
        return _nameStrings[nameHash];
    }

    // --- ERC-721 Override: sync identity owner on transfer ---

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override returns (address from) {
        from = super._update(to, tokenId, auth);

        // Only update identity owner for regular transfers (not mint/burn),
        // and only if this token is the CURRENT token for the name.
        // Stale tokens from expired re-registrations must not corrupt ownership.
        if (from != address(0) && to != address(0)) {
            bytes32 nameHash = _tokenToName[tokenId];
            if (nameHash != bytes32(0) && _identities[nameHash].tokenId == tokenId) {
                _identities[nameHash].owner = to;
                emit NameTransferred(_nameStrings[nameHash], _nameStrings[nameHash], from, to);
            }
        }

        return from;
    }

    // --- Admin ---

    function setOperator(address operator, bool authorized) external onlyOwner {
        require(operator != address(0), "Invalid operator");
        operators[operator] = authorized;
        emit OperatorUpdated(operator, authorized);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function withdraw(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        usdc.safeTransfer(to, amount);
    }

    // --- Internal ---

    function _validateAndHash(string calldata name) internal pure returns (bytes32) {
        bytes memory b = bytes(name);
        uint256 len = b.length;

        require(len >= MIN_NAME_LENGTH && len <= MAX_NAME_LENGTH, "Invalid name length");
        require(b[0] != 0x2D, "No leading hyphen");
        require(b[len - 1] != 0x2D, "No trailing hyphen");

        for (uint256 i = 0; i < len; i++) {
            bytes1 c = b[i];
            bool valid = (c >= 0x61 && c <= 0x7A)  // a-z
                || (c >= 0x30 && c <= 0x39)          // 0-9
                || c == 0x2D;                         // hyphen
            require(valid, "Invalid character");
        }

        return keccak256(abi.encodePacked(name));
    }

    function _isAvailableByHash(bytes32 nameHash) internal view returns (bool) {
        AgentIdentity storage identity = _identities[nameHash];
        // Available if never registered OR expired
        return identity.tokenId == 0 || block.timestamp > identity.expiresAt;
    }

    // --- Storage Gap ---

    uint256[50] private __gap;
}
