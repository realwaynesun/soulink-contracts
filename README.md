# Soulink Contracts

ERC-721 registry for `.agent` names on Base. Each name is an NFT representing an on-chain identity for AI agents.

## Architecture

- **SoulinkRegistry** — UUPS-upgradeable ERC-721. Names are registered by authorized operators after x402 payment verification off-chain.
- **ISoulinkRegistry** — Interface with events and structs.
- **Deploy.s.sol** — Foundry deployment script targeting Base mainnet (8453) and Base Sepolia (84532).

## Key Features

| Feature | Detail |
|---------|--------|
| Name format | `[a-z0-9-]{3,32}.agent` |
| Pricing | Configurable (currently $50 USDC short, $1 USDC standard — promo through March 31, 2026) |
| Expiry | 365 days, renewable |
| Payment | Off-chain via [x402](https://www.x402.org/) protocol |
| Upgradeability | UUPS proxy pattern |
| Soul storage | On-chain encrypted soul data (owner-decryptable) |

## Build

```bash
forge build
```

## Test

```bash
forge test
```

## Deploy

```bash
# Base Sepolia
forge script Deploy --rpc-url $BASE_SEPOLIA_RPC --broadcast --verify

# Base Mainnet
forge script Deploy --rpc-url $BASE_MAINNET_RPC --broadcast --verify --slow
```

Requires `DEPLOYER_PRIVATE_KEY` and `BASESCAN_API_KEY` env vars.

## Dependencies

- [OpenZeppelin Contracts v5](https://github.com/OpenZeppelin/openzeppelin-contracts) (ERC-721, UUPS, Ownable, Pausable)
- [Foundry](https://book.getfoundry.sh/)

## License

MIT
