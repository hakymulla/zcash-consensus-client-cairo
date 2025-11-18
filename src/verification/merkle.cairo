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
        return Result::Ok(tx_hashes[0].clone());
    }

    // Build tree level by level
    let mut current_level: Array<Array<u8>> = ArrayTrait::new();

    // Copy initial hashes
    let mut i = 0;
    loop {
        if i >= tx_hashes.len() {
            break;
        }
        current_level.append(tx_hashes[i].clone());
        i += 1;
    };

    // Process levels until we have single root
    loop {
        if current_level.len() == 1 {
            break;
        }

        let mut next_level: Array<Array<u8>> = ArrayTrait::new();
        let mut j: usize = 0;

        loop {
            if j >= current_level.len() {
                break;
            }

            if j + 1 < current_level.len() {
                // Hash pair
                let left = current_level[j];
                let right = current_level[j + 1];
                let combined = hash_pair(@left, @right);
                next_level.append(combined);
                j += 2;
            } else {
                // Odd number - duplicate last element
                let last = current_level[j];
                let combined = hash_pair(@last, @last);
                next_level.append(combined);
                j += 1;
            }
        };

        current_level = next_level;
    };

    Result::Ok(current_level[0].clone())
}

/// Hash a pair of nodes using SHA-256d
///
/// SHA-256d(a, b) = SHA256(SHA256(a || b))
///
/// TODO: Implement when SHA-256 is ready
fn hash_pair(left: @Array<u8>, right: @Array<u8>) -> Array<u8> {
    // Concatenate left and right
    let mut combined = ArrayTrait::new();

    let mut i = 0;
    loop {
        if i >= left.len() {
            break;
        }
        combined.append(*left[i]);
        i += 1;
    };

    let mut j = 0;
    loop {
        if j >= right.len() {
            break;
        }
        combined.append(*right[j]);
        j += 1;
    };

    // TODO: Apply SHA-256d
    // For now, return placeholder
    combined
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
            tree.append(output.cmu)?;
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
    if tree.size() != *block.sapling_commitment_tree_size.into() {
        return Result::Err(
            ZcashError::ValidationError("Sapling tree size mismatch")
        );
    }

    Result::Ok(())
}

/// Full merkle validation for a block
pub fn validate_block_merkle_roots(
    header: @BlockHeader,
    block: @CompactBlock,
    prev_sapling_root: @Array<u8>,
    prev_sapling_size: u64,
) -> Result<(), ZcashError> {
    // 1. Validate transaction merkle root
    // TODO: Extract transaction hashes from block
    let tx_hashes = ArrayTrait::new();  // Placeholder
    // validate_tx_merkle_root(header, tx_hashes.span())?;

    // 2. Validate Sapling commitment tree root
    validate_sapling_root(header, prev_sapling_root, prev_sapling_size, block)?;

    Result::Ok(())
}

#[cfg(test)]
mod tests {
    use super::{compute_tx_merkle_root, SaplingTreeTrait, SAPLING_TREE_DEPTH};

    #[test]
    fn test_sapling_tree_depth() {
        assert!(SAPLING_TREE_DEPTH == 32, "Sapling tree should be depth 32");
    }

    #[test]
    fn test_sapling_tree_initialization() {
        let root = ArrayTrait::new();
        let tree = SaplingTreeTrait::from_root(@root, 0);
        assert!(tree.size() == 0, "New tree should have size 0");
    }
}
