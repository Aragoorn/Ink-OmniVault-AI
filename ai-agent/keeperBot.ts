import { ethers } from "ethers";
import { CONFIG, VAULT_ABI } from "./config";
import { AIAnalyzer } from "./aiAnalyzer";

async function main() {
  if (!CONFIG.VAULT_ADDRESS || !CONFIG.AI_PRIVATE_KEY) {
    throw new Error("Missing VAULT_ADDRESS or AI_PRIVATE_KEY in .env");
  }

  const provider = new ethers.JsonRpcProvider(CONFIG.RPC_URL);
  const wallet = new ethers.Wallet(CONFIG.AI_PRIVATE_KEY, provider);
  const vault = new ethers.Contract(CONFIG.VAULT_ADDRESS, VAULT_ABI, wallet);
  const analyzer = new AIAnalyzer();

  console.log("🤖 AI Keeper Bot started (Ink Network)");
  console.log("Agent address:", wallet.address);
  console.log("Vault:", CONFIG.VAULT_ADDRESS);

  // Check agent policy
  const policy = await vault.getAgentPolicy(wallet.address);
  if (!policy.isActive) {
    console.error("Agent is not active on-chain");
    process.exit(1);
  }

  // Check pause
  if (await vault.paused()) {
    console.error("Vault is paused – waiting");
    return;
  }

  // Get market data
  const ethPrice = await analyzer.getEthPriceFromOracle(CONFIG.PRICE_FEED);
  const feeData = await provider.getFeeData();
  const gasPriceGwei = Number(ethers.formatUnits(feeData.gasPrice || 0n, "gwei"));

  const signal = await analyzer.analyze(ethPrice, 4.2, gasPriceGwei); // volatility mock
  console.log("Signal:", signal);

  if (signal.action === "HOLD" || signal.confidence < 60) {
    console.log("No action taken");
    return;
  }

  // Safety: check cooldown
  const lastTrade = await vault.lastTradeTimestamp(wallet.address);
  const now = Math.floor(Date.now() / 1000);
  if (now < Number(lastTrade) + CONFIG.TRADE_COOLDOWN_SEC) {
    console.log("Cooldown active");
    return;
  }

  // Example safe action (you can expand)
  if (signal.action === "BUY" || signal.action === "SWAP") {
    const amount = ethers.parseEther(signal.suggestedAmountEth);
    const maxLimit = await vault.maxTradeLimit();
    if (amount > maxLimit) {
      console.log("Amount exceeds maxTradeLimit");
      return;
    }

    // Example: just log – replace with real swap path when ready
    console.log(`Would execute ${signal.action} for ${signal.suggestedAmountEth} ETH on Ink via Velodrome`);
    // Uncomment when ready:
    // const tx = await vault.swapExactETHForTokensVelodrome(...);
    // await tx.wait();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});