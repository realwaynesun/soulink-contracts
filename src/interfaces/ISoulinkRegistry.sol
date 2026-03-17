// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ISoulinkRegistry {
    struct AgentIdentity {
        uint256 tokenId;
        address owner;
        bytes32 soulHash;
        address paymentAddress;
        uint256 registeredAt;
        uint256 expiresAt;
    }

    // --- Soulink Events ---

    event NameRegistered(
        string indexed indexedName,
        string name,
        address indexed owner,
        uint256 indexed tokenId,
        bytes32 soulHash,
        address paymentAddress,
        uint256 expiresAt
    );

    event NameRenewed(
        string indexed indexedName,
        string name,
        uint256 newExpiresAt
    );

    event SoulUpdated(
        string indexed indexedName,
        string name,
        bytes32 newSoulHash
    );

    event PaymentAddressUpdated(
        string indexed indexedName,
        string name,
        address newPaymentAddress
    );

    event NameTransferred(
        string indexed indexedName,
        string name,
        address indexed from,
        address indexed to
    );

    event OperatorUpdated(address indexed operator, bool authorized);

    event PricesUpdated(uint256 priceShort, uint256 priceStandard);

    event EncryptedSoulStored(
        string indexed indexedName,
        string name
    );

    // --- ERC-8004 Events ---

    event Registered(uint256 indexed agentId, string agentURI, address indexed owner);
    event URIUpdated(uint256 indexed agentId, string newURI);
    event MetadataSet(uint256 indexed agentId, string key);
    event AgentWalletUpdated(uint256 indexed agentId, address wallet);

    // --- Registration ---

    function registerFor(
        string calldata name,
        address agentOwner,
        bytes32 soulHash,
        address paymentAddress
    ) external;

    function registerFor(
        string calldata name,
        address agentOwner,
        bytes32 soulHash,
        address paymentAddress,
        string calldata agentURI
    ) external;

    // --- Resolution ---

    function resolve(string calldata name) external view returns (AgentIdentity memory identity);
    function renewFor(string calldata name) external;

    // --- Updates ---

    function updateSoulFor(string calldata name, bytes32 newSoulHash) external;
    function updatePaymentAddressFor(string calldata name, address newPaymentAddress) external;
    function storeEncryptedSoulFor(string calldata name, bytes calldata encryptedData) external;
    function getEncryptedSoul(string calldata name) external view returns (bytes memory);

    // --- ERC-8004 Identity ---

    function setAgentURI(uint256 agentId, string calldata newURI) external;
    function getMetadata(uint256 agentId, string calldata key) external view returns (bytes memory);
    function setMetadata(uint256 agentId, string calldata key, bytes calldata value) external;
    function setAgentWalletFor(uint256 agentId, address wallet) external;
    function getAgentWallet(uint256 agentId) external view returns (address);
    function unsetAgentWallet(uint256 agentId) external;

    // --- Queries ---

    function isAvailable(string calldata name) external view returns (bool);
    function getPrice(string calldata name) external view returns (uint256);
    function nameToTokenId(string calldata name) external view returns (uint256);
    function tokenToName(uint256 tokenId) external view returns (string memory);
}
