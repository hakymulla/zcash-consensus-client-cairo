# Zcash Consensus Client Implementation Requirements (Cairo)

## Goal
Implement a **full consensus client** in Cairo (like Raito for Bitcoin) that can independently verify Zcash blocks and generate STARK proofs of validity.

## Key Distinction: Consensus Client vs Light Client

| Aspect | Light Client (Swift SDK) | Consensus Client (Our Goal) |
|--------|-------------------------|----------------------------|
| Block Validation | Trusts `lightwalletd` server | Validates all consensus rules |
| Equihash PoW | Skipped (trusted) | **Must verify** |
| Block Headers | Basic linkage only | **Full validation** (version, bits, nonce, solution) |
| Merkle Roots | Not verified | **Must verify** transaction and Sapling roots |
| Difficulty Adjustment | Skipped | **Must implement** |
| Network Upgrades | Handled by server | **Must implement** all upgrade rules |
| Security Model | SPV-style trust | **Trustless** (like full node) |

## Critical Components from librustzcash Analysis

### 1. Block Header Structure (COMPLETE)

From `/librustzcash/zcash_primitives/src/block.rs`:

```rust
pub struct BlockHeaderData {
    pub version: i32,              // Protocol version
    pub prev_block: BlockHash,     // Previous block hash (32 bytes)
    pub merkle_root: [u8; 32],     // Transaction merkle root
    pub final_sapling_root: [u8; 32], // Sapling note commitment tree root
    pub time: u32,                 // Unix timestamp
    pub bits: u32,                 // Difficulty target (compact format)
    pub nonce: [u8; 32],          // PoW nonce
    pub solution: Vec<u8>,         // Equihash solution (1344 bytes for n=200,k=9)
}
```

**Block Hash Calculation:**
- SHA-256d (double SHA-256) of serialized header
- Format: `SHA256(SHA256(header_bytes))`

**Cairo Implementation Needed:**
```cairo
#[derive(Drop, Serde, Debug)]
pub struct BlockHeader {
    pub version: i32,
    pub prev_block: Array<u8>,  // 32 bytes
    pub merkle_root: Array<u8>, // 32 bytes
    pub final_sapling_root: Array<u8>, // 32 bytes
    pub time: u32,
    pub bits: u32,              // NEW: Difficulty target
    pub nonce: Array<u8>,       // 32 bytes
    pub solution: Array<u8>,    // 1344 bytes (Equihash solution)
}
```

### 2. Equihash Proof-of-Work Verification (CRITICAL)

From `/librustzcash/components/equihash/src/verify.rs`:

**Parameters for Zcash:**
- n = 200 (hash output bits)
- k = 9 (Wagner's algorithm parameter)
- Solution size: 2^k = 512 indices
- Encoded solution size: (k+1) * 2^k * (n/(k+1))/8 = 1344 bytes

**Verification Algorithm:**
```
1. Initialize Blake2b state with personalization "ZcashPoW" + n + k
2. Update state with block header (minus solution) + nonce
3. Generate 512 indices from solution
4. Build binary tree of hashes:
   - Leaf nodes: Generate hash for each index
   - Internal nodes: XOR child hashes, trim collision bits
   - Validate: No duplicate indices, correct ordering, proper collisions
5. Check: Root hash must be zero (after trimming)
```

**Why This Is Hard in Cairo:**
- **Computational Cost**: Equihash is designed to be memory-hard and CPU-intensive
- **512 indices × multiple rounds** of Blake2b hashing
- **Binary tree construction** with collision detection
- Each verification might exceed Cairo VM step limits

**Options:**
1. **Skip Equihash** (trust checkpoint/oracle) - NOT a true consensus client
2. **Simplified validation** - Partial checks only
3. **Full implementation** - True consensus validation but expensive
4. **Off-chain hint system** - Verify with hints, prove correctness

**Recommendation:** Implement full Equihash verification but use Cairo's hint system for optimization.

### 3. Difficulty Adjustment Validation

**From Zcash Protocol Spec:**
- Target block time: 150 seconds (2.5 minutes)
- Difficulty adjustment: Every block (Bitcoin-style but adjusted)
- `bits` field encodes difficulty target in compact format

**Validation Required:**
```cairo
fn validate_difficulty(
    header: @BlockHeader,
    prev_header: @BlockHeader,
    network: NetworkType
) -> Result<(), ZcashError> {
    // 1. Decode bits to get target threshold
    let target = expand_compact_bits(*header.bits);

    // 2. Check block hash is below target
    let block_hash = calculate_block_hash(header);
    if block_hash >= target {
        return Err(ZcashError::InvalidProofOfWork);
    }

    // 3. Verify difficulty adjustment is correct
    let expected_bits = calculate_next_difficulty(
        prev_header.time,
        header.time,
        prev_header.bits
    );
    if expected_bits != header.bits {
        return Err(ZcashError::InvalidDifficulty);
    }

    Ok(())
}
```

### 4. Cryptographic Primitives Required

#### A. Blake2b (INCOMPLETE - TODO marked)

**Current Status:** `zcash_light_client/src/crypto/blake2b.cairo:3` - `///TODO INCOMPLETE`

**What's Missing:**
- Full compression function with G function
- Round permutations (12 rounds for Blake2b-512)
- Proper mixing of message blocks
- IV constants and sigma permutations

**Reference:** `/librustzcash/components/equihash/src/blake2b.rs`

**Full Implementation Required:**
```cairo
// Blake2b constants
const SIGMA: [[usize; 16]; 12] = [...]; // Round permutations
const IV: [u64; 8] = [0x6a09e667f3bcc908, ...]; // Initial values

fn G(
    v: @mut Array<u64>,
    a: usize, b: usize, c: usize, d: usize,
    x: u64, y: u64
) {
    // Quarter-round mixing function
    // 4 mixing operations with rotations
}

fn compress(
    h: @mut Array<u64>,
    m: @Array<u64>,
    t: u128,
    f: bool
) {
    // 12 rounds of G function
    // Mix state with message
    // XOR with initial state
}
```

#### B. SHA-256d (MISSING)

**Required for:** Block hash calculation

```cairo
fn sha256d(data: @Array<u8>) -> Array<u8> {
    let first_hash = sha256(data);
    sha256(@first_hash)
}
```

**Challenge:** Cairo doesn't have native SHA-256. Options:
1. Implement from scratch (expensive)
2. Use Cairo built-in Keccak + conversion
3. Use hint system for optimization

#### C. Pedersen Hash (EXISTS)

Located at: `zcash_light_client/src/crypto/pedersen.cairo`

**Used for:** Note commitments, nullifiers

### 5. Merkle Tree Validation

#### A. Transaction Merkle Root

**Must verify:**
```cairo
fn validate_merkle_root(
    transactions: @Array<Transaction>,
    claimed_root: @Array<u8>
) -> bool {
    let computed_root = compute_merkle_root(transactions);
    computed_root == *claimed_root
}
```

**Hash Function:** SHA-256d (Bitcoin-style)

#### B. Sapling Commitment Tree Root

**Must verify:**
```cairo
fn validate_sapling_root(
    block: @CompactBlock,
    prev_sapling_root: @Array<u8>,
    expected_tree_size: u32
) -> bool {
    // Update tree with new note commitments
    let mut tree = SaplingTree::from_root(prev_sapling_root);

    // Add all new commitments from block
    for output in block.get_all_outputs() {
        tree.append(output.cmu);
    }

    // Verify root matches
    tree.root() == block.final_sapling_root
}
```

**Tree Structure:** Incremental Merkle tree (depth 32)
**Hash Function:** Pedersen hash

### 6. Network Upgrade Consensus Rules

From `/librustzcash/components/zcash_protocol/src/consensus.rs`:

**Zcash Network Upgrades:**
1. **Overwinter** (Block ~347,500)
   - Transaction v3
   - Header commitment field

2. **Sapling** (Block ~419,200)
   - Sapling shielded pool
   - Transaction v4

3. **Blossom** (Block ~653,600)
   - Reduced block time to 75s

4. **Heartwood** (Block ~903,000)
   - FlyClient support

5. **Canopy** (Block ~1,046,400)
   - Transaction v5 prep

6. **NU5** (Block ~1,687,104)
   - Orchard shielded pool
   - Transaction v5

**Implementation Required:**
```cairo
pub enum NetworkUpgrade {
    Overwinter,
    Sapling,
    Blossom,
    Heartwood,
    Canopy,
    NU5,
}

fn get_active_upgrade(height: BlockHeight) -> NetworkUpgrade {
    // Return which upgrade is active at this height
}

fn validate_transaction_version(
    tx_version: i32,
    block_height: BlockHeight
) -> Result<(), ZcashError> {
    let upgrade = get_active_upgrade(block_height);

    match upgrade {
        NetworkUpgrade::Overwinter => {
            if tx_version < 3 { return Err(...); }
        },
        NetworkUpgrade::Sapling => {
            if tx_version < 4 { return Err(...); }
        },
        // ... etc
    }
    Ok(())
}
```

### 7. Transaction Validation

**Consensus Rules to Implement:**

```cairo
fn validate_transaction(
    tx: @Transaction,
    block_height: BlockHeight,
    network: NetworkType
) -> Result<(), ZcashError> {
    // 1. Version check
    validate_transaction_version(tx.version, block_height)?;

    // 2. Expiry height check (if set)
    if tx.expiry_height > 0 && block_height >= tx.expiry_height {
        return Err(ZcashError::TransactionExpired);
    }

    // 3. Value balance check (transparent + shielded)
    // Ensure no value is created from nothing
    let total_in = tx.transparent_inputs_value() +
                   tx.sapling_value_balance +
                   tx.orchard_value_balance;
    let total_out = tx.transparent_outputs_value();

    if total_in < total_out {
        return Err(ZcashError::InvalidValueBalance);
    }

    // 4. Shielded pool-specific rules
    validate_sapling_spends(tx)?;
    validate_sapling_outputs(tx)?;
    validate_orchard_actions(tx)?;

    // 5. Signature validation (complex)
    // Defer to specialized functions

    Ok(())
}
```

### 8. Trial Decryption with Note Commitment Verification

**Current Status:** TODO at `zcash_cairo_bridge/src/cairo_ffi.rs:103`

**Full Implementation Required:**

```cairo
fn trial_decrypt_and_verify(
    output: @CompactOutput,
    ivk: @IncomingViewingKey,
    height: u64
) -> Option<DecryptedNote> {
    // 1. Derive shared secret using KDF
    let shared_secret = ka_sapling_agree(ivk, output.epk);
    let kdf_output = kdf_sapling(shared_secret, output.epk);

    // 2. Decrypt first 52 bytes
    let plaintext = decrypt_compact_note(
        output.ciphertext,  // Only 52 bytes
        kdf_output
    );

    // 3. Parse plaintext to extract note components
    let (value, d, rcm) = parse_note_plaintext(plaintext)?;

    // 4. CRITICAL: Verify note commitment
    // This proves the note is well-formed
    let computed_cmu = note_commit(
        value,
        d,
        output.epk,
        rcm
    );

    if computed_cmu != output.cmu {
        return None;  // Decryption succeeded but note is invalid
    }

    // 5. Success - return decrypted note
    Some(DecryptedNote {
        value,
        diversifier: d,
        rcm,
        position: height,
    })
}
```

**Why This Matters:**
- Prevents malicious servers from sending fake notes
- Ensures note was properly constructed
- Critical security property for light clients

### 9. Protocol Buffer Support

**Currently Missing:** No protobuf in Cairo implementation

**Required for:**
- Compatibility with `lightwalletd` servers
- Standard message encoding/decoding
- Cross-implementation compatibility

**Implementation Options:**
1. **Manual serialization** - Write protobuf encoder/decoder in Cairo
2. **Pre-processing** - Convert protobuf to Cairo-friendly format in Rust layer
3. **Hybrid approach** - Protobuf in Rust, pure validation in Cairo

**Recommended:** Hybrid approach - Rust FFI handles protobuf, Cairo does pure verification

## Complete Implementation Checklist

### Phase 1: Cryptographic Primitives (Foundation)
- [ ] **Complete Blake2b implementation**
  - [ ] Full compression function with G rounds
  - [ ] Proper IV and sigma constants
  - [ ] All 12 rounds implemented
  - [ ] Test vectors from RFC 7693

- [ ] **Implement SHA-256**
  - [ ] Core SHA-256 function
  - [ ] SHA-256d (double hash)
  - [ ] Test vectors from NIST

- [ ] **Verify Pedersen hash works correctly**
  - [ ] Test against known commitments
  - [ ] Performance optimization

### Phase 2: Block Header Validation
- [ ] **Extend BlockHeader structure**
  - [ ] Add `version` field
  - [ ] Add `merkle_root` field
  - [ ] Add `final_sapling_root` field
  - [ ] Add `bits` field (difficulty)
  - [ ] Add `solution` field (Equihash)

- [ ] **Implement block hash calculation**
  - [ ] Serialize header correctly
  - [ ] SHA-256d implementation
  - [ ] Test with known blocks

- [ ] **Implement difficulty validation**
  - [ ] Compact bits expansion
  - [ ] Target threshold checking
  - [ ] Difficulty adjustment calculation

### Phase 3: Equihash Verification (HARDEST)
- [ ] **Equihash parameters (n=200, k=9)**
  - [ ] Solution parsing (1344 bytes → 512 indices)
  - [ ] Blake2b state initialization with "ZcashPoW"

- [ ] **Binary tree construction**
  - [ ] Generate leaf hashes for all 512 indices
  - [ ] Collision detection and validation
  - [ ] Index ordering verification
  - [ ] No duplicate indices check

- [ ] **Root hash verification**
  - [ ] Tree reduction with XOR
  - [ ] Proper bit trimming at each level
  - [ ] Final root must be zero

- [ ] **Optimization strategies**
  - [ ] Use Cairo hint system
  - [ ] Batch operations where possible
  - [ ] Consider proof-of-computation approach

### Phase 4: Merkle Tree Validation
- [ ] **Transaction merkle root**
  - [ ] Build merkle tree from transaction hashes
  - [ ] SHA-256d hash function
  - [ ] Compare with header merkle_root

- [ ] **Sapling commitment tree**
  - [ ] Incremental merkle tree (depth 32)
  - [ ] Pedersen hash for internal nodes
  - [ ] Root update validation
  - [ ] Tree size tracking

### Phase 5: Network Upgrade Rules
- [ ] **Define upgrade activation heights**
  - [ ] Mainnet heights
  - [ ] Testnet heights
  - [ ] Regtest (for testing)

- [ ] **Version validation per upgrade**
  - [ ] Transaction version rules
  - [ ] Block version rules
  - [ ] Consensus parameter changes

- [ ] **Block time adjustments**
  - [ ] Pre-Blossom: 150s target
  - [ ] Post-Blossom: 75s target

### Phase 6: Transaction Validation
- [ ] **Basic validation**
  - [ ] Version check against network upgrade
  - [ ] Expiry height check
  - [ ] Value balance validation

- [ ] **Shielded pool validation**
  - [ ] Sapling spend validation
  - [ ] Sapling output validation
  - [ ] Orchard action validation

- [ ] **Advanced validation**
  - [ ] Signature verification (complex)
  - [ ] Anchor validation
  - [ ] Nullifier uniqueness

### Phase 7: Trial Decryption (Light Client Feature)
- [ ] **Key agreement**
  - [ ] Sapling KA-agree function
  - [ ] KDF derivation

- [ ] **Decryption**
  - [ ] ChaCha20-Poly1305 for compact notes
  - [ ] Plaintext parsing

- [ ] **Note commitment verification**
  - [ ] Recompute note commitment
  - [ ] Compare with output.cmu
  - [ ] Critical security check

### Phase 8: Integration & Testing
- [ ] **Protocol buffer support**
  - [ ] Define strategy (manual/hybrid/pre-process)
  - [ ] Implement serialization if needed

- [ ] **Test with real blocks**
  - [ ] Genesis block
  - [ ] Sapling activation block
  - [ ] Recent mainnet blocks

- [ ] **Performance optimization**
  - [ ] Identify bottlenecks
  - [ ] Use Cairo hints
  - [ ] Batch operations

- [ ] **STARK proof generation**
  - [ ] Integrate with STWO prover
  - [ ] Verify proofs validate correctly
  - [ ] Measure proof size and verification time

## Key Files from librustzcash to Reference

1. **Block structure:** `/zcash_primitives/src/block.rs`
2. **Equihash:** `/components/equihash/src/verify.rs`
3. **Consensus:** `/components/zcash_protocol/src/consensus.rs`
4. **Transactions:** `/zcash_primitives/src/transaction/mod.rs`
5. **Merkle trees:** `/zcash_primitives/src/merkle_tree.rs`
6. **Blake2b:** `/components/equihash/src/blake2b.rs`

## Estimated Complexity

| Component | Difficulty | LOC Estimate | Cairo Steps Estimate |
|-----------|-----------|--------------|---------------------|
| Blake2b Complete | Medium | 500 | 10,000 |
| SHA-256d | Medium | 400 | 8,000 |
| Equihash Verify | **Very Hard** | 1,500 | 500,000+ |
| Difficulty Check | Easy | 200 | 2,000 |
| Merkle Trees | Medium | 600 | 15,000 |
| Network Upgrades | Easy | 300 | 1,000 |
| Transaction Validation | Hard | 1,000 | 50,000 |
| Trial Decryption | Medium | 400 | 10,000 |
| **TOTAL** | **Hard** | **~5,000** | **~600,000** |

## Success Criteria

✅ **Minimum Viable Consensus Client:**
1. Verify block headers (prev_hash linkage)
2. Verify Equihash proof-of-work
3. Verify difficulty adjustment
4. Verify transaction merkle root
5. Verify Sapling commitment tree root
6. Validate transaction versions per network upgrade

✅ **Full Consensus Client (Goal):**
All of the above, plus:
7. Complete transaction validation (value balance, signatures)
8. Trial decryption with cmu verification
9. Support for all network upgrades
10. Protocol buffer compatibility
11. Generate STARK proofs for block ranges
12. Fast-sync using checkpoint proofs

## Next Steps

1. **Complete Blake2b** - Foundation for everything else
2. **Implement SHA-256d** - Required for block hashes
3. **Tackle Equihash** - The hardest part
4. **Add full BlockHeader** - Extend current structure
5. **Test with real blocks** - Validate against zcashd

---

**Note:** This is a consensus client, NOT just a light client. We must implement the same validation logic as zcashd/zebrad full nodes, just in Cairo for STARK provability.
