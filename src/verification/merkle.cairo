/// Merkle Tree Validation for Zcash
///
/// Two types of merkle trees in Zcash:
/// 1. Transaction Merkle Tree - SHA-256d hash of transactions (Bitcoin-style)
/// 2. Sapling Note Commitment Tree - Incremental tree with Pedersen hashes
///
/// Reference: librustzcash/zcash_primitives/src/merkle_tree.rs

use crate::types::block_header::BlockHeader;
use crate::types::compact_block::{CompactBlock, CompactTx};
use crate::utils::errors::ZcashError;
use crate::crypto::sha256d;
use alexandria_bytes::byte_array_ext::{ByteArrayTraitExt, ByteArrayIntoArrayU8};

/// Transaction Merkle Tree Validation
/// Uses SHA-256d (double SHA-256) like Bitcoin

/// Compute merkle root from transaction hashes
///
/// Algorithm (Bitcoin-style):
/// 1. Start with leaf level (transaction hashes)
/// 2. If odd number of elements, duplicate the last one
/// 3. Hash pairs: SHA256d(left || right)
/// 4. Repeat until single root hash
///
/// Example with 4 transactions [A, B, C, D]:
///        ROOT
///       /    \
///    H(A,B)  H(C,D)
///     / \      / \
///    A   B    C   D
pub fn compute_tx_merkle_root(
    tx_hashes: Span<Array<u8>>
) -> Result<Array<u8>, ZcashError> {
    if tx_hashes.len() == 0 {
        return Result::Err(ZcashError::ValidationError("No transactions"));
    }

    // Single transaction - return its hash
    if tx_hashes.len() == 1 {
        return Result::Ok(copy_array(tx_hashes[0]));
    }

    // Build tree level by level
    let mut current_level: Array<Array<u8>> = ArrayTrait::new();

    // Copy initial hashes
    let mut i = 0;
    loop {
        if i >= tx_hashes.len() {
            break;
        }
        current_level.append(copy_array(tx_hashes[i]));
        i += 1;
    };

    // Process levels until we have single root
    loop {
        if current_level.len() == 1 {
            break;
        }

        let mut next_level: Array<Array<u8>> = ArrayTrait::new();
        let mut j: usize = 0;
        let level_span = current_level.span();

        loop {
            if j >= level_span.len() {
                break;
            }

            if j + 1 < level_span.len() {
                // Hash pair (span indexing gives @T)
                let combined = hash_pair(level_span[j], level_span[j + 1]);
                next_level.append(combined);
                j += 2;
            } else {
                // Odd number - duplicate last element
                let combined = hash_pair(level_span[j], level_span[j]);
                next_level.append(combined);
                j += 1;
            }
        };

        current_level = next_level;
    };

    // Return the final root
    let root_span = current_level.span();
    Result::Ok(copy_array(root_span[0]))
}

/// Helper: Copy array from snapshot
fn copy_array(arr: @Array<u8>) -> Array<u8> {
    let mut result = ArrayTrait::new();
    let mut i: u32 = 0;
    while i < arr.len() {
        result.append(*arr[i]);
        i += 1;
    };
    result
}

/// Hash a pair of nodes using SHA-256d
///
/// This is the standard Bitcoin/Zcash transaction merkle tree hash function:
/// SHA-256d(a || b) = SHA-256(SHA-256(a || b))
///
/// #### Arguments
/// * `left` - Left hash (32 bytes)
/// * `right` - Right hash (32 bytes)
///
/// #### Returns
/// * `Array<u8>` - Combined hash (32 bytes)
///
/// #### Reference
/// Zcash Protocol Specification Section 7.1
fn hash_pair(left: @Array<u8>, right: @Array<u8>) -> Array<u8> {
    // Concatenate left and right (64 bytes total)
    let mut combined = ArrayTrait::new();

    let mut i: u32 = 0;
    while i < left.len() {
        combined.append(*left[i]);
        i += 1;
    };

    let mut j: u32 = 0;
    while j < right.len() {
        combined.append(*right[j]);
        j += 1;
    };

    // Apply SHA-256d: SHA-256(SHA-256(combined))
    sha256d(combined)
}

/// Validate transaction merkle root in block header
pub fn validate_tx_merkle_root(
    header: @BlockHeader,
    tx_hashes: Span<Array<u8>>
) -> Result<(), ZcashError> {
    let computed_root = compute_tx_merkle_root(tx_hashes)?;

    // Compare with header's merkle_root
    if computed_root.len() != header.merkle_root.len() {
        return Result::Err(
            ZcashError::ValidationError("Merkle root size mismatch")
        );
    }

    let mut i = 0;
    loop {
        if i >= computed_root.len() {
            break;
        }
        if *computed_root[i] != *header.merkle_root[i] {
            return Result::Err(
                ZcashError::ValidationError("Merkle root mismatch")
            );
        }
        i += 1;
    };

    Result::Ok(())
}

/// Sapling Note Commitment Tree
///
/// This is an incremental Merkle tree that tracks all Sapling note commitments.
/// Unlike the transaction merkle tree, this tree persists across blocks.
///
/// Properties:
/// - Depth: 32 (can hold 2^32 notes)
/// - Hash function: Pedersen hash
/// - Incremental: Can append without rebuilding entire tree

/// Sapling tree depth
pub const SAPLING_TREE_DEPTH: u8 = 32;

/// Incremental Merkle Tree for Sapling
#[derive(Drop, Debug)]
pub struct SaplingTree {
    /// Current root hash
    pub root: Array<u8>,

    /// Number of leaves in the tree
    pub size: u64,

    /// Cached authentication path for recent leaves
    pub auth_path: Array<Array<u8>>,
}

pub trait SaplingTreeTrait {
    /// Create tree from existing root
    fn from_root(root: @Array<u8>, size: u64) -> SaplingTree;

    /// Append a new note commitment
    fn append(ref self: SaplingTree, commitment: felt252) -> Result<(), ZcashError>;

    /// Get current root
    fn root(self: @SaplingTree) -> Array<u8>;

    /// Get tree size
    fn size(self: @SaplingTree) -> u64;
}

impl SaplingTreeImpl of SaplingTreeTrait {
    fn from_root(root: @Array<u8>, size: u64) -> SaplingTree {
        SaplingTree {
            root: root.clone(),
            size,
            auth_path: ArrayTrait::new(),
        }
    }

    fn append(ref self: SaplingTree, commitment: felt252) -> Result<(), ZcashError> {
        // TODO: Implement incremental tree append
        // This requires Pedersen hash implementation
        self.size += 1;
        Result::Ok(())
    }

    fn root(self: @SaplingTree) -> Array<u8> {
        self.root.clone()
    }

    fn size(self: @SaplingTree) -> u64 {
        *self.size
    }
}

/// Validate Sapling tree root in block header
///
/// Algorithm:
/// 1. Start with previous block's Sapling root
/// 2. Append all new note commitments from this block
/// 3. Verify computed root matches header's final_sapling_root
pub fn validate_sapling_root(
    header: @BlockHeader,
    prev_root: @Array<u8>,
    prev_size: u64,
    block: @CompactBlock
) -> Result<(), ZcashError> {
    // Initialize tree from previous state
    let mut tree = SaplingTreeTrait::from_root(prev_root, prev_size);

    // Append all new commitments from this block
    let vtx = block.vtx.span();
    let mut i = 0;
    loop {
        if i >= vtx.len() {
            break;
        }

        let tx = vtx[i];

        // Add Sapling outputs
        let outputs = tx.outputs.span();
        let mut j = 0;
        loop {
            if j >= outputs.len() {
                break;
            }
            let output = outputs[j];
            tree.append(*output.cmu)?;
            j += 1;
        };

        i += 1;
    };

    // Verify root matches
    let computed_root = tree.root();

    if computed_root.len() != header.final_sapling_root.len() {
        return Result::Err(
            ZcashError::ValidationError("Sapling root size mismatch")
        );
    }

    let mut k = 0;
    loop {
        if k >= computed_root.len() {
            break;
        }
        if *computed_root[k] != *header.final_sapling_root[k] {
            return Result::Err(
                ZcashError::ValidationError("Sapling root mismatch")
            );
        }
        k += 1;
    };

    // Verify tree size matches
    if tree.size() != (*block.sapling_commitment_tree_size).into() {
        return Result::Err(
            ZcashError::ValidationError("Sapling tree size mismatch")
        );
    }

    Result::Ok(())
}

/// Extract transaction hashes from CompactBlock
///
/// Converts CompactTx hashes from felt252 to Array<u8> (32 bytes)
/// for merkle tree validation.
///
/// # Arguments
/// * `block` - The compact block containing transactions
///
/// # Returns
/// * `Array<Array<u8>>` - Array of 32-byte transaction hashes
fn extract_tx_hashes(block: @CompactBlock) -> Array<Array<u8>> {
    let mut tx_hashes = ArrayTrait::new();
    let vtx = block.vtx.span();

    let mut i: usize = 0;
    loop {
        if i >= vtx.len() {
            break;
        }

        let tx = vtx[i];

        // Convert felt252 → u256 → ByteArray → Array<u8>
        let hash_u256: u256 = (*tx.hash).into();

        // Create ByteArray and append u256
        let mut byte_array: ByteArray = Default::default();
        ByteArrayTraitExt::append_u256(ref byte_array, hash_u256);

        // Convert ByteArray → Array<u8>
        let hash_bytes: Array<u8> = byte_array.into();

        tx_hashes.append(hash_bytes);
        i += 1;
    };

    tx_hashes
}

/// Full merkle validation for a block
pub fn validate_block_merkle_roots(
    header: @BlockHeader,
    block: @CompactBlock,
    prev_sapling_root: @Array<u8>,
    prev_sapling_size: u64,
) -> Result<(), ZcashError> {
    // 1. Validate transaction merkle root
    let tx_hashes = extract_tx_hashes(block);
    validate_tx_merkle_root(header, tx_hashes.span())?;

    // 2. Validate Sapling commitment tree root
    validate_sapling_root(header, prev_sapling_root, prev_sapling_size, block)?;

    Result::Ok(())
}

#[cfg(test)]
mod tests {
    use super::{compute_tx_merkle_root, hash_pair, SaplingTreeTrait, SAPLING_TREE_DEPTH};

    fn create_test_hash(value: u8) -> Array<u8> {
        let mut hash = ArrayTrait::new();
        let mut i: u32 = 0;
        while i < 32 {
            hash.append(value);
            i += 1;
        };
        hash
    }

    #[test]
    fn test_hash_pair() {
        let left = create_test_hash(0xAA);
        let right = create_test_hash(0xBB);

        let result = hash_pair(@left, @right);

        // Result should be 32 bytes (SHA-256d output)
        assert(result.len() == 32, 'Hash pair should be 32 bytes');
    }

    #[test]
    fn test_single_transaction_merkle_root() {
        let mut tx_hashes: Array<Array<u8>> = ArrayTrait::new();
        tx_hashes.append(create_test_hash(0x01));

        let result = compute_tx_merkle_root(tx_hashes.span());

        assert(result.is_ok(), 'Should succeed');
        let root = result.unwrap();

        // Single transaction - root should equal the transaction hash
        assert(root.len() == 32, 'Root should be 32 bytes');
        assert(*root[0] == 0x01, 'Root should match input');
    }

    #[test]
    fn test_two_transaction_merkle_root() {
        let mut tx_hashes: Array<Array<u8>> = ArrayTrait::new();
        tx_hashes.append(create_test_hash(0x01));
        tx_hashes.append(create_test_hash(0x02));

        let result = compute_tx_merkle_root(tx_hashes.span());

        assert(result.is_ok(), 'Should succeed');
        let root = result.unwrap();
        assert(root.len() == 32, 'Root should be 32 bytes');
    }

    #[test]
    fn test_odd_transaction_merkle_root() {
        // Test with 3 transactions (odd number)
        let mut tx_hashes: Array<Array<u8>> = ArrayTrait::new();
        tx_hashes.append(create_test_hash(0x01));
        tx_hashes.append(create_test_hash(0x02));
        tx_hashes.append(create_test_hash(0x03));

        let result = compute_tx_merkle_root(tx_hashes.span());

        assert(result.is_ok(), 'Should succeed');
        let root = result.unwrap();
        assert(root.len() == 32, 'Root should be 32 bytes');
    }

    #[test]
    fn test_empty_merkle_root() {
        let tx_hashes: Array<Array<u8>> = ArrayTrait::new();
        let result = compute_tx_merkle_root(tx_hashes.span());

        assert(result.is_err(), 'Should fail for empty');
    }

    #[test]
    fn test_sapling_tree_depth() {
        assert(SAPLING_TREE_DEPTH == 32, 'Depth should be 32');
    }

    #[test]
    fn test_sapling_tree_initialization() {
        let root = ArrayTrait::new();
        let tree = SaplingTreeTrait::from_root(@root, 0);
        assert(tree.size() == 0, 'New tree should have size 0');
    }
}
