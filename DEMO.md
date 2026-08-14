# Ink OmniVault AI — Live Demo Guide

**For Grant Reviewers & Ecosystem Team**

---

## Live Demo Website

**Professional Demo Site:** [https://ink-omnivault.netlify.app/](https://ink-omnivault.netlify.app/)

---

## Contract Information

| Item                | Value |
|---------------------|-------|
| Network             | Ink Mainnet |
| Chain ID            | 57073 |
| **Proxy Address**   | [`0xFb47b3F8A7BD7EB6A7844DbF3930f82D360d78a3`](https://explorer.inkonchain.com/address/0xFb47b3F8A7BD7EB6A7844DbF3930f82D360d78a3) |
| Implementation      | [`0x3FD122771DBc7605ee7D515876F41826C2eb515e`](https://explorer.inkonchain.com/address/0x3FD122771DBc7605ee7D515876F41826C2eb515e#code) |
| Verified on Explorer| Yes (both Proxy & Implementation) |

---

## Successful Live Demo Results

The professional demo was successfully executed on **Ink Mainnet**.

**Results:**
- Contract Version: `InkOmniVaultAI v3.1.1-size-optimized`
- AI Agent registered with policy controls
- Session Key created with spending limit
- Controlled execution by AI Agent → Success
- Controlled execution by Session Key → Success
- Circuit Breaker: Healthy (`Paused = false`, `Failures = 0`)

**Transaction Hashes:**
- AI Agent Execute: [0xae267cabc55986a704a5b83409a0896549489494ee5f5d3b43d2e761b4cf44c6](https://explorer.inkonchain.com/tx/0xae267cabc55986a704a5b83409a0896549489494ee5f5d3b43d2e761b4cf44c6)
- Session Key Execute: [0x9a30fa797920aa66eb3bae41e006e693f95407e3ce907b669ef36830826da306](https://explorer.inkonchain.com/tx/0x9a30fa797920aa66eb3bae41e006e693f95407e3ce907b669ef36830826da306)

---

How to quickly check the live contract:Open the demo website: https://ink-omnivault.netlify.app/
Make sure your wallet is connected to Ink Mainnet (Chain ID 57073)
The Proxy Address is already filled:
0xFb47b3F8A7BD7EB6A7844DbF3930f82D360d78a3
Click the Status tab → Read Version / Paused / Balance / Failures
→ You should see the version, paused status, and balance.

Optional deeper checks:Agent Policy tab → enter a registered agent address to see daily limit & risk score
Session Key tab → enter a session key address to check spending limit and expiry


## Quick Start

```bash
echo "VAULT_ADDRESS=0xFb47b3F8A7BD7EB6A7844DbF3930f82D360d78a3" >> .env
npx hardhat run scripts/demo.ts --network ink

The script automatically demonstrates:Contract version check
AI Agent registration + Policy controls
Session Key creation with spending limit
Controlled execution by AI Agent
Controlled execution by Session Key
Cooldown & safety mechanisms

What This Demo ProvesSecure AI Agent infrastructure on Ink
Daily spending limits & risk scoring
Session Keys with strict controls
Native readiness for Tydro, Nado & Velodrome
Production-grade safety (cooldown, circuit breaker, roles)
