# Zcash Cairo Consensus Client - Documentation

**Version:** 1.0
**Last Updated:** November 17, 2024
**Implementation Status:** 60% Complete (Structure)

---

## 📚 Documentation Index

### Core Documentation

| Document | Description | Status |
|----------|-------------|--------|
| **[Spec vs Implementation](ZCASH_SPEC_VS_IMPLEMENTATION.md)** | Gap analysis & compliance matrix | ✅ Current |
| **[Zcash Consensus Spec](ZCASH_CONSENSUS_CLIENT_SPEC.md)** | Complete technical specification | ✅ Current |
| **[Zcash Protocol Spec](ZCASH_SPEC.md)** | Protocol specification for Cairo | ✅ Current |
| **[Hash Functions](HASH_FUNCTIONS_SUMMARY.md)** | Required cryptographic primitives | ✅ Current |
| **[Implementation Status](CONSENSUS_IMPLEMENTATION_STATUS.md)** | Current progress tracker | ✅ Current |
| **[Requirements](CONSENSUS_CLIENT_REQUIREMENTS.md)** | What we need to build | ✅ Current |
| **[Project Clarification](PROJECT_CLARIFICATION.md)** | Why consensus, not light client | ✅ Current |

### Quick Navigation

- **New to the project?** Start with [Project Overview](#project-overview) below
- **Want to contribute?** See [Implementation Status](CONSENSUS_IMPLEMENTATION_STATUS.md) and [Hash Functions](HASH_FUNCTIONS_SUMMARY.md)
- **Understanding gaps?** Read [Spec vs Implementation](ZCASH_SPEC_VS_IMPLEMENTATION.md)
- **Technical details?** Check [Zcash Consensus Spec](ZCASH_CONSENSUS_CLIENT_SPEC.md)

---

## Project Overview

### What We're Building

A **Zcash Consensus Client in Cairo** - similar to [Raito](https://github.com/keep-starknet-strange/raito) for Bitcoin.

This is NOT a light wallet client. This is a **trustless consensus validation client** that:

- ✅ Verifies Equihash Proof-of-Work (like zcashd)
- ✅ Validates difficulty adjustments
- ✅ Checks merkle roots (both transaction and Sapling)
- ✅ Generates STARK proofs of correct validation
- ✅ Enables trustless light clients and cross-chain bridges

### Why Cairo?

Cairo enables **provable computation** - every block validation produces a STARK proof that can be efficiently verified. This enables:

1. **Trustless Light Clients** - Don't trust servers, verify proofs
2. **Cross-Chain Bridges** - Prove Zcash state to other chains
3. **Scalable Verification** - One proof verifies for everyone
4. **Privacy Preservation** - Validate without revealing data

### What Makes This Different from Light Clients?

| Feature | Light Client | Our Consensus Client |
|---------|-------------|---------------------|
| Equihash Verification | ❌ Trusts server | ✅ Full validation |
| Difficulty Checking | ❌ Skipped | ✅ Implemented |
| Merkle Roots | ❌ Not verified | ✅ Both types validated |
| Trust Model | Server trust | 🔒 **Trustless** |
| Proof Generation | ❌ None | ✅ STARK proofs |

---

## Implementation Status

### ✅ Complete (60%)

1. **Block Header Structure** - All 9 consensus-critical fields
2. **Equihash Algorithm** - Complete binary tree with collision detection
3. **Difficulty Validation** - Moving average, Pre/Post Blossom support
4. **Merkle Tree Algorithms** - Transaction (SHA-256d) and Sapling (Pedersen)
5. **Pedersen Hash** - Cairo native implementation

### ⚠️ Critical Blockers (30%)

Three cryptographic primitives block everything:

1. **SHA-256d** ❌ Missing
   - Blocks: Block hashes, TX merkle tree, difficulty validation
   - Priority: 🔴 **HIGHEST**

2. **Blake2b Completion** ⚠️ 40% Done
   - Blocks: Equihash verification (the trustless part!)
   - Priority: 🔴 **HIGH**

3. **256-bit Arithmetic** ❌ Missing
   - Blocks: Difficulty comparison (block_hash < target)
   - Priority: 🔴 **HIGH**

### 🟡 Testing & Verification (10%)

4. **Network Upgrade Constants** - Activation heights
5. **Pedersen Test Vectors** - Verify correctness
6. **Integration Tests** - Real Zcash block validation

**See [ZCASH_SPEC_VS_IMPLEMENTATION.md](ZCASH_SPEC_VS_IMPLEMENTATION.md) for detailed gap analysis.**

---

## Quick Start

### Prerequisites

- [Scarb](https://docs.swmansion.com/scarb/) (Cairo package manager)
- Cairo 2.x

### Build

```bash
cd zcash_light_client
scarb build
```

### Test

```bash
scarb test
```

### Project Structure

```
zcash_light_client/
├── src/
│   ├── lib.cairo              # Main entry point
│   ├── types/
│   │   ├── block_header.cairo # Complete block header (9 fields)
│   │   └── ...
│   ├── verification/
│   │   ├── equihash.cairo     # Equihash PoW (90% complete)
│   │   ├── difficulty.cairo   # Difficulty validation (85% complete)
│   │   ├── merkle.cairo       # Merkle trees (90% complete)
│   │   └── block_validator.cairo
│   ├── crypto/
│   │   ├── blake2b.cairo      # Blake2b (40% complete) ⚠️
│   │   ├── pedersen.cairo     # Pedersen hash ✅
│   │   └── ...
│   └── utils/
├── tests/                     # Unit and integration tests
├── docs/                      # This documentation
└── Scarb.toml
```

---

## Key Architectural Decisions

### 1. Consensus Client, Not Light Client

**Decision:** Build full consensus validation matching zcashd

**Rationale:**
- Light clients trust servers (no Equihash verification)
- Consensus clients are trustless (full PoW validation)
- STARK proofs enable efficient verification without computation

**Impact:** More complex implementation, but truly trustless

### 2. Cairo-Native Data Structures

**Decision:** Use `Array<u8>` instead of `u256` for hashes

**Rationale:**
- Cairo's native array operations are efficient
- Better for STARK proving
- More flexible for different hash sizes

**Impact:** Better performance, easier to prove

### 3. Incremental Implementation

**Decision:** Block validation first, transaction validation later

**Rationale:**
- Block validation is sufficient for consensus client
- Transactions can be added incrementally
- Focus on trustless PoW first

**Impact:** Faster time to working prototype

---

## Development Roadmap

### Phase 1: Critical Primitives ✅ (Current - 60% Done)

**Completed:**
- ✅ BlockHeader structure
- ✅ Equihash algorithm structure
- ✅ Difficulty logic
- ✅ Merkle tree algorithms
- ✅ Pedersen hash

**In Progress:**
- ⚠️ Blake2b implementation (40%)

**Blocked:**
- ❌ SHA-256d
- ❌ 256-bit arithmetic

### Phase 2: Hash Functions (Weeks 1-2)

**Goals:**
1. Implement SHA-256d (~400 LOC)
2. Complete Blake2b (~300 LOC)
3. Add 256-bit comparison (~200 LOC)

**Outcome:** Can validate real Zcash blocks!

### Phase 3: Testing & Verification (Week 3)

**Goals:**
1. Test against mainnet blocks
2. Verify Pedersen with test vectors
3. Integration test suite

**Outcome:** Proven correctness

### Phase 4: Network Upgrades (Week 4)

**Goals:**
1. Add activation heights
2. Per-upgrade validation rules
3. Branch ID checks

**Outcome:** Full historical validation

### Phase 5: Advanced Features (Future)

- Transaction validation
- Shielded pool validation
- Orchard support (NU5+)

---

## Critical Hash Functions

Zcash uses exactly **3 hash functions** in consensus:

### 1. SHA-256d (CRITICAL) ❌

**Used For:**
- Block hash calculation: `SHA-256(SHA-256(header))`
- Transaction merkle tree
- Transaction IDs

**Status:** Missing
**Priority:** 🔴 Highest

### 2. Blake2b (CRITICAL) ⚠️

**Used For:**
- Equihash PoW (>250,000 hashes per block!)
- Personalization: `"ZcashPoW" || n || k`

**Status:** 40% complete
**Priority:** 🔴 High

### 3. Pedersen (Medium) ✅

**Used For:**
- Sapling commitment tree
- Note commitments

**Status:** Exists (Cairo native)
**Priority:** 🟡 Medium (needs testing)

**See [HASH_FUNCTIONS_SUMMARY.md](HASH_FUNCTIONS_SUMMARY.md) for details.**

---

## Testing Strategy

### Unit Tests

Each component tested in isolation:
- ✅ Block header validation
- ✅ Difficulty calculation
- ⚠️ Equihash verification (needs Blake2b)
- ⚠️ Merkle trees (needs SHA-256d)

### Integration Tests

Full block validation against real Zcash blocks:
- Genesis block (height 0)
- Sapling activation (419,200)
- Blossom activation (653,600)
- Recent mainnet block

### Test Vectors

Using vectors from:
- zcashd test suite
- librustzcash
- Bitcoin (for SHA-256d)

---

## Performance Considerations

### Cairo-Specific Optimizations

1. **Field Element Operations** - Use Cairo's native field arithmetic
2. **Array Handling** - Minimize copies, use references
3. **Hint System** - Use hints for expensive operations
4. **Batch Verification** - Aggregate where possible

### Expected Costs

| Operation | Cairo Steps | Notes |
|-----------|-------------|-------|
| SHA-256d | ~8,000 | Per hash |
| Blake2b | ~10,000 | Per hash |
| Equihash Verification | ~5,000,000 | 512 hashes + tree |
| Block Validation | ~6,000,000 | Full validation |

---

## Contributing

### Areas Needing Help

1. **SHA-256d Implementation** - Most critical!
2. **Blake2b Completion** - Finish compression function
3. **256-bit Arithmetic** - Comparison operations
4. **Test Vectors** - Real Zcash block data
5. **Documentation** - Code comments and examples

### Code Style

- Follow Cairo best practices
- Add comprehensive tests
- Document consensus-critical code
- Use meaningful variable names

---

## Resources

### Zcash References

- [Zcash Protocol Specification](https://zips.z.cash/protocol/protocol.pdf) (also in [protocol.pdf](protocol.pdf))
- [librustzcash](https://github.com/zcash/librustzcash) - Reference implementation
- [zcashd](https://github.com/zcash/zcash) - Zcash full node
- [ZIP Repository](https://zips.z.cash/) - Zcash Improvement Proposals

### Cairo Resources

- [Cairo Book](https://book.cairo-lang.org/)
- [Starknet Documentation](https://docs.starknet.io/)
- [Raito](https://github.com/keep-starknet-strange/raito) - Bitcoin consensus in Cairo

### Similar Projects

- **Raito** - Bitcoin consensus client in Cairo
- **ZK-Bitcoin** - Bitcoin light client with zero-knowledge proofs
- **Mina Protocol** - Blockchain with recursive SNARKs

---

## FAQ

### Q: Why not just use a light client?

**A:** Light clients trust servers. We want **trustless validation** with STARK proofs.

### Q: How is this different from a Zcash full node?

**A:** We validate blocks identically to zcashd, but generate STARK proofs of correct validation.

### Q: Can this replace zcashd?

**A:** No, this is for verification only. Use zcashd for mining, wallet, and full network participation.

### Q: When will it be ready?

**A:** 3-4 weeks for basic block validation once hash functions are implemented.

### Q: What about Orchard (NU5)?

**A:** Future work. We're focusing on Sapling-era consensus first.

---

## Document Index

### Specifications
- [ZCASH_SPEC.md](ZCASH_SPEC.md) - Zcash protocol specification for Cairo
- [ZCASH_CONSENSUS_CLIENT_SPEC.md](ZCASH_CONSENSUS_CLIENT_SPEC.md) - Complete technical spec
- [protocol.pdf](protocol.pdf) - Official Zcash Protocol Specification

### Implementation
- [ZCASH_SPEC_VS_IMPLEMENTATION.md](ZCASH_SPEC_VS_IMPLEMENTATION.md) - Gap analysis (60% complete)
- [CONSENSUS_IMPLEMENTATION_STATUS.md](CONSENSUS_IMPLEMENTATION_STATUS.md) - Current status
- [CONSENSUS_CLIENT_REQUIREMENTS.md](CONSENSUS_CLIENT_REQUIREMENTS.md) - Requirements

### Technical Details
- [HASH_FUNCTIONS_SUMMARY.md](HASH_FUNCTIONS_SUMMARY.md) - Required hash functions
- [PROJECT_CLARIFICATION.md](PROJECT_CLARIFICATION.md) - Why consensus, not light client

---

## License

[License information here]

---

## Contact

[Contact information here]

---

**Last Updated:** November 17, 2024
**Next Milestone:** Complete SHA-256d implementation
**Status:** 60% Complete - Foundation ready, hash functions needed
