# 🏗️ DSC Framework — Universal Decentralized Stablecoin Framework

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.30-363636?logo=solidity)](https://soliditylang.org/)
[![Built with Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C?logo=ethereum)](https://getfoundry.sh/)

A universal, extensible framework for building overcollateralized, algorithmically stable stablecoins pegged to any fiat currency. Ships with a production-ready CNY (Chinese Yuan) implementation.

> This project is for educational purposes and is based on Patrick Collins' Cyfrin Updraft DeFi course.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Contracts](#contracts)
- [How It Works](#how-it-works)
- [Creating a New Implementation](#creating-a-new-implementation)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
  - [Environment Setup](#environment-setup)
- [Usage](#usage)
  - [Build](#build)
  - [Test](#test)
  - [Deploy](#deploy)
- [Deployed Contracts](#deployed-contracts)
- [Security Considerations](#security-considerations)
- [Known Issues & Limitations](#known-issues--limitations)
- [License](#license)

---

## Overview

The **DSC Framework** provides a reusable base for any overcollateralized stablecoin system. All protocol logic — collateral management, health factor enforcement, liquidation mechanics, and oracle integration — lives in abstract base contracts. A new stablecoin pegged to any fiat currency requires only **two files and one function**.

The framework ships with a complete **CNY-pegged (Chinese Yuan)** implementation as a reference.

---

## Features

- **Peg-Agnostic** — Works with any fiat currency that has a Chainlink USD price feed
- **Minimal Implementation** — New currencies require one function and one token contract
- **Overcollateralized** — Minimum 200% collateralization ratio enforced at all times
- **Algorithmic Stability** — No governance; stability maintained entirely by on-chain logic
- **Chainlink Price Feeds** — Real-time price data with stale price protection via `OracleLib`
- **Dual Currency Display** — Collateral queryable in both reference currency and USD
- **Liquidation Mechanism** — Undercollateralized positions liquidated with 10% bonus incentive
- **Reentrancy Protected** — All state-changing functions protected by OpenZeppelin's `ReentrancyGuard`

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                            User                                     │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ deposit / mint / burn / redeem
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    CnyEngine (or any implementation)                │
│                                                                     │
│  Inherits from AbstractDSCEngine:                                   │
│  - Collateral deposits & redemptions                                │
│  - DSC minting & burning                                            │
│  - Health factor enforcement                                        │
│  - Liquidation mechanism                                            │
│                                                                     │
│  Implements ONE function:                                           │
│  - _getReferenceValuePerUsd() → reads CNY/USD feed                 │
└──────────────┬────────────────────────────┬────────────────────────┘
               │ mint / burn                │ price queries
               ▼                            ▼
┌──────────────────────────┐  ┌─────────────────────────────────────┐
│     CnyStablecoin        │  │      Chainlink Price Feeds          │
│  (inherits BasePeggedToken)│ │                                     │
│  - ERC20Burnable         │  │  ETH/USD ──┐                        │
│  - Ownable (engine)      │  │  BTC/USD ──┤── collateral pricing   │
└──────────────────────────┘  │  CNY/USD ──┘── peg conversion       │
                               └─────────────────────────────────────┘
```

### Inheritance Hierarchy

```
IDSCEngine (interface)
    └── AbstractDSCEngine (abstract — all protocol logic)
            └── CnyEngine (concrete — CNY price feed only)

IBasePeggedToken (interface)
    └── BasePeggedToken (abstract — mint/burn logic)
            └── CnyStablecoin (concrete — name and symbol only)
```

---

## Contracts

### Framework (Abstract Layer)

| Contract | Description |
|---|---|
| `interfaces/IDSCEngine.sol` | Universal engine interface. Defines all protocol functions, errors, and events. |
| `interfaces/IBasePeggedToken.sol` | Universal token interface. Defines mint and burn signatures. |
| `abstract/AbstractDSCEngine.sol` | All protocol logic. Subclasses implement one virtual function. |
| `abstract/BasePeggedToken.sol` | All token logic. Subclasses provide name and symbol only. |
| `libraries/OracleLib.sol` | Chainlink oracle wrapper with stale price detection. |

### CNY Implementation

| Contract | Description |
|---|---|
| `implementations/CnyEngine.sol` | CNY engine. Reads CNY/USD feed and inverts to get CNY per USD. |
| `implementations/CnyStablecoin.sol` | CNY token. Sets name to "CNY Stablecoin" and symbol to "CNYdsc". |

### Key Constants (AbstractDSCEngine)

| Constant | Value | Description |
|---|---|---|
| `LIQUIDATION_ADJUSTMENT` | 50 | Effective 200% collateralization threshold |
| `LIQUIDATION_PRECISION` | 100 | Divisor for liquidation math |
| `LIQUIDATION_BONUS` | 10 | 10% bonus paid to liquidators |
| `MIN_HEALTH_FACTOR` | 1e18 | Minimum health factor (= 1.0) |
| `ADDITIONAL_FEED_PRECISION` | 1e10 | Scales Chainlink's 8-decimal price to 18 decimals |

---

## How It Works

### Minting DSC

1. User calls `depositCollateralAndMintDsc()` (or separately `depositCollateral()` then `mintDsc()`)
2. The engine records the collateral and transfers it to the contract
3. Before minting, the **health factor** is checked:

```
Health Factor = (Collateral Value [ref currency] × 0.5 × 1e18) / DSC Minted
```

4. If `Health Factor >= 1e18`, DSC is minted to the user

### Redeeming Collateral

1. User calls `redeemCollateralForDsc()` to burn DSC and retrieve collateral atomically, or each step separately
2. Health factor is verified after redemption — if it drops below 1, the transaction reverts

### Liquidation

If a user's health factor falls below `1e18` (due to collateral price dropping):

1. Any liquidator calls `liquidate(collateral, user, debtToCover)`
2. The liquidator burns `debtToCover` DSC on behalf of the user
3. The liquidator receives the equivalent collateral **+ a 10% bonus**
4. The protocol verifies the user's health factor actually improved

### Peg Mechanism

All internal accounting uses the reference currency. Collateral USD prices from Chainlink are converted via the peg currency's USD feed:

```
Collateral Value [ref] = (Token Amount × Token/USD Price) / (RefCurrency/USD Price)
```

USD display functions (`getAccountCollateralValueInReferenceValue`) are available for convenience but are never used in protocol logic.

---

## Creating a New Implementation

Adding a new peg currency requires exactly **two files**:

### 1. The Engine (one function)

```solidity
// src/implementations/EurEngine.sol
contract EurEngine is AbstractDSCEngine {
    using OracleLib for AggregatorV3Interface;

    AggregatorV3Interface private immutable i_eurPriceFeed;

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address eurPriceFeedAddress,
        address dscAddress
    ) AbstractDSCEngine(tokenAddresses, priceFeedAddresses, dscAddress) {
        i_eurPriceFeed = AggregatorV3Interface(eurPriceFeedAddress);
    }

    function _getReferenceValuePerUsd() internal view override returns (uint256) {
        (, int256 eurPrice,,,) = i_eurPriceFeed.stalePriceCheck();
        // eurPrice = EUR/USD e.g. 0.92e8
        // return USD/EUR = 1 / 0.92 scaled to 1e18
        return (1e18 * 1e18) / (uint256(eurPrice) * 1e10);
    }
}
```

### 2. The Token (name and symbol only)

```solidity
// src/implementations/EurStablecoin.sol
contract EurStablecoin is BasePeggedToken {
    constructor(address initialOwner)
        BasePeggedToken("EUR Stablecoin", "EURdsc", initialOwner)
    {}
}
```

### 3. The Deploy Script

```solidity
// script/DeployEur.s.sol
contract DeployEur is Script {
    function run() external returns (EurStablecoin, EurEngine, HelperConfig) {
        // Step 1 — deploy token
        EurStablecoin eurToken = new EurStablecoin(deployer);
        // Step 2 — deploy engine
        EurEngine eurEngine = new EurEngine(tokens, feeds, eurFeed, address(eurToken));
        // Step 3 — transfer ownership
        eurToken.transferOwnership(address(eurEngine));
    }
}
```

**That's it.** All protocol logic is inherited automatically.

---

## Getting Started

### Prerequisites

- [Foundry](https://getfoundry.sh/) — Solidity development toolchain
- [Git](https://git-scm.com/)

Install Foundry if you haven't:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Installation

```bash
git clone https://github.com/danushkka/dsc-framework.git
cd dsc-framework
forge install
```

### Environment Setup

Create a `.env` file in the root directory:

```env
# Sepolia
PRIVATE_KEY=your_private_key_here
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/your_api_key
ETHERSCAN_API_KEY=your_etherscan_api_key

# Anvil (local)
ANVIL_RPC_URL=http://localhost:8545
```

> ⚠️ Never commit your `.env` file. Make sure it is listed in `.gitignore`.

---

## Usage

### Build

```bash
forge build
```

### Test

```bash
# Run all tests
forge test

# Run with verbosity for detailed output
forge test -vvvv

# Run a specific test file
forge test --match-path test/unit/CnyEngineTest.t.sol

# Run with gas reporting
forge test --gas-report

# Run coverage report
forge coverage

# Run coverage with lcov output
forge coverage --report lcov
```

### Deploy

**Local Anvil:**

```bash
anvil
forge script script/DeployCnyStablecoin.s.sol:DeployCnyStablecoin \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --broadcast
```

**Sepolia testnet:**

```bash
source .env
forge script script/DeployCnyStablecoin.s.sol:DeployCnyStablecoin \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

---

## Deployed Contracts

### Sepolia Testnet (CNY Implementation)

| Contract | Address |
|---|---|
| `CnyStablecoin` | `0xA9c7B834efC87440d46740c87BECD32829519B1b` |
| `CnyEngine` | `0x73eCdC66fe72111b1c5EfB944c5Cd0895A692C24` |


---

## Security Considerations

- **Reentrancy** — All external state-changing functions are protected by `nonReentrant` from OpenZeppelin's `ReentrancyGuard`
- **Stale Oracles** — `OracleLib.stalePriceCheck()` reverts if any Chainlink price feed hasn't been updated within 3 hours, including the peg currency feed
- **Health Factor Enforcement** — Every mint and collateral withdrawal checks the health factor post-action
- **Liquidation Safeguard** — Liquidations require the target user's health factor to actually improve, preventing broken liquidation calls
- **CEI Pattern** — All state-changing functions follow Checks-Effects-Interactions to minimize reentrancy surface

---

## Known Issues & Limitations

- **No governance** — Protocol parameters (collateral ratio, bonus, supported tokens) are hardcoded. Updating them requires redeployment.

- **Centralized minting** — `BasePeggedToken` uses `Ownable`. If the engine is compromised, all DSC can be minted arbitrarily.

- **Peg currency oracle dependency** — Peg accuracy depends entirely on the Chainlink reference currency feed. If that feed goes stale, the protocol freezes by design.

- **Single collateral liquidation** — Liquidations only seize one collateral type per call. A user with both wETH and wBTC collateral may require multiple liquidation calls.

- **Not audited** — This is an educational project. Do not use in production without a formal security audit.

---

## License

This project is licensed under the [MIT License](LICENSE).