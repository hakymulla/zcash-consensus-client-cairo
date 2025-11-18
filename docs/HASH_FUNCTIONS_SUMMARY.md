# Zcash Hash Functions - What We Actually Use

## Quick Reference: Hash Functions in Zcash

| Hash Function | Where Used | Priority | Status |
|--------------|-----------|----------|--------|
| **SHA-256d** | Block hashes, TX merkle tree | 🔴 CRITICAL | ❌ Missing |
| **Blake2b** | Equihash PoW, note commitments | 🔴 CRITICAL | ⚠️ Incomplete |
| **Pedersen** | Sapling commitment tree | 🟡 Medium | ✅ Exists |

---

## 1. SHA-256d (Double SHA-256)

### What It Is
```
SHA-256d(x) = SHA-256(SHA-256(x))
```

### Where Zcash Uses It

#### ✅ Block Hash Calculation (MOST CRITICAL!)
```rust
// From librustzcash/zcash_primitives/src/block.rs:109
header.hash.0.copy_from_slice(&Sha256::digest(Sha256::digest(&raw)));
```

**Our Implementation Needs:**
```cairo
pub fn compute_block_hash(header: @BlockHeader) -> Array<u8> {
    let serialized = serialize_header_without_hash(header);
    sha256d(serialized)  // Returns 32 bytes
}
```

#### ✅ Transaction Merkle Root
```cairo
pub fn compute_tx_merkle_root(tx_hashes: Span<Array<u8>>) -> Array<u8> {
    // Build merkle tree using SHA-256d for internal nodes
    // Same as Bitcoin
}
```

#### ✅ Transaction IDs
```cairo
pub fn compute_txid(tx: @Transaction) -> Array<u8> {
    sha256d(serialize(tx))
}
```

### Why It's Critical
Without SHA-256d, we CANNOT:
- ❌ Compute block hashes
- ❌ Validate difficulty (block_hash < target)
- ❌ Verify transaction merkle roots
- ❌ Link blocks in the chain

### Implementation Priority
🔴 **HIGHEST PRIORITY** - Everything else depends on this!

---

## 2. Blake2b-512

### What It Is
Blake2b is a cryptographic hash function that's:
- Faster than SHA-256
- More secure than SHA-256
- Customizable with personalization strings

### Where Zcash Uses It

#### ✅ Equihash Proof-of-Work (CRITICAL!)
```cairo
// Initialize with personalization "ZcashPoW" + n + k
let mut state = Blake2b::new_with_personal("ZcashPoW", 200, 9);
state.update(header_without_solution);
state.update(nonce);

// Generate 512 hashes for Equihash indices
for i in 0..512 {
    let hash = state.clone().finalize_with_index(i);
    // Use for Equihash tree construction
}
```

**From librustzcash:**
```rust
// components/equihash/src/verify.rs:119
let mut personalization: Vec<u8> = Vec::from("ZcashPoW");
personalization.write_all(&n.to_le_bytes()).unwrap();
personalization.write_all(&k.to_le_bytes()).unwrap();

Blake2bParams::new()
    .hash_length(digest_len as usize)
    .personal(&personalization)
    .to_state()
```

#### ✅ Sapling Note Commitments
```cairo
// Different personalization for note commitments
let commitment = blake2b_personalized(
    "Zcash_PH",  // Personalization
    note_data
);
```

#### ✅ Nullifier Derivation
```cairo
let nullifier = blake2b_personalized(
    "Zcash_nf",
    nullifier_data
);
```

### Why It's Critical
Without Blake2b, we CANNOT:
- ❌ Verify Equihash solutions (→ No trustless PoW validation!)
- ❌ Compute Sapling note commitments
- ❌ Derive nullifiers

**This is what makes us a consensus client, not just a light client!**

### Current Status
⚠️ **INCOMPLETE** - Marked `///TODO INCOMPLETE` at [blake2b.cairo:3](zcash_light_client/src/crypto/blake2b.cairo#L3)

**What's Missing:**
- Full compression function
- G function (quarter-round)
- All 12 rounds
- Proper sigma permutations

### Implementation Priority
🔴 **CRITICAL - SECOND PRIORITY** (after SHA-256d)

---

## 3. Pedersen Hash

### What It Is
Pedersen hash is based on elliptic curve operations:
- Uses Jubjub curve (Edwards curve)
- Homomorphic properties
- Efficient for zero-knowledge proofs

### Where Zcash Uses It

#### ✅ Sapling Note Commitment Tree
```cairo
pub struct SaplingTree {
    pub root: Array<u8>,
    pub size: u64,
}

impl SaplingTreeTrait {
    fn append(ref self: SaplingTree, note_commitment: felt252) {
        // Use Pedersen hash to update tree
        let new_root = pedersen_merkle_update(
            self.root,
            note_commitment,
            self.size
        );
        self.root = new_root;
        self.size += 1;
    }
}
```

#### ✅ Internal Merkle Tree Nodes
```cairo
fn pedersen_merge(left: felt252, right: felt252) -> felt252 {
    pedersen_hash_merge(left, right)
}
```

### Why It's Needed
- ✅ Sapling commitment tree validation
- ✅ Incremental tree updates
- ✅ Witness generation

### Current Status
✅ **EXISTS** at [pedersen.cairo](zcash_light_client/src/crypto/pedersen.cairo)

**Action Needed:**
🟡 Test against Sapling test vectors to ensure correctness

### Implementation Priority
🟡 **MEDIUM** - Verify it works correctly

---

## 4. NOT Used: What Zcash Doesn't Use

### ❌ RIPEMD-160
Bitcoin uses this for addresses, Zcash does NOT.

### ❌ Keccak-256
Ethereum hash, not used in Zcash.

### ❌ SHA-3
Not used in Zcash consensus.

---

## Summary: Implementation Checklist

### 🔴 Critical (Must Implement)

1. **SHA-256d** ❌
   - For: Block hashes, merkle trees, transaction IDs
   - Effort: ~400 LOC, ~8,000 Cairo steps
   - Blocks: Everything

2. **Blake2b (Complete)** ⚠️
   - For: Equihash, note commitments, nullifiers
   - Effort: ~500 LOC, ~10,000 Cairo steps per hash
   - Blocks: Equihash verification

### 🟡 Medium (Verify & Test)

3. **Pedersen Hash** ✅
   - For: Sapling commitment trees
   - Action: Test with vectors
   - Effort: Testing only

### 🟢 Low (Future)

4. **Sinsemilla** (NU5/Orchard) ❌
   - For: Orchard commitment trees
   - Priority: Future feature

---

## Architecture Diagram

```
Block Validation Flow:
┌─────────────────────────────────────┐
│ 1. Compute Block Hash                │
│    Input: BlockHeader                │
│    Hash: SHA-256d ❌ MISSING         │
│    Output: 32-byte hash              │
└─────────────────────────────────────┘
            ↓
┌─────────────────────────────────────┐
│ 2. Verify Equihash PoW               │
│    Input: Header + Solution          │
│    Hash: Blake2b ⚠️ INCOMPLETE       │
│    Output: Valid/Invalid             │
└─────────────────────────────────────┘
            ↓
┌─────────────────────────────────────┐
│ 3. Validate Difficulty               │
│    Compare: block_hash < target      │
│    Needs: SHA-256d ❌ MISSING        │
│    Output: Valid/Invalid             │
└─────────────────────────────────────┘
            ↓
┌─────────────────────────────────────┐
│ 4. Verify TX Merkle Root             │
│    Input: Transaction hashes         │
│    Hash: SHA-256d ❌ MISSING         │
│    Output: Valid/Invalid             │
└─────────────────────────────────────┘
            ↓
┌─────────────────────────────────────┐
│ 5. Verify Sapling Tree Root          │
│    Input: Note commitments           │
│    Hash: Pedersen ✅ EXISTS          │
│    Output: Valid/Invalid             │
└─────────────────────────────────────┘
```

---

## Evidence from librustzcash

### SHA-256d for Block Hash
```rust
// zcash_primitives/src/block.rs:109
header.hash.0.copy_from_slice(&Sha256::digest(Sha256::digest(&raw)));
```

### Blake2b for Equihash
```rust
// components/equihash/src/verify.rs:119-128
fn initialise_state(n: u32, k: u32, digest_len: u8) -> Blake2bState {
    let mut personalization: Vec<u8> = Vec::from("ZcashPoW");
    personalization.write_all(&n.to_le_bytes()).unwrap();
    personalization.write_all(&k.to_le_bytes()).unwrap();

    Blake2bParams::new()
        .hash_length(digest_len as usize)
        .personal(&personalization)
        .to_state()
}
```

### SHA-256d for TX Hashing
```rust
// zcash_primitives/src/transaction/util/sha256d.rs:25
pub fn into_hash(self) -> Output<Sha256> {
    Sha256::digest(self.hasher.finalize())
}
```

---

## Bottom Line

### What Zcash Actually Uses:
1. **SHA-256d** - Block hashes, TX merkle tree (Bitcoin legacy) ❌ **MUST IMPLEMENT**
2. **Blake2b** - Equihash, note commitments (Sapling) ⚠️ **MUST COMPLETE**
3. **Pedersen** - Sapling commitment tree ✅ **VERIFY**

### NOT Used in Consensus:
- ❌ RIPEMD-160
- ❌ Keccak
- ❌ SHA-3

### Implementation Order:
1. **SHA-256d** first (enables block validation)
2. **Blake2b** second (enables Equihash)
3. **Test Pedersen** third (verify correctness)

**Once these 3 are done, we have a working consensus client!**
