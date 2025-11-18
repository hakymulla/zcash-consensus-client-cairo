# Zcash Consensus Client Specification for Cairo

**Version:** 1.0  
**Target Protocol:** Zcash Protocol Specification v2025.6.1 (NU6.1)  
**Implementation Language:** Cairo  
**Purpose:** Zero-knowledge provable Zcash consensus validation

---

## Executive Summary

This specification defines a Zcash consensus client implementation in Cairo, enabling provable verification of Zcash block validation logic. Unlike Zcash Core (written in C++), this implementation leverages Cairo's provable computation capabilities to generate cryptographic proofs that blocks were validated correctly according to consensus rules.

**Key Innovation:** Every block validation produces a STARK proof that can be verified efficiently, enabling trustless light clients and cross-chain bridges.

---

## 1. Architecture Overview

### 1.1 System Components

```
┌─────────────────────────────────────────────────────┐
│          Cairo Consensus Client                      │
├─────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌───────────┐ │
│  │   Block      │  │  Transaction │  │  State    │ │
│  │  Validator   │──│   Validator  │──│  Manager  │ │
│  └──────────────┘  └──────────────┘  └───────────┘ │
│         │                  │                │       │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────┐ │
│  │   Crypto     │  │     Proof    │  │   Merkle  │ │
│  │  Primitives  │  │   Verifiers  │  │   Trees   │ │
│  └──────────────┘  └──────────────┘  └───────────┘ │
└─────────────────────────────────────────────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │   STARK Proof Output │
              └──────────────────────┘
```

### 1.2 Core Principles

1. **Provable Execution:** All validation logic must be executable in Cairo and produce verifiable proofs
2. **Consensus Fidelity:** Implement identical validation rules as Zcash Core
3. **Deterministic:** All computations must be deterministic and reproducible
4. **Gas Efficiency:** Optimize for Cairo VM execution costs
5. **Modularity:** Separate concerns for maintainability and testability

---

## 2. Block Header Validation

### 2.1 Block Header Structure

```cairo
struct BlockHeader {
    version: u32,              // Block version (MUST be >= 4)
    prev_block_hash: u256,     // SHA-256d of previous block
    merkle_root: u256,         // Merkle root of transactions
    block_commitment: u256,    // hashBlockCommitments (NU5+)
    timestamp: u32,            // Unix timestamp
    bits: u32,                 // Difficulty target (nBits)
    nonce: u256,               // 32-byte nonce
    solution_size: u32,        // Equihash solution size (1344)
    solution: Array<u8>,       // Equihash solution
}
```

### 2.2 Block Header Validation Rules

Implement the following consensus rules from Section 7.6:

```cairo
fn validate_block_header(header: BlockHeader, height: u64, prev_headers: Array<BlockHeader>) -> Result<(), ConsensusError> {
    // Rule 1: Version check
    require(header.version >= 4, "Block version must be >= 4");
    
    // Rule 2: nBits verification
    let expected_bits = calculate_threshold_bits(height, prev_headers);
    require(header.bits == expected_bits, "Invalid nBits");
    
    // Rule 3: Difficulty filter
    require(check_difficulty_filter(header), "Failed difficulty filter");
    
    // Rule 4: Equihash solution validation
    require(verify_equihash_solution(header), "Invalid Equihash solution");
    
    // Rule 5: Timestamp validation (median-time-past)
    let median_time_past = calculate_median_time_past(prev_headers);
    require(header.timestamp > median_time_past, "Timestamp too old");
    require(header.timestamp <= median_time_past + 5400, "Timestamp too far in future");
    
    // Rule 6: hashBlockCommitments (NU5+)
    // Validated separately after transaction processing
    
    Ok(())
}
```

### 2.3 Equihash Verification

**Parameters:** n = 200, k = 9

```cairo
fn verify_equihash_solution(header: BlockHeader) -> bool {
    let N = pow(2, 200/10) + 1;  // 2^20 + 1
    let pow_header = serialize_pow_header(header);
    
    // Decode solution indices
    let indices = decode_equihash_solution(header.solution);
    require(indices.len() == 512, "Invalid solution length");
    
    // Generate X values
    let mut x_values = ArrayTrait::new();
    for i in 1..=N {
        x_values.append(equihash_gen(pow_header, i));
    }
    
    // Check generalized birthday condition
    let mut xor_result = 0;
    for idx in indices {
        xor_result ^= x_values[idx];
    }
    require(xor_result == 0, "Birthday condition failed");
    
    // Check algorithm binding conditions
    verify_binding_conditions(indices, x_values)
}

fn equihash_gen(pow_header: Array<u8>, i: u32) -> u256 {
    // Implementation of EquihashGen using BLAKE2b-256
    // See Section 5.4.1.11
    blake2b_personalized("ZcashPoW", &[pow_header, i.to_bytes()])
}
```

### 2.4 Difficulty Adjustment

```cairo
fn calculate_threshold_bits(height: u64, prev_headers: Array<BlockHeader>) -> u32 {
    // Implement Zcash difficulty adjustment algorithm
    // See Section 7.7.3
    
    if height == 0 {
        return GENESIS_BITS;
    }
    
    let difficulty_window = 17;
    let window_start = max(1, height - difficulty_window);
    
    // Calculate average solve time
    let mut total_time = 0;
    for i in window_start..height {
        total_time += prev_headers[i].timestamp - prev_headers[i-1].timestamp;
    }
    let avg_time = total_time / difficulty_window;
    
    // Adjust difficulty based on target block time (150 seconds)
    adjust_difficulty(prev_headers[height-1].bits, avg_time, 150)
}
```

---

## 3. Transaction Validation

### 3.1 Transaction Structure

```cairo
struct Transaction {
    version: u32,
    version_group_id: u32,
    consensus_branch_id: u32,
    lock_time: u32,
    expiry_height: u32,
    
    // Transparent components
    tx_in: Array<TxIn>,
    tx_out: Array<TxOut>,
    
    // Sprout (JoinSplit) components
    joinsplits: Array<JoinSplitDescription>,
    joinsplit_pubkey: Option<Array<u8>>,
    joinsplit_sig: Option<Array<u8>>,
    
    // Sapling components
    spends_sapling: Array<SpendDescription>,
    outputs_sapling: Array<OutputDescription>,
    value_balance_sapling: i64,
    binding_sig_sapling: Option<Array<u8>>,
    
    // Orchard components (NU5+)
    actions_orchard: Array<ActionDescription>,
    flags_orchard: u8,
    value_balance_orchard: i64,
    anchor_orchard: Option<u256>,
    proofs_orchard: Option<Array<u8>>,
    binding_sig_orchard: Option<Array<u8>>,
}
```

### 3.2 Transaction Consensus Rules (Section 7.1.2)

```cairo
fn validate_transaction(
    tx: Transaction,
    block_height: u64,
    is_coinbase: bool,
    utxo_set: UTXOSet,
    nullifier_set: NullifierSet
) -> Result<(), ConsensusError> {
    
    // Version and network upgrade checks
    validate_version_and_upgrade(tx, block_height)?;
    
    // Input/output existence rules
    validate_tx_structure(tx, is_coinbase)?;
    
    // Coinbase-specific rules
    if is_coinbase {
        validate_coinbase_transaction(tx, block_height)?;
    } else {
        validate_regular_transaction(tx, block_height, utxo_set, nullifier_set)?;
    }
    
    // Value balance checks
    validate_value_balance(tx, is_coinbase)?;
    
    // Signature validations
    validate_signatures(tx)?;
    
    // Shielded pool validations
    validate_shielded_pools(tx, nullifier_set)?;
    
    Ok(())
}
```

### 3.3 Version and Upgrade Validation

```cairo
fn validate_version_and_upgrade(tx: Transaction, height: u64) -> Result<(), ConsensusError> {
    // NU5+ rules
    if height >= NU5_ACTIVATION_HEIGHT {
        require(tx.version == 4 || tx.version == 5, "Invalid tx version for NU5+");
        
        if tx.version == 4 {
            require(tx.version_group_id == 0x892F2085, "Invalid version group ID for v4");
        } else if tx.version == 5 {
            require(tx.version_group_id == 0x26A7270A, "Invalid version group ID for v5");
            require(tx.consensus_branch_id == NU5_BRANCH_ID, "Invalid consensus branch ID");
        }
        
        // Check array bounds
        require(tx.spends_sapling.len() < 65536, "Too many Sapling spends");
        require(tx.outputs_sapling.len() < 65536, "Too many Sapling outputs");
        require(tx.actions_orchard.len() < 65536, "Too many Orchard actions");
    }
    
    Ok(())
}
```

### 3.4 Transparent Input/Output Validation

```cairo
fn validate_transparent_io(
    tx: Transaction,
    is_coinbase: bool,
    utxo_set: UTXOSet
) -> Result<(), ConsensusError> {
    
    if !is_coinbase {
        // Non-coinbase: validate all inputs reference valid UTXOs
        for input in tx.tx_in {
            require(!input.prevout.is_null(), "Null prevout in non-coinbase tx");
            require(utxo_set.contains(input.prevout), "UTXO not found");
            
            let utxo = utxo_set.get(input.prevout);
            
            // Coinbase maturity check
            if utxo.is_coinbase {
                let utxo_height = utxo.block_height;
                require(
                    block_height >= utxo_height + 100,
                    "Coinbase output not mature"
                );
            }
        }
    } else {
        // Coinbase: first input must be null, subsequent inputs forbidden
        require(tx.tx_in.len() == 1, "Coinbase must have exactly 1 input");
        require(tx.tx_in[0].prevout.is_null(), "Coinbase input must be null");
    }
    
    // Coinbase outputs cannot be spent to transparent addresses
    if has_coinbase_inputs(tx) {
        require(tx.tx_out.len() == 0, "Coinbase-funded tx cannot have transparent outputs");
    }
    
    Ok(())
}
```

---

## 4. Shielded Pool Validation

### 4.1 Sapling Validation

#### 4.1.1 Spend Description Validation

```cairo
struct SpendDescription {
    cv: felt252,              // Value commitment
    anchor: Option<u256>,     // Note commitment tree root
    nullifier: u256,          // Nullifier
    rk: felt252,              // Randomized verification key
    zkproof: Option<Array<u8>>, // Groth16 proof
    spend_auth_sig: Option<Array<u8>>, // Spend authorization signature
}

fn validate_spend_description(
    spend: SpendDescription,
    anchor: u256,
    nullifier_set: NullifierSet,
    sighash: u256
) -> Result<(), ConsensusError> {
    
    // Check nullifier uniqueness
    require(!nullifier_set.contains(spend.nullifier), "Nullifier already spent");
    
    // Verify anchor matches block's Sapling tree root
    require(spend.anchor.unwrap_or(anchor) == anchor, "Invalid anchor");
    
    // Verify Groth16 zk-SNARK proof
    let spend_statement = construct_spend_statement(spend);
    require(verify_groth16_proof(spend.zkproof, spend_statement), "Invalid spend proof");
    
    // Verify spend authorization signature (RedJubjub)
    require(
        verify_redjubjub_signature(spend.rk, sighash, spend.spend_auth_sig),
        "Invalid spend authorization"
    );
    
    Ok(())
}
```

#### 4.1.2 Output Description Validation

```cairo
struct OutputDescription {
    cv: felt252,              // Value commitment
    cmu: u256,                // Note commitment u-coordinate
    ephemeral_key: felt252,   // Ephemeral public key
    enc_ciphertext: Array<u8>,  // Encrypted note (580 bytes)
    out_ciphertext: Array<u8>,  // Outgoing ciphertext (80 bytes)
    zkproof: Option<Array<u8>>, // Groth16 proof
}

fn validate_output_description(
    output: OutputDescription
) -> Result<(), ConsensusError> {
    
    // Verify commitment is in valid range
    require(output.cmu < JUBJUB_Q, "Invalid note commitment");
    
    // Verify Groth16 zk-SNARK proof
    let output_statement = construct_output_statement(output);
    require(verify_groth16_proof(output.zkproof, output_statement), "Invalid output proof");
    
    Ok(())
}
```

#### 4.1.3 Sapling Binding Signature

```cairo
fn validate_sapling_binding_signature(tx: Transaction) -> Result<(), ConsensusError> {
    if tx.spends_sapling.len() == 0 && tx.outputs_sapling.len() == 0 {
        return Ok(());
    }
    
    // Calculate binding verification key
    let mut bvk = calculate_binding_vk_sapling(tx);
    
    // Compute SIGHASH for binding signature
    let sighash = compute_sighash_sapling(tx);
    
    // Verify RedJubjub binding signature
    require(
        verify_redjubjub_signature(bvk, sighash, tx.binding_sig_sapling),
        "Invalid Sapling binding signature"
    );
    
    Ok(())
}

fn calculate_binding_vk_sapling(tx: Transaction) -> felt252 {
    let mut cv_sum = JUBJUB_IDENTITY;
    
    // Sum value commitments from spends (positive)
    for spend in tx.spends_sapling {
        cv_sum = jubjub_add(cv_sum, spend.cv);
    }
    
    // Sum value commitments from outputs (negative)
    for output in tx.outputs_sapling {
        cv_sum = jubjub_sub(cv_sum, output.cv);
    }
    
    // Add value balance commitment
    let value_commitment = pedersen_commit(tx.value_balance_sapling, 0);
    cv_sum = jubjub_add(cv_sum, value_commitment);
    
    cv_sum
}
```

### 4.2 Orchard Validation (NU5+)

#### 4.2.1 Action Description Validation

```cairo
struct ActionDescription {
    cv: felt252,              // Net value commitment
    nullifier: u256,          // Nullifier
    rk: felt252,              // Randomized verification key
    cmx: u256,                // Note commitment x-coordinate
    ephemeral_key: felt252,   // Ephemeral public key
    enc_ciphertext: Array<u8>,  // Encrypted note (580 bytes)
    out_ciphertext: Array<u8>,  // Outgoing ciphertext (80 bytes)
}

fn validate_action_description(
    action: ActionDescription,
    nullifier_set: NullifierSet,
    flags: u8
) -> Result<(), ConsensusError> {
    
    // Check nullifier uniqueness if spends enabled
    if flags & 0x01 != 0 {  // enableSpendsOrchard
        require(!nullifier_set.contains(action.nullifier), "Nullifier already spent");
    }
    
    // Verify commitment is in valid range
    require(action.cmx < PALLAS_Q, "Invalid note commitment");
    
    Ok(())
}
```

#### 4.2.2 Orchard Proof Verification

```cairo
fn validate_orchard_proofs(
    tx: Transaction,
    anchor: u256
) -> Result<(), ConsensusError> {
    
    if tx.actions_orchard.len() == 0 {
        return Ok(());
    }
    
    // Verify Halo 2 aggregated proof
    let action_statements = construct_action_statements(tx.actions_orchard, anchor, tx.flags_orchard);
    require(
        verify_halo2_proof(tx.proofs_orchard, action_statements),
        "Invalid Orchard proof"
    );
    
    // Verify spend authorization signatures (RedPallas)
    for (i, action) in tx.actions_orchard.iter().enumerate() {
        let sighash = compute_sighash_orchard(tx, i);
        require(
            verify_redpallas_signature(action.rk, sighash, tx.spend_auth_sigs_orchard[i]),
            "Invalid Orchard spend authorization"
        );
    }
    
    // Verify binding signature
    validate_orchard_binding_signature(tx)?;
    
    Ok(())
}
```

---

## 5. Cryptographic Primitives

### 5.1 Hash Functions

```cairo
// SHA-256 and SHA-256d
fn sha256(data: Array<u8>) -> u256 { /* ... */ }
fn sha256d(data: Array<u8>) -> u256 { sha256(sha256(data)) }

// BLAKE2b variants
fn blake2b_256(data: Array<u8>) -> u256 { /* ... */ }
fn blake2b_512(data: Array<u8>) -> u512 { /* ... */ }
fn blake2b_personalized(personalization: Array<u8>, data: Array<u8>) -> u256 { /* ... */ }

// Pedersen hash (for Sapling)
fn pedersen_hash(bits: Array<bool>) -> felt252 {
    // Implement Pedersen hash on Jubjub
    // See Section 5.4.1.7
}

// Sinsemilla hash (for Orchard)
fn sinsemilla_hash(bits: Array<bool>) -> felt252 {
    // Implement Sinsemilla hash on Pallas
    // See Section 5.4.1.9
}

// Poseidon hash (for Orchard)
fn poseidon_hash(inputs: Array<felt252>) -> felt252 {
    // Implement Poseidon permutation
    // See Section 5.4.1.10
}
```

### 5.2 Elliptic Curve Operations

```cairo
// Jubjub curve operations (for Sapling)
const JUBJUB_Q: felt252 = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
const JUBJUB_IDENTITY: felt252 = /* ... */;

fn jubjub_add(a: felt252, b: felt252) -> felt252 { /* ... */ }
fn jubjub_mul(point: felt252, scalar: felt252) -> felt252 { /* ... */ }

// Pallas curve operations (for Orchard)
const PALLAS_Q: felt252 = 0x40000000000000000000000000000000224698fc094cf91b992d30ed00000001;

fn pallas_add(a: felt252, b: felt252) -> felt252 { /* ... */ }
fn pallas_mul(point: felt252, scalar: felt252) -> felt252 { /* ... */ }
```

### 5.3 Signature Verification

```cairo
// RedJubjub (for Sapling)
fn verify_redjubjub_signature(
    vk: felt252,
    message: u256,
    signature: Array<u8>
) -> bool {
    // Implement RedDSA verification on Jubjub
    // See Section 5.4.7
}

// RedPallas (for Orchard)
fn verify_redpallas_signature(
    vk: felt252,
    message: u256,
    signature: Array<u8>
) -> bool {
    // Implement RedDSA verification on Pallas
    // See Section 5.4.7
}

// Ed25519 (for JoinSplit)
fn verify_ed25519_signature(
    vk: Array<u8>,
    message: Array<u8>,
    signature: Array<u8>
) -> bool { /* ... */ }
```

### 5.4 Zero-Knowledge Proof Verification

```cairo
// Groth16 (for Sapling)
fn verify_groth16_proof(
    proof: Array<u8>,
    statement: ProofStatement
) -> bool {
    // Implement Groth16 verification on BLS12-381
    // See Section 5.4.10.2
}

// Halo 2 (for Orchard)
fn verify_halo2_proof(
    proof: Array<u8>,
    statements: Array<ProofStatement>
) -> bool {
    // Implement Halo 2 verification on Pallas/Vesta
    // See Section 5.4.10.3
}
```

---

## 6. State Management

### 6.1 UTXO Set

```cairo
struct UTXO {
    txid: u256,
    output_index: u32,
    value: u64,
    script_pubkey: Array<u8>,
    block_height: u64,
    is_coinbase: bool,
}

trait UTXOSet {
    fn contains(&self, prevout: OutPoint) -> bool;
    fn get(&self, prevout: OutPoint) -> UTXO;
    fn add(&mut self, utxo: UTXO);
    fn remove(&mut self, prevout: OutPoint);
}
```

### 6.2 Note Commitment Trees

```cairo
// Merkle tree for note commitments
const MERKLE_DEPTH_SAPLING: u32 = 32;
const MERKLE_DEPTH_ORCHARD: u32 = 32;

struct MerkleTree {
    root: u256,
    nodes: Map<u64, u256>,
    leaf_count: u64,
}

impl MerkleTree {
    fn append(&mut self, commitment: u256) {
        // Append note commitment to tree
    }
    
    fn root(&self) -> u256 {
        self.root
    }
    
    fn verify_path(&self, commitment: u256, position: u64, path: Array<u256>) -> bool {
        // Verify Merkle authentication path
        let mut current = commitment;
        for (i, sibling) in path.iter().enumerate() {
            let is_right = (position >> i) & 1 == 1;
            current = if is_right {
                merkle_hash(sibling, current)
            } else {
                merkle_hash(current, sibling)
            };
        }
        current == self.root
    }
}

fn merkle_hash(left: u256, right: u256) -> u256 {
    // Use appropriate hash function based on tree type
    // Sapling: Pedersen hash
    // Orchard: Sinsemilla hash
}
```

### 6.3 Nullifier Set

```cairo
trait NullifierSet {
    fn contains(&self, nullifier: u256) -> bool;
    fn add(&mut self, nullifier: u256);
}

struct NullifierSetImpl {
    sprout: Set<u256>,
    sapling: Set<u256>,
    orchard: Set<u256>,
}
```

---

## 7. Block Validation Flow

### 7.1 Main Validation Function

```cairo
fn validate_block(
    block: Block,
    prev_block: Block,
    prev_headers: Array<BlockHeader>,
    chain_state: ChainState
) -> Result<ChainState, ConsensusError> {
    
    // 1. Validate block header
    validate_block_header(block.header, block.height, prev_headers)?;
    
    // 2. Validate block size
    require(block.size() <= 2_000_000, "Block too large");
    
    // 3. Validate transaction count
    require(block.transactions.len() >= 1, "Block has no transactions");
    
    // 4. Validate coinbase transaction
    require(block.transactions[0].is_coinbase(), "First tx must be coinbase");
    for i in 1..block.transactions.len() {
        require(!block.transactions[i].is_coinbase(), "Only first tx can be coinbase");
    }
    
    // 5. Validate each transaction
    let mut new_state = chain_state.clone();
    for (i, tx) in block.transactions.iter().enumerate() {
        validate_transaction(tx, block.height, i == 0, new_state.utxo_set, new_state.nullifier_set)?;
        new_state = apply_transaction(new_state, tx)?;
    }
    
    // 6. Update note commitment trees
    new_state.sapling_tree = update_sapling_tree(block.transactions, chain_state.sapling_tree)?;
    new_state.orchard_tree = update_orchard_tree(block.transactions, chain_state.orchard_tree)?;
    
    // 7. Verify hashBlockCommitments
    let expected_commitment = calculate_block_commitments(block, new_state)?;
    require(block.header.block_commitment == expected_commitment, "Invalid block commitments");
    
    // 8. Validate block subsidy and fees
    validate_block_subsidy(block, chain_state)?;
    
    Ok(new_state)
}
```

### 7.2 State Transition

```cairo
fn apply_transaction(state: ChainState, tx: Transaction) -> Result<ChainState, ConsensusError> {
    let mut new_state = state;
    
    // Remove spent UTXOs
    for input in tx.tx_in {
        new_state.utxo_set.remove(input.prevout);
    }
    
    // Add new UTXOs
    for (i, output) in tx.tx_out.iter().enumerate() {
        new_state.utxo_set.add(UTXO {
            txid: tx.txid(),
            output_index: i,
            value: output.value,
            script_pubkey: output.script_pubkey.clone(),
            block_height: state.height,
            is_coinbase: tx.is_coinbase(),
        });
    }
    
    // Add nullifiers
    for spend in tx.spends_sapling {
        new_state.nullifier_set.add(spend.nullifier);
    }
    for action in tx.actions_orchard {
        new_state.nullifier_set.add(action.nullifier);
    }
    
    // Add note commitments
    for output in tx.outputs_sapling {
        new_state.sapling_tree.append(output.cmu);
    }
    for action in tx.actions_orchard {
        new_state.orchard_tree.append(action.cmx);
    }
    
    Ok(new_state)
}
```

---

## 8. Block Subsidy and Coinbase Validation

### 8.1 Block Subsidy Calculation

```cairo
fn calculate_block_subsidy(height: u64) -> u64 {
    // Zcash halving schedule: every 840,000 blocks (~4 years)
    let halving_interval = 840_000;
    let halvings = height / halving_interval;
    
    if halvings >= 64 {
        return 0;  // Subsidy goes to zero after 64 halvings
    }
    
    let initial_subsidy = 12_50000_000;  // 12.5 ZEC in zatoshis
    initial_subsidy >> halvings  // Right shift for halving
}

fn calculate_founders_reward(height: u64) -> u64 {
    // Founders' reward was 20% of block subsidy until Canopy
    if height < CANOPY_ACTIVATION_HEIGHT {
        calculate_block_subsidy(height) / 5
    } else {
        0
    }
}

fn calculate_funding_streams(height: u64) -> Array<(Address, u64)> {
    // Calculate funding stream amounts (NU5+)
    // See Section 7.10 and ZIP-214
    if height < NU5_ACTIVATION_HEIGHT {
        return ArrayTrait::new();
    }
    
    // Implement ZIP-214 funding stream logic
    // ...
}
```

### 8.2 Coinbase Validation

```cairo
fn validate_coinbase_transaction(
    coinbase: Transaction,
    block_height: u64,
    block_fees: u64
) -> Result<(), ConsensusError> {
    
    // Must have exactly one input with null prevout
    require(coinbase.tx_in.len() == 1, "Coinbase must have 1 input");
    require(coinbase.tx_in[0].prevout.is_null(), "Coinbase input must be null");
    
    // Script must encode block height
    validate_coinbase_script(coinbase.tx_in[0].script_sig, block_height)?;
    
    // Cannot have JoinSplits or Sapling spends
    require(coinbase.joinsplits.len() == 0, "Coinbase cannot have JoinSplits");
    require(coinbase.spends_sapling.len() == 0, "Coinbase cannot have Sapling spends");
    
    // NU5+: enableSpendsOrchard must be 0
    if coinbase.version >= 5 {
        require(coinbase.flags_orchard & 0x01 == 0, "Coinbase cannot enable Orchard spends");
    }
    
    // Calculate total input and output values
    let subsidy = calculate_block_subsidy(block_height);
    let total_input = subsidy + block_fees;
    
    let mut total_output = 0_u64;
    for output in coinbase.tx_out {
        total_output += output.value;
    }
    
    // Account for value balance
    total_output -= coinbase.value_balance_sapling as u64;
    total_output -= coinbase.value_balance_orchard as u64;
    
    // NU6+: Total output must equal total input
    if block_height >= NU6_ACTIVATION_HEIGHT {
        require(total_output == total_input, "Coinbase output != input");
    } else {
        require(total_output <= total_input, "Coinbase output > input");
    }
    
    // Validate founders' reward / funding streams
    validate_coinbase_distribution(coinbase, block_height, subsidy)?;
    
    Ok(())
}

fn validate_coinbase_script(script: Array<u8>, height: u64) -> Result<(), ConsensusError> {
    // First item must encode block height
    // See BIP-34 encoding rules
    if height <= 16 {
        require(script[0] == 0x50 + height as u8, "Invalid height encoding");
    } else {
        let height_bytes = height.to_le_bytes_minimal();
        require(height_bytes.len() >= 1 && height_bytes.len() <= 5, "Invalid height length");
        require(script[0] == height_bytes.len() as u8, "Invalid height length byte");
        require(script[1..=height_bytes.len()] == height_bytes, "Invalid height bytes");
    }
    
    // Total script length must be 2..100 bytes
    require(script.len() >= 2 && script.len() <= 100, "Invalid script length");
    
    Ok(())
}
```

---

## 9. Network Upgrades

### 9.1 Activation Heights

```cairo
// Mainnet activation heights
const OVERWINTER_HEIGHT: u64 = 347_500;
const SAPLING_HEIGHT: u64 = 419_200;
const BLOSSOM_HEIGHT: u64 = 653_600;
const HEARTWOOD_HEIGHT: u64 = 903_000;
const CANOPY_HEIGHT: u64 = 1_046_400;
const NU5_HEIGHT: u64 = 1_687_104;
const NU6_HEIGHT: u64 = 2_726_400;

// Branch IDs
const OVERWINTER_BRANCH_ID: u32 = 0x5ba81b19;
const SAPLING_BRANCH_ID: u32 = 0x76b809bb;
const BLOSSOM_BRANCH_ID: u32 = 0x2bb40e60;
const HEARTWOOD_BRANCH_ID: u32 = 0xf5b9230b;
const CANOPY_BRANCH_ID: u32 = 0xe9ff75a6;
const NU5_BRANCH_ID: u32 = 0xc2d6d0b4;
const NU6_BRANCH_ID: u32 = 0xc8e71055;
```

### 9.2 Consensus Rule Activation

```cairo
fn get_active_rules(height: u64) -> ConsensusRules {
    ConsensusRules {
        overwinter: height >= OVERWINTER_HEIGHT,
        sapling: height >= SAPLING_HEIGHT,
        blossom: height >= BLOSSOM_HEIGHT,
        heartwood: height >= HEARTWOOD_HEIGHT,
        canopy: height >= CANOPY_HEIGHT,
        nu5: height >= NU5_HEIGHT,
        nu6: height >= NU6_HEIGHT,
    }
}
```

---

## 10. Error Handling

### 10.1 Error Types

```cairo
enum ConsensusError {
    InvalidBlockVersion,
    InvalidDifficulty,
    InvalidEquihashSolution,
    InvalidTimestamp,
    InvalidMerkleRoot,
    InvalidBlockCommitment,
    InvalidTransactionVersion,
    InvalidTransactionStructure,
    UTXONotFound,
    NullifierAlreadySpent,
    InvalidAnchor,
    InvalidProof,
    InvalidSignature,
    InvalidValueBalance,
    CoinbaseMaturityViolation,
    BlockSizeExceeded,
    SubsidyExceeded,
    InvalidCoinbaseScript,
}
```

---

## 11. Optimization Considerations

### 11.1 Cairo-Specific Optimizations

1. **Batch Verification:** Aggregate signature and proof verifications where possible
2. **Lazy State Updates:** Defer expensive state updates until validation passes
3. **Merkle Tree Caching:** Cache intermediate tree nodes to reduce computation
4. **Hint System:** Use Cairo hints for expensive operations (hash preimages, etc.)
5. **Field Arithmetic:** Leverage Cairo's native field operations for curve arithmetic

### 11.2 Proof Generation Strategies

```cairo
// Generate STARK proof for block validation
fn prove_block_validation(block: Block, chain_state: ChainState) -> StarkProof {
    // Run validation in provable mode
    let (valid, new_state) = validate_block_provable(block, chain_state);
    
    // Generate proof
    let proof = cairo_prove(validate_block_provable, (block, chain_state));
    
    proof
}
```

---

## 12. Testing Strategy

### 12.1 Unit Tests

Test each component in isolation:
- Hash functions
- Signature verification
- Proof verification
- State transitions
- Merkle tree operations

### 12.2 Integration Tests

Test full block validation against Zcash mainnet/testnet blocks:
- Genesis block
- Pre-Sapling blocks
- Sapling activation block
- NU5 activation block
- Recent blocks with all pool types

### 12.3 Fuzz Testing

Random input generation for:
- Malformed transactions
- Invalid proofs
- Boundary conditions
- DoS vectors

### 12.4 Consensus Compatibility

```cairo
// Test against Zcash Core reference implementation
fn test_consensus_compatibility() {
    let test_blocks = load_test_vectors("zcash_mainnet_blocks.json");
    
    for (block, expected_valid) in test_blocks {
        let result = validate_block(block, ...);
        assert_eq!(result.is_ok(), expected_valid);
    }
}
```

---

## 13. Implementation Roadmap

### Phase 1: Core Infrastructure (Weeks 1-4)
- ✓ Define data structures
- ✓ Implement hash functions
- ✓ Implement elliptic curve operations
- ✓ Basic serialization/deserialization

### Phase 2: Transparent Validation (Weeks 5-8)
- ✓ UTXO set management
- ✓ Transparent input/output validation
- ✓ Block header validation
- ✓ Equihash verification

### Phase 3: Sprout Support (Weeks 9-12)
- JoinSplit validation
- Ed25519 signatures
- Sprout note commitment trees

### Phase 4: Sapling Support (Weeks 13-18)
- Spend/Output validation
- Groth16 proof verification
- RedJubjub signatures
- Sapling note commitment trees

### Phase 5: Orchard Support (Weeks 19-24)
- Action validation
- Halo 2 proof verification
- RedPallas signatures
- Orchard note commitment trees

### Phase 6: Integration & Testing (Weeks 25-28)
- End-to-end block validation
- Mainnet compatibility testing
- Performance optimization
- Documentation

---

## 14. Security Considerations

### 14.1 Consensus-Critical Components

The following components are consensus-critical and require extreme care:
- Proof verification (Groth16, Halo 2)
- Signature verification (Ed25519, RedJubjub, RedPallas)
- Merkle tree construction
- Value balance calculations
- Nullifier checking

### 14.2 Attack Vectors

1. **Proof Malleability:** Ensure proof encodings are canonical
2. **Signature Malleability:** Reject non-canonical signature encodings
3. **Integer Overflow:** Use checked arithmetic for all value calculations
4. **Merkle Tree Collisions:** Use domain-separated hash functions
5. **Replay Attacks:** Properly track nullifiers across all pools

### 14.3 Audit Requirements

Before mainnet deployment:
- Independent cryptographic audit
- Formal verification of critical paths
- Extensive fuzzing campaign
- Bug bounty program

---

## 15. References

- **[Protocol]** Zcash Protocol Specification v2025.6.1
- **[ZIP-200]** Network Upgrade Mechanism
- **[ZIP-213]** Shielded Coinbase
- **[ZIP-214]** Consensus rules for a Zcash Development Fund
- **[ZIP-221]** FlyClient - Consensus-Layer Changes
- **[ZIP-244]** Transaction Identifier Non-Malleability
- **[BK2016]** Equihash: Asymmetric Proof-of-Work Based on the Generalized Birthday Problem
- **[Cairo]** Cairo Language Documentation

---

## Appendix A: Constants

```cairo
// Network parameters
const MAX_MONEY: u64 = 21_000_000 * 100_000_000;  // 21 million ZEC in zatoshis
const COIN: u64 = 100_000_000;  // 1 ZEC in zatoshis

// Block timing
const TARGET_BLOCK_TIME: u64 = 150;  // 150 seconds (2.5 minutes)
const POW_MEDIAN_BLOCK_SPAN: usize = 11;

// Equihash parameters
const EQUIHASH_N: u32 = 200;
const EQUIHASH_K: u32 = 9;
const EQUIHASH_SOLUTION_SIZE: usize = 1344;

// Curve parameters
const JUBJUB_Q: felt252 = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
const PALLAS_Q: felt252 = 0x40000000000000000000000000000000224698fc094cf91b992d30ed00000001;
```

---

## Appendix B: Transaction ID Calculation

```cairo
fn calculate_txid(tx: Transaction) -> u256 {
    // v1-v4: SHA-256d of serialized transaction
    if tx.version < 5 {
        return sha256d(serialize_tx_legacy(tx));
    }
    
    // v5+: ZIP-244 transaction identifier
    // See ZIP-244 for full specification
    calculate_txid_v5(tx)
}

fn calculate_txid_v5(tx: Transaction) -> u256 {
    // ZIP-244: TxId digest = BLAKE2b-256 hash of:
    // - header_digest
    // - transparent_digest  
    // - sapling_digest
    // - orchard_digest
    
    let header = hash_tx_header(tx);
    let transparent = hash_transparent(tx);
    let sapling = hash_sapling(tx);
    let orchard = hash_orchard(tx);
    
    blake2b_personalized(
        b"ZTxIdSigHash",
        &[header, transparent, sapling, orchard]
    )
}
```

---

## Appendix C: Sample Cairo Module Structure

```
zcash_consensus/
├── src/
│   ├── lib.cairo              # Main entry point
│   ├── block/
│   │   ├── header.cairo       # Block header validation
│   │   ├── validation.cairo   # Block validation logic
│   │   └── subsidy.cairo      # Block subsidy calculation
│   ├── transaction/
│   │   ├── transparent.cairo  # Transparent tx validation
│   │   ├── sprout.cairo       # Sprout (JoinSplit) validation
│   │   ├── sapling.cairo      # Sapling validation
│   │   └── orchard.cairo      # Orchard validation
│   ├── crypto/
│   │   ├── hash.cairo         # Hash functions
│   │   ├── curves.cairo       # Elliptic curve ops
│   │   ├── signatures.cairo   # Signature verification
│   │   └── proofs.cairo       # ZK proof verification
│   ├── state/
│   │   ├── utxo.cairo         # UTXO set
│   │   ├── nullifiers.cairo   # Nullifier set
│   │   └── trees.cairo        # Note commitment trees
│   ├── upgrades.cairo         # Network upgrade logic
│   └── constants.cairo        # Protocol constants
├── tests/
│   ├── unit/                  # Unit tests
│   ├── integration/           # Integration tests
│   └── vectors/               # Test vectors from Zcash
└── Scarb.toml                 # Cairo package manifest
```

---

## Document History

- **v1.0 (2024-11-17):** Initial specification based on Zcash Protocol v2025.6.1

---

**END OF SPECIFICATION**
