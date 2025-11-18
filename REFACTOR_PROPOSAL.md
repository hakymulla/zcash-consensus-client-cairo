# Refactor Proposal: Remove State Machine from Cairo

## Current Problem

Cairo currently has a `CBPState` enum with 17 states, but:
- ❌ Cairo doesn't execute the state machine (Rust does)
- ❌ Most states are [RUST-ONLY] with I/O operations
- ❌ Confuses the architectural boundary
- ❌ Duplicates state definitions between Cairo and Rust

## Proposed Change

### Remove from Cairo:
1. `state/processor_state.cairo` - Delete entire file
2. `state/action.cairo` - Delete (no actions in Cairo)
3. `core/processor.cairo` - Delete (Rust orchestrates)

### What Stays in Cairo:
```
zcash_light_client/
├── crypto/
│   ├── blake2b.cairo          ✅ Pure crypto
│   ├── nullifier.cairo        ✅ Pure crypto
│   └── note_encryption.cairo  ✅ Pure crypto
├── types/
│   ├── compact_block.cairo    ✅ Data structures
│   ├── scan_range.cairo       ✅ Data structures
│   └── balance.cairo          ✅ Data structures
└── lib.cairo                  ✅ Exports

# NO state/ directory
# NO core/ directory
```

### What Moves to Rust:
```rust
// rust-client/src/state_machine.rs
pub enum SyncState {
    Idle,
    ValidateServer,      // Rust does gRPC
    UpdateSubtreeRoots,  // Rust does gRPC
    UpdateChainTip,      // Rust does gRPC
    ProcessScanRanges,   // Rust calculates, Cairo validates
    Download,            // Rust does gRPC
    Scan,                // Rust calls Cairo.scan_blocks()
    Enhance,             // Rust calls Cairo.enhance()
    // ... all states
}

impl StateMachine {
    pub async fn run(&mut self) -> Result<()> {
        loop {
            match self.state {
                SyncState::Scan => {
                    let blocks = self.db.get_unscanned()?;
                    
                    // Call Cairo for pure crypto
                    let notes = self.cairo_vm.call(
                        "scan_blocks",
                        &[blocks.serialize()]
                    )?;
                    
                    self.db.store_notes(notes)?;
                    self.state = SyncState::Enhance;
                }
                // ...
            }
        }
    }
}
```

### Cairo Becomes:
```cairo
// lib.cairo - Pure function exports
pub mod crypto;
pub mod types;

// crypto/scanner.cairo
pub fn scan_blocks(
    blocks: @Array<CompactBlock>,
    ivk: @IncomingViewingKey
) -> ScanResult {
    // Pure trial decryption
}

pub fn compute_nullifiers(
    notes: @Array<Note>,
    nk: @NullifierKey
) -> Array<Nullifier> {
    // Pure computation
}

pub fn validate_block_chain(
    blocks: @Array<CompactBlock>
) -> bool {
    // Pure validation
}
```

## Benefits

✅ **Clear separation**: Rust = I/O + State, Cairo = Crypto  
✅ **No duplication**: State defined once (in Rust)  
✅ **Simpler Cairo**: Just pure functions  
✅ **Easier to understand**: No confusion about who runs what  
✅ **Matches Raito**: Exactly how they do it  

## Migration Path

### Phase 1: Current (Keep for now)
- Keep `CBPState` enum for reference
- Document as "Rust will implement this"
- Use for design discussion

### Phase 2: When Rust integration starts
- Remove `state/` directory from Cairo
- Remove `core/` directory from Cairo  
- Implement state machine in Rust
- Cairo exports only pure functions

## Final Architecture

```
┌─────────────────────────────────┐
│     Rust State Machine          │
│  - Owns all 17 states           │
│  - Handles all I/O              │
│  - Orchestrates workflow        │
└────────────┬────────────────────┘
             │
             │ Calls for crypto/validation
             ▼
┌─────────────────────────────────┐
│     Cairo Pure Functions        │
│  - scan_blocks()                │
│  - validate_blocks()            │
│  - compute_nullifiers()         │
│  - NO STATE MACHINE             │
└─────────────────────────────────┘
```

## Recommendation

**For Phase 1 (now):** Keep `CBPState` as documentation  
**For Phase 2 (Rust integration):** Delete it completely

The enum is useful NOW for understanding the design, but will be removed when Rust takes over.
