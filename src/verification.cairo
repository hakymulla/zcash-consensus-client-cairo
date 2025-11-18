/// Verification module - Pure functions for STWO prover
///
/// This module contains the main entry points for block and transaction verification.
/// All functions are pure (no storage, no I/O) and suitable for STARK proof generation.

pub mod block_validator;
pub mod note_scanner;
pub mod difficulty;
pub mod equihash;
pub mod merkle;

// Re-export main verification functions
pub use block_validator::{verify_block, verify_block_range, BlockVerificationResult, ChainVerificationResult};
pub use note_scanner::{scan_block_for_notes, ScanResult};
pub use difficulty::{validate_block_difficulty, expand_compact_bits, check_proof_of_work};
pub use equihash::{verify_block_equihash, verify_equihash_solution};
pub use merkle::{validate_tx_merkle_root, validate_sapling_root, validate_block_merkle_roots};
