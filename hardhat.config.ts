import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-verify";
import "@openzeppelin/hardhat-upgrades";
import * as dotenv from "dotenv";
import "hardhat-contract-sizer";

dotenv.config();

const PRIVATE_KEY =
  process.env.PRIVATE_KEY && process.env.PRIVATE_KEY.length >= 64
    ? process.env.PRIVATE_KEY
    : "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";

const INK_RPC = process.env.INK_RPC || "https://rpc-gel.inkonchain.com";
const INK_SEPOLIA_RPC = process.env.INK_SEPOLIA_RPC || "https://rpc-gel-sepolia.inkonchain.com";

// برای Blockscout معمولاً کلید واقعی لازم نیست، یک مقدار دلخواه کافی است
const EXPLORER_API_KEY = process.env.EXPLORER_API_KEY || "ink-blockscout";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1,               // برای کاهش سایز قرارداد
      },
      viaIR: true,
      metadata: {
        bytecodeHash: "none",
      },
    },
  },
  networks: {
    hardhat: {
      chainId: 31337,
      allowUnlimitedContractSize: true,
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      chainId: 31337,
    },
    ink: {
      url: INK_RPC,
      accounts: [PRIVATE_KEY],
      chainId: 57073,
    },
    inkSepolia: {
      url: INK_SEPOLIA_RPC,
      accounts: [PRIVATE_KEY],
      chainId: 763373,
    },
  },
  etherscan: {
    apiKey: {
      ink: EXPLORER_API_KEY,
      inkSepolia: EXPLORER_API_KEY,
    },
    customChains: [
      {
        network: "ink",
        chainId: 57073,
        urls: {
          apiURL: "https://explorer.inkonchain.com/api",
          browserURL: "https://explorer.inkonchain.com",
        },
      },
      {
        network: "inkSepolia",
        chainId: 763373,
        urls: {
          apiURL: "https://explorer-sepolia.inkonchain.com/api",
          browserURL: "https://explorer-sepolia.inkonchain.com",
        },
      },
    ],
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  typechain: {
    outDir: "typechain-types",
    target: "ethers-v6",
  },
  mocha: {
    timeout: 120000,
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false,
  },
};

export default config;