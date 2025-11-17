/// Test suite for Zcash Consensus Client in Cairo
/// Tests for pure verification functions (Raito pattern)

// Core functionality tests
mod data_structures_test;
mod crypto_test;

// Verification tests are in the verification module itself
// State machine and action tests removed (moved to Rust layer)