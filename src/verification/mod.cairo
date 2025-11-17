/// Verification module - Pure functions for STWO prover
///
/// This module contains the main entry points for block and transaction verification.
/// All functions are pure (no storage, no I/O) and suitable for STARK proof generation.

pub mod block_validator;
pub mod note_scanner;

// Re-export main verification functions
pub use block_validator::{verify_block, verify_block_range, BlockVerificationResult, ChainVerificationResult};
pub use note_scanner::{scan_block_for_notes, ScanResult};
