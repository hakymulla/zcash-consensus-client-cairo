# Zcash Light Client - Cairo/Rust Architecture

## Overview

This Zcash light client implementation follows the **Raito pattern** for Cairo/Rust separation:
- **Cairo** provides pure functions for cryptography and validation (NO state machine!)
- **Rust** owns the state machine and handles ALL I/O operations
- **Key insight**: Cairo is a pure function library, not a state machine runner

## Architectural Boundaries

### Cairo's Responsibilities ✅

Cairo code should ONLY contain:

1. **Cryptographic Operations**
   - Trial decryption of notes
   - Nullifier generation and tracking
   - Commitment tree operations
   - Blake2b hashing
   - Key derivation (KDF)

2. **Pure Validation Logic**
   - Block validation
   - Transaction validation
   - Range validation

3. **Pure Algorithms**
   - Priority-based scan range logic (pure math)
   - State validation (no I/O)
   - Data structure transformations

4. **Data Structures**
   - Type definitions (CompactBlock, ScanRange, etc.)
   - Balance tracking
   - Progress reporting

### Rust's Responsibilities 🦀

Rust code must handle ALL I/O operations:

1. **Network Communication**
   - gRPC client to lightwalletd
   - TLS/SSL connections
   - HTTP requests

2. **Database Operations**
   - SQLite for wallet state
   - Cache management
   - Transaction persistence

3. **Filesystem I/O**
   - Sapling parameter files
   - Configuration files
   - Logs

4. **System Integration**
   - Threading/async
   - Error handling
   - Resource management

5. **Cairo VM Integration**
   - Call Cairo functions for crypto/validation
   - Pass data between Rust and Cairo
   - Manage Cairo VM lifecycle

## State Machine: I/O vs Pure Logic

Following the **Raito pattern**, the 17-state FSM separates I/O from computation:

**[RUST-ONLY] States** (require external I/O - Network/Database/Filesystem):
- MigrateLegacyCacheDB - Database schema migrations
- ValidateServer - gRPC GetLightdInfo()
- UpdateSubtreeRoots - gRPC GetSubtreeRoots()
- UpdateChainTip - gRPC GetLatestBlock()
- Rewind - Database rollback operations
- Download - gRPC GetBlockRange() streaming
- FetchUTXO - gRPC GetAddressUtxos()
- HandleSaplingParams - File I/O for proving keys
- ClearCache - Filesystem cleanup
- TxResubmission - gRPC SendTransaction()

**[CAIRO] States** (pure computation/cryptography - NO I/O):
- ProcessSuggestedScanRanges - Priority algorithm (pure math)
- Scan - Trial decryption (pure crypto)
- ClearAlreadyScannedBlocks - State marking (pure logic)
- Enhance - Data merging/validation (pure computation)

**[CONTROL] Terminal States** (managed by Rust):
- Idle, Finished, Failed, Stopped

## Data Flow Example

### Scan Operation

```
┌─────────┐                           ┌──────────┐
│  Rust   │                           │  Cairo   │
└────┬────┘                           └────┬─────┘
     │                                     │
     │ 1. Download blocks (gRPC)           │
     │────────────────────────────>        │
     │                                     │
     │ 2. Pass CompactBlock data           │
     │─────────────────────────────────────>
     │                                     │
     │                        3. Trial decryption
     │                        Note detection
     │                        Nullifier generation
     │                                     │
     │ 4. Return found notes               │
     │<─────────────────────────────────────
     │                                     │
     │ 5. Store to database                │
     │────────────────────────────>        │
     │                                     │
```

## Module Structure

```
src/
├── core/           # Main processor orchestration
├── crypto/         # CAIRO: Cryptographic primitives
├── state/          # CAIRO: State machine & context
├── types/          # CAIRO: Data structures
└── utils/          # CAIRO: Error types, helpers

# Network and database modules NOT in Cairo
# These belong in the Rust codebase
```

## Why This Separation?

1. **Security**: Cairo VM provides provable computation for critical crypto operations
2. **Efficiency**: Rust handles I/O much faster than Cairo
3. **Practicality**: Cairo cannot do network/filesystem I/O
4. **Verification**: Cairo code can be formally verified
5. **Portability**: Cairo state machine can run in different environments

## Phase 1 vs Phase 2

**Phase 1 (Current)**: Pure Cairo implementation
- Compiles and type-checks
- Contains crypto and state machine logic
- Placeholder/stub implementations for I/O states
- Foundation for Phase 2 integration

**Phase 2 (Future)**: Rust + Cairo integration
- Rust orchestrates the workflow
- Calls into Cairo VM for crypto/validation
- Handles all I/O operations
- Production-ready light client

## Key Principle

> **If it touches the network, filesystem, or database, it belongs in Rust.**
> **If it's cryptography or pure logic, it belongs in Cairo.**


## Critical Architectural Insight (Raito Pattern)

### Cairo is NOT a State Machine! 

Unlike traditional implementations, Cairo should NOT contain state transition logic with I/O.

**❌ WRONG (Don't do this in Cairo):**
```cairo
// This suggests Cairo would orchestrate I/O - it can't!
fn run_state_machine() {
    match current_state {
        State::Download => download_blocks(),  // ❌ Network I/O
        State::Scan => scan_blocks(),          // ✅ Pure crypto
        State::Store => save_to_db(),          // ❌ Database I/O
    }
}
```

**✅ CORRECT (Raito pattern):**

**Rust owns the state machine:**
```rust
// rust-client/src/state_machine.rs
impl ZcashSync {
    async fn run(&mut self) -> Result<()> {
        loop {
            match self.state {
                State::Download => {
                    let blocks = self.client.get_blocks().await?;  // Rust does I/O
                    self.db.store(blocks)?;                        // Rust does I/O
                    self.state = State::Scan;
                }
                State::Scan => {
                    let blocks = self.db.get_unscanned()?;         // Rust does I/O
                    let notes = self.cairo.scan_blocks(blocks)?;   // Cairo does crypto
                    self.db.store_notes(notes)?;                   // Rust does I/O
                    self.state = State::Enhance;
                }
                // ... Rust orchestrates everything
            }
        }
    }
}
```

**Cairo provides pure functions only:**
```cairo
// zcash_light_client/src/crypto/scanner.cairo
// NO state machine - just pure functions!

pub fn scan_blocks(
    blocks: @Array<CompactBlock>,
    ivk: @IncomingViewingKey
) -> ScanResult {
    // Pure cryptography - no I/O, no state transitions
    let mut notes = ArrayTrait::new();
    // Trial decryption logic...
    ScanResult { notes }
}

pub fn validate_block_continuity(
    blocks: @Array<CompactBlock>
) -> bool {
    // Pure validation - no I/O
    // Check height continuity, hash chains, etc.
}
```

### Why This Matters

1. **Cairo can't do I/O** - It's a VM for provable computation
2. **Rust is better at I/O** - Async, threading, error handling
3. **Cairo proves correctness** - Cryptographic operations are verifiable
4. **Separation of concerns** - Clear boundary between I/O and computation

### Data Flow Pattern

```
Rust State Machine          Cairo Pure Functions
     (I/O Layer)            (Computation Layer)
         │                         │
         ├─ Download (gRPC) ───────┤
         ├─ Store (SQLite) ────────┤
         │                         │
         ├─── blocks ──────────────>
         │                    scan_blocks()
         │                    (pure crypto)
         <──── notes ──────────────┤
         │                         │
         ├─ Store notes ───────────┤
         ├─ Fetch tx (gRPC) ───────┤
         │                         │
         ├─── full_txs ────────────>
         │                    enhance()
         │                    (pure logic)
         <──── enhanced ───────────┤
         │                         │
         ├─ Persist ───────────────┤
```

## Current Implementation Status

**Phase 1 (Current):** Cairo code compiles with state enums
- ✅ Compiles successfully
- ✅ Contains crypto primitives
- ⚠️ Has `CBPState` enum (for reference only)
- ⚠️ State transitions are placeholders
- 🎯 **Next**: Remove state machine from Cairo, make it pure functions

**Phase 2 (Next):** Rust + Cairo integration
- Rust implements the full state machine
- Cairo exports pure functions only
- Rust calls Cairo VM for crypto operations
- Production-ready light client

