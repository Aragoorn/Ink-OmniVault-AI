<img width="990" height="948" alt="test compile" src="https://github.com/user-attachments/assets/9a14946c-1598-4d5b-95b6-3f105b6bdde4" />

# Ink OmniVault AI

**Upgradeable Smart Account (ERC-4337) optimized for the Ink Network (OP Stack / Superchain)**

A modular, security-focused smart account designed for autonomous AI agents, biometric/passkey signers, social recovery, and controlled DeFi execution on Ink.

---
## Live Demo Website

**Professional Demo Site:** [https://ink-omnivault.netlify.app/](https://ink-omnivault.netlify.app/)

---

## Overview

Ink OmniVault AI is a UUPS-upgradeable smart account that combines:

- ERC-4337 Account Abstraction foundation
- AI Agent policies with daily limits and risk controls
- Session keys for temporary delegated execution
- Passkey / WebAuthn registry (ready for cryptographic verification)
- Social recovery with threshold and deadline
- Circuit breaker and oracle price validation (eOracle compatible)
- Native helpers for Ink DeFi protocols:
  - **Velodrome** (DEX swaps)
  - **Tydro** (Aave V3 white-label lending)
  - **Nado** (Perp + Spot CLOB DEX)
- Gas tank, linear vesting, and modular extension system

The contract prioritizes **security, modularity, and controlled autonomy**.

---

## Key Features

| Feature                    | Description                                              |
|---------------------------|----------------------------------------------------------|
| Account Abstraction       | ERC-4337 compatible (`validateUserOp`, EntryPoint support) |
| AI Agent Policies         | Daily spending limits, risk score, automatic reset       |
| Session Keys              | Time-bound + spending-limited delegated keys             |
| Social Recovery           | Guardian-based recovery with threshold and expiry        |
| Passkey Registry          | Structured storage for biometric / WebAuthn keys         |
| Module System             | Enable/disable external modules securely                 |
| Circuit Breaker           | Automatic pause after consecutive execution failures     |
| Oracle Guard              | eOracle / Chainlink-compatible price feed staleness checks |
| Velodrome Helper          | Dedicated ETH → Token swap helper                        |
| Tydro & Nado Support      | Native whitelist for Ink’s flagship lending & perp DEX   |
| Gas Tank                  | Simple sponsored gas deposits                            |
| Linear Vesting            | Native ETH + ERC-20 vesting                              |
| Two-step Admin Transfer   | Safe ownership handover                                  |

---

## Architecture
InkOmniVaultAI (UUPS Proxy)
├── AccessControl + Pausable + ReentrancyGuard
├── ERC-4337 validation layer
├── AI Agent + Session Key policies
├── Social Recovery module
├── Passkey registry
├── Module registry
├── Trading guards (whitelist, cooldown, limits, oracle)
│   ├── Velodrome Router
│   ├── Tydro Pool
│   └── Nado Endpoint
└── Utility modules (Gas Tank, Vesting, Emergency)


---

## Network Information

| Network       | Chain ID | RPC (Primary)                          | Explorer                          |
|---------------|----------|----------------------------------------|-----------------------------------|
| Ink Mainnet   | 57073    | https://rpc-gel.inkonchain.com         | https://explorer.inkonchain.com   |
| Ink Sepolia   | 763373   | https://rpc-gel-sepolia.inkonchain.com | https://explorer-sepolia.inkonchain.com |

- Native Token: ETH  
- EntryPoint (v0.7): `0x0000000071727De22E5E9d8BAf0edAc6f37da032`  
- Default Oracle (eOracle ETH/USD): `0xdFc720E1ef024bfc768ed9E6F0e7Fc80E28f8CFA`

---

## Deployments

| Network       | Status          | Proxy Address                  |
|---------------|-----------------|--------------------------------|
| Ink Sepolia   | Ready to deploy | _To be filled after deployment_ |
| Ink Mainnet   | Ready           | 0xFb47b3F8A7BD7EB6A7844DbF3930f82D360d78a3 |

---

## Getting Started

### Prerequisites

- Node.js 18+
- npm or yarn
- Hardhat
- A funded wallet for the target network

### Installation

```bash
npm install
npx hardhat clean
npx hardhat compile
npx hardhat test

Deploy
# Testnet (recommended first)
npx hardhat run scripts/deploy.ts --network inkSepolia

# Mainnet
npx hardhat run scripts/deploy.ts --network ink

Useful Commands
npx hardhat clean
npx hardhat compile
npx hardhat test
npx hardhat coverage
npx hardhat run scripts/deploy.ts --network inkSepolia
npx hardhat run scripts/deploy.ts --network ink

Project Structure
contracts/
  ├── InkOmniVaultAI.sol
  └── mocks/
      ├── InkMockPriceFeed.sol
      ├── VeloRouterMock.sol
      └── EntryPointMock.sol
scripts/
  └── deploy.ts
test/
  └── InkOmniVaultAI.test.ts
ai-agent/
  ├── config.ts
  ├── aiAnalyzer.ts
  └── keeperBot.ts
hardhat.config.ts
package.json
tsconfig.json
.env
README.md

Native Protocol Addresses (Ink Mainnet)
Velodrome:Universal Router:0x01D40099fCD87C018969B0e8D4aB1633Fb34763C
Tydro:Pool (Aave V3):0x2816cf15F6d2A220E789aA011D5EE4eB6c47FEbA
Nado:Endpoint:0x05ec92D78ED421f3D3Ada77FFdE167106565974E


Security Considerations
Built with OpenZeppelin upgradeable contracts (UUPS)
Critical actions protected by roles + optional timelock + two-step admin transfer
AI agents and session keys strictly limited by daily/spending caps
Circuit breaker pauses the contract after consecutive failures
Oracle staleness protection (1 hour threshold)
This code has not been audited.
Do not use with significant funds before a professional audit.
Passkey cryptographic verification (P256 / WebAuthn) is prepared at the storage level but requires a verifier implementation for production.

License
MIT
