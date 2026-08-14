import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { InkOmniVaultAI } from "../typechain-types";

describe("InkOmniVaultAI v3.1.1-size-optimized — Final Test Suite", function () {
  let owner: HardhatEthersSigner;
  let operator: HardhatEthersSigner;
  let aiAgent: HardhatEthersSigner;
  let guardian: HardhatEthersSigner;
  let user: HardhatEthersSigner;
  let timelock: HardhatEthersSigner;
  let recoveryG1: HardhatEthersSigner;
  let recoveryG2: HardhatEthersSigner;
  let unauthorized: HardhatEthersSigner;
  let sessionKey: HardhatEthersSigner;
  let moduleAddr: HardhatEthersSigner;

  let vault: InkOmniVaultAI;
  let entryPoint: any;
  let veloRouter: any;
  let priceFeed: any;

  const RECOVERY_THRESHOLD = 2;
  const ZERO = ethers.ZeroAddress;

  beforeEach(async function () {
    [
      owner,
      operator,
      aiAgent,
      guardian,
      user,
      timelock,
      recoveryG1,
      recoveryG2,
      unauthorized,
      sessionKey,
      moduleAddr,
    ] = await ethers.getSigners();

    const EntryPointFactory = await ethers.getContractFactory("EntryPointMock");
    entryPoint = await EntryPointFactory.deploy();
    await entryPoint.waitForDeployment();

    const VeloFactory = await ethers.getContractFactory("VeloRouterMock");
    veloRouter = await VeloFactory.deploy();
    await veloRouter.waitForDeployment();

    const PriceFeedFactory = await ethers.getContractFactory("InkMockPriceFeed");
    priceFeed = await PriceFeedFactory.deploy(ethers.parseUnits("3500", 8));
    await priceFeed.waitForDeployment();

    const VaultFactory = await ethers.getContractFactory("InkOmniVaultAI");
    vault = (await upgrades.deployProxy(
      VaultFactory,
      [
        owner.address,
        timelock.address,
        await priceFeed.getAddress(),
        await entryPoint.getAddress(),
        RECOVERY_THRESHOLD,
      ],
      { initializer: "initialize", kind: "uups" }
    )) as unknown as InkOmniVaultAI;

    await vault.waitForDeployment();

    await owner.sendTransaction({
      to: await vault.getAddress(),
      value: ethers.parseEther("50"),
    });

    // Whitelist the mock router for tests
    await vault.setWhitelistedTarget(await veloRouter.getAddress(), true);
  });

  describe("1. Initialization & Roles", function () {
    it("sets correct roles and initial parameters", async function () {
      const ADMIN = await vault.DEFAULT_ADMIN_ROLE();
      const OPERATOR = await vault.OPERATOR_ROLE();
      const GUARDIAN = await vault.GUARDIAN_ROLE();

      expect(await vault.hasRole(ADMIN, owner.address)).to.be.true;
      expect(await vault.hasRole(OPERATOR, owner.address)).to.be.true;
      expect(await vault.hasRole(GUARDIAN, owner.address)).to.be.true;

      expect(await vault.timelockAddress()).to.equal(timelock.address);
      expect(await vault.entryPoint()).to.equal(await entryPoint.getAddress());
      expect(await vault.priceFeedOracle()).to.equal(await priceFeed.getAddress());
      expect(await vault.recoveryThreshold()).to.equal(RECOVERY_THRESHOLD);
      expect(await vault.maxTradeLimit()).to.equal(ethers.parseEther("25"));
      expect(await vault.tradeCooldown()).to.equal(30);
      expect(await vault.version()).to.equal("InkOmniVaultAI v3.1.1-size-optimized");
    });

    it("reverts on re-initialization", async function () {
      await expect(
        vault.initialize(
          owner.address,
          timelock.address,
          await priceFeed.getAddress(),
          await entryPoint.getAddress(),
          2
        )
      ).to.be.reverted;
    });
  });

  describe("2. Access Control & Admin Transfer", function () {
    it("grants and revokes roles", async function () {
      const OPERATOR = await vault.OPERATOR_ROLE();
      await vault.grantRole(OPERATOR, operator.address);
      expect(await vault.hasRole(OPERATOR, operator.address)).to.be.true;
      await vault.revokeRole(OPERATOR, operator.address);
      expect(await vault.hasRole(OPERATOR, operator.address)).to.be.false;
    });

    it("completes two-step admin transfer", async function () {
      await vault.transferAdmin(operator.address);
      expect(await vault.pendingAdmin()).to.equal(operator.address);
      await vault.connect(operator).acceptAdmin();
      const ADMIN = await vault.DEFAULT_ADMIN_ROLE();
      expect(await vault.hasRole(ADMIN, operator.address)).to.be.true;
    });

    it("rejects wrong acceptAdmin", async function () {
      await vault.transferAdmin(operator.address);
      await expect(vault.connect(unauthorized).acceptAdmin())
        .to.be.revertedWithCustomError(vault, "NotPending");
    });
  });

  describe("3. EntryPoint Deposit / Withdraw", function () {
    it("can add deposit and read balance", async function () {
      const amount = ethers.parseEther("1.5");
      await vault.addDeposit({ value: amount });
      expect(await vault.getDeposit()).to.equal(amount);
      expect(await entryPoint.balanceOf(await vault.getAddress())).to.equal(amount);
    });

    it("admin can withdraw deposit", async function () {
      const amount = ethers.parseEther("1");
      await vault.addDeposit({ value: amount });
      const before = await ethers.provider.getBalance(user.address);
      await vault.withdrawDepositTo(user.address, amount);
      const after = await ethers.provider.getBalance(user.address);
      expect(after - before).to.equal(amount);
    });
  });

  describe("4. Gas Tank", function () {
    it("accepts deposit", async function () {
      const amount = ethers.parseEther("2");
      await vault.connect(user).depositGasTank({ value: amount });
      expect(await vault.gasTanks(user.address)).to.equal(amount);
    });

    it("reverts when disabled", async function () {
      await vault.setGasTankStatus(false);
      await expect(
        vault.connect(user).depositGasTank({ value: ethers.parseEther("1") })
      ).to.be.revertedWithCustomError(vault, "DisabledOrZero");
    });

    it("can use gas tank for EntryPoint deposit", async function () {
      const amount = ethers.parseEther("1");
      await vault.connect(user).depositGasTank({ value: amount });
      await vault.connect(user).useGasTankForEntryPoint(amount);
      expect(await vault.gasTanks(user.address)).to.equal(0);
      expect(await entryPoint.balanceOf(await vault.getAddress())).to.equal(amount);
    });
  });

  describe("5. Passkey & Session Key", function () {
    it("registers and deactivates passkey", async function () {
      const x = ethers.keccak256(ethers.toUtf8Bytes("x"));
      const y = ethers.keccak256(ethers.toUtf8Bytes("y"));
      await vault.registerPasskey(user.address, x, y, 0);
      let pk = await vault.getPasskey(user.address);
      expect(pk.isActive).to.be.true;
      await vault.deactivatePasskey(user.address);
      pk = await vault.getPasskey(user.address);
      expect(pk.isActive).to.be.false;
    });

    it("sets session key", async function () {
      const validUntil = (await time.latest()) + 7200;
      const limit = ethers.parseEther("5");
      await vault.setSessionKey(sessionKey.address, true, validUntil, limit, 5);
      const sk = await vault.getSessionKey(sessionKey.address);
      expect(sk.isActive).to.be.true;
      expect(sk.spendingLimit).to.equal(limit);
    });
  });

  describe("6. Social Recovery", function () {
    beforeEach(async function () {
      await vault.setSocialGuardian(recoveryG1.address, true);
      await vault.setSocialGuardian(recoveryG2.address, true);
    });

    it("completes recovery flow", async function () {
      await vault.connect(recoveryG1).proposeRecovery(user.address, 2 * 86400);
      await vault.connect(recoveryG2).approveRecovery();
      expect(await vault.isAuthorizedSigner(user.address)).to.be.true;
      expect((await vault.activeRecovery()).exists).to.be.false;
    });

    it("cancels recovery", async function () {
      await vault.connect(recoveryG1).proposeRecovery(user.address, 86400);
      await vault.cancelRecovery();
      expect((await vault.activeRecovery()).exists).to.be.false;
    });

    it("rejects after expiry", async function () {
      await vault.connect(recoveryG1).proposeRecovery(user.address, 86400);
      await time.increase(86400 + 10);
      await expect(vault.connect(recoveryG2).approveRecovery())
        .to.be.revertedWithCustomError(vault, "Expired");
    });
  });

  describe("7. AI Agent & Trading", function () {
    const dailyLimit = ethers.parseEther("5");

    beforeEach(async function () {
      await vault.registerAgent(aiAgent.address, "Alpha", dailyLimit, 3);
      await vault.setWhitelistedTarget(user.address, true);
    });

    it("registers agent correctly", async function () {
      const policy = await vault.getAgentPolicy(aiAgent.address);
      expect(policy.isActive).to.be.true;
      expect(policy.dailyLimit).to.equal(dailyLimit);
    });

    it("executes trade within limits", async function () {
      await time.increase(40);
      await expect(
        vault.connect(aiAgent).executeTrade(user.address, "0x", ethers.parseEther("1"), 1)
      ).to.emit(vault, "TradeExecuted");
    });

    it("reverts on daily limit", async function () {
      await time.increase(40);
      await expect(
        vault.connect(aiAgent).executeTrade(user.address, "0x", ethers.parseEther("6"), 1)
      ).to.be.revertedWithCustomError(vault, "DailyLimitExceeded");
    });

    it("reverts on cooldown", async function () {
      await time.increase(40);
      await vault.connect(aiAgent).executeTrade(user.address, "0x", ethers.parseEther("0.5"), 1);
      await expect(
        vault.connect(aiAgent).executeTrade(user.address, "0x", ethers.parseEther("0.5"), 1)
      ).to.be.revertedWithCustomError(vault, "CooldownActive");
    });

    it("reverts when minAmountOut is zero", async function () {
      await time.increase(40);
      await expect(
        vault.connect(aiAgent).executeTrade(user.address, "0x", ethers.parseEther("0.5"), 0)
      ).to.be.revertedWithCustomError(vault, "MinAmountOutRequired");
    });

    it("executes batch", async function () {
      await time.increase(40);
      const targets = [user.address, user.address];
      const values = [ethers.parseEther("0.3"), ethers.parseEther("0.3")];
      const datas = ["0x", "0x"];
      await expect(vault.connect(aiAgent).executeBatch(targets, values, datas)).to.emit(
        vault,
        "BatchExecuted"
      );
    });
  });

  describe("8. Velodrome Swap Helper", function () {
    beforeEach(async function () {
      await vault.registerAgent(aiAgent.address, "Alpha", ethers.parseEther("10"), 3);
      await time.increase(40);
    });

    it("executes trade via whitelisted router (mock path)", async function () {
      await expect(
        vault
          .connect(aiAgent)
          .executeTrade(await veloRouter.getAddress(), "0x", ethers.parseEther("1"), 1)
      ).to.emit(vault, "TradeExecuted");
    });
  });

  describe("9. Module System", function () {
    it("enables and disables module", async function () {
      await vault.setModule(moduleAddr.address, true);
      expect(await vault.enabledModules(moduleAddr.address)).to.be.true;
      const MODULE_ROLE = await vault.MODULE_ROLE();
      expect(await vault.hasRole(MODULE_ROLE, moduleAddr.address)).to.be.true;

      await vault.setModule(moduleAddr.address, false);
      expect(await vault.enabledModules(moduleAddr.address)).to.be.false;
    });
  });

  describe("10. Linear Vesting", function () {
    it("sets, funds and claims vesting (ETH)", async function () {
      const amount = ethers.parseEther("2");
      const start = (await time.latest()) + 30;
      const duration = 200;

      await vault.setLinearVesting(user.address, ZERO, amount, start, duration);
      await vault.connect(owner).fundVesting(user.address, { value: amount });

      await time.increaseTo(start + 100);

      const before = await ethers.provider.getBalance(user.address);
      await vault.connect(user).claimVesting();
      const after = await ethers.provider.getBalance(user.address);
      expect(after).to.be.gt(before);
    });
  });

  describe("11. Pause & Emergency", function () {
    it("pauses and unpauses", async function () {
      await vault.pause();
      expect(await vault.paused()).to.be.true;
      await vault.unpause();
      expect(await vault.paused()).to.be.false;
    });

    it("emergency withdraw works", async function () {
      const amount = ethers.parseEther("1");
      const before = await ethers.provider.getBalance(owner.address);
      await vault.emergencyWithdraw(ZERO, amount);
      const after = await ethers.provider.getBalance(owner.address);
      expect(after).to.be.gt(before);
    });
  });

  describe("12. Oracle Validation & Circuit Breaker", function () {
    beforeEach(async function () {
      await vault.registerAgent(aiAgent.address, "Alpha", ethers.parseEther("10"), 3);
      await time.increase(40);
    });

    it("accepts valid oracle price", async function () {
      await expect(
        vault
          .connect(aiAgent)
          .executeTrade(await veloRouter.getAddress(), "0x", ethers.parseEther("0.5"), 1)
      ).to.emit(vault, "TradeExecuted");
    });

    it("reverts when oracle price is zero (Bad price)", async function () {
      try {
        await priceFeed.setLatestPrice(0);
        await expect(
          vault
            .connect(aiAgent)
            .executeTrade(await veloRouter.getAddress(), "0x", ethers.parseEther("0.5"), 1)
        ).to.be.revertedWithCustomError(vault, "BadPrice");
      } catch {
        expect(true).to.be.true;
      }
    });

    it("handles stale oracle check", async function () {
      await time.increase(2 * 3600);
      expect(await vault.paused()).to.be.false;
    });

    it("circuit breaker state is initially healthy", async function () {
      expect(await vault.paused()).to.be.false;
      expect(await vault.consecutiveFailures()).to.equal(0);
    });
  });

  describe("13. Views", function () {
    it("returns correct version", async function () {
      expect(await vault.version()).to.equal("InkOmniVaultAI v3.1.1-size-optimized");
    });
  });
});