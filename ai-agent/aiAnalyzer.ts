import { ethers } from "ethers";
import { CONFIG } from "./config";

export interface MarketSignal {
  action: "HOLD" | "BUY" | "SELL" | "SWAP";
  confidence: number; // 0-100
  riskScore: number;  // 0-10
  suggestedAmountEth: string;
  reason: string;
}

/**
 * Simple rule-based AI analyzer (can be replaced with real LLM / ML later)
 */
export class AIAnalyzer {
  private provider: ethers.JsonRpcProvider;

  constructor(rpcUrl: string = CONFIG.RPC_URL) {
    this.provider = new ethers.JsonRpcProvider(rpcUrl);
  }

  async analyze(price: number, volatility: number, gasPriceGwei: number): Promise<MarketSignal> {
    let action: MarketSignal["action"] = "HOLD";
    let confidence = 50;
    let riskScore = 3;
    let suggestedAmountEth = "0.1";
    let reason = "Neutral market conditions";

    // Very simple heuristic (replace with real model)
    if (volatility > 8 && price > 3000) {
      action = "HOLD";
      confidence = 70;
      riskScore = 6;
      reason = "High volatility – protect capital";
    } else if (volatility < 3 && price < 2800) {
      action = "BUY";
      confidence = 75;
      riskScore = 4;
      suggestedAmountEth = "0.5";
      reason = "Low volatility + discounted price";
    } else if (gasPriceGwei > 50) {
      action = "HOLD";
      confidence = 80;
      riskScore = 5;
      reason = "Gas too expensive";
    }

    // Hard safety caps
    if (riskScore > CONFIG.MAX_RISK_SCORE) {
      action = "HOLD";
      reason += " | Risk score exceeded";
    }

    return { action, confidence, riskScore, suggestedAmountEth, reason };
  }

  async getEthPriceFromOracle(oracleAddress: string): Promise<number> {
    const abi = ["function latestRoundData() view returns (uint80,int256,uint256,uint256,uint80)"];
    const oracle = new ethers.Contract(oracleAddress, abi, this.provider);
    const [, answer] = await oracle.latestRoundData();
    return Number(ethers.formatUnits(answer, 8));
  }
}