# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Foundry-based NFT auction smart contracts. Sellers list ERC721 NFTs; bidders bid in **ETH or whitelisted ERC20 tokens**. Bids are compared fairly by converting both to USD via **Chainlink `AggregatorV3Interface`** price feeds. The auction is deployed behind a **UUPS proxy** and upgradeable to V2 (dynamic fee tiers). Solidity `^0.8.24`, comments/docs are in Chinese.

## Commands

```bash
forge build                                    # compile
forge test                                     # run all tests
forge test -vvv                                # tests with trace output
forge test --match-test test_BidWithEth        # single test by name (substring match)
forge test --match-contract NFTAuctionUpgradeTest   # by contract name
forge coverage                                 # coverage report
forge script script/DeployNFTAuction.s.sol --rpc-url $SEPOLIA_RPC --broadcast --verify
forge script script/UpgradeNFTAuction.s.sol   --rpc-url $SEPOLIA_RPC --broadcast
```

Profiles: `default` (optimizer_runs=200), `ci` (runs=1), `production` (runs=10000). `.env` (see `.env.example`) must provide `PRIVATE_KEY`, `SEPOLIA_RPC`, `ETHERSCAN_API_KEY`, `ETH_USD_PRICE_FEED`, `FEE_RECIPIENT`, `PROXY_ADDRESS`.

## Architecture

**`NFTAuction.sol` (V1, implementation behind UUPS proxy)** — Inheriting `Initializable`, `OwnableUpgradeable`, `ReentrancyGuard`, `UUPSUpgradeable`. Constructor calls `_disableInitializers()`; real setup is in `initialize(_ethUsdPriceFeed, _feeRecipient)` (sets default `platformFeeBps = 250` = 2.5%). Upgrade gate is `_authorizeUpgrade` → `onlyOwner`.

Core flow:
- `createAuction` — seller registers an NFT (must own it and have approved the contract; NFT is **not** escrowed — it stays with the seller until settlement, then `safeTransferFrom`'d directly seller→winner in `endAuction`).
- `bidWithEth` / `bidWithERC20` — converts bid to USD, enforces **5% minimum increment** over `highestBidUsd`. The previous high bidder's funds are recorded in `pendingReturns[auctionId][bidder][token]` for later withdrawal (`address(0)` token slot = ETH). ERC20 bids `transferFrom` the bidder into the contract immediately; ETH bids are held as `msg.value`.
- `endAuction` (anyone, after `endTime`) — splits `highestBidAmount` into `feeAmount` (`* platformFeeBps / 10000`) to `feeRecipient` and the rest to seller, transfers NFT to winner.
- `cancelAuction` — seller only, only while no bids exist.

**USD conversion & oracle safety** (`getUsdValueEth` / `getUsdValueToken`): reads `latestRoundData`, reverts `InvalidPriceFeed` if `price <= 0`, `StalePrice` if `updatedAt` is 0 / older than `PRICE_STALE_THRESHOLD` (1h) / if `answeredInRound < roundId`. USD values are normalized to **8 decimals** (`USD_DECIMALS`). The divisor is `10 ** (feedDecimals + 18 - USD_DECIMALS)` — this assumes the priced asset has 18 decimals; keep this in mind when adding tokens.

**`NFTAuctionV2.sol`** — adds **dynamic fee tiers** (`feeTiers[3]` bps, `feeThresholds[2]` USD-8d, descending tiers: <thr0 → tier0, <thr1 → tier1, else tier2). Initialized via `initializeV2` guarded by `reinitializer(2)`. Overrides `endAuction` to use `getDynamicFeeBps(highestBidUsd)` instead of the flat `platformFeeBps`; falls back to flat fee when `dynamicFeeEnabled == false`. Adds 4 new storage slots and **reduces `__gap` from 40 to 36** to preserve layout — any further V3 must shrink `__gap` accordingly.

**`MyNFT.sol`** — plain `ERC721URIStorage` + `Ownable`, `MAX_SUPPLY = 10000`, owner-only `mint`.

## Proxy / test harness details

The deployment scripts and tests use a **minimal inline `ERC1967Proxy`** implementation (hand-written assembly, defined in both `script/DeployNFTAuction.s.sol` and `test/NFTAuction.t.sol`) rather than OpenZeppelin's `ERC1967Proxy`. Tests interact through `NFTAuction(address(proxy))`; upgrade tests call `proxy.upgradeToAndCall(implV2, abi.encodeCall(NFTAuctionV2.initializeV2, ...))`.

Test mocks in `test/mocks/`: `MockAggregator` (Chainlink feed stub, with `setAnswer`/`setUpdatedAt` for stale/negative-price tests) and `MockERC20`.

## Dependency remappings (foundry.toml)

```
@openzeppelin/            → lib/openzeppelin-contracts/
@openzeppelin-upgradeable/ → lib/openzeppelin-contracts-upgradeable/contracts/
@chainlink/               → lib/chainlink-brownie-contracts/   (note: submodule is lib/chainlink)
forge-std/                → lib/forge-std/src/
```

The OZ-upgradeable and OZ `test/` dirs are in `skip` to avoid compile errors. If `lib/chainlink-brownie-contracts/` is missing, that's the expected source for `@chainlink/contracts/...` imports (the `lib/chainlink` submodule alone won't resolve them).

## Invariants worth preserving when editing

- `endAuction` and `withdrawPendingReturn` are `nonReentrant` and zero-out state before external transfers (CEI).
- Minimum bid increment is hardcoded as `highestBidUsd * 5 / 100` in **three** places (both bid functions and `getMinBidUsd`) — keep them in sync.
- Storage layout compatibility: `NFTAuction.__gap` is `[40]`; `NFTAuctionV2` consumes 4 slots and uses `[36]`. Do not reorder or insert state variables without adjusting `__gap`.
- `address(0)` as a token address consistently means ETH (in `highestBidToken`, `pendingReturns`, `withdrawPendingReturn`).
