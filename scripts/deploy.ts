import { ethers, upgrades, network } from "hardhat";
import * as dotenv from "dotenv";

dotenv.config();

async function main() {
  const [deployer] = await ethers.getSigners();
  const balance = await ethers.provider.getBalance(deployer.address);

  console.log("=".repeat(60));
  console.log("Ink OmniVault AI — Deployment");
  console.log("=".repeat(60));
  console.log(`Network   : ${network.name}`);
  console.log(`Deployer  : ${deployer.address}`);
  console.log(`Balance   : ${ethers.formatEther(balance)} ETH`);
  console.log("=".repeat(60));

  // ---------- Configuration ----------
  const admin =
    process.env.ADMIN_ADDRESS || deployer.address;

  const timelock =
    process.env.TIMELOCK_ADDRESS || deployer.address;

  // eOracle ETH/USD on Ink Mainnet
  const defaultOracle =
    network.name === "ink"
      ? "0xdFc720E1ef024bfc768ed9E6F0e7Fc80E28f8CFA"
      : ethers.ZeroAddress;

  const oracle = process.env.ORACLE_ADDRESS || defaultOracle;

  // Canonical ERC-4337 EntryPoint v0.7 (preinstalled on Ink)
  const defaultEntryPoint = "0x0000000071727De22E5E9d8BAf0edAc6f37da032";
  const entryPoint =
    process.env.ENTRY_POINT_ADDRESS || defaultEntryPoint;

  const recoveryThreshold = 2;

  console.log("\nInitialization Parameters:");
  console.log(`  Admin              : ${admin}`);
  console.log(`  Timelock           : ${timelock}`);
  console.log(`  Oracle (eOracle)   : ${oracle}`);
  console.log(`  EntryPoint         : ${entryPoint}`);
  console.log(`  Recovery Threshold : ${recoveryThreshold}`);
  console.log("");

  // ---------- Deploy ----------
  const InkOmniVaultAI = await ethers.getContractFactory("InkOmniVaultAI");

  console.log("Deploying UUPS proxy...");

  const vault = await upgrades.deployProxy(
    InkOmniVaultAI,
    [admin, timelock, oracle, entryPoint, recoveryThreshold],
    {
      initializer: "initialize",
      kind: "uups",
      timeout: 0,
    }
  );

  await vault.waitForDeployment();
  const proxyAddress = await vault.getAddress();

  // Get implementation address
  const implementationAddress =
    await upgrades.erc1967.getImplementationAddress(proxyAddress);

  console.log("\n✅ Deployment successful!");
  console.log("=".repeat(60));
  console.log(`Proxy Address          : ${proxyAddress}`);
  console.log(`Implementation Address : ${implementationAddress}`);
  console.log("=".repeat(60));

  console.log("\nNext steps:");
  console.log(`1. Verify the proxy on https://explorer.inkonchain.com`);
  console.log(`2. Update README.md with the address above`);
  console.log(`3. (Optional) Call setWhitelistedTarget for any extra protocols`);
  console.log(`4. Register AI agents / guardians as needed`);
  console.log("");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ Deployment failed:");
    console.error(error);
    process.exit(1);
  });
