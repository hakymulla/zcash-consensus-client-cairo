/// Nullifier generation and management
/// Prevents double-spending by tracking spent notes

use core::pedersen::pedersen;
use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

/// Nullifier type - unique identifier for spent notes
#[derive(Drop, Copy, Serde, PartialEq, Debug)]
pub struct Nullifier {
    pub value: felt252,
}

/// Nullifier key for deriving nullifiers
#[derive(Drop, Copy, Serde, Debug)]
pub struct NullifierKey {
    pub nk: felt252,
}

pub trait NullifierTrait {
    fn derive(nk: @NullifierKey, rho: felt252, position: u64) -> Nullifier;
    fn equals(self: @Nullifier, other: @Nullifier) -> bool;
}

impl NullifierImpl of NullifierTrait {
    /// Generate nullifier for a note
    fn derive(
        nk: @NullifierKey,
        rho: felt252,  // Note's rho (randomness)
        position: u64   // Note's position in commitment tree
    ) -> Nullifier {
        // PRF_nf^nk(rho)
        // Simplified - real implementation would use Blake2s
        let pos_felt: felt252 = position.into();
        let h1 = pedersen(*nk.nk, rho);
        let nullifier_value = pedersen(h1, pos_felt);

        Nullifier { value: nullifier_value }
    }

    /// Check if two nullifiers are equal
    fn equals(self: @Nullifier, other: @Nullifier) -> bool {
        *self.value == *other.value
    }
}

/// Nullifier set for tracking spent notes
#[derive(Drop, Serde)]
pub struct NullifierSet {
    /// Set of nullifiers (using array for simplicity)
    /// In production, use a more efficient data structure
    pub nullifiers: Array<Nullifier>,

    /// Merkle root of nullifier set for compact representation
    pub merkle_root: felt252,
}

pub trait NullifierSetTrait {
    fn new() -> NullifierSet;
    fn contains(self: @NullifierSet, nullifier: @Nullifier) -> bool;
    fn insert(ref self: NullifierSet, nullifier: Nullifier) -> bool;
    fn update_merkle_root(ref self: NullifierSet);
    fn len(self: @NullifierSet) -> usize;
    fn clear(ref self: NullifierSet);
}

impl NullifierSetImpl of NullifierSetTrait {
    /// Create empty nullifier set
    fn new() -> NullifierSet {
        NullifierSet {
            nullifiers: ArrayTrait::new(),
            merkle_root: 0,
        }
    }

    /// Check if nullifier exists (note is spent)
    fn contains(self: @NullifierSet, nullifier: @Nullifier) -> bool {
        let nullifiers = self.nullifiers.span();
        let mut i = 0;
        loop {
            if i >= nullifiers.len() {
                break false;
            }
            if nullifiers[i].equals(nullifier) {
                break true;
            }
            i += 1;
        }
    }

    /// Add nullifier to set (mark note as spent)
    fn insert(ref self: NullifierSet, nullifier: Nullifier) -> bool {
        if self.contains(@nullifier) {
            false // Already exists
        } else {
            self.nullifiers.append(nullifier);
            self.update_merkle_root();
            true
        }
    }

    /// Update merkle root after insertion
    fn update_merkle_root(ref self: NullifierSet) {
        // Simplified merkle root calculation
        let mut root = 0;
        let nullifiers = self.nullifiers.span();

        let mut i = 0;
        loop {
            if i >= nullifiers.len() {
                break;
            }
            root = pedersen(root, *nullifiers[i].value);
            i += 1;
        };

        self.merkle_root = root;
    }

    /// Get number of nullifiers
    fn len(self: @NullifierSet) -> usize {
        self.nullifiers.len()
    }

    /// Clear all nullifiers
    fn clear(ref self: NullifierSet) {
        self.nullifiers = ArrayTrait::new();
        self.merkle_root = 0;
    }
}

/// Storage-efficient nullifier cache for recent blocks
#[derive(Drop, Serde)]
pub struct NullifierCache {
    /// Recent nullifiers for quick access
    pub recent: Array<Nullifier>,

    /// Maximum cache size
    pub max_size: usize,

    /// Height of oldest cached nullifier
    pub oldest_height: u64,
}

pub trait NullifierCacheTrait {
    fn new(max_size: usize) -> NullifierCache;
    fn add(ref self: NullifierCache, nullifier: Nullifier, height: u64);
    fn contains(self: @NullifierCache, nullifier: @Nullifier) -> bool;
    fn clear_before(ref self: NullifierCache, height: u64);
}

impl NullifierCacheImpl of NullifierCacheTrait {
    /// Create new cache with size limit
    fn new(max_size: usize) -> NullifierCache {
        NullifierCache {
            recent: ArrayTrait::new(),
            max_size,
            oldest_height: 0,
        }
    }

    /// Add nullifier to cache
    fn add(ref self: NullifierCache, nullifier: Nullifier, height: u64) {
        // Remove oldest if at capacity
        if self.recent.len() >= self.max_size {
            self.recent.pop_front();
        }

        self.recent.append(nullifier);

        if self.recent.len() == 1 {
            self.oldest_height = height;
        }
    }

    /// Quick check if nullifier is in cache
    fn contains(self: @NullifierCache, nullifier: @Nullifier) -> bool {
        let recent = self.recent.span();
        let mut i = 0;
        loop {
            if i >= recent.len() {
                break false;
            }
            if recent[i].equals(nullifier) {
                break true;
            }
            i += 1;
        }
    }

    /// Clear cache entries older than height
    fn clear_before(ref self: NullifierCache, height: u64) {
        if height > self.oldest_height {
            // In real implementation, track heights per nullifier
            // For now, clear if oldest is before threshold
            self.recent = ArrayTrait::new();
            self.oldest_height = height;
        }
    }
}