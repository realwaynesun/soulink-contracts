// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISoulinkRegistry} from "../src/interfaces/ISoulinkRegistry.sol";

/// @dev Minimal V1 mock with the original storage layout (ERC721Upgradeable, NOT URIStorage)
///      Used to test real V1 → V2 upgrade path with storage compatibility.
contract SoulinkRegistryV1 is
    Initializable,
    ERC721Upgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    uint256 public constant REGISTRATION_PERIOD = 365 days;
    uint256 public constant MIN_NAME_LENGTH = 3;
    uint256 public constant MAX_NAME_LENGTH = 32;

    IERC20 public usdc;
    uint256 private _nextTokenId;

    mapping(address => bool) public operators;
    mapping(bytes32 => ISoulinkRegistry.AgentIdentity) private _identities;
    mapping(bytes32 => string) private _nameStrings;
    mapping(uint256 => bytes32) private _tokenToName;
    mapping(bytes32 => bytes) private _encryptedSouls;

    uint256 public priceShort;
    uint256 public priceStandard;

    modifier onlyOperator() {
        require(operators[msg.sender], "Not authorized operator");
        _;
    }

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

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function registerFor(
        string calldata name,
        address agentOwner,
        bytes32 soulHash,
        address paymentAddress
    ) external whenNotPaused onlyOperator {
        bytes memory b = bytes(name);
        uint256 len = b.length;
        require(len >= MIN_NAME_LENGTH && len <= MAX_NAME_LENGTH, "Invalid name length");
        bytes32 nameHash = keccak256(abi.encodePacked(name));

        require(agentOwner != address(0), "Invalid agent owner");
        require(soulHash != bytes32(0), "Invalid soul hash");

        uint256 tokenId = _nextTokenId++;
        uint256 expiresAt = block.timestamp + REGISTRATION_PERIOD;

        _identities[nameHash] = ISoulinkRegistry.AgentIdentity({
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
    }

    function resolve(string calldata name) external view returns (ISoulinkRegistry.AgentIdentity memory) {
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        ISoulinkRegistry.AgentIdentity storage identity = _identities[nameHash];
        require(identity.tokenId != 0 && block.timestamp <= identity.expiresAt, "Name not registered");
        return identity;
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

    function setOperator(address op, bool authorized) external onlyOwner {
        operators[op] = authorized;
    }

    uint256[48] private __gap;
}
