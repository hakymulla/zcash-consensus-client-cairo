/// Pedersen hash wrapper for Cairo native implementation
/// Used for note commitments and merkle trees

use core::pedersen::pedersen;

/// Compute Pedersen hash of two field elements
pub fn hash_pedersen(left: felt252, right: felt252) -> felt252 {
    pedersen(left, right)
}

/// Note commitment using Pedersen hash
#[derive(Drop, Copy, Serde, Debug)]
pub struct NoteCommitment {
    pub value: felt252,
}

/// Trait for note commitment operations
pub trait NoteCommitmentTrait {
    fn commit(value: u64, recipient: felt252, rho: felt252, rcm: felt252) -> NoteCommitment;
    fn verify(self: @NoteCommitment, expected: felt252) -> bool;
}

impl NoteCommitmentImpl of NoteCommitmentTrait {
    /// Create note commitment from components
    fn commit(
        value: u64,
        recipient: felt252,
        rho: felt252,
        rcm: felt252
    ) -> NoteCommitment {
        // Simplified commitment scheme
        // Real implementation would follow Zcash protocol exactly
        let h1 = pedersen(value.into(), recipient);
        let h2 = pedersen(h1, rho);
        let commitment = pedersen(h2, rcm);

        NoteCommitment { value: commitment }
    }

    /// Verify commitment matches expected value
    fn verify(self: @NoteCommitment, expected: felt252) -> bool {
        *self.value == expected
    }
}

/// Merkle tree node using Pedersen hash
#[derive(Drop, Copy, Serde, Debug)]
pub struct MerkleNode {
    pub hash: felt252,
    pub height: u32,
}

/// Compute parent hash from two children
pub fn merkle_hash(left: felt252, right: felt252) -> felt252 {
    pedersen(left, right)
}

/// Incremental Merkle tree for note commitments
#[derive(Drop, Serde)]
pub struct IncrementalMerkleTree {
    /// Current root hash
    pub root: felt252,

    /// Frontier nodes for incremental updates
    pub frontier: Array<felt252>,

    /// Tree depth
    pub depth: u32,
}

/// Trait for incremental merkle tree operations
pub trait IncrementalMerkleTreeTrait {
    fn new(depth: u32) -> IncrementalMerkleTree;
    fn append(ref self: IncrementalMerkleTree, leaf: felt252);
    fn witness(self: @IncrementalMerkleTree, position: u32) -> Array<felt252>;
}

impl IncrementalMerkleTreeImpl of IncrementalMerkleTreeTrait {
    /// Create new empty tree
    fn new(depth: u32) -> IncrementalMerkleTree {
        IncrementalMerkleTree {
            root: 0,
            frontier: ArrayTrait::new(),
            depth,
        }
    }

    /// Append a new commitment to the tree
    fn append(ref self: IncrementalMerkleTree, leaf: felt252) {
        // Simplified incremental update
        // Real implementation would handle frontier properly
        self.frontier.append(leaf);

        // Update root inline
        if !self.frontier.is_empty() {
            // Simplified root calculation
            // Real implementation would build full tree path
            let mut current = *self.frontier[0];
            let mut i = 1;

            loop {
                if i >= self.frontier.len() {
                    break;
                }
                current = merkle_hash(current, *self.frontier[i]);
                i += 1;
            };

            self.root = current;
        }
    }

    /// Get witness path for a position
    fn witness(self: @IncrementalMerkleTree, position: u32) -> Array<felt252> {
        // Returns authentication path for merkle proof
        // Simplified - real implementation would compute full path
        let mut path = ArrayTrait::new();

        // Add siblings along path to root
        let frontier = self.frontier.span();
        let mut i = 0;
        loop {
            if i >= frontier.len() || i >= 10 {
                break;
            }
            path.append(*frontier[i]);
            i += 1;
        };

        path
    }
}