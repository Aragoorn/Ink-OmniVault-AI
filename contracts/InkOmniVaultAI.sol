// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/*──────────────────────────── ERC-4337 Interfaces ────────────────────────────*/
interface IEntryPoint {
    function getUserOpHash(UserOperation calldata userOp) external view returns (bytes32);
    function balanceOf(address account) external view returns (uint256);
    function depositTo(address account) external payable;
    function withdrawTo(address payable dest, uint256 amount) external;
}

struct UserOperation {
    address sender;
    uint256 nonce;
    bytes initCode;
    bytes callData;
    bytes32 accountGasLimits;
    uint256 preVerificationGas;
    bytes32 gasFees;
    bytes paymasterAndData;
    bytes signature;
}

interface IAccount {
    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external returns (uint256 validationData);
}

interface IPriceFeed {
    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80);
}

interface IVeloRouter {
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
}

// Custom Errors (size optimization)
error InvalidAddress();
error Unauthorized();
error ZeroTarget();
error TargetNotAllowed();
error SessionLimitExceeded();
error CallFailed();
error InvalidBatchSize();
error LengthMismatch();
error CooldownActive();
error MaxTradeExceeded();
error NotWhitelisted();
error AgentInactive();
error RiskTooHigh();
error DailyLimitExceeded();
error OracleFailed();
error BadPrice();
error StalePrice();
error ZeroAddress();
error BadDuration();
error ActiveProposal();
error NotGuardian();
error NoProposal();
error Expired();
error AlreadyApproved();
error ZeroValue();
error TooHigh();
error NotPending();
error DisabledOrZero();
error InsufficientBalance();
error InvalidParams();
error NoVesting();
error NothingToClaim();
error ETHTransferFailed();
error NoPermission();
error MinAmountOutRequired();
error InvalidPath();
error DeadlineExpired();
error DepositFailed();

/**
 * @title InkOmniVaultAI
 * @notice Production-ready UUPS Smart Account for Ink (v3.1.1-size-optimized)
 * @dev Includes native support for Velodrome, Tydro and Nado on Ink
 */
contract InkOmniVaultAI is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    IAccount
{
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant AI_AGENT_ROLE = keccak256("AI_AGENT_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant MODULE_ROLE = keccak256("MODULE_ROLE");

    uint256 public constant PRICE_STALENESS_THRESHOLD = 1 hours;
    uint256 public constant MAX_CONSECUTIVE_FAILURES = 3;
    uint256 public constant MAX_SLIPPAGE_BPS = 500;
    uint256 public constant MAX_RECOVERY_DURATION = 30 days;
    uint256 public constant MIN_RECOVERY_DURATION = 1 days;
    uint256 public constant MAX_BATCH_SIZE = 15;

    // Ink-native protocol addresses
    address public constant VELODROME_ROUTER = 0x01D40099fCD87C018969B0e8D4aB1633Fb34763C;
    address public constant TYDRO_POOL = 0x2816cf15F6d2A220E789aA011D5EE4eB6c47FEbA;      // Tydro (Aave V3)
    address public constant NADO_ENDPOINT = 0x05ec92D78ED421f3D3Ada77FFdE167106565974E;  // Nado DEX

    IEntryPoint public entryPoint;
    address public priceFeedOracle;
    address public timelockAddress;
    address public pendingAdmin;
    uint256 public maxTradeLimit;
    uint256 public tradeCooldown;
    uint256 public maxAllowedSlippageBps;
    uint256 public consecutiveFailures;
    uint256 public recoveryThreshold;

    mapping(address => bool) public isAuthorizedSigner;

    struct PasskeySigner {
        bytes32 pubKeyX;
        bytes32 pubKeyY;
        bool isActive;
        uint48 validUntil;
    }
    mapping(address => PasskeySigner) public passkeyRegistry;

    struct SessionKey {
        bool isActive;
        uint48 validUntil;
        uint256 spendingLimit;
        uint256 spent;
        uint8 maxRiskScore;
    }
    mapping(address => SessionKey) public sessionKeys;

    mapping(address => bool) public isSocialGuardian;
    uint256 public totalSocialGuardians;

    struct RecoveryProposal {
        address newSigner;
        uint256 approvalsCount;
        uint48 deadline;
        bool executed;
        bool exists;
    }
    RecoveryProposal public activeRecovery;
    mapping(address => mapping(address => bool)) private recoveryApprovals;

    mapping(address => bool) public enabledModules;
    mapping(bytes4 => address) public selectorToModule;

    mapping(address => uint256) public gasTanks;
    bool public gasTankEnabled;

    struct AgentPolicy {
        bool isActive;
        uint256 dailyLimit;
        uint256 spentToday;
        uint48 lastResetTime;
        uint8 riskScore;
    }
    mapping(address => AgentPolicy) public agentPolicies;

    struct AgentMetadata {
        string name;
        address owner;
        uint8 riskProfile;
    }
    mapping(address => AgentMetadata) public agentRegistry;

    mapping(address => bool) public whitelistedTargets;
    mapping(address => uint256) public lastTradeTimestamp;

    struct LinearVesting {
        uint256 totalAmount;
        uint256 amountClaimed;
        uint48 startTime;
        uint48 duration;
        address token;
    }
    mapping(address => LinearVesting) public userVestings;

    event AgentRegistered(address indexed agent, string name, address indexed owner, uint8 riskProfile);
    event PolicyUpdated(address indexed agent, uint256 dailyLimit, uint8 riskScore, bool isActive);
    event SessionKeyUpdated(address indexed key, bool active, uint48 validUntil, uint256 spendingLimit);
    event TradeExecuted(address indexed executor, address indexed target, uint256 value, bytes data);
    event BatchExecuted(address indexed executor, uint256 count);
    event VelodromeSwapExecuted(address indexed tokenOut, uint256 amountIn, uint256 amountOutMin);
    event TargetWhitelisted(address indexed target, bool status);
    event ModuleUpdated(address indexed module, bool enabled);
    event VestingSet(address indexed beneficiary, address token, uint256 amount, uint48 startTime, uint48 duration);
    event VestingFunded(address indexed beneficiary, address token, uint256 amount);
    event VestingClaimed(address indexed beneficiary, address token, uint256 amount);
    event EmergencyWithdrawn(address indexed by, address indexed token, uint256 amount);
    event SignerUpdated(address indexed signer, bool status);
    event PasskeyRegistered(address indexed account, bytes32 pubKeyX, bytes32 pubKeyY, uint48 validUntil);
    event PasskeyDeactivated(address indexed account);
    event SocialGuardianUpdated(address indexed guardian, bool status);
    event RecoveryProposed(address indexed newSigner, uint48 deadline);
    event RecoveryApproved(address indexed guardian, address indexed newSigner);
    event RecoveryExecuted(address indexed newSigner);
    event RecoveryCancelled();
    event GasTankFunded(address indexed sponsor, uint256 amount);
    event GasTankUsed(address indexed user, uint256 amount);
    event CircuitBreakerTriggered(uint256 failures);
    event AdminTransferProposed(address indexed pendingAdmin);
    event AdminTransferCompleted(address indexed newAdmin);
    event EntryPointUpdated(address indexed newEntryPoint);
    event MaxTradeLimitUpdated(uint256 newLimit);
    event TradeCooldownUpdated(uint256 newCooldown);
    event OracleUpdated(address indexed newOracle);
    event TimelockUpdated(address indexed newTimelock);
    event MaxSlippageUpdated(uint256 bps);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address admin,
        address timelock,
        address oracle,
        address _entryPoint,
        uint256 _recoveryThreshold
    ) public initializer {
        if (admin == address(0) || _entryPoint == address(0)) revert InvalidAddress();

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, admin);
        _grantRole(GUARDIAN_ROLE, admin);

        timelockAddress = timelock;
        priceFeedOracle = oracle;
        entryPoint = IEntryPoint(_entryPoint);
        recoveryThreshold = _recoveryThreshold == 0 ? 2 : _recoveryThreshold;

        maxTradeLimit = 25 ether;
        tradeCooldown = 30;
        maxAllowedSlippageBps = 100;
        gasTankEnabled = true;

        // Whitelist native Ink protocols
        whitelistedTargets[VELODROME_ROUTER] = true;
        whitelistedTargets[TYDRO_POOL] = true;
        whitelistedTargets[NADO_ENDPOINT] = true;
    }

    modifier onlyAdminOrTimelock() {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender) && msg.sender != timelockAddress) {
            revert Unauthorized();
        }
        _;
    }

    modifier onlyAuthorizedExecutor() {
        if (
            !hasRole(DEFAULT_ADMIN_ROLE, msg.sender) &&
            !hasRole(AI_AGENT_ROLE, msg.sender) &&
            !hasRole(MODULE_ROLE, msg.sender) &&
            !isAuthorizedSigner[msg.sender] &&
            !sessionKeys[msg.sender].isActive &&
            msg.sender != address(entryPoint)
        ) revert Unauthorized();
        _;
    }

    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external override returns (uint256 validationData) {
        if (msg.sender != address(entryPoint)) revert Unauthorized();
        if (userOp.sender != address(this)) revert InvalidAddress();

        bytes32 ethHash = userOpHash.toEthSignedMessageHash();
        address recovered = ethHash.recover(userOp.signature);

        bool valid =
            hasRole(DEFAULT_ADMIN_ROLE, recovered) ||
            hasRole(AI_AGENT_ROLE, recovered) ||
            isAuthorizedSigner[recovered] ||
            _isValidPasskey(recovered) ||
            _isValidSessionKey(recovered);

        if (!valid) return 1;

        if (missingAccountFunds > 0) {
            (bool ok, ) = payable(address(entryPoint)).call{value: missingAccountFunds}("");
            if (!ok) revert DepositFailed();
        }
        return 0;
    }

    function _isValidPasskey(address account) internal view returns (bool) {
        PasskeySigner memory pk = passkeyRegistry[account];
        return pk.isActive && (pk.validUntil == 0 || pk.validUntil >= block.timestamp);
    }

    function _isValidSessionKey(address key) internal view returns (bool) {
        SessionKey memory sk = sessionKeys[key];
        return sk.isActive && sk.validUntil >= block.timestamp && sk.spent < sk.spendingLimit;
    }

    function execute(address target, uint256 value, bytes calldata data)
        external
        payable
        onlyAuthorizedExecutor
        nonReentrant
        whenNotPaused
    {
        _execute(target, value, data, msg.sender);
    }

    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas
    )
        external
        payable
        onlyAuthorizedExecutor
        nonReentrant
        whenNotPaused
    {
        uint256 len = targets.length;
        if (len == 0 || len > MAX_BATCH_SIZE) revert InvalidBatchSize();
        if (len != values.length || len != datas.length) revert LengthMismatch();

        for (uint256 i; i < len; ) {
            _execute(targets[i], values[i], datas[i], msg.sender);
            unchecked { ++i; }
        }
        emit BatchExecuted(msg.sender, len);
    }

    function _execute(address target, uint256 value, bytes memory data, address executor) internal {
        if (target == address(0)) revert ZeroTarget();
        if (
            !whitelistedTargets[target] &&
            target != address(this) &&
            !enabledModules[target]
        ) revert TargetNotAllowed();

        if (sessionKeys[executor].isActive) {
            SessionKey storage sk = sessionKeys[executor];
            if (sk.spent + value > sk.spendingLimit) revert SessionLimitExceeded();
            sk.spent += value;
        }

        (bool success, bytes memory ret) = target.call{value: value}(data);
        if (!success) {
            consecutiveFailures++;
            if (consecutiveFailures >= MAX_CONSECUTIVE_FAILURES) {
                _pause();
                emit CircuitBreakerTriggered(consecutiveFailures);
            }
            _bubbleRevert(ret);
        }
        if (consecutiveFailures > 0) consecutiveFailures = 0;

        emit TradeExecuted(executor, target, value, data);
    }

    function _bubbleRevert(bytes memory ret) private pure {
        if (ret.length > 0) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
        revert CallFailed();
    }

    function executeTrade(
        address target,
        bytes calldata data,
        uint256 value,
        uint256 minAmountOut
    )
        external
        payable
        onlyAuthorizedExecutor
        nonReentrant
        whenNotPaused
    {
        if (minAmountOut == 0) revert MinAmountOutRequired();
        _preTradeChecks(msg.sender, target, value);
        _execute(target, value, data, msg.sender);
    }

    function swapExactETHForTokensVelodrome(
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    )
        external
        payable
        onlyAuthorizedExecutor
        nonReentrant
        whenNotPaused
    {
        if (path.length < 2) revert InvalidPath();
        if (deadline < block.timestamp) revert DeadlineExpired();
        if (msg.value == 0) revert ZeroValue();
        if (amountOutMin == 0) revert MinAmountOutRequired();

        _preTradeChecks(msg.sender, VELODROME_ROUTER, msg.value);
        if (!_validateOracle()) revert OracleFailed();

        if (sessionKeys[msg.sender].isActive) {
            SessionKey storage sk = sessionKeys[msg.sender];
            if (sk.spent + msg.value > sk.spendingLimit) revert SessionLimitExceeded();
            sk.spent += msg.value;
        }

        (bool success, bytes memory ret) = VELODROME_ROUTER.call{value: msg.value}(
            abi.encodeWithSelector(
                IVeloRouter.swapExactETHForTokens.selector,
                amountOutMin,
                path,
                address(this),
                deadline
            )
        );

        if (!success) {
            consecutiveFailures++;
            if (consecutiveFailures >= MAX_CONSECUTIVE_FAILURES) {
                _pause();
                emit CircuitBreakerTriggered(consecutiveFailures);
            }
            _bubbleRevert(ret);
        }
        if (consecutiveFailures > 0) consecutiveFailures = 0;

        emit VelodromeSwapExecuted(path[path.length - 1], msg.value, amountOutMin);
        emit TradeExecuted(msg.sender, VELODROME_ROUTER, msg.value, ret);
    }

    function _preTradeChecks(address executor, address target, uint256 value) internal {
        if (block.timestamp < lastTradeTimestamp[executor] + tradeCooldown) revert CooldownActive();
        if (value > maxTradeLimit) revert MaxTradeExceeded();
        if (!whitelistedTargets[target] && target != VELODROME_ROUTER) revert NotWhitelisted();

        if (priceFeedOracle != address(0)) {
            if (!_validateOracle()) revert OracleFailed();
        }

        if (hasRole(AI_AGENT_ROLE, executor)) {
            AgentPolicy storage policy = agentPolicies[executor];
            if (!policy.isActive) revert AgentInactive();
            if (policy.riskScore > 8) revert RiskTooHigh();
            _resetDaily(policy);
            if (policy.spentToday + value > policy.dailyLimit) revert DailyLimitExceeded();
            policy.spentToday += value;
        }

        lastTradeTimestamp[executor] = block.timestamp;
    }

    function _validateOracle() internal view returns (bool) {
        if (priceFeedOracle == address(0)) return true;
        (, int256 price, , uint256 updatedAt, ) = IPriceFeed(priceFeedOracle).latestRoundData();
        if (price <= 0) revert BadPrice();
        if (block.timestamp - updatedAt > PRICE_STALENESS_THRESHOLD) revert StalePrice();
        return true;
    }

    function _resetDaily(AgentPolicy storage policy) internal {
        if (block.timestamp >= uint256(policy.lastResetTime) + 1 days) {
            policy.spentToday = 0;
            policy.lastResetTime = uint48(block.timestamp);
        }
    }

    function setSessionKey(
        address key,
        bool active,
        uint48 validUntil,
        uint256 spendingLimit,
        uint8 maxRiskScore
    ) external onlyAdminOrTimelock {
        if (key == address(0)) revert ZeroAddress();
        sessionKeys[key] = SessionKey({
            isActive: active,
            validUntil: validUntil,
            spendingLimit: spendingLimit,
            spent: 0,
            maxRiskScore: maxRiskScore
        });
        emit SessionKeyUpdated(key, active, validUntil, spendingLimit);
    }

    function setModule(address module, bool enabled) external onlyAdminOrTimelock {
        if (module == address(0)) revert ZeroAddress();
        enabledModules[module] = enabled;
        if (enabled) {
            _grantRole(MODULE_ROLE, module);
        } else {
            _revokeRole(MODULE_ROLE, module);
        }
        emit ModuleUpdated(module, enabled);
    }

    function registerPasskey(
        address account,
        bytes32 pubKeyX,
        bytes32 pubKeyY,
        uint48 validUntil
    ) external onlyAdminOrTimelock {
        if (account == address(0)) revert ZeroAddress();
        passkeyRegistry[account] = PasskeySigner(pubKeyX, pubKeyY, true, validUntil);
        emit PasskeyRegistered(account, pubKeyX, pubKeyY, validUntil);
    }

    function deactivatePasskey(address account) external onlyAdminOrTimelock {
        passkeyRegistry[account].isActive = false;
        emit PasskeyDeactivated(account);
    }

    function setSocialGuardian(address guardian, bool status) external onlyAdminOrTimelock {
        if (guardian == address(0)) revert ZeroAddress();
        if (isSocialGuardian[guardian] != status) {
            isSocialGuardian[guardian] = status;
            status ? totalSocialGuardians++ : totalSocialGuardians--;
        }
        emit SocialGuardianUpdated(guardian, status);
    }

    function proposeRecovery(address newSigner, uint48 duration) external {
        if (!isSocialGuardian[msg.sender]) revert NotGuardian();
        if (newSigner == address(0)) revert ZeroAddress();
        if (duration < MIN_RECOVERY_DURATION || duration > MAX_RECOVERY_DURATION) revert BadDuration();
        if (activeRecovery.exists && !activeRecovery.executed && block.timestamp <= activeRecovery.deadline) {
            revert ActiveProposal();
        }

        activeRecovery = RecoveryProposal({
            newSigner: newSigner,
            approvalsCount: 1,
            deadline: uint48(block.timestamp + duration),
            executed: false,
            exists: true
        });
        recoveryApprovals[newSigner][msg.sender] = true;
        emit RecoveryProposed(newSigner, activeRecovery.deadline);
    }

    function approveRecovery() external {
        if (!isSocialGuardian[msg.sender]) revert NotGuardian();
        RecoveryProposal storage p = activeRecovery;
        if (!p.exists || p.executed) revert NoProposal();
        if (block.timestamp > p.deadline) revert Expired();
        if (recoveryApprovals[p.newSigner][msg.sender]) revert AlreadyApproved();

        recoveryApprovals[p.newSigner][msg.sender] = true;
        p.approvalsCount++;
        emit RecoveryApproved(msg.sender, p.newSigner);

        if (p.approvalsCount >= recoveryThreshold) {
            p.executed = true;
            isAuthorizedSigner[p.newSigner] = true;
            emit RecoveryExecuted(p.newSigner);
            delete activeRecovery;
        }
    }

    function cancelRecovery() external onlyAdminOrTimelock {
        delete activeRecovery;
        emit RecoveryCancelled();
    }

    function registerAgent(
        address agent,
        string calldata name,
        uint256 dailyLimit,
        uint8 riskScore
    ) external onlyAdminOrTimelock {
        if (agent == address(0) || bytes(name).length == 0) revert InvalidParams();
        _grantRole(AI_AGENT_ROLE, agent);

        agentRegistry[agent] = AgentMetadata(name, msg.sender, riskScore);
        agentPolicies[agent] = AgentPolicy({
            isActive: true,
            dailyLimit: dailyLimit,
            spentToday: 0,
            lastResetTime: uint48(block.timestamp),
            riskScore: riskScore
        });
        emit AgentRegistered(agent, name, msg.sender, riskScore);
    }

    function updateAgentPolicy(
        address agent,
        uint256 dailyLimit,
        bool isActive,
        uint8 riskScore
    ) external onlyAdminOrTimelock {
        AgentPolicy storage p = agentPolicies[agent];
        p.dailyLimit = dailyLimit;
        p.isActive = isActive;
        p.riskScore = riskScore;
        emit PolicyUpdated(agent, dailyLimit, riskScore, isActive);
    }

    function revokeAgent(address agent) external onlyAdminOrTimelock {
        _revokeRole(AI_AGENT_ROLE, agent);
        agentPolicies[agent].isActive = false;
    }

    function setSigner(address signer, bool status) external onlyAdminOrTimelock {
        isAuthorizedSigner[signer] = status;
        emit SignerUpdated(signer, status);
    }

    function setEntryPoint(address ep) external onlyAdminOrTimelock {
        if (ep == address(0)) revert ZeroAddress();
        entryPoint = IEntryPoint(ep);
        emit EntryPointUpdated(ep);
    }

    function setWhitelistedTarget(address target, bool status) external onlyAdminOrTimelock {
        whitelistedTargets[target] = status;
        emit TargetWhitelisted(target, status);
    }

    function setMaxTradeLimit(uint256 limit) external onlyAdminOrTimelock {
        maxTradeLimit = limit;
        emit MaxTradeLimitUpdated(limit);
    }

    function setTradeCooldown(uint256 cd) external onlyAdminOrTimelock {
        tradeCooldown = cd;
        emit TradeCooldownUpdated(cd);
    }

    function setMaxSlippage(uint256 bps) external onlyAdminOrTimelock {
        if (bps > MAX_SLIPPAGE_BPS) revert TooHigh();
        maxAllowedSlippageBps = bps;
        emit MaxSlippageUpdated(bps);
    }

    function setPriceFeedOracle(address oracle) external onlyAdminOrTimelock {
        priceFeedOracle = oracle;
        emit OracleUpdated(oracle);
    }

    function setTimelockAddress(address t) external onlyAdminOrTimelock {
        timelockAddress = t;
        emit TimelockUpdated(t);
    }

    function setRecoveryThreshold(uint256 t) external onlyAdminOrTimelock {
        if (t == 0) revert ZeroValue();
        recoveryThreshold = t;
    }

    function transferAdmin(address newAdmin) external onlyAdminOrTimelock {
        if (newAdmin == address(0)) revert ZeroAddress();
        pendingAdmin = newAdmin;
        emit AdminTransferProposed(newAdmin);
    }

    function acceptAdmin() external {
        if (msg.sender != pendingAdmin) revert NotPending();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        pendingAdmin = address(0);
        emit AdminTransferCompleted(msg.sender);
    }

    function depositGasTank() external payable {
        if (!gasTankEnabled || msg.value == 0) revert DisabledOrZero();
        gasTanks[msg.sender] += msg.value;
        emit GasTankFunded(msg.sender, msg.value);
    }

    function useGasTankForEntryPoint(uint256 amount) external nonReentrant {
        if (!gasTankEnabled) revert DisabledOrZero();
        if (gasTanks[msg.sender] < amount || amount == 0) revert InsufficientBalance();
        gasTanks[msg.sender] -= amount;
        entryPoint.depositTo{value: amount}(address(this));
        emit GasTankUsed(msg.sender, amount);
    }

    function setGasTankStatus(bool s) external onlyAdminOrTimelock {
        gasTankEnabled = s;
    }

    function setLinearVesting(
        address beneficiary,
        address token,
        uint256 amount,
        uint48 start,
        uint48 duration
    ) external onlyAdminOrTimelock {
        if (beneficiary == address(0) || amount == 0 || duration == 0) revert InvalidParams();
        userVestings[beneficiary] = LinearVesting(amount, 0, start, duration, token);
        emit VestingSet(beneficiary, token, amount, start, duration);
    }

    function fundVesting(address beneficiary) external payable nonReentrant {
        LinearVesting storage v = userVestings[beneficiary];
        if (v.totalAmount == 0) revert NoVesting();
        if (v.amountClaimed != 0) revert InvalidParams();

        if (v.token == address(0)) {
            if (msg.value != v.totalAmount) revert InvalidParams();
        } else {
            if (msg.value != 0) revert InvalidParams();
            IERC20(v.token).safeTransferFrom(msg.sender, address(this), v.totalAmount);
        }
        emit VestingFunded(beneficiary, v.token, v.totalAmount);
    }

    function claimVesting() external nonReentrant whenNotPaused {
        LinearVesting storage v = userVestings[msg.sender];
        if (v.totalAmount == 0) revert NoVesting();
        uint256 vested = _vestedAmount(v);
        uint256 claimable = vested - v.amountClaimed;
        if (claimable == 0) revert NothingToClaim();

        v.amountClaimed += claimable;

        if (v.token == address(0)) {
            (bool ok, ) = payable(msg.sender).call{value: claimable}("");
            if (!ok) revert ETHTransferFailed();
        } else {
            IERC20(v.token).safeTransfer(msg.sender, claimable);
        }
        emit VestingClaimed(msg.sender, v.token, claimable);
    }

    function _vestedAmount(LinearVesting memory v) internal view returns (uint256) {
        if (block.timestamp < v.startTime) return 0;
        if (block.timestamp >= uint256(v.startTime) + v.duration) return v.totalAmount;
        return (v.totalAmount * (block.timestamp - v.startTime)) / v.duration;
    }

    function pause() external {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender) && !hasRole(GUARDIAN_ROLE, msg.sender)) {
            revert NoPermission();
        }
        _pause();
    }

    function unpause() external onlyAdminOrTimelock {
        consecutiveFailures = 0;
        _unpause();
    }

    function recoverStuckTokens(address token, uint256 amount, address to)
        external
        onlyAdminOrTimelock
        nonReentrant
    {
        if (to == address(0)) revert ZeroAddress();
        if (token == address(0)) {
            (bool ok, ) = payable(to).call{value: amount}("");
            if (!ok) revert ETHTransferFailed();
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    function emergencyWithdraw(address token, uint256 amount)
        external
        onlyAdminOrTimelock
        nonReentrant
    {
        if (token == address(0)) {
            (bool ok, ) = payable(msg.sender).call{value: amount}("");
            if (!ok) revert ETHTransferFailed();
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }
        emit EmergencyWithdrawn(msg.sender, token, amount);
    }

    function addDeposit() external payable {
        entryPoint.depositTo{value: msg.value}(address(this));
    }

    function getDeposit() external view returns (uint256) {
        return entryPoint.balanceOf(address(this));
    }

    function withdrawDepositTo(address payable to, uint256 amount) external onlyAdminOrTimelock {
        entryPoint.withdrawTo(to, amount);
    }

    function _authorizeUpgrade(address) internal override onlyAdminOrTimelock {}

    receive() external payable {}

    function version() external pure returns (string memory) {
        return "InkOmniVaultAI v3.1.1-size-optimized";
    }

    function getAgentPolicy(address agent) external view returns (AgentPolicy memory) {
        return agentPolicies[agent];
    }

    function getSessionKey(address key) external view returns (SessionKey memory) {
        return sessionKeys[key];
    }

    function getPasskey(address account) external view returns (PasskeySigner memory) {
        return passkeyRegistry[account];
    }
}