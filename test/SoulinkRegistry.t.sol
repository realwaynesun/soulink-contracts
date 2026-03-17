// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SoulinkRegistry} from "../src/SoulinkRegistry.sol";
import {ISoulinkRegistry} from "../src/interfaces/ISoulinkRegistry.sol";
import {SoulinkRegistryV1} from "./SoulinkRegistryV1.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockUSDC is IERC20 {
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;
    uint256 public override totalSupply;

    function transfer(address to, uint256 amount) external override returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}

contract SoulinkRegistryTest is Test {
    SoulinkRegistry public registry;
    MockUSDC public usdc;

    address owner = address(this);
    address operator = address(0xCAFE);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    bytes32 soulHash = keccak256("soul");
    bytes32 soulHash2 = keccak256("soul-v2");

    function setUp() public {
        usdc = new MockUSDC();

        SoulinkRegistry impl = new SoulinkRegistry();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(SoulinkRegistry.initialize, (address(usdc), owner, 50e6, 1e6))
        );
        registry = SoulinkRegistry(address(proxy));
        registry.setOperator(operator, true);
    }

    // --- Registration ---

    function test_register() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);

        SoulinkRegistry.AgentIdentity memory id = registry.resolve("alice");
        assertEq(id.owner, alice);
        assertEq(id.soulHash, soulHash);
        assertEq(id.paymentAddress, alice);
        assertGt(id.expiresAt, block.timestamp);
    }

    function test_register_mints_nft() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);

        uint256 tokenId = registry.nameToTokenId("alice");
        assertEq(registry.ownerOf(tokenId), alice);
    }

    function test_register_revert_not_operator() public {
        vm.prank(alice);
        vm.expectRevert("Not authorized operator");
        registry.registerFor("alice", alice, soulHash, alice);
    }

    function test_register_revert_duplicate() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);

        vm.prank(operator);
        vm.expectRevert("Name not available");
        registry.registerFor("alice", bob, soulHash, bob);
    }

    function test_register_revert_short_name() public {
        vm.prank(operator);
        vm.expectRevert("Invalid name length");
        registry.registerFor("ab", alice, soulHash, alice);
    }

    function test_register_revert_invalid_char() public {
        vm.prank(operator);
        vm.expectRevert("Invalid character");
        registry.registerFor("Alice", alice, soulHash, alice);
    }

    function test_register_revert_leading_hyphen() public {
        vm.prank(operator);
        vm.expectRevert("No leading hyphen");
        registry.registerFor("-abc", alice, soulHash, alice);
    }

    // --- Expiry & Re-registration ---

    function test_expired_name_available() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);

        vm.warp(block.timestamp + 366 days);
        assertTrue(registry.isAvailable("alice"));
    }

    function test_expired_name_resolve_reverts() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);

        vm.warp(block.timestamp + 366 days);
        vm.expectRevert("Name not registered");
        registry.resolve("alice");
    }

    function test_reregister_expired_name() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);

        vm.warp(block.timestamp + 366 days);

        vm.prank(operator);
        registry.registerFor("alice", bob, soulHash2, bob);

        SoulinkRegistry.AgentIdentity memory id = registry.resolve("alice");
        assertEq(id.owner, bob);
        assertEq(id.soulHash, soulHash2);
    }

    // --- Renewal ---

    function test_renew() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);

        SoulinkRegistry.AgentIdentity memory before = registry.resolve("alice");

        vm.prank(operator);
        registry.renewFor("alice");

        SoulinkRegistry.AgentIdentity memory after_ = registry.resolve("alice");
        assertEq(after_.expiresAt, before.expiresAt + 365 days);
    }

    function test_renew_expired_extends_from_now() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);

        vm.warp(block.timestamp + 400 days);

        vm.prank(operator);
        registry.renewFor("alice");

        SoulinkRegistry.AgentIdentity memory id = registry.resolve("alice");
        assertEq(id.expiresAt, block.timestamp + 365 days);
    }

    // --- Updates ---

    function test_update_soul() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);

        vm.prank(operator);
        registry.updateSoulFor("alice", soulHash2);

        assertEq(registry.resolve("alice").soulHash, soulHash2);
    }

    function test_update_payment_address() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);

        vm.prank(operator);
        registry.updatePaymentAddressFor("alice", bob);

        assertEq(registry.resolve("alice").paymentAddress, bob);
    }

    function test_store_encrypted_soul() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);

        bytes memory data = hex"deadbeef";
        vm.prank(operator);
        registry.storeEncryptedSoulFor("alice", data);

        assertEq(registry.getEncryptedSoul("alice"), data);
    }

    // --- Pause ---

    function test_pause_blocks_register() public {
        registry.pause();

        vm.prank(operator);
        vm.expectRevert();
        registry.registerFor("alice", alice, soulHash, alice);
    }

    function test_pause_blocks_renew() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);

        registry.pause();

        vm.prank(operator);
        vm.expectRevert();
        registry.renewFor("alice");
    }

    function test_pause_blocks_update_soul() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);

        registry.pause();

        vm.prank(operator);
        vm.expectRevert();
        registry.updateSoulFor("alice", soulHash2);
    }

    function test_pause_blocks_update_payment() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);

        registry.pause();

        vm.prank(operator);
        vm.expectRevert();
        registry.updatePaymentAddressFor("alice", bob);
    }

    function test_pause_blocks_store_soul() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);

        registry.pause();

        vm.prank(operator);
        vm.expectRevert();
        registry.storeEncryptedSoulFor("alice", hex"dead");
    }

    function test_unpause_resumes() public {
        registry.pause();
        registry.unpause();

        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);
        assertEq(registry.resolve("alice").owner, alice);
    }

    // --- Transfer ---

    function test_transfer_updates_identity_owner_and_payment() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);

        uint256 tokenId = registry.nameToTokenId("alice");

        vm.prank(alice);
        registry.transferFrom(alice, bob, tokenId);

        assertEq(registry.ownerOf(tokenId), bob);
        SoulinkRegistry.AgentIdentity memory id = registry.resolve("alice");
        assertEq(id.owner, bob);
        assertEq(id.paymentAddress, bob);
    }

    // --- Operator ---

    function test_set_operator() public {
        address newOp = address(0xDEAD);
        registry.setOperator(newOp, true);
        assertTrue(registry.operators(newOp));

        registry.setOperator(newOp, false);
        assertFalse(registry.operators(newOp));
    }

    function test_set_operator_revert_not_owner() public {
        vm.prank(alice);
        vm.expectRevert();
        registry.setOperator(alice, true);
    }

    // --- Pricing ---

    function test_price_short() public view {
        assertEq(registry.getPrice("abc"), 50e6);
        assertEq(registry.getPrice("abcd"), 50e6);
    }

    function test_price_standard() public view {
        assertEq(registry.getPrice("alice"), 1e6);
        assertEq(registry.getPrice("longname"), 1e6);
    }

    function test_set_prices() public {
        registry.setPrices(200e6, 10e6);
        assertEq(registry.getPrice("abc"), 200e6);
        assertEq(registry.getPrice("alice"), 10e6);
    }

    function test_set_prices_revert_not_owner() public {
        vm.prank(alice);
        vm.expectRevert();
        registry.setPrices(200e6, 10e6);
    }

    // --- Token-Name mapping ---

    function test_token_to_name() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);

        uint256 tokenId = registry.nameToTokenId("alice");
        assertEq(registry.tokenToName(tokenId), "alice");
    }

    // --- Withdraw ---

    function test_withdraw() public {
        usdc.mint(address(registry), 1000e6);

        registry.withdraw(alice, 500e6);
        assertEq(usdc.balanceOf(alice), 500e6);
    }

    // ================================================================
    // ERC-8004 Tests
    // ================================================================

    // --- tokenURI tests ---

    function test_registerFor_with_agentURI() public {
        string memory uri = "https://api.soulink.dev/api/v1/agents/alice/card.json";

        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice, uri);

        uint256 tokenId = registry.nameToTokenId("alice");
        assertEq(registry.tokenURI(tokenId), uri);
    }

    function test_registerFor_without_agentURI() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);

        uint256 tokenId = registry.nameToTokenId("alice");
        // tokenURI should return empty string when not set (ERC721URIStorage behavior)
        assertEq(registry.tokenURI(tokenId), "");
    }

    function test_setAgentURI() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);
        uint256 tokenId = registry.nameToTokenId("alice");

        string memory newURI = "https://api.soulink.dev/api/v1/agents/alice/card.json";
        vm.prank(alice);
        registry.setAgentURI(tokenId, newURI);

        assertEq(registry.tokenURI(tokenId), newURI);
    }

    function test_setAgentURI_by_operator() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);
        uint256 tokenId = registry.nameToTokenId("alice");

        string memory newURI = "https://api.soulink.dev/api/v1/agents/alice/card.json";
        vm.prank(operator);
        registry.setAgentURI(tokenId, newURI);

        assertEq(registry.tokenURI(tokenId), newURI);
    }

    function test_setAgentURI_revert_unauthorized() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);
        uint256 tokenId = registry.nameToTokenId("alice");

        vm.prank(bob);
        vm.expectRevert("Not authorized");
        registry.setAgentURI(tokenId, "https://example.com");
    }

    // --- Metadata tests ---

    function test_setMetadata_and_getMetadata() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);
        uint256 tokenId = registry.nameToTokenId("alice");

        bytes memory value = abi.encode("data-scientist");
        vm.prank(alice);
        registry.setMetadata(tokenId, "role", value);

        assertEq(registry.getMetadata(tokenId, "role"), value);
    }

    function test_setMetadata_revert_unauthorized() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);
        uint256 tokenId = registry.nameToTokenId("alice");

        vm.prank(bob);
        vm.expectRevert("Not authorized");
        registry.setMetadata(tokenId, "role", hex"dead");
    }

    function test_getMetadata_nonexistent() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);
        uint256 tokenId = registry.nameToTokenId("alice");

        bytes memory result = registry.getMetadata(tokenId, "nonexistent");
        assertEq(result.length, 0);
    }

    // --- Agent wallet tests ---

    function test_agentWallet_set_on_register() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);
        uint256 tokenId = registry.nameToTokenId("alice");

        assertEq(registry.getAgentWallet(tokenId), alice);
    }

    function test_setAgentWalletFor() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);
        uint256 tokenId = registry.nameToTokenId("alice");

        vm.prank(operator);
        registry.setAgentWalletFor(tokenId, bob);

        assertEq(registry.getAgentWallet(tokenId), bob);
    }

    function test_getAgentWallet_fallback_to_paymentAddress() public {
        // Simulate pre-V2 token: register without agentWallet being set via V2 path
        // The setUp deploys V2 directly, so agentWallet IS set. Instead, test
        // that after unset, fallback returns paymentAddress.
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);
        uint256 tokenId = registry.nameToTokenId("alice");

        // Unset the agentWallet
        vm.prank(alice);
        registry.unsetAgentWallet(tokenId);

        // Should fall back to identity.paymentAddress
        assertEq(registry.getAgentWallet(tokenId), alice);
    }

    function test_getAgentWallet_returns_zero_for_nonexistent() public view {
        assertEq(registry.getAgentWallet(999), address(0));
    }

    function test_unsetAgentWallet_falls_back_to_payment() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);
        uint256 tokenId = registry.nameToTokenId("alice");

        vm.prank(alice);
        registry.unsetAgentWallet(tokenId);

        // agentWallet slot cleared, falls back to identity.paymentAddress
        assertEq(registry.getAgentWallet(tokenId), alice);
    }

    function test_transfer_clears_agentWallet_falls_back_to_payment() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);
        uint256 tokenId = registry.nameToTokenId("alice");

        assertEq(registry.getAgentWallet(tokenId), alice);

        vm.prank(alice);
        registry.transferFrom(alice, bob, tokenId);

        // agentWallet slot cleared, but getAgentWallet falls back to paymentAddress (now bob)
        assertEq(registry.getAgentWallet(tokenId), bob);
    }

    // --- updatePaymentAddressFor syncs agentWallet ---

    function test_updatePaymentAddress_syncs_agentWallet() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);
        uint256 tokenId = registry.nameToTokenId("alice");

        assertEq(registry.getAgentWallet(tokenId), alice);

        vm.prank(operator);
        registry.updatePaymentAddressFor("alice", bob);

        assertEq(registry.resolve("alice").paymentAddress, bob);
        assertEq(registry.getAgentWallet(tokenId), bob);
    }

    // --- Pause blocks ERC-8004 writes ---

    function test_pause_blocks_setAgentURI() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);
        uint256 tokenId = registry.nameToTokenId("alice");

        registry.pause();

        vm.prank(alice);
        vm.expectRevert();
        registry.setAgentURI(tokenId, "https://example.com");
    }

    function test_pause_blocks_setMetadata() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);
        uint256 tokenId = registry.nameToTokenId("alice");

        registry.pause();

        vm.prank(alice);
        vm.expectRevert();
        registry.setMetadata(tokenId, "role", hex"dead");
    }

    function test_pause_blocks_setAgentWalletFor() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);
        uint256 tokenId = registry.nameToTokenId("alice");

        registry.pause();

        vm.prank(operator);
        vm.expectRevert();
        registry.setAgentWalletFor(tokenId, bob);
    }

    function test_pause_blocks_unsetAgentWallet() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);
        uint256 tokenId = registry.nameToTokenId("alice");

        registry.pause();

        vm.prank(alice);
        vm.expectRevert();
        registry.unsetAgentWallet(tokenId);
    }

    // --- V1 → V2 upgrade safety test ---

    function test_v1_to_v2_upgrade_preserves_state() public {
        // Deploy real V1 (ERC721Upgradeable, no URIStorage)
        SoulinkRegistryV1 v1Impl = new SoulinkRegistryV1();
        ERC1967Proxy v1Proxy = new ERC1967Proxy(
            address(v1Impl),
            abi.encodeCall(SoulinkRegistryV1.initialize, (address(usdc), owner, 50e6, 1e6))
        );
        SoulinkRegistryV1 v1 = SoulinkRegistryV1(address(v1Proxy));
        v1.setOperator(operator, true);

        // Register on V1
        vm.prank(operator);
        v1.registerFor("alice", alice, soulHash, alice);

        uint256 v1TokenId = v1.nameToTokenId("alice");
        assertEq(v1.ownerOf(v1TokenId), alice);

        // Upgrade V1 → V2
        SoulinkRegistry v2Impl = new SoulinkRegistry();
        v1.upgradeToAndCall(
            address(v2Impl),
            abi.encodeCall(SoulinkRegistry.initializeV2, ())
        );

        // Cast proxy to V2 interface
        SoulinkRegistry v2 = SoulinkRegistry(address(v1Proxy));

        // Verify all V1 state is intact
        SoulinkRegistry.AgentIdentity memory id = v2.resolve("alice");
        assertEq(id.owner, alice);
        assertEq(id.soulHash, soulHash);
        assertEq(id.paymentAddress, alice);
        assertEq(id.tokenId, v1TokenId);

        assertEq(v2.ownerOf(v1TokenId), alice);
        assertEq(v2.tokenToName(v1TokenId), "alice");
        assertTrue(v2.operators(operator));
        assertEq(v2.getPrice("abc"), 50e6);

        // V2 features work on the upgraded contract
        string memory uri = "https://api.soulink.dev/api/v1/agents/alice/card.json";
        vm.prank(operator);
        v2.setAgentURI(v1TokenId, uri);
        assertEq(v2.tokenURI(v1TokenId), uri);

        // New 5-param registration works
        vm.prank(operator);
        v2.registerFor("bobby", bob, soulHash2, bob, "https://example.com/bob.json");
        assertEq(v2.tokenURI(v2.nameToTokenId("bobby")), "https://example.com/bob.json");
    }

    function test_supportsInterface_erc4906() public view {
        // ERC-4906 interface ID: 0x49064906
        assertTrue(registry.supportsInterface(0x49064906));
    }

    // --- ERC-8004 events ---

    function test_registerFor_emits_registered_event() public {
        vm.prank(operator);
        vm.expectEmit(true, true, false, true);
        emit ISoulinkRegistry.Registered(1, "https://example.com/card.json", alice);
        registry.registerFor("alice", alice, soulHash, alice, "https://example.com/card.json");
    }

    function test_setAgentURI_emits_uri_updated_event() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);
        uint256 tokenId = registry.nameToTokenId("alice");

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit ISoulinkRegistry.URIUpdated(tokenId, "https://new-uri.com");
        registry.setAgentURI(tokenId, "https://new-uri.com");
    }
}
