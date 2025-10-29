---
title: MultiVault Contract
description: Complete reference for the MultiVault smart contract interface
---

# MultiVault Contract Reference

The MultiVault contract is the core protocol contract that manages all ERC4626-style vaults for atoms and triples. It handles creation, deposits, redemptions, and vault state management.

## Contract Overview

- **Solidity Version**: 0.8.29
- **License**: BUSL-1.1
- **Inheritance**: ERC4626-style vault pattern
- **Standards**: EIP-4626 (Tokenized Vaults)

## Architecture

The MultiVault contract implements a multi-vault system where:
- Each **atom** has one or more vaults (different bonding curves)
- Each **triple** has two vaults (for and against)
- Each vault uses **bonding curves** for dynamic pricing
- Shares are **non-transferable** and tied to accounts

## Core Concepts

### Vaults

```solidity
struct VaultState {
    uint256 totalAssets;    // Total assets held in vault
    uint256 totalShares;    // Total shares issued
    mapping(address => uint256) balanceOf;  // User shares
}
```

Each vault is identified by:
- `termId`: bytes32 hash of the atom or triple
- `curveId`: uint256 bonding curve identifier

### Vault Types

```solidity
enum VaultType {
    ATOM,           // Vault for an atom
    TRIPLE,         // Vault for a triple (pro)
    COUNTER_TRIPLE  // Vault for counter-triple (con)
}
```

### Approval Types

```solidity
enum ApprovalTypes {
    NONE,       // No approval
    DEPOSIT,    // Approved to deposit on behalf
    REDEMPTION, // Approved to redeem on behalf
    BOTH        // Approved for both operations
}
```

## Write Functions

### Creating Atoms

Creates one or more atoms with initial deposits.

```solidity
function createAtoms(
    bytes[] calldata atomDatas,
    uint256[] calldata assets
) external payable returns (bytes32[] memory);
```

**Parameters:**
- `atomDatas`: Array of atom metadata (IPFS CID or raw data)
- `assets`: Array of initial deposit amounts (in wei)

**Returns:**
- Array of `termId` (bytes32) for each created atom

**Events Emitted:**
- `AtomCreated` for each atom
- `Deposited` for initial deposit
- `SharePriceChanged` for vault updates

**Usage with viem:**

```typescript
import { parseEther, toHex } from 'viem';

const ipfsCID = 'QmExample...';
const atomData = toHex(ipfsCID);
const depositAmount = parseEther('1.0');

const { request } = await publicClient.simulateContract({
  address: MULTIVAULT_ADDRESS,
  abi: MULTIVAULT_ABI,
  functionName: 'createAtoms',
  args: [[atomData], [depositAmount]],
  value: depositAmount,
  account: walletClient.account,
});

const hash = await walletClient.writeContract(request);
const receipt = await publicClient.waitForTransactionReceipt({ hash });
```

**Gas Costs:**
- Single atom: ~200,000 - 300,000 gas
- Batch (5 atoms): ~800,000 - 1,200,000 gas

### Creating Triples

Creates one or more triples (relationships between atoms).

```solidity
function createTriples(
    bytes32[] calldata subjectIds,
    bytes32[] calldata predicateIds,
    bytes32[] calldata objectIds,
    uint256[] calldata assets
) external payable returns (bytes32[] memory);
```

**Parameters:**
- `subjectIds`: Array of subject atom IDs
- `predicateIds`: Array of predicate atom IDs
- `objectIds`: Array of object atom IDs
- `assets`: Array of initial deposit amounts

**Returns:**
- Array of `termId` for each created triple

**Requirements:**
- All referenced atoms (subject, predicate, object) must exist
- Assets must be provided for each triple
- Arrays must have equal lengths

**Events Emitted:**
- `TripleCreated` for each triple
- `Deposited` for triple vault
- `Deposited` for underlying atom vaults (fractional deposits)
- `SharePriceChanged` events

**Usage with viem:**

```typescript
const subjectId = '0xabc...';
const predicateId = '0xdef...';
const objectId = '0x123...';
const depositAmount = parseEther('1.0');

const hash = await walletClient.writeContract({
  address: MULTIVAULT_ADDRESS,
  abi: MULTIVAULT_ABI,
  functionName: 'createTriples',
  args: [[subjectId], [predicateId], [objectId], [depositAmount]],
  value: depositAmount,
});
```

**Important:** When depositing into a triple vault, a fraction of the assets (configured in `atomDepositFraction`) is deposited into the underlying atom vaults (subject, predicate, object).

### Depositing into Vaults

Deposits assets into an existing vault and mints shares.

```solidity
function deposit(
    address receiver,
    bytes32 termId,
    uint256 curveId,
    uint256 minShares
) external payable returns (uint256);
```

**Parameters:**
- `receiver`: Address to receive the minted shares
- `termId`: ID of the atom or triple vault
- `curveId`: Bonding curve ID (typically 0)
- `minShares`: Minimum shares to mint (slippage protection)

**Returns:**
- Number of shares minted

**Requirements:**
- `msg.value` must be greater than 0
- Vault must exist (term must be created)
- Minted shares must be >= `minShares`

**Events Emitted:**
- `Deposited`
- `SharePriceChanged`
- `ProtocolFeeAccrued`
- `AtomWalletDepositFeeCollected` (if atom vault)

**Fee Structure:**

```
msg.value (100%)
├─ Protocol Fee (e.g., 2%)
├─ Entry Fee (e.g., 1%)
├─ Atom Wallet Fee (e.g., 0.3%, atom vaults only)
└─ Net to Vault → Shares Minted
```

**Usage with viem:**

```typescript
const depositAmount = parseEther('5.0');
const minShares = 0n; // Set based on previewDeposit for production

const hash = await walletClient.writeContract({
  address: MULTIVAULT_ADDRESS,
  abi: MULTIVAULT_ABI,
  functionName: 'deposit',
  args: [walletClient.account.address, termId, 0n, minShares],
  value: depositAmount,
});
```

### Batch Deposits

Deposits into multiple vaults in a single transaction.

```solidity
function depositBatch(
    address receiver,
    bytes32[] calldata termIds,
    uint256[] calldata curveIds,
    uint256[] calldata assets,
    uint256[] calldata minShares
) external payable returns (uint256[] memory);
```

**Parameters:**
- `receiver`: Address to receive shares
- `termIds`: Array of vault term IDs
- `curveIds`: Array of curve IDs
- `assets`: Array of deposit amounts
- `minShares`: Array of minimum shares for each deposit

**Returns:**
- Array of shares minted for each deposit

**Requirements:**
- All arrays must have equal length
- `msg.value` must equal sum of `assets` array

**Gas Optimization:**
Batch deposits save gas compared to individual deposits:
- 5 individual deposits: ~1,000,000 gas
- 1 batch deposit (5 vaults): ~700,000 gas

### Redeeming from Vaults

Redeems shares from a vault and returns assets.

```solidity
function redeem(
    address receiver,
    bytes32 termId,
    uint256 curveId,
    uint256 shares,
    uint256 minAssets
) external returns (uint256);
```

**Parameters:**
- `receiver`: Address to receive the assets
- `termId`: ID of the vault
- `curveId`: Bonding curve ID
- `shares`: Number of shares to redeem
- `minAssets`: Minimum assets to receive (slippage protection)

**Returns:**
- Number of assets returned (after fees)

**Requirements:**
- Sender must have >= `shares` in the vault
- Assets returned must be >= `minAssets`

**Events Emitted:**
- `Redeemed`
- `SharePriceChanged`
- `ProtocolFeeAccrued`

**Fee Structure:**

```
Shares Redeemed → Assets Value (100%)
├─ Protocol Fee (e.g., 2%)
├─ Exit Fee (e.g., 1%)
└─ Net to Receiver
```

**Usage with viem:**

```typescript
// Get user's shares
const shares = await publicClient.readContract({
  address: MULTIVAULT_ADDRESS,
  abi: MULTIVAULT_ABI,
  functionName: 'getShares',
  args: [account.address, termId, 0n],
});

// Redeem all shares
const hash = await walletClient.writeContract({
  address: MULTIVAULT_ADDRESS,
  abi: MULTIVAULT_ABI,
  functionName: 'redeem',
  args: [account.address, termId, 0n, shares, 0n],
});
```

### Batch Redemptions

Redeems from multiple vaults in a single transaction.

```solidity
function redeemBatch(
    address receiver,
    bytes32[] calldata termIds,
    uint256[] calldata curveIds,
    uint256[] calldata shares,
    uint256[] calldata minAssets
) external returns (uint256[] memory);
```

**Parameters:**
- `receiver`: Address to receive assets
- `termIds`: Array of vault term IDs
- `curveIds`: Array of curve IDs
- `shares`: Array of share amounts to redeem
- `minAssets`: Array of minimum assets for each redemption

**Returns:**
- Array of assets returned for each redemption

### Approvals

Grants another address permission to deposit or redeem on your behalf.

```solidity
function approve(
    address sender,
    ApprovalTypes approvalType
) external;
```

**Parameters:**
- `sender`: Address to grant approval to
- `approvalType`: Type of approval (NONE=0, DEPOSIT=1, REDEMPTION=2, BOTH=3)

**Events Emitted:**
- `ApprovalTypeUpdated`

**Usage:**

```typescript
const hash = await walletClient.writeContract({
  address: MULTIVAULT_ADDRESS,
  abi: MULTIVAULT_ABI,
  functionName: 'approve',
  args: [operatorAddress, 3], // BOTH
});
```

### Claiming Atom Wallet Fees

Atom creators can claim accumulated fees from their atom wallets.

```solidity
function claimAtomWalletDepositFees(bytes32 atomId) external;
```

**Parameters:**
- `atomId`: The atom ID to claim fees for

**Requirements:**
- Caller must be the atom creator (wallet owner)

**Events Emitted:**
- `AtomWalletDepositFeesClaimed`

## Read Functions (Views)

### Get Vault State

```solidity
function getVault(bytes32 termId, uint256 curveId)
    external view
    returns (uint256 totalAssets, uint256 totalShares);
```

Returns the total assets and shares for a vault.

### Get User Shares

```solidity
function getShares(address account, bytes32 termId, uint256 curveId)
    external view
    returns (uint256);
```

Returns the number of shares held by an account in a specific vault.

### Convert Between Assets and Shares

```solidity
function convertToShares(bytes32 termId, uint256 curveId, uint256 assets)
    external view
    returns (uint256 shares);

function convertToAssets(bytes32 termId, uint256 curveId, uint256 shares)
    external view
    returns (uint256 assets);
```

Converts between assets and shares using current vault state.

### Preview Operations

Simulates operations without executing them.

```solidity
function previewAtomCreate(bytes32 termId, uint256 assets)
    external view
    returns (
        uint256 shares,
        uint256 assetsAfterFixedFees,
        uint256 assetsAfterFees
    );

function previewTripleCreate(bytes32 termId, uint256 assets)
    external view
    returns (
        uint256 shares,
        uint256 assetsAfterFixedFees,
        uint256 assetsAfterFees
    );

function previewDeposit(bytes32 termId, uint256 curveId, uint256 assets)
    external view
    returns (uint256 shares, uint256 assetsAfterFees);

function previewRedeem(bytes32 termId, uint256 curveId, uint256 shares)
    external view
    returns (uint256 assetsAfterFees, uint256 sharesUsed);
```

**Usage:**

```typescript
// Preview deposit before executing
const [shares, assetsAfterFees] = await publicClient.readContract({
  address: MULTIVAULT_ADDRESS,
  abi: MULTIVAULT_ABI,
  functionName: 'previewDeposit',
  args: [termId, 0n, parseEther('1.0')],
});

console.log('Expected shares:', shares);
console.log('Net assets to vault:', assetsAfterFees);

// Use shares as minShares for actual deposit
const hash = await walletClient.writeContract({
  address: MULTIVAULT_ADDRESS,
  abi: MULTIVAULT_ABI,
  functionName: 'deposit',
  args: [account.address, termId, 0n, shares * 95n / 100n], // 5% slippage
  value: parseEther('1.0'),
});
```

### Fee Calculations

```solidity
function protocolFeeAmount(uint256 assets)
    external view
    returns (uint256 feeAmount);

function entryFeeAmount(uint256 assets)
    external view
    returns (uint256 feeAmount);

function exitFeeAmount(uint256 assets)
    external view
    returns (uint256 feeAmount);

function atomDepositFractionAmount(uint256 assets)
    external view
    returns (uint256);
```

### Current Share Price

```solidity
function currentSharePrice(bytes32 termId, uint256 curveId)
    external view
    returns (uint256 price);
```

Returns the current share price for a vault (totalAssets / totalShares * 1e18).

### Max Redemption

```solidity
function maxRedeem(address sender, bytes32 termId, uint256 curveId)
    external view
    returns (uint256);
```

Returns the maximum shares a user can redeem.

### Compute Atom Wallet Address

```solidity
function computeAtomWalletAddr(bytes32 atomId)
    external view
    returns (address);
```

Computes the deterministic address for an atom wallet.

### Check if Term Exists

```solidity
function isTermCreated(bytes32 id)
    external view
    returns (bool);
```

Checks if an atom or triple has been created.

### Epoch Functions

```solidity
function currentEpoch() external view returns (uint256);

function getTotalUtilizationForEpoch(uint256 epoch)
    external view
    returns (int256);

function getUserUtilizationForEpoch(address user, uint256 epoch)
    external view
    returns (int256);

function getUserLastActiveEpoch(address user)
    external view
    returns (uint256);
```

Epoch-based utilization tracking for incentive mechanisms.

## Events

### AtomCreated

Emitted when an atom vault is created.

```solidity
event AtomCreated(
    address indexed creator,
    bytes32 indexed termId,
    bytes atomData,
    address atomWallet
);
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `creator` | `address indexed` | The address of the creator |
| `termId` | `bytes32 indexed` | The ID of the atom vault |
| `atomData` | `bytes` | The data associated with the atom |
| `atomWallet` | `address` | The address of the atom wallet associated with the atom vault |

### TripleCreated

Emitted when a triple vault is created.

```solidity
event TripleCreated(
    address indexed creator,
    bytes32 indexed termId,
    bytes32 subjectId,
    bytes32 predicateId,
    bytes32 objectId
);
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `creator` | `address indexed` | The address of the creator |
| `termId` | `bytes32 indexed` | The ID of the triple vault |
| `subjectId` | `bytes32` | The ID of the subject atom |
| `predicateId` | `bytes32` | The ID of the predicate atom |
| `objectId` | `bytes32` | The ID of the object atom |

### Deposited

Emitted when assets are deposited into a vault.

```solidity
event Deposited(
    address indexed sender,
    address indexed receiver,
    bytes32 indexed termId,
    uint256 curveId,
    uint256 assets,
    uint256 assetsAfterFees,
    uint256 shares,
    uint256 totalShares,
    VaultType vaultType
);
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `sender` | `address indexed` | The address of the sender |
| `receiver` | `address indexed` | The address of the receiver |
| `termId` | `bytes32 indexed` | The ID of the term (atom or triple) |
| `curveId` | `uint256` | The ID of the bonding curve |
| `assets` | `uint256` | The amount of assets deposited (gross assets deposited by the sender, including atomCost or tripleCost where applicable) |
| `assetsAfterFees` | `uint256` | The amount of assets after all deposit fees are deducted |
| `shares` | `uint256` | The amount of shares minted to the receiver |
| `totalShares` | `uint256` | The user's share balance in the vault after the deposit |
| `vaultType` | `VaultType` | The type of vault (ATOM, TRIPLE, or COUNTER_TRIPLE) |

### Redeemed

Emitted when shares are redeemed from a vault.

```solidity
event Redeemed(
    address indexed sender,
    address indexed receiver,
    bytes32 indexed termId,
    uint256 curveId,
    uint256 shares,
    uint256 totalShares,
    uint256 assets,
    uint256 fees,
    VaultType vaultType
);
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `sender` | `address indexed` | The address of the sender |
| `receiver` | `address indexed` | The address of the receiver |
| `termId` | `bytes32 indexed` | The ID of the term (atom or triple) |
| `curveId` | `uint256` | The ID of the bonding curve |
| `shares` | `uint256` | The amount of shares redeemed |
| `totalShares` | `uint256` | The user's share balance in the vault after the redemption |
| `assets` | `uint256` | The amount of assets withdrawn (net assets received by the receiver) |
| `fees` | `uint256` | The amount of fees charged |
| `vaultType` | `VaultType` | The type of vault (ATOM, TRIPLE, or COUNTER_TRIPLE) |

### SharePriceChanged

Emitted when the share price changes.

```solidity
event SharePriceChanged(
    bytes32 indexed termId,
    uint256 indexed curveId,
    uint256 sharePrice,
    uint256 totalAssets,
    uint256 totalShares,
    VaultType vaultType
);
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `termId` | `bytes32 indexed` | The ID of the term (atom or triple) |
| `curveId` | `uint256 indexed` | The ID of the bonding curve |
| `sharePrice` | `uint256` | The new share price |
| `totalAssets` | `uint256` | The total assets in the vault after the change |
| `totalShares` | `uint256` | The total shares in the vault after the change |
| `vaultType` | `VaultType` | The type of vault (ATOM, TRIPLE, or COUNTER_TRIPLE) |

### ApprovalTypeUpdated

Emitted when approval permissions are updated for an address.

```solidity
event ApprovalTypeUpdated(
    address indexed sender,
    address indexed receiver,
    ApprovalTypes approvalType
);
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `sender` | `address indexed` | The address granting the approval |
| `receiver` | `address indexed` | The address receiving the approval |
| `approvalType` | `ApprovalTypes` | The type of approval granted (NONE, DEPOSIT, REDEMPTION, or BOTH) |

### AtomWalletDepositFeeCollected

Emitted when an atom wallet deposit fee is collected.

The atom wallet deposit fee is charged when depositing assets into atom vaults and accumulates as claimable fees for the atom wallet owner of the corresponding atom vault.

```solidity
event AtomWalletDepositFeeCollected(
    bytes32 indexed termId,
    address indexed sender,
    uint256 amount
);
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `termId` | `bytes32 indexed` | The ID of the term (atom) |
| `sender` | `address indexed` | The address of the sender |
| `amount` | `uint256` | The amount of atom wallet deposit fee collected |

### AtomWalletDepositFeesClaimed

Emitted when atom wallet deposit fees are claimed.

```solidity
event AtomWalletDepositFeesClaimed(
    bytes32 indexed termId,
    address indexed atomWalletOwner,
    uint256 indexed feesClaimed
);
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `termId` | `bytes32 indexed` | The ID of the atom |
| `atomWalletOwner` | `address indexed` | The address of the atom wallet owner |
| `feesClaimed` | `uint256 indexed` | The amount of fees claimed from the atom wallet |

### ProtocolFeeAccrued

Emitted when a protocol fee is accrued internally.

```solidity
event ProtocolFeeAccrued(
    uint256 indexed epoch,
    address indexed sender,
    uint256 amount
);
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `epoch` | `uint256 indexed` | The epoch in which the protocol fee was accrued (current epoch) |
| `sender` | `address indexed` | The address of the user who paid the protocol fee |
| `amount` | `uint256` | The amount of protocol fee accrued |

### ProtocolFeeTransferred

Emitted when a protocol fee is transferred to the protocol multisig or the TrustBonding contract.

The protocol fee is charged when depositing assets and redeeming shares from the vault, except when the contract is paused.

```solidity
event ProtocolFeeTransferred(
    uint256 indexed epoch,
    address indexed destination,
    uint256 amount
);
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `epoch` | `uint256 indexed` | The epoch for which the protocol fee was transferred (previous epoch) |
| `destination` | `address indexed` | The address of the destination (protocol multisig or TrustBonding contract) |
| `amount` | `uint256` | The amount of protocol fee transferred |

### TotalUtilizationAdded

Emitted when total utilization is added for an epoch.

```solidity
event TotalUtilizationAdded(
    uint256 indexed epoch,
    int256 indexed valueAdded,
    int256 indexed totalUtilization
);
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `epoch` | `uint256 indexed` | The epoch in which the total utilization was added |
| `valueAdded` | `int256 indexed` | The value of the utilization added (in TRUST tokens) |
| `totalUtilization` | `int256 indexed` | The total utilization for the epoch after adding the value |

### PersonalUtilizationAdded

Emitted when personal utilization is added for a user.

```solidity
event PersonalUtilizationAdded(
    address indexed user,
    uint256 indexed epoch,
    int256 indexed valueAdded,
    int256 personalUtilization
);
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `user` | `address indexed` | The address of the user |
| `epoch` | `uint256 indexed` | The epoch in which the utilization was added |
| `valueAdded` | `int256 indexed` | The value of the utilization added (in TRUST tokens) |
| `personalUtilization` | `int256` | The personal utilization for the user after adding the value |

### TotalUtilizationRemoved

Emitted when total utilization is removed for an epoch.

```solidity
event TotalUtilizationRemoved(
    uint256 indexed epoch,
    int256 indexed valueRemoved,
    int256 indexed totalUtilization
);
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `epoch` | `uint256 indexed` | The epoch in which the total utilization was removed |
| `valueRemoved` | `int256 indexed` | The value of the utilization removed (in TRUST tokens) |
| `totalUtilization` | `int256 indexed` | The total utilization for the epoch after removing the value |

### PersonalUtilizationRemoved

Emitted when personal utilization is removed for a user.

```solidity
event PersonalUtilizationRemoved(
    address indexed user,
    uint256 indexed epoch,
    int256 indexed valueRemoved,
    int256 personalUtilization
);
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `user` | `address indexed` | The address of the user |
| `epoch` | `uint256 indexed` | The epoch in which the utilization was removed |
| `valueRemoved` | `int256 indexed` | The value of the utilization removed (in TRUST tokens) |
| `personalUtilization` | `int256` | The personal utilization for the user after removing the value |

## Security Considerations

### Reentrancy Protection
All state-changing functions are protected against reentrancy attacks.

### Slippage Protection
Always use `minShares` and `minAssets` parameters:

```typescript
// Good: Protected against frontrunning
const [expectedShares] = await previewDeposit(termId, 0n, amount);
const minShares = expectedShares * 95n / 100n; // 5% slippage tolerance

await deposit(receiver, termId, 0n, minShares);

// Bad: No protection
await deposit(receiver, termId, 0n, 0n);
```

### Fee Validation
Preview operations to understand fee impact:

```typescript
const assets = parseEther('100.0');
const [shares, assetsAfterFees] = await previewDeposit(termId, 0n, assets);
const fees = assets - assetsAfterFees;
console.log(`Fees: ${formatEther(fees)} TRUST (${fees * 100n / assets}%)`);
```

### Term Existence
Always verify terms exist before operating on them:

```typescript
const exists = await isTermCreated(termId);
if (!exists) {
  throw new Error('Term does not exist');
}
```

## Gas Optimization Tips

1. **Batch Operations**: Use `createAtoms`, `depositBatch`, `redeemBatch`
2. **Avoid Unnecessary Reads**: Cache vault state when possible
3. **Optimal Approval**: Set approvals once, use many times
4. **Event Parsing**: Parse events instead of reading state after writes

## Common Patterns

### Create and Deposit Pattern

```typescript
// Create atom with initial deposit
const atomIds = await createAtoms([atomData], [parseEther('1.0')]);

// Additional deposit
await deposit(receiver, atomIds[0], 0n, minShares);
```

### Query Position Value

```typescript
const shares = await getShares(account, termId, 0n);
const [totalAssets, totalShares] = await getVault(termId, 0n);
const positionValue = (shares * totalAssets) / totalShares;
```

### Stake on Triple and Counter

```typescript
// Stake on triple (pro)
await deposit(account, tripleId, 0n, minShares);

// Stake on counter-triple (con)
await deposit(account, counterTripleId, 0n, minShares);
```

## Next Steps

- [Core Concepts](/core-concepts) - Understand Atoms, Triples, and Vaults
- [Quick Start](/quick-start) - Build your first integration
- [GraphQL API](/api/graphql-schema) - Query protocol data
- [Event Processing](/indexer/event-processing) - Learn about the indexer
