/// Complete Zcash Block Header for Consensus Validation
/// Based on zcash_primitives/src/block.rs
///
/// This represents the full block header as validated by zcashd/zebrad

use core::array::ArrayTrait;

/// Block height type
pub type BlockHeight = u64;

/// Complete Zcash Block Header
/// Reference: librustzcash/zcash_primitives/src/block.rs::BlockHeaderData
#[derive(Drop, Serde, Debug)]
pub struct BlockHeader {
    /// Protocol version (i32 in Zcash)
    /// - Version 4: Sapling and earlier
    /// - Version 5: NU5 (Orchard)
    pub version: i32,

    /// Hash of the previous block header (32 bytes)
    /// Used for chain linkage validation
    pub prev_block: Array<u8>,  // 32 bytes

    /// Merkle root of transactions in this block (32 bytes)
    /// Computed via SHA-256d of transaction hashes
    pub merkle_root: Array<u8>,  // 32 bytes

    /// Final Sapling note commitment tree root (32 bytes)
    /// State of Sapling tree after applying this block
    /// Added in Sapling activation
    pub final_sapling_root: Array<u8>,  // 32 bytes

    /// Block timestamp (Unix epoch seconds)
    pub time: u32,

    /// Difficulty target in compact representation
    /// Encodes the PoW target threshold
    /// Format: see validate_difficulty() for expansion
    pub bits: u32,

    /// Proof-of-work nonce (32 bytes)
    /// Used in Equihash solution computation
    pub nonce: Array<u8>,  // 32 bytes

    /// Equihash solution (1344 bytes for n=200, k=9)
    /// Contains 512 indices encoded in compact format
    /// This is what makes Zcash's PoW ASIC-resistant
    pub solution: Array<u8>,  // 1344 bytes

    /// Block hash (computed, not part of serialized header)
    /// SHA-256d of the serialized header
    pub hash: Array<u8>,  // 32 bytes (computed)
}

/// Compact block header metadata
#[derive(Drop, Serde, Debug)]
pub struct BlockHeaderMeta {
    pub height: BlockHeight,
    pub hash: Array<u8>,
    pub prev_hash: Array<u8>,
    pub time: u32,
    pub bits: u32,
    pub version: i32,
}

/// Constants for block header validation
pub mod constants {
    /// Equihash solution size for n=200, k=9
    /// Calculation: (k+1) * 2^k * (n/(k+1))/8 = 10 * 512 * 20/8 = 1344
    pub const EQUIHASH_SOLUTION_SIZE: usize = 1344;

    /// Number of indices in Equihash solution
    /// 2^k where k=9 → 512 indices
    pub const EQUIHASH_INDICES_COUNT: usize = 512;

    /// Equihash parameter n
    pub const EQUIHASH_N: u32 = 200;

    /// Equihash parameter k
    pub const EQUIHASH_K: u32 = 9;

    /// Block hash size
    pub const BLOCK_HASH_SIZE: usize = 32;

    /// Nonce size
    pub const NONCE_SIZE: usize = 32;

    /// Maximum block time drift (2 hours in seconds)
    pub const MAX_FUTURE_BLOCK_TIME: u32 = 2 * 60 * 60;

    /// Target block spacing before Blossom (150 seconds)
    pub const PRE_BLOSSOM_POW_TARGET_SPACING: u32 = 150;

    /// Target block spacing after Blossom (75 seconds)
    pub const POST_BLOSSOM_POW_TARGET_SPACING: u32 = 75;
}

/// Trait for block header operations
pub trait BlockHeaderTrait {
    /// Validate this header follows from the previous header
    fn validates_against_prev(self: @BlockHeader, prev: @BlockHeader) -> bool;

    /// Check if header fields are well-formed
    fn is_well_formed(self: @BlockHeader) -> bool;

    /// Get the compact metadata
    fn to_meta(self: @BlockHeader, height: BlockHeight) -> BlockHeaderMeta;
}

impl BlockHeaderImpl of BlockHeaderTrait {
    /// Validate block header chain linkage
    fn validates_against_prev(self: @BlockHeader, prev: @BlockHeader) -> bool {
        // Check prev_block hash matches
        if self.prev_block.len() != prev.hash.len() {
            return false;
        }

        let mut i = 0;
        loop {
            if i >= self.prev_block.len() {
                break;
            }
            if *self.prev_block[i] != *prev.hash[i] {
                return false;
            }
            i += 1;
        };

        // Check timestamp is not before previous block
        if *self.time <= *prev.time {
            return false;
        }

        true
    }

    /// Check if header has correct field sizes
    fn is_well_formed(self: @BlockHeader) -> bool {
        // Check all byte arrays have correct lengths
        if self.prev_block.len() != constants::BLOCK_HASH_SIZE {
            return false;
        }

        if self.merkle_root.len() != constants::BLOCK_HASH_SIZE {
            return false;
        }

        if self.final_sapling_root.len() != constants::BLOCK_HASH_SIZE {
            return false;
        }

        if self.nonce.len() != constants::NONCE_SIZE {
            return false;
        }

        if self.solution.len() != constants::EQUIHASH_SOLUTION_SIZE {
            return false;
        }

        if self.hash.len() != constants::BLOCK_HASH_SIZE {
            return false;
        }

        true
    }

    /// Extract metadata
    fn to_meta(self: @BlockHeader, height: BlockHeight) -> BlockHeaderMeta {
        BlockHeaderMeta {
            height,
            hash: self.hash.clone(),
            prev_hash: self.prev_block.clone(),
            time: *self.time,
            bits: *self.bits,
            version: *self.version,
        }
    }
}

/// Helper function to create empty byte arrays
fn empty_32_bytes() -> Array<u8> {
    let mut arr = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= 32 {
            break;
        }
        arr.append(0);
        i += 1;
    };
    arr
}

/// Helper function to create empty solution array
fn empty_solution() -> Array<u8> {
    let mut arr = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= constants::EQUIHASH_SOLUTION_SIZE {
            break;
        }
        arr.append(0);
        i += 1;
    };
    arr
}

#[cfg(test)]
mod tests {
    use super::{BlockHeader, BlockHeaderTrait, empty_32_bytes, empty_solution, constants};

    #[test]
    fn test_header_well_formed() {
        let header = BlockHeader {
            version: 4,
            prev_block: empty_32_bytes(),
            merkle_root: empty_32_bytes(),
            final_sapling_root: empty_32_bytes(),
            time: 1234567890,
            bits: 0x1d00ffff,
            nonce: empty_32_bytes(),
            solution: empty_solution(),
            hash: empty_32_bytes(),
        };

        assert!(header.is_well_formed(), "Header should be well-formed");
    }

    #[test]
    fn test_header_malformed_prev_block() {
        let mut bad_prev = ArrayTrait::new();
        bad_prev.append(0);  // Only 1 byte instead of 32

        let header = BlockHeader {
            version: 4,
            prev_block: bad_prev,
            merkle_root: empty_32_bytes(),
            final_sapling_root: empty_32_bytes(),
            time: 1234567890,
            bits: 0x1d00ffff,
            nonce: empty_32_bytes(),
            solution: empty_solution(),
            hash: empty_32_bytes(),
        };

        assert!(!header.is_well_formed(), "Header should be malformed");
    }

    #[test]
    fn test_validates_against_prev() {
        let mut prev_hash = ArrayTrait::new();
        prev_hash.append(0xAA);  // Distinctive hash
        let mut i: u32 = 1;
        while i < 32 {
            prev_hash.append(0);
            i += 1;
        };

        let prev_header = BlockHeader {
            version: 4,
            prev_block: empty_32_bytes(),
            merkle_root: empty_32_bytes(),
            final_sapling_root: empty_32_bytes(),
            time: 1000,
            bits: 0x1d00ffff,
            nonce: empty_32_bytes(),
            solution: empty_solution(),
            hash: prev_hash.clone(),
        };

        let curr_header = BlockHeader {
            version: 4,
            prev_block: prev_hash,  // Points to prev
            merkle_root: empty_32_bytes(),
            final_sapling_root: empty_32_bytes(),
            time: 2000,  // Later timestamp
            bits: 0x1d00ffff,
            nonce: empty_32_bytes(),
            solution: empty_solution(),
            hash: empty_32_bytes(),
        };

        assert!(
            curr_header.validates_against_prev(@prev_header),
            "Should validate against previous"
        );
    }
}
