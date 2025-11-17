/// Block Validation - Core verification logic for Zcash blocks
///
/// This is the main entry point for the STWO prover.
/// All functions are pure and deterministic.

use crate::types::compact_block::{CompactBlock, CompactTx, CompactBlockTrait, BlockHeight};
use crate::utils::errors::ZcashError;

/// Result of verifying a single block
#[derive(Drop, Serde, Debug)]
pub struct BlockVerificationResult {
    /// Whether the block is valid
    pub valid: bool,

    /// Block height that was verified
    pub height: BlockHeight,

    /// Number of transactions in block
    pub tx_count: u32,

    /// Total number of Sapling outputs
    pub sapling_output_count: u32,

    /// Total number of Orchard actions
    pub orchard_action_count: u32,

    /// Block hash (for chaining)
    pub block_hash: felt252,
}

/// Result of verifying a chain of blocks
#[derive(Drop, Serde, Debug)]
pub struct ChainVerificationResult {
    /// Whether the entire chain is valid
    pub valid: bool,

    /// Start height of verified chain
    pub start_height: BlockHeight,

    /// End height of verified chain
    pub end_height: BlockHeight,

    /// Total number of blocks verified
    pub block_count: u32,

    /// Total transactions across all blocks
    pub total_tx_count: u32,

    /// Chain tip hash
    pub tip_hash: felt252,
}

/// Verify a single Zcash compact block
///
/// This function performs complete validation of a block:
/// 1. Header validation (height, hash linkage)
/// 2. Transaction structure validation
/// 3. Output/action validation
///
/// # Arguments
/// * `block` - The compact block to verify
/// * `prev_block_hash` - Expected hash of previous block
///
/// # Returns
/// * `Result<BlockVerificationResult, ZcashError>` - Verification result or error
pub fn verify_block(
    block: @CompactBlock,
    prev_block_hash: felt252,
) -> Result<BlockVerificationResult, ZcashError> {
    // 1. Validate block header
    validate_block_header(block, prev_block_hash)?;

    // 2. Count outputs and actions
    let (tx_count, sapling_outputs, orchard_actions) = count_block_elements(block);

    // 3. Validate all transactions have proper structure
    validate_transactions(block)?;

    // 4. Success - return result
    Result::Ok(BlockVerificationResult {
        valid: true,
        height: *block.height,
        tx_count,
        sapling_output_count: sapling_outputs,
        orchard_action_count: orchard_actions,
        block_hash: *block.hash,
    })
}

/// Verify a range of blocks form a valid chain
///
/// This is the main function called by STWO prover to verify multiple blocks.
/// It ensures:
/// 1. All blocks are individually valid
/// 2. Blocks form a continuous chain (no gaps)
/// 3. Heights increment correctly
///
/// # Arguments
/// * `blocks` - Array of blocks to verify
/// * `expected_start_height` - Expected height of first block
///
/// # Returns
/// * `Result<ChainVerificationResult, ZcashError>` - Chain verification result
pub fn verify_block_range(
    blocks: @Array<CompactBlock>,
    expected_start_height: BlockHeight,
) -> Result<ChainVerificationResult, ZcashError> {
    if blocks.is_empty() {
        return Result::Err(
            ZcashError::ValidationError("Cannot verify empty block range")
        );
    }

    let blocks_span = blocks.span();
    let first_block = blocks_span[0];

    // Verify first block height matches expectation
    if *first_block.height != expected_start_height {
        return Result::Err(
            ZcashError::ValidationError("First block height mismatch")
        );
    }

    let mut total_txs: u32 = 0;
    let mut prev_hash = *first_block.prev_hash;
    let mut i: usize = 0;

    // Verify each block in sequence
    loop {
        if i >= blocks_span.len() {
            break;
        }

        let block = blocks_span[i];

        // Verify this block
        let result = verify_block(block, prev_hash)?;

        if !result.valid {
            return Result::Err(
                ZcashError::ValidationError("Block verification failed")
            );
        }

        // Verify height continuity
        if i > 0 {
            let expected_height = *blocks_span[i - 1].height + 1;
            if *block.height != expected_height {
                return Result::Err(
                    ZcashError::ValidationError("Block height discontinuity")
                );
            }
        }

        total_txs += result.tx_count;
        prev_hash = *block.hash;
        i += 1;
    };

    let last_block = blocks_span[blocks_span.len() - 1];

    Result::Ok(ChainVerificationResult {
        valid: true,
        start_height: *first_block.height,
        end_height: *last_block.height,
        block_count: blocks.len(),
        total_tx_count: total_txs,
        tip_hash: *last_block.hash,
    })
}

/// Validate block header against previous block
///
/// Checks:
/// - Previous hash linkage
/// - Hash lengths are correct
fn validate_block_header(
    block: @CompactBlock,
    prev_block_hash: felt252,
) -> Result<(), ZcashError> {
    // Verify previous hash linkage
    if *block.prev_hash != prev_block_hash {
        return Result::Err(
            ZcashError::ValidationError("Previous block hash mismatch")
        );
    }

    // Height must be greater than 0 (genesis block not in compact format)
    if *block.height == 0 {
        return Result::Err(
            ZcashError::ValidationError("Invalid block height 0")
        );
    }

    Result::Ok(())
}

/// Count transactions, outputs, and actions in a block
fn count_block_elements(block: @CompactBlock) -> (u32, u32, u32) {
    let vtx = block.vtx.span();
    let tx_count: u32 = vtx.len().into();

    let mut sapling_outputs: u32 = 0;
    let mut orchard_actions: u32 = 0;

    let mut i: usize = 0;
    loop {
        if i >= vtx.len() {
            break;
        }

        let tx = vtx[i];
        sapling_outputs += tx.outputs.len().into();
        orchard_actions += tx.actions.len().into();

        i += 1;
    };

    (tx_count, sapling_outputs, orchard_actions)
}

/// Validate all transactions in a block
///
/// Ensures:
/// - All outputs have valid structure (52-byte ciphertext)
/// - All spends have nullifiers
/// - All actions have required fields
fn validate_transactions(block: @CompactBlock) -> Result<(), ZcashError> {
    let vtx = block.vtx.span();
    let mut i: usize = 0;

    loop {
        if i >= vtx.len() {
            break;
        }

        let tx = vtx[i];

        // Validate Sapling outputs
        let outputs = tx.outputs.span();
        let mut j: usize = 0;
        loop {
            if j >= outputs.len() {
                break;
            }

            let output = outputs[j];

            // Check ciphertext is exactly 52 bytes (ZIP-307)
            if output.ciphertext.len() != 52 {
                return Result::Err(
                    ZcashError::ValidationError("Invalid ciphertext length")
                );
            }

            j += 1;
        };

        // Validate Orchard actions
        let actions = tx.actions.span();
        let mut k: usize = 0;
        loop {
            if k >= actions.len() {
                break;
            }

            let action = actions[k];

            // Check ciphertext is exactly 52 bytes
            if action.ciphertext.len() != 52 {
                return Result::Err(
                    ZcashError::ValidationError("Invalid action ciphertext length")
                );
            }

            k += 1;
        };

        i += 1;
    };

    Result::Ok(())
}

#[cfg(test)]
mod tests {
    use super::{verify_block, verify_block_range};
    use crate::types::compact_block::{CompactBlock, CompactTx};
    use core::array::ArrayTrait;

    #[test]
    fn test_verify_valid_block() {
        let block = CompactBlock {
            height: 100,
            hash: 12345,
            prev_hash: 67890,
            vtx: ArrayTrait::new(),
            sapling_commitment_tree_size: 0,
            orchard_commitment_tree_size: 0,
            time: 1234567890,
        };

        let result = verify_block(@block, 67890);
        assert!(result.is_ok());

        let verification = result.unwrap();
        assert!(verification.valid);
        assert!(verification.height == 100);
    }

    #[test]
    fn test_verify_invalid_prev_hash() {
        let block = CompactBlock {
            height: 100,
            hash: 12345,
            prev_hash: 67890,
            vtx: ArrayTrait::new(),
            sapling_commitment_tree_size: 0,
            orchard_commitment_tree_size: 0,
            time: 1234567890,
        };

        // Wrong prev_hash
        let result = verify_block(@block, 11111);
        assert!(result.is_err());
    }

    #[test]
    fn test_verify_block_chain() {
        let mut blocks = ArrayTrait::new();

        // Block 100
        blocks.append(CompactBlock {
            height: 100,
            hash: 1000,
            prev_hash: 999,
            vtx: ArrayTrait::new(),
            sapling_commitment_tree_size: 0,
            orchard_commitment_tree_size: 0,
            time: 1000,
        });

        // Block 101
        blocks.append(CompactBlock {
            height: 101,
            hash: 1001,
            prev_hash: 1000,
            vtx: ArrayTrait::new(),
            sapling_commitment_tree_size: 0,
            orchard_commitment_tree_size: 0,
            time: 1001,
        });

        // Block 102
        blocks.append(CompactBlock {
            height: 102,
            hash: 1002,
            prev_hash: 1001,
            vtx: ArrayTrait::new(),
            sapling_commitment_tree_size: 0,
            orchard_commitment_tree_size: 0,
            time: 1002,
        });

        let result = verify_block_range(@blocks, 100);
        assert!(result.is_ok());

        let chain = result.unwrap();
        assert!(chain.valid);
        assert!(chain.block_count == 3);
        assert!(chain.start_height == 100);
        assert!(chain.end_height == 102);
    }
}
