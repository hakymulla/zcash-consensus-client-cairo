/// Note Scanner - Trial decryption of Zcash outputs
///
/// This module orchestrates trial decryption to find notes belonging to a wallet.
/// All functions are pure - no storage, just cryptographic operations.

use crate::types::compact_block::{CompactBlock, CompactTx, CompactOutput, BlockHeight};
use crate::crypto::note_encryption::{
    IncomingViewingKey, DecryptedNote, trial_decrypt_compact_output
};
use core::array::ArrayTrait;

/// Result of scanning a block for notes
#[derive(Drop, Serde, Debug)]
pub struct ScanResult {
    /// Block height that was scanned
    pub block_height: BlockHeight,

    /// Number of notes found belonging to this IVK
    pub notes_found: u32,

    /// Decrypted notes
    pub notes: Array<DecryptedNote>,

    /// Total outputs scanned
    pub outputs_scanned: u32,
}

/// Scan a block for notes belonging to a viewing key
///
/// This function performs trial decryption on all outputs in a block:
/// 1. Iterates through all transactions
/// 2. Attempts to decrypt each Sapling output
/// 3. Attempts to decrypt each Orchard action
/// 4. Returns all successfully decrypted notes
///
/// This is a core function for wallet synchronization and balance calculation.
///
/// # Arguments
/// * `block` - The compact block to scan
/// * `ivk` - Incoming viewing key to decrypt with
///
/// # Returns
/// * `ScanResult` - Contains all notes found and scan statistics
pub fn scan_block_for_notes(
    block: @CompactBlock,
    ivk: @IncomingViewingKey,
) -> ScanResult {
    let mut found_notes = ArrayTrait::new();
    let mut outputs_scanned: u32 = 0;
    let mut position: u64 = 0;

    let vtx = block.vtx.span();
    let mut tx_idx: usize = 0;

    // Iterate through all transactions
    loop {
        if tx_idx >= vtx.len() {
            break;
        }

        let tx = vtx[tx_idx];

        // Scan Sapling outputs
        let outputs = tx.outputs.span();
        let mut out_idx: usize = 0;

        loop {
            if out_idx >= outputs.len() {
                break;
            }

            let output = outputs[out_idx];
            outputs_scanned += 1;

            // Try to decrypt this output
            match trial_decrypt_compact_output(output, ivk, position) {
                Option::Some(note) => {
                    // Successfully decrypted - this note belongs to us!
                    found_notes.append(note);
                },
                Option::None => {
                    // Not our note, continue
                },
            }

            position += 1;
            out_idx += 1;
        };

        // TODO: Scan Orchard actions similarly
        // For now, we focus on Sapling outputs

        tx_idx += 1;
    };

    ScanResult {
        block_height: *block.height,
        notes_found: found_notes.len().into(),
        notes: found_notes,
        outputs_scanned,
    }
}

/// Scan multiple blocks for notes
///
/// Convenience function to scan a range of blocks.
/// This is useful for batch processing during wallet sync.
///
/// # Arguments
/// * `blocks` - Array of blocks to scan
/// * `ivk` - Incoming viewing key
///
/// # Returns
/// * `Array<ScanResult>` - Results for each block scanned
pub fn scan_block_range_for_notes(
    blocks: @Array<CompactBlock>,
    ivk: @IncomingViewingKey,
) -> Array<ScanResult> {
    let mut results = ArrayTrait::new();
    let blocks_span = blocks.span();
    let mut i: usize = 0;

    loop {
        if i >= blocks_span.len() {
            break;
        }

        let block = blocks_span[i];
        let result = scan_block_for_notes(block, ivk);
        results.append(result);

        i += 1;
    };

    results
}

/// Calculate total value of notes found
///
/// Helper function to sum up the value of all decrypted notes.
///
/// # Arguments
/// * `notes` - Array of decrypted notes
///
/// # Returns
/// * `u64` - Total value in zatoshis
pub fn calculate_total_value(notes: @Array<DecryptedNote>) -> u64 {
    let mut total: u64 = 0;
    let notes_span = notes.span();
    let mut i: usize = 0;

    loop {
        if i >= notes_span.len() {
            break;
        }

        let note = notes_span[i];
        total += *note.value;

        i += 1;
    };

    total
}

/// Calculate count of notes above minimum value
///
/// Returns the number of notes worth at least min_value zatoshis.
///
/// # Arguments
/// * `notes` - Array of decrypted notes
/// * `min_value` - Minimum value threshold
///
/// # Returns
/// * `u32` - Count of notes above threshold
pub fn count_notes_above_value(
    notes: @Array<DecryptedNote>,
    min_value: u64,
) -> u32 {
    let mut count: u32 = 0;
    let notes_span = notes.span();
    let mut i: usize = 0;

    loop {
        if i >= notes_span.len() {
            break;
        }

        let note = notes_span[i];
        if *note.value >= min_value {
            count += 1;
        }

        i += 1;
    };

    count
}

#[cfg(test)]
mod tests {
    use super::{scan_block_for_notes, calculate_total_value};
    use crate::types::compact_block::{CompactBlock, CompactTx, CompactOutput};
    use crate::crypto::note_encryption::IncomingViewingKey;
    use core::array::ArrayTrait;

    #[test]
    fn test_scan_empty_block() {
        let block = CompactBlock {
            height: 100,
            hash: 12345,
            prev_hash: 67890,
            vtx: ArrayTrait::new(),
            sapling_commitment_tree_size: 0,
            orchard_commitment_tree_size: 0,
            time: 1234567890,
        };

        let ivk = IncomingViewingKey { key: 11111 };

        let result = scan_block_for_notes(@block, @ivk);

        assert!(result.block_height == 100);
        assert!(result.notes_found == 0);
        assert!(result.outputs_scanned == 0);
    }

    #[test]
    fn test_scan_block_with_outputs() {
        // Create a transaction with outputs
        let mut ciphertext = ArrayTrait::new();
        let mut i: u32 = 0;
        loop {
            if i >= 52 {
                break;
            }
            ciphertext.append(i.try_into().unwrap());
            i += 1;
        };

        let output = CompactOutput {
            cmu: 123,
            epk: 456,
            ciphertext: ciphertext,
        };

        let mut outputs = ArrayTrait::new();
        outputs.append(output);

        let tx = CompactTx {
            index: 0,
            hash: 789,
            spends: ArrayTrait::new(),
            outputs: outputs,
            actions: ArrayTrait::new(),
        };

        let mut vtx = ArrayTrait::new();
        vtx.append(tx);

        let block = CompactBlock {
            height: 100,
            hash: 12345,
            prev_hash: 67890,
            vtx: vtx,
            sapling_commitment_tree_size: 1,
            orchard_commitment_tree_size: 0,
            time: 1234567890,
        };

        let ivk = IncomingViewingKey { key: 11111 };

        let result = scan_block_for_notes(@block, @ivk);

        // Should have scanned 1 output (won't decrypt with random IVK)
        assert!(result.block_height == 100);
        assert!(result.outputs_scanned == 1);
    }

    #[test]
    fn test_calculate_total_value() {
        use crate::crypto::note_encryption::DecryptedNote;

        let mut notes = ArrayTrait::new();

        notes.append(DecryptedNote {
            value: 10000,
            d: ArrayTrait::new(),
            position: 0,
            rcm: 111,
            memo: Option::None,
        });

        notes.append(DecryptedNote {
            value: 20000,
            d: ArrayTrait::new(),
            position: 1,
            rcm: 222,
            memo: Option::None,
        });

        let total = calculate_total_value(@notes);
        assert!(total == 30000);
    }
}
