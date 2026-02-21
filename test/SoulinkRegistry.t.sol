// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SoulinkRegistry} from "../src/SoulinkRegistry.sol";
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
            abi.encodeCall(SoulinkRegistry.initialize, (address(usdc), owner))
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

    function test_transfer_updates_identity_owner() public {
        vm.prank(operator);
        registry.registerFor("alice", alice, soulHash, alice);

        uint256 tokenId = registry.nameToTokenId("alice");

        vm.prank(alice);
        registry.transferFrom(alice, bob, tokenId);

        assertEq(registry.ownerOf(tokenId), bob);
        assertEq(registry.resolve("alice").owner, bob);
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
        assertEq(registry.getPrice("abc"), 100e6);
        assertEq(registry.getPrice("abcd"), 100e6);
    }

    function test_price_standard() public view {
        assertEq(registry.getPrice("alice"), 5e6);
        assertEq(registry.getPrice("longname"), 5e6);
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
}
