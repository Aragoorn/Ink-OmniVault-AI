import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.clear();
  console.log("\n╔════════════════════════════════════════════════════════════╗");
  console.log("║           Ink OmniVault AI  —  Professional Demo           ║");
  console.log("║                  For Grant Reviewers                       ║");
  console.log("╚════════════════════════════════════════════════════════════╝\n");

  const VAULT_ADDRESS = process.env.VAULT_ADDRESS;
  if (!VAULT_ADDRESS) {
    console.error("❌ VAULT_ADDRESS is not set in .env");
    process.exit(1);
  }

  const [deployer] = await ethers.getSigners();
  const vault = await ethers.getContractAt("InkOmniVaultAI", VAULT_ADDRESS);

  // کیف‌پول‌های تصادفی برای تست
  const agentWallet = ethers.Wallet.createRandom().connect(ethers.provider);
  const receiver1 = ethers.Wallet.createRandom();
  const receiver2 = ethers.Wallet.createRandom();
  const sessionWallet = ethers.Wallet.createRandom().connect(ethers.provider);

  console.log("📋 Demo Configuration");
  console.log("────────────────────────────────────────────────────────────");
  console.log("Vault Address :", VAULT_ADDRESS);
  console.log("Deployer      :", deployer.address);
  console.log("AI Agent      :", agentWallet.address);
  console.log("Session Key   :", sessionWallet.address);
  console.log("");

  const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

  try {
    // 1. Version
    console.log("① Checking Contract Version...");
    const version = await vault.version();
    console.log("   ✅ Version:", version);
    console.log("");

    // 2. Fund Vault
    console.log("② Funding Vault...");
    const balance = await ethers.provider.getBalance(VAULT_ADDRESS);
    if (balance < ethers.parseEther("0.000005")) {
      const tx = await deployer.sendTransaction({
        to: VAULT_ADDRESS,
        value: ethers.parseEther("0.00002"),
      });
      await tx.wait();
      console.log("   ✅ Vault funded with 0.00002 ETH");
    } else {
      console.log("   ✅ Vault already has enough ETH");
    }
    console.log("");

    // 3. Whitelist
    console.log("③ Whitelisting receivers...");
    await (await vault.setWhitelistedTarget(receiver1.address, true)).wait();
    await (await vault.setWhitelistedTarget(receiver2.address, true)).wait();
    console.log("   ✅ Receivers whitelisted");
    console.log("");

    // 4. Register Agent
    console.log("④ Registering AI Agent...");
    try {
      await (await vault.registerAgent(
        agentWallet.address,
        "GrantDemoAgent",
        ethers.parseEther("1"),
        3
      )).wait();
      console.log("   ✅ AI Agent registered");
    } catch {
      console.log("   ℹ️  Agent already registered (skipping)");
    }
    console.log("");

    // 5. Set Session Key
    console.log("⑤ Setting Session Key...");
    const validUntil = Math.floor(Date.now() / 1000) + 7200; // 2 hours
    await (await vault.setSessionKey(
      sessionWallet.address,
      true,
      validUntil,
      ethers.parseEther("0.001"),
      5
    )).wait();
    console.log("   ✅ Session Key set");
    console.log("");

    // 6. Send gas to agent & session key
    console.log("⑥ Sending gas to Agent & Session Key...");
    await (await deployer.sendTransaction({
      to: agentWallet.address,
      value: ethers.parseEther("0.00001"),
    })).wait();
    await (await deployer.sendTransaction({
      to: sessionWallet.address,
      value: ethers.parseEther("0.00001"),
    })).wait();
    console.log("   ✅ Gas sent");
    console.log("");

    // 7. Execute with Agent
    console.log("⑦ Executing with AI Agent...");
    const tx1 = await vault.connect(agentWallet).execute(
      receiver1.address,
      ethers.parseEther("0.000001"),
      "0x"
    );
    const rc1 = await tx1.wait();
    console.log("   ✅ Success! Tx:", rc1?.hash);
    console.log("");

    // صبر برای رد شدن cooldown
    console.log("⏳ Waiting 45 seconds for trade cooldown...");
    await sleep(45000);
    console.log("   ✅ Cooldown passed\n");

    // 8. Execute with Session Key
    console.log("⑧ Executing with Session Key...");
    const tx2 = await vault.connect(sessionWallet).execute(
      receiver2.address,
      ethers.parseEther("0.000001"),
      "0x"
    );
    const rc2 = await tx2.wait();
    console.log("   ✅ Success! Tx:", rc2?.hash);
    console.log("");

    // Final status
    console.log("⑨ Final Status");
    const isPaused = await vault.paused();
    const failures = await vault.consecutiveFailures();
    console.log("   • Paused               :", isPaused);
    console.log("   • Consecutive Failures :", failures.toString());
    console.log("");

    console.log("╔════════════════════════════════════════════════════════════╗");
    console.log("║                     DEMO COMPLETED ✅                      ║");
    console.log("╚════════════════════════════════════════════════════════════╝\n");

  } catch (error: any) {
    console.error("\n❌ Demo failed:");
    console.error(error.reason || error.shortMessage || error.message || error);
    process.exit(1);
  }
}

main();