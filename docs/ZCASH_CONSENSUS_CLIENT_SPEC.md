# Zcash Consensus Client in Cairo - Complete Specification

**Based on:** librustzcash analysis + our Cairo implementation
**Goal:** Match zcashd/zebrad consensus validation exactly
**Pattern:** Raito architecture (Cairo verification + Rust I/O + STWO proving)

---

## 1. Hash Functions Used by Zcash

### Overview of Zcash Hash Functions

| Hash Function | Used For | Introduced | Verification Status |
|--------------|----------|------------|-------------------|
| **SHA-256d** | Block hashes, TX merkle tree | Bitcoin legacy | ⚠️ **NEEDED** |
| **Blake2b** | Equihash PoW, note commitments | Sapling | ⚠️ **INCOMPLETE** |
| **Pedersen** | Sapling note commitment tree | Sapling | ✅ Exists |
| **Sinsemilla** | Orchard trees | NU5 | ❌ Future |

### 1.1 SHA-256d (Double SHA-256)

**Used For:**
- ✅ **Block hash calculation** (most critical!)
- ✅ **Transaction merkle root**
- ✅ Transaction IDs
- ✅ Signature hashing (sighash)

**Formula:**
```
SHA-256d(x) = SHA-256(SHA-256(x))
```

**Evidence from librustzcash:**
```rust
// From zcash_primitives/src/block.rs:109
header.hash.0.copy_from_slice(&Sha256::digest(Sha256::digest(&raw)));
```

**Block Hash Calculation:**
```
1. Serialize block header (version, prev_block, merkle_root,
   final_sapling_root, time, bits, nonce, solution)
2. Hash = SHA-256(SHA-256(serialized_header))
3. Compare hash with difficulty target
```

**Cairo Implementation Priority:** 🔴 **CRITICAL - HIGHEST PRIORITY**

### 1.2 Blake2b-512

**Used For:**
- ✅ **Equihash proof-of-work** (n=200, k=9)
- ✅ **Sapling note commitments** (commitment scheme)
- ✅ **Nullifier derivation**
- ✅ Key derivation functions

**Personalization:**
- Equihash: `"ZcashPoW" || n || k` (16 bytes)
- Note commitments: Different personalization strings

**Evidence from librustzcash:**
```rust
// From components/equihash/src/verify.rs:119
let mut personalization: Vec<u8> = Vec::from("ZcashPoW");
personalization.write_all(&n.to_le_bytes()).unwrap();
personalization.write_all(&k.to_le_bytes()).unwrap();

Blake2bParams::new()
    .hash_length(digest_len as usize)
    .personal(&personalization)
    .to_state()
```

**Blake2b Variants:**
- Blake2b-512 (64 bytes output) - General purpose
- Blake2b-256 (32 bytes output) - Some commitments

**Current Status:** Marked `///TODO INCOMPLETE` at [blake2b.cairo:3](zcash_light_client/src/crypto/blake2b.cairo#L3)

**What's Missing:**
- Full compression function with G rounds
- All 12 rounds properly implemented
- IV constants (correct)
- Sigma permutations
- Message block mixing

**Cairo Implementation Priority:** 🔴 **CRITICAL - SECOND PRIORITY**

### 1.3 Pedersen Hash

**Used For:**
- ✅ **Sapling note commitment tree** (incremental merkle tree)
- ✅ **Note commitments** (combined with Blake2b)
- ✅ **Nullifier computation**

**Properties:**
- Based on elliptic curve operations (Jubjub curve)
- Homomorphic - allows efficient zero-knowledge proofs
- Collision-resistant

**Current Status:** Exists at [pedersen.cairo](zcash_light_client/src/crypto/pedersen.cairo)

**Action Needed:** Verify against test vectors

**Cairo Implementation Priority:** 🟡 **MEDIUM - TEST & VERIFY**

### 1.4 Sinsemilla Hash (Future)

**Used For:**
- Orchard note commitment trees (post-NU5)

**Priority:** 🟢 **LOW - Future feature**

---

## 2. Zcash Block Structure

### 2.1 Block Header (Consensus-Critical Fields)

**Reference:** [zcash_primitives/src/block.rs::BlockHeaderData](https://github.com/zcash/librustzcash/blob/main/zcash_primitives/src/block.rs)

```cairo
#[derive(Drop, Serde, Debug)]
pub struct BlockHeader {
    /// Protocol version (i32)
    /// - v1-3: Sprout
    /// - v4: Sapling
    /// - v5: NU5 (Orchard)
    pub version: i32,

    /// Previous block hash (32 bytes)
    /// SHA-256d hash of previous header
    pub prev_block: Array<u8>,  // 32 bytes

    /// Transaction merkle root (32 bytes)
    /// SHA-256d merkle tree of transaction hashes
    pub merkle_root: Array<u8>,  // 32 bytes

    /// Sapling commitment tree root (32 bytes)
    /// Pedersen hash merkle tree root
    pub final_sapling_root: Array<u8>,  // 32 bytes

    /// Block timestamp (Unix seconds)
    pub time: u32,

    /// Difficulty target (compact format)
    pub bits: u32,

    /// Equihash nonce (32 bytes)
    pub nonce: Array<u8>,  // 32 bytes

    /// Equihash solution (1344 bytes)
    /// For n=200, k=9: 512 indices
    pub solution: Array<u8>,  // 1344 bytes

    /// Block hash (computed via SHA-256d)
    pub hash: Array<u8>,  // 32 bytes
}
```

**Cairo Implementation:** ✅ **COMPLETE** at [block_header.cairo](zcash_light_client/src/types/block_header.cairo)

### 2.2 Serialization Format

**Order (for hashing):**
1. version (4 bytes, little-endian i32)
2. prev_block (32 bytes)
3. merkle_root (32 bytes)
4. final_sapling_root (32 bytes)
5. time (4 bytes, little-endian u32)
6. bits (4 bytes, little-endian u32)
7. nonce (32 bytes)
8. solution (variable length, prefixed with compact size)

**Total:** ~140 bytes + solution length encoding

---

## 3. Consensus Validation Rules

### 3.1 Block Header Validation

#### Step 1: Structural Validation ✅
```cairo
fn validate_structure(header: @BlockHeader) -> Result<(), ZcashError> {
    // Check field sizes
    assert(header.prev_block.len() == 32);
    assert(header.merkle_root.len() == 32);
    assert(header.final_sapling_root.len() == 32);
    assert(header.nonce.len() == 32);
    assert(header.solution.len() == 1344); // For n=200, k=9
    assert(header.hash.len() == 32);
}
```

**Status:** ✅ Implemented in [block_header.cairo](zcash_light_client/src/types/block_header.cairo)

#### Step 2: Previous Block Linkage ✅
```cairo
fn validate_chain_linkage(
    curr: @BlockHeader,
    prev: @BlockHeader
) -> Result<(), ZcashError> {
    // Check prev_block matches previous hash
    assert(curr.prev_block == prev.hash);

    // Check timestamp is after previous
    assert(curr.time > prev.time);
}
```

**Status:** ✅ Implemented in `validates_against_prev()`

#### Step 3: Proof-of-Work Validation ⚠️

**3a. Equihash Verification** (CRITICAL!)
```cairo
fn verify_equihash(header: @BlockHeader) -> Result<(), ZcashError> {
    // 1. Parse solution: 1344 bytes → 512 indices
    let indices = parse_equihash_solution(header.solution);

    // 2. Initialize Blake2b with personalization
    let mut state = Blake2b::new_with_personal(
        "ZcashPoW",
        EQUIHASH_N,  // 200
        EQUIHASH_K   // 9
    );
    state.update(header_without_solution);
    state.update(header.nonce);

    // 3. Build binary tree (9 levels, 512 leaves)
    let root = build_equihash_tree(state, indices);

    // 4. Validate:
    //    - No duplicate indices
    //    - Proper collisions at each level
    //    - Root hash is zero
    assert(root.is_zero());
}
```

**Status:** ✅ Structure complete at [equihash.cairo](zcash_light_client/src/verification/equihash.cairo)
**Blocker:** ⚠️ Needs complete Blake2b implementation

**3b. Difficulty Target Validation**
```cairo
fn validate_difficulty(header: @BlockHeader) -> Result<(), ZcashError> {
    // 1. Expand compact bits to 256-bit target
    let target = expand_compact_bits(header.bits);

    // 2. Compute block hash via SHA-256d
    let block_hash = sha256d(serialize(header));

    // 3. Check: block_hash < target
    assert(compare_256bit(block_hash, target) == Less);
}
```

**Status:** ✅ Structure complete at [difficulty.cairo](zcash_light_client/src/verification/difficulty.cairo)
**Blocker:** ⚠️ Needs SHA-256d implementation

#### Step 4: Merkle Root Validation ⚠️

**4a. Transaction Merkle Root**
```cairo
fn validate_tx_merkle_root(
    header: @BlockHeader,
    transactions: Span<Transaction>
) -> Result<(), ZcashError> {
    // 1. Compute transaction hashes (SHA-256d)
    let mut tx_hashes = ArrayTrait::new();
    for tx in transactions {
        let tx_hash = sha256d(serialize(tx));
        tx_hashes.append(tx_hash);
    }

    // 2. Build merkle tree (Bitcoin-style)
    let computed_root = compute_merkle_root(tx_hashes.span());

    // 3. Compare with header
    assert(computed_root == header.merkle_root);
}
```

**Status:** ✅ Structure complete at [merkle.cairo](zcash_light_client/src/verification/merkle.cairo)
**Blocker:** ⚠️ Needs SHA-256d implementation

**4b. Sapling Commitment Tree Root**
```cairo
fn validate_sapling_root(
    header: @BlockHeader,
    prev_root: @Array<u8>,
    prev_size: u64,
    new_commitments: Span<felt252>
) -> Result<(), ZcashError> {
    // 1. Initialize tree from previous state
    let mut tree = SaplingTree::from_root(prev_root, prev_size);

    // 2. Append new note commitments (Pedersen hash)
    for cmu in new_commitments {
        tree.append(cmu);
    }

    // 3. Verify root matches
    assert(tree.root() == header.final_sapling_root);
    assert(tree.size() == expected_size);
}
```

**Status:** ✅ Structure complete at [merkle.cairo](zcash_light_client/src/verification/merkle.cairo)
**Blocker:** 🟡 Needs Pedersen hash verification

### 3.2 Network Upgrade Consensus Rules

Zcash has gone through multiple network upgrades with different consensus rules:

| Upgrade | Activation Height (Mainnet) | Key Changes |
|---------|---------------------------|-------------|
| **Overwinter** | 347,500 | Transaction v3, expiry height |
| **Sapling** | 419,200 | Shielded pool v2, final_sapling_root |
| **Blossom** | 653,600 | 75s block time (was 150s) |
| **Heartwood** | 903,000 | FlyClient support |
| **Canopy** | 1,046,400 | Dev fund |
| **NU5** | 1,687,104 | Orchard pool, tx v5 |

**Consensus Rule Changes:**

```cairo
fn get_block_time_target(height: BlockHeight) -> u32 {
    if height >= BLOSSOM_ACTIVATION {
        75  // Post-Blossom
    } else {
        150  // Pre-Blossom
    }
}

fn get_min_tx_version(height: BlockHeight) -> i32 {
    if height >= NU5_ACTIVATION {
        5
    } else if height >= SAPLING_ACTIVATION {
        4
    } else if height >= OVERWINTER_ACTIVATION {
        3
    } else {
        1
    }
}
```

**Status:** ❌ Not yet implemented
**Priority:** 🟡 **MEDIUM** (after hash functions)

### 3.3 Difficulty Adjustment

Zcash uses a **moving average** difficulty adjustment (different from Bitcoin's 2016-block adjustment):

```cairo
fn calculate_next_difficulty(
    prev_headers: Span<BlockHeader>,
    target_spacing: u32,
    averaging_window: u32  // 17 blocks
) -> u32 {
    // 1. Get time span over averaging window
    let first = prev_headers[0];
    let last = prev_headers[averaging_window - 1];
    let actual_time = last.time - first.time;

    // 2. Calculate expected time
    let expected_time = target_spacing * (averaging_window - 1);

    // 3. Adjust target proportionally (with bounds)
    // new_target = old_target * actual_time / expected_time
    // Bounded by [old_target * 0.68, old_target * 1.16]

    let old_target = expand_compact_bits(last.bits);
    let new_target = adjust_target(old_target, actual_time, expected_time);

    compact_target(new_target)
}
```

**Status:** ✅ Structure complete at [difficulty.cairo](zcash_light_client/src/verification/difficulty.cairo)
**Blocker:** ⚠️ Needs 256-bit arithmetic

---

## 4. Implementation Architecture

### 4.1 Layer Separation (Raito Pattern)

```
┌─────────────────────────────────────────────────┐
│ CAIRO LAYER: Pure Verification Functions        │
│  - All functions are deterministic              │
│  - No I/O, no storage, no external calls        │
│  - Suitable for STARK proof generation          │
├─────────────────────────────────────────────────┤
│ Functions:                                       │
│  ✅ verify_block_header(header, prev)           │
│  ✅ verify_equihash(header)                     │
│  ✅ validate_difficulty(header, prev_headers)   │
│  ✅ validate_merkle_roots(header, block)        │
│  ✅ verify_block_range(blocks, start_height)    │
├─────────────────────────────────────────────────┤
│ Inputs: BlockHeader, CompactBlock, ChainState   │
│ Outputs: BlockVerificationResult, NewChainState │
└─────────────────────────────────────────────────┘
                      ↕
┌─────────────────────────────────────────────────┐
│ RUST LAYER: Orchestration & I/O                 │
│  - Fetch blocks from lightwalletd (gRPC)        │
│  - Serialize/deserialize Protocol Buffers       │
│  - Prepare inputs for Cairo functions           │
│  - Handle file I/O and networking               │
├─────────────────────────────────────────────────┤
│ Components:                                      │
│  zcash_cairo_bridge/src/cairo_runner.rs         │
│  zcash_cairo_bridge/src/client.rs               │
│  zcash_cairo_bridge/src/cairo_ffi.rs            │
└─────────────────────────────────────────────────┘
                      ↕
┌─────────────────────────────────────────────────┐
│ STWO PROVER: Proof Generation                   │
│  - Takes Cairo execution trace                  │
│  - Generates STARK proof of correctness         │
│  - Outputs succinct proof (~100KB)              │
└─────────────────────────────────────────────────┘
```

### 4.2 File Organization

```
darth/
├── zcash_light_client/          # Cairo consensus validation
│   └── src/
│       ├── types/
│       │   ├── block_header.cairo      ✅ COMPLETE
│       │   ├── compact_block.cairo     ✅ Existing
│       │   └── chain_state.cairo       ❌ TODO
│       │
│       ├── verification/
│       │   ├── block_validator.cairo   ✅ Basic (needs update)
│       │   ├── equihash.cairo          ✅ STRUCTURE DONE
│       │   ├── difficulty.cairo        ✅ STRUCTURE DONE
│       │   ├── merkle.cairo            ✅ STRUCTURE DONE
│       │   └── network_upgrades.cairo  ❌ TODO
│       │
│       ├── crypto/
│       │   ├── blake2b.cairo           ⚠️ INCOMPLETE
│       │   ├── sha256.cairo            ❌ MISSING
│       │   └── pedersen.cairo          ✅ Exists
│       │
│       └── lib.cairo                   ✅ Updated exports
│
└── zcash_cairo_bridge/          # Rust orchestration
    └── src/
        ├── cairo_runner.rs             ⚠️ Placeholder
        ├── client.rs                   ✅ Exists
        ├── cairo_ffi.rs                ⚠️ Placeholder
        └── proof.rs                    ⚠️ Placeholder
```

---

## 5. Critical Path Implementation

### Priority 1: Complete Hash Functions 🔴

#### 1.1 Implement SHA-256d
**File:** `zcash_light_client/src/crypto/sha256.cairo`

**Requirements:**
- SHA-256 core algorithm (64 rounds)
- Double-hashing wrapper
- Test with known Zcash block hashes

**Test Vectors:**
```cairo
// Genesis block hash (mainnet)
// Expected: 00040fe8ec8471911baa1db1266ea15dd06b4a8a5c453883c000b031973dce08
let genesis_hash = sha256d(serialize(genesis_header));
```

**Effort:** ~400 LOC, ~8,000 Cairo steps

#### 1.2 Complete Blake2b
**File:** `zcash_light_client/src/crypto/blake2b.cairo`

**Requirements:**
- Full compression function with G rounds
- All 12 rounds
- Proper IV and sigma constants
- Personalization support
- Test with RFC 7693 vectors

**Effort:** ~500 LOC, ~10,000 Cairo steps per hash

### Priority 2: 256-bit Arithmetic 🟡

**File:** `zcash_light_client/src/utils/uint256.cairo`

**Requirements:**
```cairo
struct U256 {
    low: u128,
    high: u128,
}

trait U256Trait {
    fn from_bytes(bytes: @Array<u8>) -> U256;
    fn to_bytes(self: @U256) -> Array<u8>;
    fn lt(self: @U256, other: @U256) -> bool;  // Less than
    fn mul(self: @U256, other: @U256) -> U256;
    fn div(self: @U256, other: @U256) -> U256;
}
```

**Effort:** ~300 LOC

### Priority 3: Integration Testing 🟢

**Test with real Zcash blocks:**
1. Genesis block (height 0)
2. Sapling activation block (height 419,200)
3. Recent mainnet block

---

## 6. Verification Functions API

### 6.1 Main Entry Point

```cairo
/// Verify a single Zcash block
/// Returns proof of valid consensus
pub fn verify_block(
    header: @BlockHeader,
    block: @CompactBlock,
    prev_header: @BlockHeader,
    prev_sapling_state: @SaplingTreeState,
    network_params: @NetworkParams
) -> Result<BlockVerificationResult, ZcashError> {
    // 1. Structural validation
    header.is_well_formed()?;

    // 2. Chain linkage
    header.validates_against_prev(prev_header)?;

    // 3. Proof of work
    verify_block_equihash(header)?;
    validate_block_difficulty(
        header,
        get_prev_headers(),
        network_params
    )?;

    // 4. Merkle roots
    validate_block_merkle_roots(
        header,
        block,
        prev_sapling_state
    )?;

    // 5. Network upgrade rules
    enforce_network_upgrade_rules(
        header,
        block,
        network_params
    )?;

    Result::Ok(BlockVerificationResult {
        valid: true,
        height: block.height,
        new_sapling_state: compute_new_sapling_state(),
        block_hash: header.hash,
    })
}
```

### 6.2 Batch Verification

```cairo
/// Verify a range of blocks (generates recursive proof)
pub fn verify_block_range(
    blocks: Span<CompactBlock>,
    headers: Span<BlockHeader>,
    initial_state: @ChainState,
    network_params: @NetworkParams
) -> Result<ChainVerificationResult, ZcashError> {
    let mut state = initial_state.clone();

    for i in 0..blocks.len() {
        let result = verify_block(
            headers[i],
            blocks[i],
            headers[i-1],
            state.sapling_tree,
            network_params
        )?;

        state.update(result);
    }

    Result::Ok(ChainVerificationResult {
        valid: true,
        start_height: blocks[0].height,
        end_height: blocks[blocks.len()-1].height,
        final_state: state,
    })
}
```

---

## 7. Comparison with Raito (Bitcoin)

| Component | Raito (Bitcoin) | Our Zcash Client | Complexity |
|-----------|----------------|------------------|------------|
| **Block Header** | 80 bytes fixed | ~140 bytes + solution | Similar |
| **PoW Algorithm** | SHA-256d (simple) | **Equihash** (complex!) | 10x harder |
| **Difficulty** | Every 2016 blocks | **Every block** (moving avg) | 2x harder |
| **Merkle Trees** | 1 type (SHA-256d) | **2 types** (SHA-256d + Pedersen) | 2x harder |
| **State Tracking** | UTXO set (Utreexo) | **Note commitment trees** | Similar |
| **Hash Functions** | SHA-256 only | **SHA-256 + Blake2b + Pedersen** | 3x harder |

**Verdict:** Zcash consensus validation is **~5-10x more complex** than Bitcoin due to:
1. Equihash (memory-hard PoW)
2. Multiple hash functions
3. Dual merkle trees
4. Shielded pool state tracking

---

## 8. Success Metrics

### Phase 1: Minimum Viable Consensus Client ✅ (60% Complete)
- [x] Complete BlockHeader structure
- [x] Equihash verification structure
- [x] Difficulty validation structure
- [x] Merkle tree validation structure
- [ ] SHA-256d implementation
- [ ] Blake2b completion
- [ ] 256-bit arithmetic

### Phase 2: Full Consensus Validation
- [ ] Verify real mainnet blocks
- [ ] Match zcashd validation exactly
- [ ] All network upgrade rules
- [ ] Transaction validation
- [ ] Generate STARK proofs

### Phase 3: Production Ready
- [ ] Optimize for Cairo steps
- [ ] Fast-sync with checkpoint proofs
- [ ] Integration with lightwalletd
- [ ] Performance benchmarks

---

## 9. Key Takeaways

### What We Have
✅ **Complete consensus client structure** matching zcashd
✅ **Full BlockHeader** with all 9 fields
✅ **Equihash algorithm** ready (needs Blake2b)
✅ **Difficulty adjustment** ready (needs SHA-256d)
✅ **Dual merkle trees** ready (needs hash functions)

### What We Need
⚠️ **SHA-256d** - CRITICAL for block hashes
⚠️ **Blake2b** - CRITICAL for Equihash
🟡 **256-bit arithmetic** - For difficulty
🟡 **Network upgrade rules** - For full compliance

### Why This Matters
🔒 **Trustless** - Validates everything like a full node
⚡ **Fast-sync** - STARK proofs enable quick bootstrap
🌉 **Bridges** - Prove Zcash state on other chains
🏦 **Proof of reserves** - Exchanges can prove holdings

---

**Status:** 60% complete - Foundation solid, hash functions next!
