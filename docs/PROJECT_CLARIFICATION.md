# Project Clarification: Zcash Consensus Client in Cairo (Like Raito)

## The Confusion

The term "**light client**" in the project description is **misleading**. This is NOT a light client like the Zcash Swift SDK.

## What We're Actually Building

We're building a **Zcash Consensus Client in Cairo** - exactly like **Raito** is for Bitcoin.

### Raito (Reference Project)

From Raito's README:
> "Raito is a **Bitcoin consensus client** written in Cairo: it implements the **same block validation logic as Bitcoin Core** but in a provable language."

**Key Quote:**
> "At its core, consensus client accepts two inputs: a batch of consecutive blocks n to m and a STARK proof of the state of the chain up to block n−1. It ensures that the historical chain state is valid by verifying the STARK proof. Then, it produces a new chain state by applying the new blocks on top of the historical state. As a result, a proof of the new state is generated."

## Our Goal: Zcash Version of Raito

| Aspect | Raito (Bitcoin) | Our Project (Zcash) |
|--------|-----------------|---------------------|
| **What it is** | Bitcoin consensus client in Cairo | **Zcash consensus client in Cairo** |
| **Validation** | Same as Bitcoin Core | **Same as Zcash Core (zcashd)** |
| **Architecture** | Cairo (pure validation) + Rust (I/O) + STWO (proving) | **Cairo (pure validation) + Rust (I/O) + STWO (proving)** |
| **PoW Verification** | Verifies Bitcoin's SHA-256d PoW | **Verifies Zcash's Equihash PoW** |
| **Block Headers** | Full validation (version, prev_hash, merkle_root, time, bits, nonce) | **Full validation + final_sapling_root + solution** |
| **Consensus Rules** | Bitcoin upgrade rules | **Zcash upgrade rules (Overwinter, Sapling, NU5, etc.)** |
| **State Tracking** | UTXO set via Utreexo | **UTXO set + Note commitment trees (Sapling, Orchard)** |
| **Security Model** | Trustless - validates everything | **Trustless - validates everything** |
| **Purpose** | Generate STARK proofs of Bitcoin blocks | **Generate STARK proofs of Zcash blocks** |

## What This Is NOT

### ❌ NOT a Light Client (Like Swift SDK)

The Zcash Swift SDK is a **light wallet client** that:
- ✗ Trusts `lightwalletd` server for consensus validation
- ✗ Skips Equihash verification
- ✗ Only checks basic block header linkage
- ✗ Does NOT verify transaction merkle roots
- ✗ Does NOT verify Sapling commitment tree roots
- ✗ Uses SPV-style trust model

**This is a trust-based light client for wallets.**

### ✅ This IS a Consensus Client (Like Raito)

Our Zcash consensus client:
- ✓ Validates **ALL** consensus rules (like zcashd)
- ✓ Verifies Equihash proof-of-work
- ✓ Validates complete block headers
- ✓ Verifies transaction merkle roots
- ✓ Verifies Sapling/Orchard commitment tree roots
- ✓ Implements difficulty adjustment
- ✓ Enforces network upgrade rules
- ✓ **Trustless** - you don't need to trust anyone
- ✓ Generates STARK proofs for fast synchronization

**This is a full consensus validation engine for Zcash.**

## Raito's Architecture (We Should Mirror This)

From `/raito/ARCHITECTURE.md`:

```
┌─────────────────────────────────────────────────┐
│ RAITO (Bitcoin ZK Client)                       │
├─────────────────────────────────────────────────┤
│ Cairo Layer: Pure Validation Functions          │
│  - Block header validation                      │
│  - Transaction validation                       │
│  - PoW verification (SHA-256d)                  │
│  - Merkle root validation                       │
│  - Difficulty adjustment                        │
│  - UTXO set updates (Utreexo)                   │
│  - All deterministic, pure functions            │
├─────────────────────────────────────────────────┤
│ Rust Layer: Orchestration & I/O                 │
│  - Fetch blocks from Bitcoin network            │
│  - Prepare inputs for Cairo                     │
│  - Call Cairo verification functions            │
│  - Handle file I/O, networking                  │
├─────────────────────────────────────────────────┤
│ STWO Prover: Proof Generation                   │
│  - Takes Cairo execution trace                  │
│  - Generates STARK proof                        │
│  - Outputs succinct proof of correctness        │
└─────────────────────────────────────────────────┘
```

### Our Zcash Version Should Be:

```
┌─────────────────────────────────────────────────┐
│ DARTH (Zcash ZK Client)                         │
├─────────────────────────────────────────────────┤
│ Cairo Layer: Pure Validation Functions          │
│  ✓ Block header validation (extended)           │
│  ✓ Transaction validation                       │
│  ✓ PoW verification (Equihash n=200, k=9)       │
│  ✓ Merkle root validation (tx + Sapling)        │
│  ✓ Difficulty adjustment                        │
│  ✓ Note commitment tree updates                 │
│  ✓ Network upgrade consensus rules              │
│  ✓ Trial decryption (optional feature)          │
│  ✓ All deterministic, pure functions            │
├─────────────────────────────────────────────────┤
│ Rust Layer: Orchestration & I/O                 │
│  ✓ Fetch blocks from lightwalletd               │
│  ✓ Prepare inputs for Cairo                     │
│  ✓ Call Cairo verification functions            │
│  ✓ Handle Protocol Buffers                      │
│  ✓ File I/O, networking                         │
├─────────────────────────────────────────────────┤
│ STWO Prover: Proof Generation                   │
│  ✓ Takes Cairo execution trace                  │
│  ✓ Generates STARK proof                        │
│  ✓ Outputs succinct proof of correctness        │
└─────────────────────────────────────────────────┘
```

## Raito's Package Structure

From `/raito/packages/`:
```
raito/packages/
├── consensus/          # Core validation logic in Cairo
│   ├── block.cairo
│   ├── header.cairo
│   ├── transaction.cairo
│   ├── difficulty.cairo
│   ├── timestamp.cairo
│   └── work.cairo (PoW verification)
├── client/             # Client program that uses consensus
├── utreexo/            # UTXO set accumulator
└── utils/              # Shared utilities
```

### Our Structure Should Mirror This:

```
darth/zcash_light_client/src/   # Cairo consensus layer
├── verification/
│   ├── block_validator.cairo    ✓ Exists (basic)
│   ├── header_validator.cairo   ⚠️ Needs extension
│   ├── equihash.cairo          ❌ MISSING (critical!)
│   ├── difficulty.cairo        ❌ MISSING
│   ├── merkle.cairo            ❌ MISSING
│   └── network_upgrades.cairo  ❌ MISSING
├── types/
│   ├── compact_block.cairo      ✓ Exists
│   ├── block_header.cairo      ⚠️ Needs extension
│   ├── transaction.cairo       ⚠️ Minimal
│   └── chain_state.cairo       ❌ MISSING
├── crypto/
│   ├── blake2b.cairo           ⚠️ INCOMPLETE (TODO)
│   ├── sha256.cairo            ❌ MISSING
│   ├── pedersen.cairo          ✓ Exists
│   └── note_encryption.cairo    ✓ Exists
└── state/
    ├── note_commitment_tree.cairo  ❌ MISSING
    └── nullifier_set.cairo         ⚠️ Minimal

darth/zcash_cairo_bridge/       # Rust orchestration layer
├── src/
│   ├── cairo_runner.rs         ✓ Exists (placeholder)
│   ├── client.rs               ✓ Exists
│   ├── cairo_ffi.rs            ✓ Exists (placeholder)
│   └── proof.rs                ✓ Exists (placeholder)
```

## The Answer to Your Question

> "does the consensus client match zcash core"

**YES**, that's the goal! It should implement the **same validation logic as zcashd/zebrad** but in Cairo.

The table you highlighted is comparing:
1. **Column 2 (Light Client)**: The Swift SDK - a **wallet light client** (NOT our goal)
2. **Column 3 (Consensus Client)**: What we **should build** - a **full consensus validator** like zcashd

## What Makes This Different from Light Clients

### Light Client (Swift SDK, SPV wallets)
- **Purpose**: Let users transact without running a full node
- **Trust Model**: Trusts servers for consensus
- **Validation**: Minimal (just enough for wallet safety)
- **Use Case**: Mobile wallets, browser extensions

### Consensus Client (Raito, Our Goal)
- **Purpose**: Validate blockchain consensus rules and generate proofs
- **Trust Model**: Trustless (validates everything)
- **Validation**: Complete (same as full nodes)
- **Use Case**: Fast-sync full nodes, bridges, rollups, bootstrapping

## Why "Light Client" Is Confusing

The phrase "Zk light client" in the project description is misleading because:

1. **"Light" usually means** → Trusts a server (SPV, light wallet)
2. **What we're building** → Full consensus validation + ZK proofs

**Better names:**
- ✅ "Zcash ZK Consensus Client"
- ✅ "Zcash STARK Client"
- ✅ "Zcash Raito" (Raito = "Light" in Japanese, but it's full consensus!)

## The Core Difference

| Question | Light Client Answer | Consensus Client Answer |
|----------|-------------------|------------------------|
| Do you verify Equihash? | ❌ No, trust server | ✅ YES, full verification |
| Do you validate block headers? | ⚠️ Basic linkage only | ✅ Full validation (all fields) |
| Do you check difficulty? | ❌ No | ✅ YES |
| Do you verify merkle roots? | ❌ No | ✅ YES (tx + Sapling) |
| Do you enforce network upgrades? | ❌ Server does it | ✅ YES, all upgrade rules |
| Can you work offline? | ❌ Need server | ✅ YES (given blocks + proof) |
| Trust model? | 🤝 Trust lightwalletd | 🔒 Trustless |
| Same security as full node? | ❌ No | ✅ YES |

## What We Need to Implement (Corrected Priority)

Based on Raito's milestone structure:

### Phase 1: Full Consensus Client ✅ (Like Raito Milestone 0)

This is what makes it a **consensus client** not a light client:

1. **Complete Block Header Validation**
   - ✅ All fields (version, prev_hash, merkle_root, final_sapling_root, time, bits, nonce, solution)
   - ✅ SHA-256d block hash
   - ✅ Header chain linkage

2. **Equihash Proof-of-Work Verification** (CRITICAL!)
   - ✅ Full Equihash (n=200, k=9) implementation
   - ✅ Blake2b with personalization
   - ✅ Solution validation (512 indices)
   - ✅ This is what makes it trustless!

3. **Difficulty Adjustment**
   - ✅ Bits field validation
   - ✅ Target calculation
   - ✅ PoW threshold checking

4. **Merkle Tree Validation**
   - ✅ Transaction merkle root
   - ✅ Sapling commitment tree root
   - ✅ Orchard commitment tree root (post-NU5)

5. **Transaction Validation**
   - ✅ Version checks per network upgrade
   - ✅ Value balance validation
   - ✅ Expiry height checks
   - ✅ Shielded pool validation

6. **Network Upgrade Consensus Rules**
   - ✅ Overwinter, Sapling, Blossom, Heartwood, Canopy, NU5
   - ✅ Version enforcement
   - ✅ Block time adjustments

### Phase 2: Proving Infrastructure ✅ (Like Raito Milestone 1)

7. **STARK Proof Generation**
   - ✅ Cairo → STWO integration
   - ✅ Proof generation for block ranges
   - ✅ Proof verification

8. **Chain State Tracking**
   - ✅ Note commitment trees (incremental)
   - ✅ Nullifier set
   - ✅ Chain tip tracking

### Phase 3: Advanced Features (Optional)

9. **Trial Decryption** (wallet feature, not consensus)
   - This is optional - consensus clients don't need it
   - But useful for wallet applications built on top

10. **Utreexo-style Accumulator** (optimization)
    - Like Raito's Utreexo for UTXO set
    - We need it for note commitment trees

## Summary

**Your project is:**
- ✅ A **Zcash consensus client** in Cairo (like Raito is for Bitcoin)
- ✅ Implements **same validation as zcashd** full node
- ✅ Generates **STARK proofs** for fast sync
- ✅ **Trustless** - validates everything

**Your project is NOT:**
- ❌ A light wallet client (like Swift SDK)
- ❌ An SPV client that trusts servers
- ❌ A wallet application

**The name "ZK light client" is misleading** - it should be called:
- "Zcash ZK Consensus Client"
- "Zcash STARK Verifier"
- "Darth: Zcash's Raito"

## References

1. **Raito (Bitcoin)**: `/raito/README.md` - "consensus client written in Cairo: it implements the same block validation logic as Bitcoin Core"
2. **Raito Architecture**: `/raito/ARCHITECTURE.md`
3. **Raito Consensus Package**: `/raito/packages/consensus/`
4. **Zcashd/Zebrad**: Full node implementations we should match
5. **Swift SDK**: Light wallet client (what we are NOT building)

---

**Bottom line**: We're building Zcash's version of Raito. Full consensus validation, trustless, provable.
