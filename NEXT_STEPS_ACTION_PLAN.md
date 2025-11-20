# Zcash Cairo Consensus Client - Action Plan

**Date:** November 17, 2024
**Current Status:** 60% Complete (Structure)
**Goal:** Working block validation in 2-3 weeks

---

## 🎯 Objective

Complete the **3 critical cryptographic primitives** using Alexandria library, then integrate and test against real Zcash mainnet blocks.

---

## 📊 Current Situation

### ✅ What We Have (60%)

| Component | Status | Lines |
|-----------|--------|-------|
| BlockHeader | 100% ✅ | 284 LOC |
| Equihash algorithm | 90% ✅ | 371 LOC |
| Difficulty logic | 85% ✅ | 246 LOC |
| Merkle trees | 90% ✅ | 324 LOC |
| Pedersen hash | 95% ✅ | 132 LOC |

**Total:** ~1,400 LOC of solid foundation

### ❌ Critical Blockers (40%)

| Blocker | Impact | Solution | Effort |
|---------|--------|----------|--------|
| SHA-256d | Can't hash blocks | ✅ Alexandria | 30 min |
| Blake2b | Can't verify Equihash | ⚠️ Implement (use SHA-512 ref) | 4 hours |
| u256 ops | Can't compare difficulty | ✅ Native Cairo | 0 min |

**With Alexandria:** Only Blake2b remains!

---

## 📅 3-Week Plan

### **Week 1: Foundation with Alexandria**

#### Day 1 (Monday): Setup & SHA-256d ⏱️ 3 hours

**Morning: Add Dependencies (1 hour)**

1. **Update Scarb.toml**
   ```bash
   cd /Users/ak36/Desktop/rust/darth/zcash_light_client
   ```

   Add to `Scarb.toml`:
   ```toml
   [dependencies]
   starknet = ">=2.8.2"

   # Alexandria libraries
   alexandria_math = "0.7.0"
   alexandria_bytes = "0.7.0"
   alexandria_data_structures = "0.7.0"
   ```

2. **Build and verify**
   ```bash
   scarb build
   ```

   Expected: Clean build with new dependencies

**Afternoon: Implement SHA-256d (2 hours)**

3. **Create `src/crypto/sha256.cairo`**

   ```cairo
   use alexandria_math::sha256::sha256;

   /// Compute SHA-256d (double SHA-256)
   /// Used for: block hashes, TX merkle tree, TX IDs
   pub fn sha256d(data: Array<u8>) -> Array<u8> {
       let first_hash = sha256(data);
       sha256(first_hash)
   }

   /// Compute block hash from header
   pub fn compute_block_hash(header: @BlockHeader) -> Array<u8> {
       let serialized = serialize_header(header);
       sha256d(serialized)
   }

   /// Serialize block header (all fields except hash)
   fn serialize_header(header: @BlockHeader) -> Array<u8> {
       let mut bytes = ArrayTrait::new();

       // version (4 bytes, LE)
       append_i32_le(&mut bytes, *header.version);

       // prev_block (32 bytes)
       append_bytes(&mut bytes, @header.prev_block);

       // merkle_root (32 bytes)
       append_bytes(&mut bytes, @header.merkle_root);

       // final_sapling_root (32 bytes)
       append_bytes(&mut bytes, @header.final_sapling_root);

       // time (4 bytes, LE)
       append_u32_le(&mut bytes, *header.time);

       // bits (4 bytes, LE)
       append_u32_le(&mut bytes, *header.bits);

       // nonce (32 bytes)
       append_bytes(&mut bytes, @header.nonce);

       // solution (1344 bytes)
       append_bytes(&mut bytes, @header.solution);

       bytes
   }

   // Helper functions
   fn append_i32_le(bytes: ref Array<u8>, value: i32) {
       let val = value as u32;
       bytes.append((val & 0xFF) as u8);
       bytes.append(((val >> 8) & 0xFF) as u8);
       bytes.append(((val >> 16) & 0xFF) as u8);
       bytes.append(((val >> 24) & 0xFF) as u8);
   }

   fn append_u32_le(bytes: ref Array<u8>, value: u32) {
       bytes.append((value & 0xFF) as u8);
       bytes.append(((value >> 8) & 0xFF) as u8);
       bytes.append(((value >> 16) & 0xFF) as u8);
       bytes.append(((value >> 24) & 0xFF) as u8);
   }

   fn append_bytes(bytes: ref Array<u8>, data: @Array<u8>) {
       let mut i = 0;
       while i < data.len() {
           bytes.append(*data[i]);
           i += 1;
       };
   }
   ```

4. **Add tests with Bitcoin test vectors**

   ```cairo
   #[cfg(test)]
   mod tests {
       use super::sha256d;

       #[test]
       fn test_sha256d_hello() {
           // "hello" in ASCII
           let data = array![0x68, 0x65, 0x6c, 0x6c, 0x6f];
           let hash = sha256d(data);

           // Known SHA-256d("hello")
           // Should match Bitcoin test vector
           assert(hash.len() == 32, 'Hash should be 32 bytes');
       }

       #[test]
       fn test_empty_hash() {
           let data = array![];
           let hash = sha256d(data);
           assert(hash.len() == 32, 'Hash should be 32 bytes');
       }
   }
   ```

5. **Update `src/crypto/mod.cairo`**
   ```cairo
   pub mod blake2b;
   pub mod pedersen;
   pub mod note_encryption;
   pub mod nullifier;
   pub mod sha256;  // Add this
   ```

6. **Test**
   ```bash
   scarb test sha256
   ```

**Deliverable:** ✅ Working SHA-256d implementation

---

#### Day 2 (Tuesday): Difficulty Validation ⏱️ 4 hours

**Morning: u256 Utilities (2 hours)**

7. **Create `src/utils/u256.cairo`**

   ```cairo
   use alexandria_math::BitShift;

   /// Convert 32-byte array to u256 (little-endian)
   pub fn bytes_to_u256_le(bytes: @Array<u8>) -> u256 {
       assert(bytes.len() == 32, 'Invalid byte array size');

       let mut low: u128 = 0;
       let mut high: u128 = 0;

       // Lower 16 bytes → low
       let mut i = 0;
       while i < 16 {
           low = low | ((*bytes[i] as u128) << (i * 8));
           i += 1;
       };

       // Upper 16 bytes → high
       while i < 32 {
           high = high | ((*bytes[i] as u128) << ((i - 16) * 8));
           i += 1;
       };

       u256 { low, high }
   }

   /// Convert u256 to 32-byte array (little-endian)
   pub fn u256_to_bytes_le(value: u256) -> Array<u8> {
       let mut bytes = ArrayTrait::new();

       // Low 128 bits (16 bytes)
       let mut i = 0;
       while i < 16 {
           let byte = ((value.low >> (i * 8)) & 0xFF) as u8;
           bytes.append(byte);
           i += 1;
       };

       // High 128 bits (16 bytes)
       i = 0;
       while i < 16 {
           let byte = ((value.high >> (i * 8)) & 0xFF) as u8;
           bytes.append(byte);
           i += 1;
       };

       bytes
   }

   #[cfg(test)]
   mod tests {
       use super::{bytes_to_u256_le, u256_to_bytes_le};

       #[test]
       fn test_roundtrip() {
           let original = u256 { low: 0x123456789ABCDEF, high: 0xFEDCBA987654321 };
           let bytes = u256_to_bytes_le(original);
           let recovered = bytes_to_u256_le(@bytes);

           assert(recovered == original, 'Roundtrip failed');
       }
   }
   ```

**Afternoon: Update Difficulty Module (2 hours)**

8. **Update `src/verification/difficulty.cairo`**

   ```cairo
   use alexandria_math::BitShift;
   use crate::utils::u256::{bytes_to_u256_le, u256_to_bytes_le};
   use crate::crypto::sha256::compute_block_hash;

   /// Expand compact bits to full 256-bit target
   pub fn expand_compact_bits(bits: u32) -> u256 {
       let exponent = ((bits >> 24) & 0xFF) as u8;
       let mantissa = (bits & 0x00FFFFFF) as u256;

       // Handle edge cases
       if mantissa == 0 || exponent == 0 {
           return 0_u256;
       }

       if exponent <= 3 {
           // Right shift instead
           let shift = (3 - exponent) * 8;
           return mantissa >> shift;
       }

       // Calculate: mantissa * 256^(exponent - 3)
       // Which is: mantissa << (8 * (exponent - 3))
       let shift_amount = ((exponent as u256 - 3) * 8);
       BitShift::shl(mantissa, shift_amount)
   }

   /// Compress 256-bit target to compact bits
   pub fn compact_u256(target: u256) -> u32 {
       // Find most significant byte
       // Extract exponent and mantissa
       // Return compact representation

       // TODO: Implement full compression
       0x1d00ffff  // Placeholder
   }

   /// Check if block hash meets difficulty target
   pub fn check_proof_of_work(
       block_hash: @Array<u8>,
       bits: u32
   ) -> Result<(), ZcashError> {
       // Validate input
       if block_hash.len() != 32 {
           return Err(ValidationError("Invalid block hash size"));
       }

       if bits == 0 {
           return Err(ValidationError("Invalid difficulty bits"));
       }

       // Expand target
       let target = expand_compact_bits(bits);

       // Convert block hash to u256
       let hash_u256 = bytes_to_u256_le(block_hash);

       // THE CRITICAL CHECK: hash < target
       if hash_u256 >= target {
           return Err(ValidationError("Hash doesn't meet difficulty"));
       }

       Ok(())
   }

   /// Full difficulty validation for a block
   pub fn validate_block_difficulty(
       header: @BlockHeader,
       prev_headers: Span<BlockHeader>,
       height: BlockHeight,
       is_blossom_active: bool,
   ) -> Result<(), ZcashError> {
       // Get difficulty parameters
       let params = get_difficulty_params(height, is_blossom_active);

       // Compute block hash
       let block_hash = compute_block_hash(header);

       // Check PoW: hash < target
       check_proof_of_work(@block_hash, *header.bits)?;

       // Validate difficulty adjustment (if not genesis)
       if prev_headers.len() > 0 {
           validate_difficulty_transition(header, prev_headers, params)?;
       }

       Ok(())
   }
   ```

9. **Add comprehensive tests**

   ```cairo
   #[test]
   fn test_expand_compact_bits() {
       // Mainnet genesis: 0x1f07ffff
       let bits = 0x1f07ffff_u32;
       let target = expand_compact_bits(bits);

       // Target should be 0x07ffff * 256^(0x1f - 3)
       assert(target > 0_u256, 'Target should be non-zero');
   }

   #[test]
   fn test_genesis_block_pow() {
       // Genesis block hash is known to be valid
       let genesis_hash = array![/* 32 bytes */];
       let bits = 0x1f07ffff_u32;

       let result = check_proof_of_work(@genesis_hash, bits);
       assert(result.is_ok(), 'Genesis should be valid');
   }
   ```

10. **Test**
    ```bash
    scarb test difficulty
    ```

**Deliverable:** ✅ Working difficulty validation with native u256

---

#### Day 3 (Wednesday): Merkle Trees ⏱️ 3 hours

11. **Update `src/verification/merkle.cairo`**

    ```cairo
    use crate::crypto::sha256::sha256d;

    /// Hash a pair of nodes using SHA-256d
    fn hash_pair(left: @Array<u8>, right: @Array<u8>) -> Array<u8> {
        let mut combined = ArrayTrait::new();

        // Append left (32 bytes)
        let mut i = 0;
        while i < left.len() {
            combined.append(*left[i]);
            i += 1;
        };

        // Append right (32 bytes)
        let mut j = 0;
        while j < right.len() {
            combined.append(*right[j]);
            j += 1;
        };

        // Hash with SHA-256d
        sha256d(combined)
    }

    /// Compute transaction merkle root (Bitcoin-style)
    pub fn compute_tx_merkle_root(
        tx_hashes: Span<Array<u8>>
    ) -> Result<Array<u8>, ZcashError> {
        if tx_hashes.len() == 0 {
            return Err(ValidationError("No transactions"));
        }

        if tx_hashes.len() == 1 {
            return Ok(tx_hashes[0].clone());
        }

        // Build tree level by level
        let mut current_level: Array<Array<u8>> = ArrayTrait::new();

        let mut i = 0;
        while i < tx_hashes.len() {
            current_level.append(tx_hashes[i].clone());
            i += 1;
        };

        // Process levels until single root
        while current_level.len() > 1 {
            let mut next_level: Array<Array<u8>> = ArrayTrait::new();
            let mut j: usize = 0;

            while j < current_level.len() {
                if j + 1 < current_level.len() {
                    // Hash pair
                    let combined = hash_pair(
                        @current_level[j],
                        @current_level[j + 1]
                    );
                    next_level.append(combined);
                    j += 2;
                } else {
                    // Odd number - duplicate last
                    let combined = hash_pair(
                        @current_level[j],
                        @current_level[j]
                    );
                    next_level.append(combined);
                    j += 1;
                }
            };

            current_level = next_level;
        };

        Ok(current_level[0].clone())
    }

    /// Validate TX merkle root in block header
    pub fn validate_tx_merkle_root(
        header: @BlockHeader,
        tx_hashes: Span<Array<u8>>
    ) -> Result<(), ZcashError> {
        let computed_root = compute_tx_merkle_root(tx_hashes)?;

        // Compare with header's merkle_root
        if computed_root.len() != header.merkle_root.len() {
            return Err(ValidationError("Merkle root size mismatch"));
        }

        let mut i = 0;
        while i < computed_root.len() {
            if *computed_root[i] != *header.merkle_root[i] {
                return Err(ValidationError("Merkle root mismatch"));
            }
            i += 1;
        };

        Ok(())
    }
    ```

12. **Add tests**

    ```cairo
    #[test]
    fn test_single_tx_merkle() {
        let tx_hash = array![/* 32 bytes */];
        let root = compute_tx_merkle_root(array![tx_hash].span());

        assert(root.is_ok(), 'Should succeed');
        assert(root.unwrap() == tx_hash, 'Should equal input');
    }

    #[test]
    fn test_two_tx_merkle() {
        let tx1 = array![/* 32 bytes of 0xAA */];
        let tx2 = array![/* 32 bytes of 0xBB */];

        let root = compute_tx_merkle_root(array![tx1, tx2].span());
        assert(root.is_ok(), 'Should succeed');
    }
    ```

**Deliverable:** ✅ Working TX merkle tree with SHA-256d

---

### **Week 1-2: Blake2b Implementation**

#### Days 4-5 (Thu-Fri): Blake2b Core ⏱️ 8 hours

**Reference:** Use Alexandria's SHA-512 as template

13. **Study SHA-512 implementation**
    ```bash
    cat /tmp/alexandria/packages/math/src/sha512.cairo
    ```

14. **Complete `src/crypto/blake2b.cairo`**

    **Add missing G function:**
    ```cairo
    /// Blake2b G mixing function
    fn blake2b_g(
        v: ref Array<u64>,
        a: usize,
        b: usize,
        c: usize,
        d: usize,
        x: u64,
        y: u64
    ) {
        // Round 1
        v[a] = wrapping_add_u64(v[a], wrapping_add_u64(v[b], x));
        v[d] = rotr64(v[d] ^ v[a], 32);
        v[c] = wrapping_add_u64(v[c], v[d]);
        v[b] = rotr64(v[b] ^ v[c], 24);

        // Round 2
        v[a] = wrapping_add_u64(v[a], wrapping_add_u64(v[b], y));
        v[d] = rotr64(v[d] ^ v[a], 16);
        v[c] = wrapping_add_u64(v[c], v[d]);
        v[b] = rotr64(v[b] ^ v[c], 63);
    }

    /// Right rotation for u64
    fn rotr64(x: u64, n: u32) -> u64 {
        (x >> n) | (x << (64 - n))
    }

    /// Wrapping addition for u64
    fn wrapping_add_u64(a: u64, b: u64) -> u64 {
        let sum = a.into() + b.into();
        (sum & 0xFFFFFFFFFFFFFFFF).try_into().unwrap()
    }
    ```

    **Complete compression function:**
    ```cairo
    fn compress(ref self: Blake2b, is_final: bool) {
        // Initialize working vector v[0..15]
        let mut v: Array<u64> = ArrayTrait::new();

        // v[0..7] = h[0..7]
        let mut i = 0;
        while i < 8 {
            v.append(*self.h[i]);
            i += 1;
        };

        // v[8..15] = IV[0..7]
        let iv = get_iv();
        i = 0;
        while i < 8 {
            v.append(*iv[i]);
            i += 1;
        };

        // XOR v[12] with counter (low)
        v[12] = v[12] ^ *self.t[0];

        // XOR v[13] with counter (high)
        v[13] = v[13] ^ *self.t[1];

        // XOR v[14] with final block flag
        if is_final {
            v[14] = v[14] ^ 0xFFFFFFFFFFFFFFFF;
        }

        // Extract message words
        let m = extract_message_words(@self.buffer);

        // 12 rounds of G function
        let mut round = 0;
        while round < 12 {
            let sigma = get_sigma(round % 10);

            // Column step
            blake2b_g(ref v, 0, 4, 8, 12, m[sigma[0]], m[sigma[1]]);
            blake2b_g(ref v, 1, 5, 9, 13, m[sigma[2]], m[sigma[3]]);
            blake2b_g(ref v, 2, 6, 10, 14, m[sigma[4]], m[sigma[5]]);
            blake2b_g(ref v, 3, 7, 11, 15, m[sigma[6]], m[sigma[7]]);

            // Diagonal step
            blake2b_g(ref v, 0, 5, 10, 15, m[sigma[8]], m[sigma[9]]);
            blake2b_g(ref v, 1, 6, 11, 12, m[sigma[10]], m[sigma[11]]);
            blake2b_g(ref v, 2, 7, 8, 13, m[sigma[12]], m[sigma[13]]);
            blake2b_g(ref v, 3, 4, 9, 14, m[sigma[14]], m[sigma[15]]);

            round += 1;
        };

        // Update state: h[i] = h[i] ^ v[i] ^ v[i+8]
        i = 0;
        while i < 8 {
            self.h[i] = *self.h[i] ^ v[i] ^ v[i + 8];
            i += 1;
        };
    }

    /// Extract 16 u64 message words from buffer
    fn extract_message_words(buffer: @Array<u8>) -> Array<u64> {
        let mut words = ArrayTrait::new();
        let mut i = 0;

        while i < 16 {
            let mut word: u64 = 0;
            let mut j = 0;
            while j < 8 {
                let byte_idx = i * 8 + j;
                if byte_idx < buffer.len() {
                    word |= ((*buffer[byte_idx] as u64) << (j * 8));
                }
                j += 1;
            };
            words.append(word);
            i += 1;
        };

        words
    }

    /// Get sigma permutation for round
    fn get_sigma(round: u32) -> Array<usize> {
        // Blake2b sigma permutations (10 rounds, repeated)
        if round == 0 {
            array![0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
        } else if round == 1 {
            array![14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3]
        } // ... etc (10 total permutations)
        else {
            array![0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
        }
    }
    ```

    **Add personalization support:**
    ```cairo
    /// Initialize Blake2b with personalization
    pub fn blake2b_personal(
        data: @Array<u8>,
        personal: @Array<u8>,
        outlen: usize
    ) -> Array<u8> {
        assert(personal.len() == 16, 'Personal must be 16 bytes');

        let mut state = Blake2bTrait::new(outlen);

        // XOR personalization into IV
        // personal[0..7] → h[0]
        // personal[8..15] → h[1]

        state.update(data);
        state.finalize()
    }
    ```

15. **Test Blake2b**

    ```cairo
    #[test]
    fn test_blake2b_empty() {
        let data = array![];
        let hash = blake2b(@data, 64);
        assert(hash.len() == 64, 'Should be 64 bytes');
    }

    #[test]
    fn test_blake2b_hello() {
        let data = array![0x68, 0x65, 0x6c, 0x6c, 0x6f];  // "hello"
        let hash = blake2b(@data, 64);
        // Compare with known test vector
    }

    #[test]
    fn test_blake2b_personalization() {
        let data = array![0x00];
        let personal = array![
            'Z', 'c', 'a', 's', 'h', 'P', 'o', 'W',
            0xC8, 0x00, 0x00, 0x00,  // n=200
            0x09, 0x00, 0x00, 0x00   // k=9
        ];

        let hash = blake2b_personal(@data, @personal, 64);
        assert(hash.len() == 64, 'Should be 64 bytes');
    }
    ```

**Deliverable:** ✅ Working Blake2b with personalization

---

#### Day 6-7 (Mon-Tue): Equihash Integration ⏱️ 8 hours

16. **Update `src/verification/equihash.cairo`**

    ```cairo
    use crate::crypto::blake2b::{blake2b_personal, Blake2b, Blake2bTrait};

    /// Initialize Blake2b state for Equihash
    pub fn initialize_equihash_state(
        header_bytes: @Array<u8>,
        nonce: @Array<u8>
    ) -> Blake2b {
        // Personalization: "ZcashPoW" + n (u32 LE) + k (u32 LE)
        let mut personalization = ArrayTrait::new();

        // "ZcashPoW"
        personalization.append('Z');
        personalization.append('c');
        personalization.append('a');
        personalization.append('s');
        personalization.append('h');
        personalization.append('P');
        personalization.append('o');
        personalization.append('W');

        // n=200 (little-endian)
        personalization.append(0xC8);
        personalization.append(0x00);
        personalization.append(0x00);
        personalization.append(0x00);

        // k=9 (little-endian)
        personalization.append(0x09);
        personalization.append(0x00);
        personalization.append(0x00);
        personalization.append(0x00);

        let mut state = Blake2bTrait::new_with_personal(
            HASH_OUTPUT_BYTES,
            personalization
        );

        state.update(header_bytes);
        state.update(nonce);

        state
    }

    /// Generate hash for a specific index
    fn generate_index_hash(
        base_state: @Blake2b,
        index: u32
    ) -> Array<u8> {
        let mut state = base_state.clone();

        // Append index (u32 little-endian)
        let mut index_bytes = ArrayTrait::new();
        index_bytes.append((index & 0xFF) as u8);
        index_bytes.append(((index >> 8) & 0xFF) as u8);
        index_bytes.append(((index >> 16) & 0xFF) as u8);
        index_bytes.append(((index >> 24) & 0xFF) as u8);

        state.update(@index_bytes);
        state.finalize()
    }

    /// Verify Equihash solution
    pub fn verify_equihash_solution(
        header: @BlockHeader,
        solution: EquihashSolution
    ) -> Result<(), EquihashError> {
        // 1. Verify exactly 512 indices
        if solution.indices.len() != EQUIHASH_SOLUTION_SIZE {
            return Err(EquihashError::InvalidSolutionLength);
        }

        // 2. Initialize Blake2b state
        let header_bytes = serialize_header_for_equihash(header);
        let state = initialize_equihash_state(@header_bytes, @header.nonce);

        // 3. Generate X values for each index
        let mut x_values: Array<Array<u8>> = ArrayTrait::new();
        let mut i = 0;
        while i < EQUIHASH_SOLUTION_SIZE {
            let idx = *solution.indices[i];
            let hash = generate_index_hash(@state, idx);
            x_values.append(hash);
            i += 1;
        };

        // 4. Build binary tree and validate
        validate_equihash_tree(x_values, @solution.indices)?;

        Ok(())
    }

    /// Validate Equihash binary tree
    fn validate_equihash_tree(
        x_values: Array<Array<u8>>,
        indices: @Array<u32>
    ) -> Result<(), EquihashError> {
        // Build tree level by level (9 levels, k=9)
        let mut current_level = convert_to_nodes(x_values, indices);

        let mut level = 0;
        while level < EQUIHASH_K {
            let mut next_level: Array<EquihashNode> = ArrayTrait::new();
            let mut i = 0;

            while i + 1 < current_level.len() {
                let node_a = current_level[i];
                let node_b = current_level[i + 1];

                // Validate subtree
                validate_subtrees(@node_a, @node_b)?;

                // Combine nodes
                let combined = combine_nodes(
                    node_a,
                    node_b,
                    COLLISION_BYTE_LENGTH
                );
                next_level.append(combined);

                i += 2;
            };

            current_level = next_level;
            level += 1;
        };

        // Should have exactly one node left (the root)
        if current_level.len() != 1 {
            return Err(EquihashError::InvalidSolutionLength);
        }

        // Root hash should be all zeros
        let root = current_level[0];
        if !is_zero_hash(@root.hash) {
            return Err(EquihashError::NonZeroRootHash);
        }

        Ok(())
    }
    ```

17. **Test Equihash**

    ```cairo
    #[test]
    fn test_equihash_parameters() {
        assert(EQUIHASH_N == 200, 'n should be 200');
        assert(EQUIHASH_K == 9, 'k should be 9');
        assert(EQUIHASH_SOLUTION_SIZE == 512, '2^k = 512');
    }

    #[test]
    fn test_equihash_initialization() {
        let header_bytes = array![/* test header */];
        let nonce = array![/* 32 bytes */];

        let state = initialize_equihash_state(@header_bytes, @nonce);
        // Should not panic
    }

    // TODO: Add test with known Equihash solution
    ```

**Deliverable:** ✅ Complete Equihash verification

---

### **Week 2-3: Integration & Testing**

#### Days 8-10 (Wed-Fri): Full Integration ⏱️ 12 hours

18. **Create main validator**

    **File:** `src/verification/block_validator.cairo`

    ```cairo
    use crate::types::block_header::BlockHeader;
    use crate::crypto::sha256::compute_block_hash;
    use crate::verification::difficulty::validate_block_difficulty;
    use crate::verification::equihash::verify_block_equihash;
    use crate::verification::merkle::validate_tx_merkle_root;

    /// Validate a complete block header
    pub fn validate_block_header(
        header: @BlockHeader,
        prev_headers: Span<BlockHeader>,
        height: BlockHeight,
        is_blossom_active: bool,
    ) -> Result<(), ZcashError> {
        // 1. Check header is well-formed
        if !header.is_well_formed() {
            return Err(ValidationError("Malformed header"));
        }

        // 2. Validate chain linkage (if not genesis)
        if height > 0 && prev_headers.len() > 0 {
            let prev = prev_headers[prev_headers.len() - 1];
            if !header.validates_against_prev(@prev) {
                return Err(ValidationError("Chain linkage failed"));
            }
        }

        // 3. Compute block hash
        let computed_hash = compute_block_hash(header);

        // Verify matches stored hash
        if computed_hash != *header.hash {
            return Err(ValidationError("Block hash mismatch"));
        }

        // 4. Validate Equihash PoW
        verify_block_equihash(header)?;

        // 5. Validate difficulty
        validate_block_difficulty(
            header,
            prev_headers,
            height,
            is_blossom_active
        )?;

        // 6. Validate timestamp
        if height > 0 {
            validate_timestamp(header, prev_headers)?;
        }

        Ok(())
    }

    /// Validate timestamp (median-time-past rule)
    fn validate_timestamp(
        header: @BlockHeader,
        prev_headers: Span<BlockHeader>
    ) -> Result<(), ZcashError> {
        let median_time_past = calculate_median_time_past(prev_headers);

        // Timestamp must be greater than median of last 11 blocks
        if *header.time <= median_time_past {
            return Err(ValidationError("Timestamp too old"));
        }

        // Timestamp must not be too far in future (2 hours)
        let max_future = median_time_past + 7200;  // 2 hours
        if *header.time > max_future {
            return Err(ValidationError("Timestamp too far in future"));
        }

        Ok(())
    }

    fn calculate_median_time_past(prev_headers: Span<BlockHeader>) -> u32 {
        // Get timestamps of last 11 blocks
        let count = if prev_headers.len() < 11 {
            prev_headers.len()
        } else {
            11
        };

        let mut timestamps: Array<u32> = ArrayTrait::new();
        let start = prev_headers.len() - count;
        let mut i = start;
        while i < prev_headers.len() {
            timestamps.append(*prev_headers[i].time);
            i += 1;
        };

        // Sort and take median
        timestamps.sort();
        *timestamps[count / 2]
    }
    ```

19. **Genesis block test**

    ```cairo
    #[test]
    fn test_validate_genesis_block() {
        // Mainnet genesis block
        let genesis = BlockHeader {
            version: 4,
            prev_block: array![0; 32],  // All zeros
            merkle_root: array![/* genesis merkle root */],
            final_sapling_root: array![/* genesis sapling root */],
            time: 1477641360,  // Genesis timestamp
            bits: 0x1f07ffff,
            nonce: array![/* genesis nonce */],
            solution: array![/* genesis solution */],
            hash: array![/* genesis hash */],
        };

        let result = validate_block_header(
            @genesis,
            array![].span(),
            0,  // Height 0
            false  // Pre-Blossom
        );

        assert(result.is_ok(), 'Genesis should be valid');
    }
    ```

20. **Real block data tests**

    Create test data files:
    ```bash
    mkdir -p test_vectors
    # Add mainnet block data
    # - Genesis block (height 0)
    # - Block 1
    # - Sapling activation (419,200)
    # - Blossom activation (653,600)
    # - Recent block
    ```

**Deliverable:** ✅ Full block validation pipeline

---

#### Days 11-15 (Week 3): Testing & Documentation ⏱️ 20 hours

21. **Comprehensive test suite**

    - Bitcoin test vectors for SHA-256
    - Zcash test vectors for Blake2b
    - Known Equihash solutions
    - Mainnet blocks at different heights
    - Edge cases (malformed headers, invalid PoW)

22. **Performance benchmarks**

    ```cairo
    #[test]
    fn bench_sha256d() {
        // Measure Cairo steps for block hash
    }

    #[test]
    fn bench_equihash() {
        // Measure Cairo steps for full verification
    }

    #[test]
    fn bench_full_validation() {
        // Measure total block validation cost
    }
    ```

23. **Update documentation**

    - Update README with "90% complete" status
    - Document all test vectors
    - Add usage examples
    - Performance metrics

24. **Code cleanup**

    - Remove TODOs and placeholders
    - Add comprehensive comments
    - Format code
    - Update module exports

**Deliverable:** ✅ Production-ready implementation

---

## 📊 Success Metrics

### Week 1 Milestones

- [ ] SHA-256d working with test vectors
- [ ] Difficulty validation with u256
- [ ] TX merkle tree complete
- [ ] Blake2b 50% done

### Week 2 Milestones

- [ ] Blake2b 100% complete
- [ ] Equihash verification working
- [ ] Full block validation pipeline
- [ ] Genesis block validates

### Week 3 Milestones

- [ ] All mainnet test blocks validate
- [ ] Performance benchmarks complete
- [ ] Documentation updated
- [ ] Ready for production use

---

## 🎯 Final Deliverables

### Code (2,200 LOC total)

```
src/
├── crypto/
│   ├── sha256.cairo (150 LOC) ✅
│   ├── blake2b.cairo (400 LOC) ⚠️
│   └── pedersen.cairo (132 LOC) ✅
├── verification/
│   ├── difficulty.cairo (350 LOC) ✅
│   ├── equihash.cairo (450 LOC) ✅
│   ├── merkle.cairo (400 LOC) ✅
│   └── block_validator.cairo (200 LOC) ⚠️
├── utils/
│   └── u256.cairo (100 LOC) ⚠️
└── types/
    └── block_header.cairo (284 LOC) ✅
```

### Tests (500 LOC)

- Unit tests for each module
- Integration tests
- Mainnet block validation
- Performance benchmarks

### Documentation

- [x] ZCASH_SPEC_VS_IMPLEMENTATION.md (gap analysis)
- [x] ALEXANDRIA_LIBRARY_ANALYSIS.md (library usage)
- [x] HASH_FUNCTIONS_SUMMARY.md (requirements)
- [ ] IMPLEMENTATION_COMPLETE.md (final status)
- [ ] API_REFERENCE.md (usage guide)

---

## 🚧 Risk Management

### High Risk Items

1. **Blake2b Complexity**
   - **Risk:** Implementation bugs in compression function
   - **Mitigation:** Use SHA-512 as reference, extensive testing
   - **Contingency:** Ask for help from Cairo community

2. **Equihash Performance**
   - **Risk:** Too many Cairo steps (>10M)
   - **Mitigation:** Profile early, optimize critical paths
   - **Contingency:** Simplify or use hints

3. **Test Vector Availability**
   - **Risk:** Hard to find Zcash test vectors
   - **Mitigation:** Extract from zcashd test suite
   - **Contingency:** Generate our own with zcashd

### Medium Risk Items

4. **Alexandria Compatibility**
   - **Risk:** Version mismatch
   - **Mitigation:** Check early, test thoroughly
   - **Contingency:** Use core Cairo SHA-256 instead

5. **Edge Cases**
   - **Risk:** Missing consensus rules
   - **Mitigation:** Cross-reference with spec
   - **Contingency:** Add after discovery

---

## 📞 Help & Resources

### When Stuck

1. **Alexandria Issues:** https://github.com/keep-starknet-strange/alexandria/issues
2. **Cairo Community:** Starknet Discord
3. **Zcash Spec:** docs/protocol.pdf
4. **librustzcash:** https://github.com/zcash/librustzcash (reference implementation)

### Key References

- Alexandria documentation
- Zcash Protocol Specification
- Bitcoin Core (for SHA-256d)
- Equihash paper (for algorithm details)

---

## ✅ Definition of Done

**Block validation is complete when:**

1. ✅ All 3 hash functions working (SHA-256d, Blake2b, Pedersen)
2. ✅ Genesis block validates successfully
3. ✅ Sapling activation block validates
4. ✅ Blossom activation block validates
5. ✅ Recent mainnet block validates
6. ✅ All tests passing (>50 test cases)
7. ✅ Documentation complete
8. ✅ Performance acceptable (<10M Cairo steps per block)

---

## 🚀 Next Immediate Actions

**Today (Day 1):**

1. Add Alexandria dependencies to Scarb.toml
2. Create `src/crypto/sha256.cairo`
3. Implement SHA-256d wrapper
4. Test with "hello" vector
5. Commit progress

**Tomorrow (Day 2):**

6. Create `src/utils/u256.cairo`
7. Update difficulty.cairo
8. Test with genesis block bits
9. Commit progress

**This Week:**

10. Complete merkle trees
11. Start Blake2b implementation
12. Daily commits to track progress

---

**Created:** November 17, 2024
**Target Completion:** December 8, 2024 (3 weeks)
**Status:** Ready to start! 🚀
