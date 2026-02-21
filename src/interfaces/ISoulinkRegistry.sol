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

    /// @notice Register a name on behalf of an agent (called by API server after x402 payment)
    /// @dev Only callable by authorized operator. No USDC transfer.
    /// @param name The .agent name to register
    /// @param agentOwner The wallet that will own the NFT
    /// @param soulHash SHA-256 hash of Soul.md
    /// @param paymentAddress Address to receive x402 payments for this agent
    function registerFor(
        string calldata name,
        address agentOwner,
        bytes32 soulHash,
        address paymentAddress
    ) external;

    /// @notice Resolve a name to its full agent identity
    /// @param name The .agent name to resolve
    /// @return identity The AgentIdentity struct
    function resolve(string calldata name) external view returns (AgentIdentity memory identity);

    /// @notice Renew on behalf of an agent (operator-only, no USDC transfer)
    /// @param name The .agent name to renew
    function renewFor(string calldata name) external;

    /// @notice Update soul on behalf of an agent (operator-only)
    /// @param name The .agent name
    /// @param newSoulHash New SHA-256 hash of Soul.md
    function updateSoulFor(
        string calldata name,
        bytes32 newSoulHash
    ) external;

    /// @notice Update the payment address on behalf of an agent (operator-only)
    /// @param name The .agent name
    /// @param newPaymentAddress New address to receive payments
    function updatePaymentAddressFor(
        string calldata name,
        address newPaymentAddress
    ) external;

    /// @notice Store encrypted soul data on behalf of an agent (operator-only)
    /// @param name The .agent name
    /// @param encryptedData Encrypted soul data
    function storeEncryptedSoulFor(
        string calldata name,
        bytes calldata encryptedData
    ) external;

    /// @notice Get encrypted soul data for a name (anyone can read, only owner can decrypt)
    /// @param name The .agent name
    /// @return Encrypted soul data bytes
    function getEncryptedSoul(string calldata name) external view returns (bytes memory);

    /// @notice Check if a name is available for registration
    /// @param name The name to check
    /// @return True if available
    function isAvailable(string calldata name) external view returns (bool);

    /// @notice Get the annual price for a name in USDC (6 decimals)
    /// @param name The name to price
    /// @return USDC amount with 6 decimals
    function getPrice(string calldata name) external view returns (uint256);

    /// @notice Get the token ID for a registered name
    /// @param name The .agent name
    /// @return tokenId The ERC-721 token ID
    function nameToTokenId(string calldata name) external view returns (uint256);

}
