/// Zcash Consensus Client - Cairo Pure Function Library (Raito Pattern)
///
/// This is a Zcash consensus client similar to Raito (Bitcoin consensus client).
/// It provides pure verification functions that generate STARK proofs of valid Zcash blocks.
///
/// ARCHITECTURE (Raito Pattern):
/// - Cairo: Pure verification functions (block validation, trial decryption, crypto)
/// - Rust: Orchestration, I/O, fetching blocks from lightwalletd
/// - STWO: Proof generation from Cairo execution
///
/// USE CASES:
/// - Fast sync: Download proofs instead of validating all blocks
/// - Light clients: Trust-minimized verification without full node
/// - Cross-chain bridges: Prove Zcash state on other chains
/// - Proof of reserves: Exchanges prove Zcash holdings

// Pure cryptographic functions
pub mod crypto;

// Data structure definitions
pub mod types;

// Error types and utilities
pub mod utils;

// Verification functions (main entry points for STWO prover)
pub mod verification;

// ============================================================================
// Main Exports for STWO Prover
// ============================================================================

// Core verification functions
pub use verification::{
    verify_block,
    verify_block_range,
    scan_block_for_notes,
    BlockVerificationResult,
    ChainVerificationResult,
    ScanResult,
};

// Data types
pub use types::compact_block::{CompactBlock, CompactTx, CompactOutput, CompactOrchardAction, BlockHeight};
pub use types::scan_range::{ScanRange, ScanPriority, ScanSummary};
pub use types::balance::{AccountBalance, PoolBalance, WalletSummary, Zatoshi};

// Crypto primitives
pub use crypto::note_encryption::{IncomingViewingKey, DecryptedNote};
pub use crypto::nullifier::{Nullifier, NullifierKey};

// Error handling
pub use utils::errors::ZcashError;
