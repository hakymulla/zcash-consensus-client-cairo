/// Compact Block data structures for ZIP-307 compliance
/// Implements bandwidth-efficient block representation

use core::array::ArrayTrait;

/// Block height type
pub type BlockHeight = u64;

/// Transaction ID type
pub type TxId = felt252;

/// Compact Block - ZIP-307 compliant structure
#[derive(Drop, Serde, Debug)]
pub struct CompactBlock {
    /// Block height in the chain
    pub height: BlockHeight,

    /// Block hash
    pub hash: felt252,

    /// Previous block hash for chain validation
    pub prev_hash: felt252,

    /// Compact transactions in this block
    pub vtx: Array<CompactTx>,

    /// Sapling commitment tree size after this block
    pub sapling_commitment_tree_size: u32,

    /// Orchard commitment tree size after this block
    pub orchard_commitment_tree_size: u32,

    /// Block timestamp
    pub time: u32,
}

/// Compact Transaction - contains only essential data
#[derive(Drop, Serde, Debug)]
pub struct CompactTx {
    /// Transaction index in the block
    pub index: u64,

    /// Transaction hash
    pub hash: TxId,

    /// Compact spend descriptions (nullifiers only)
    pub spends: Array<CompactSpend>,

    /// Compact output descriptions
    pub outputs: Array<CompactOutput>,

    /// Orchard actions (spends and outputs combined)
    pub actions: Array<CompactOrchardAction>,
}

/// Compact Spend - only contains nullifier (90% bandwidth reduction)
#[derive(Drop, Serde, Debug)]
pub struct CompactSpend {
    /// Nullifier to prevent double-spending
    pub nf: felt252,
}

/// Compact Output - truncated ciphertext for bandwidth efficiency
#[derive(Drop, Serde, Debug)]
pub struct CompactOutput {
    /// Note commitment (cmu)
    pub cmu: felt252,

    /// Ephemeral public key for note encryption
    pub epk: felt252,

    /// First 52 bytes of encrypted note (out of 580 total)
    /// Enough for trial decryption but 80% bandwidth reduction
    pub ciphertext: Array<u8>, // Must be exactly 52 bytes
}

/// Compact Orchard Action - combined spend and output
#[derive(Drop, Serde, Debug)]
pub struct CompactOrchardAction {
    /// Nullifier for spent note
    pub nullifier: felt252,

    /// Commitment for new note
    pub cmx: felt252,

    /// Ephemeral public key
    pub ephemeral_key: felt252,

    /// Truncated ciphertext (52 bytes)
    pub ciphertext: Array<u8>,
}

/// Block metadata for caching
#[derive(Drop, Serde, Debug)]
pub struct CompactBlockMeta {
    pub height: BlockHeight,
    pub hash: felt252,
    pub sapling_outputs_count: u32,
    pub orchard_actions_count: u32,
    pub time: u32,
}

/// Constants for ZIP-307 compliance
pub const COMPACT_NOTE_SIZE: usize = 52; // Truncated ciphertext size
pub const FULL_NOTE_SIZE: usize = 580;   // Full ciphertext size

pub trait CompactBlockTrait {
    fn total_outputs(self: @CompactBlock) -> u32;
    fn validates_against_prev(self: @CompactBlock, prev: @CompactBlock) -> bool;
}

impl CompactBlockImpl of CompactBlockTrait {
    /// Calculate total number of outputs in block
    fn total_outputs(self: @CompactBlock) -> u32 {
        let mut count: u32 = 0;
        let vtx = self.vtx.span();

        let mut i: usize = 0;
        loop {
            if i >= vtx.len() {
                break;
            }
            let tx = vtx.at(i);
            count += tx.outputs.len().into();
            count += tx.actions.len().into();
            i += 1;
        };

        count
    }

    /// Validate block header linkage
    fn validates_against_prev(self: @CompactBlock, prev: @CompactBlock) -> bool {
        *self.prev_hash == *prev.hash && *self.height == *prev.height + 1
    }
}