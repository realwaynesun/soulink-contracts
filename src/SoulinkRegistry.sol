// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721URIStorageUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISoulinkRegistry} from "./interfaces/ISoulinkRegistry.sol";

/// @title SoulinkRegistry
/// @notice ERC-721 registry for .agent names on Base, ERC-8004 compatible
/// @dev Each name is an NFT. Agents pay via x402 operator flow.
///      Deployed behind a UUPS proxy for upgradeability.
contract SoulinkRegistry is
    ISoulinkRegistry,
    Initializable,
    ERC721URIStorageUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    // --- Constants ---

    uint256 public constant REGISTRATION_PERIOD = 365 days;
    uint256 public constant MIN_NAME_LENGTH = 3;
    uint256 public constant MAX_NAME_LENGTH = 32;

    // --- Storage (V1 — sequential, do NOT reorder) ---

    IERC20 public usdc;
    uint256 private _nextTokenId;

    mapping(address => bool) public operators;
    mapping(bytes32 => AgentIdentity) private _identities;
    mapping(bytes32 => string) private _nameStrings;
    mapping(uint256 => bytes32) private _tokenToName;
    mapping(bytes32 => bytes) private _encryptedSouls;

    uint256 public priceShort;
    uint256 public priceStandard;

    // --- ERC-8004 Storage (ERC-7201 namespaced — zero gap consumption) ---

    /// @custom:storage-location erc7201:soulink.storage.ERC8004
    struct ERC8004Storage {
        mapping(uint256 => mapping(string => bytes)) metadata;
        mapping(uint256 => address) agentWallets;
    }

    // keccak256(abi.encode(uint256(keccak256("soulink.storage.ERC8004")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC8004_STORAGE_LOCATION =
        0xc3b2e0914a40714b26b4e4d063e62a9bf3b0b4fc9d62aa1b8e6f7c6c4a1c3e00;

    function _getERC8004Storage() private pure returns (ERC8004Storage storage $) {
        assembly {
            $.slot := ERC8004_STORAGE_LOCATION
        }
    }

    // --- Modifiers ---

    modifier onlyOperator() {
        require(operators[msg.sender], "Not authorized operator");
        _;
    }

    modifier onlyTokenAuth(uint256 tokenId) {
        address tokenOwner = ownerOf(tokenId);
        require(
            msg.sender == tokenOwner ||
            getApproved(tokenId) == msg.sender ||
            isApprovedForAll(tokenOwner, msg.sender) ||
            operators[msg.sender],
            "Not authorized"
        );
        _;
    }

    // --- Initializer ---

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address usdcAddress,
        address initialOwner,
        uint256 _priceShort,
        uint256 _priceStandard
    ) external initializer {
        __ERC721_init("Soulink", "SOUL");
        __Ownable_init(initialOwner);
        __Pausable_init();

        usdc = IERC20(usdcAddress);
        _nextTokenId = 1;

        priceShort = _priceShort;
        priceStandard = _priceStandard;
    }

    function initializeV2() external reinitializer(2) {
        __ERC721URIStorage_init();
    }

    // --- UUPS ---

    function _authorizeUpgrade(address) internal override onlyOwner {}

    // --- Registration ---

    function registerFor(
        string calldata name,
        address agentOwner,
        bytes32 soulHash,
        address paymentAddress
    ) external whenNotPaused onlyOperator {
        _registerFor(name, agentOwner, soulHash, paymentAddress, "");
    }

    function registerFor(
        string calldata name,
        address agentOwner,
        bytes32 soulHash,
        address paymentAddress,
        string calldata agentURI
    ) external whenNotPaused onlyOperator {
        _registerFor(name, agentOwner, soulHash, paymentAddress, agentURI);
    }

    function _registerFor(
        string calldata name,
        address agentOwner,
        bytes32 soulHash,
        address paymentAddress,
        string memory agentURI
    ) internal {
        bytes32 nameHash = _validateAndHash(name);

        require(_isAvailableByHash(nameHash), "Name not available");
        require(agentOwner != address(0), "Invalid agent owner");
        require(paymentAddress != address(0), "Invalid payment address");
        require(soulHash != bytes32(0), "Invalid soul hash");

        AgentIdentity storage existing = _identities[nameHash];
        if (existing.tokenId != 0 && block.timestamp > existing.expiresAt) {
            uint256 oldTokenId = existing.tokenId;
            delete _tokenToName[oldTokenId];
            delete _encryptedSouls[nameHash];
            delete _getERC8004Storage().agentWallets[oldTokenId];
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

        if (bytes(agentURI).length > 0) {
            _setTokenURI(tokenId, agentURI);
        }

        _getERC8004Storage().agentWallets[tokenId] = paymentAddress;

        emit NameRegistered(name, name, agentOwner, tokenId, soulHash, paymentAddress, expiresAt);
        emit Registered(tokenId, agentURI, agentOwner);
    }

    // --- Resolution ---

    function resolve(string calldata name) external view returns (AgentIdentity memory) {
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        AgentIdentity storage identity = _identities[nameHash];
        require(identity.tokenId != 0 && block.timestamp <= identity.expiresAt, "Name not registered");
        return identity;
    }

    // --- Renewal ---

    function renewFor(string calldata name) external whenNotPaused onlyOperator {
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        AgentIdentity storage identity = _identities[nameHash];

        require(identity.tokenId != 0, "Name not registered");

        uint256 base_ = block.timestamp > identity.expiresAt
            ? block.timestamp
            : identity.expiresAt;
        identity.expiresAt = base_ + REGISTRATION_PERIOD;

        emit NameRenewed(name, name, identity.expiresAt);
    }

    // --- Updates ---

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

    function updatePaymentAddressFor(
        string calldata name,
        address newPaymentAddress
    ) external whenNotPaused onlyOperator {
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        AgentIdentity storage identity = _identities[nameHash];

        require(identity.tokenId != 0, "Name not registered");
        require(newPaymentAddress != address(0), "Invalid payment address");

        identity.paymentAddress = newPaymentAddress;
        _getERC8004Storage().agentWallets[identity.tokenId] = newPaymentAddress;

        emit PaymentAddressUpdated(name, name, newPaymentAddress);
        emit AgentWalletUpdated(identity.tokenId, newPaymentAddress);
    }

    // --- Encrypted Soul ---

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

    // --- ERC-8004 Identity ---

    function setAgentURI(uint256 agentId, string calldata newURI) external whenNotPaused onlyTokenAuth(agentId) {
        _setTokenURI(agentId, newURI);
        emit URIUpdated(agentId, newURI);
    }

    function getMetadata(uint256 agentId, string calldata key) external view returns (bytes memory) {
        return _getERC8004Storage().metadata[agentId][key];
    }

    function setMetadata(
        uint256 agentId,
        string calldata key,
        bytes calldata value
    ) external whenNotPaused onlyTokenAuth(agentId) {
        _getERC8004Storage().metadata[agentId][key] = value;
        emit MetadataSet(agentId, key);
    }

    function setAgentWalletFor(uint256 agentId, address wallet) external whenNotPaused onlyOperator {
        _getERC8004Storage().agentWallets[agentId] = wallet;
        emit AgentWalletUpdated(agentId, wallet);
    }

    function getAgentWallet(uint256 agentId) external view returns (address) {
        address wallet = _getERC8004Storage().agentWallets[agentId];
        if (wallet != address(0)) return wallet;
        bytes32 nameHash = _tokenToName[agentId];
        if (nameHash != bytes32(0)) return _identities[nameHash].paymentAddress;
        return address(0);
    }

    function unsetAgentWallet(uint256 agentId) external whenNotPaused onlyTokenAuth(agentId) {
        delete _getERC8004Storage().agentWallets[agentId];
        emit AgentWalletUpdated(agentId, address(0));
    }

    // --- Queries ---

    function isAvailable(string calldata name) external view returns (bool) {
        bytes32 nameHash = _validateAndHash(name);
        return _isAvailableByHash(nameHash);
    }

    function getPrice(string calldata name) public view returns (uint256) {
        uint256 len = bytes(name).length;
        require(len >= MIN_NAME_LENGTH && len <= MAX_NAME_LENGTH, "Invalid name length");
        return len <= 4 ? priceShort : priceStandard;
    }

    function nameToTokenId(string calldata name) external view returns (uint256) {
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        uint256 tokenId = _identities[nameHash].tokenId;
        require(tokenId != 0, "Name not registered");
        return tokenId;
    }

    function tokenToName(uint256 tokenId) external view returns (string memory) {
        bytes32 nameHash = _tokenToName[tokenId];
        require(nameHash != bytes32(0), "Token not found");
        return _nameStrings[nameHash];
    }

    // --- ERC-721 Override: sync identity owner + clear agentWallet on transfer ---

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override returns (address from) {
        from = super._update(to, tokenId, auth);

        if (from != address(0) && to != address(0)) {
            bytes32 nameHash = _tokenToName[tokenId];
            if (nameHash != bytes32(0) && _identities[nameHash].tokenId == tokenId) {
                _identities[nameHash].owner = to;
                _identities[nameHash].paymentAddress = to;
                _getERC8004Storage().agentWallets[tokenId] = address(0);
                emit NameTransferred(_nameStrings[nameHash], _nameStrings[nameHash], from, to);
            }
        }

        return from;
    }

    // --- supportsInterface ---

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721URIStorageUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
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

    function setPrices(uint256 _priceShort, uint256 _priceStandard) external onlyOwner {
        require(_priceShort > 0 && _priceStandard > 0, "Invalid price");
        priceShort = _priceShort;
        priceStandard = _priceStandard;
        emit PricesUpdated(_priceShort, _priceStandard);
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
            bool valid = (c >= 0x61 && c <= 0x7A)
                || (c >= 0x30 && c <= 0x39)
                || c == 0x2D;
            require(valid, "Invalid character");
        }

        return keccak256(abi.encodePacked(name));
    }

    function _isAvailableByHash(bytes32 nameHash) internal view returns (bool) {
        AgentIdentity storage identity = _identities[nameHash];
        return identity.tokenId == 0 || block.timestamp > identity.expiresAt;
    }

    // --- Storage Gap ---

    uint256[48] private __gap;
}
