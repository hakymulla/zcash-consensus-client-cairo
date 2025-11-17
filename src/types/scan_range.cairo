/// Scan Range with Priority System for Spend-Before-Sync
/// Implements ZIP-307 priority-based block scanning

use super::compact_block::BlockHeight;

/// Priority levels for scan ranges (0-60 scale from Swift SDK)
#[derive(Drop, Copy, Serde, PartialEq, Debug)]
pub enum ScanPriority {
    /// Ignored - blocks that don't need scanning
    Ignored,        // 0

    /// Already scanned blocks
    Scanned,        // 10

    /// Historical blocks (low priority)
    Historic,       // 20

    /// Blocks adjacent to found notes
    OpenAdjacent,   // 30

    /// Blocks containing user's notes (high priority)
    FoundNote,      // 40

    /// Recent blocks near chain tip
    ChainTip,       // 50

    /// Blocks requiring verification
    Verify,         // 60
}

pub trait ScanPriorityTrait {
    fn to_u8(self: ScanPriority) -> u8;
    fn should_scan(self: ScanPriority) -> bool;
}

impl ScanPriorityImpl of ScanPriorityTrait {
    /// Convert to numeric priority value
    fn to_u8(self: ScanPriority) -> u8 {
        match self {
            ScanPriority::Ignored => 0,
            ScanPriority::Scanned => 10,
            ScanPriority::Historic => 20,
            ScanPriority::OpenAdjacent => 30,
            ScanPriority::FoundNote => 40,
            ScanPriority::ChainTip => 50,
            ScanPriority::Verify => 60,
        }
    }

    /// Check if this range should be scanned
    fn should_scan(self: ScanPriority) -> bool {
        match self {
            ScanPriority::Ignored | ScanPriority::Scanned => false,
            _ => true,
        }
    }
}

/// Range of blocks to scan with associated priority
#[derive(Drop, Serde, Debug)]
pub struct ScanRange {
    /// Start block height (inclusive)
    pub start_height: BlockHeight,

    /// End block height (exclusive)
    pub end_height: BlockHeight,

    /// Priority for this range
    pub priority: ScanPriority,
}

pub trait ScanRangeTrait {
    fn new(start: BlockHeight, end: BlockHeight, priority: ScanPriority) -> ScanRange;
    fn len(self: @ScanRange) -> u64;
    fn is_empty(self: @ScanRange) -> bool;
    fn contains(self: @ScanRange, height: BlockHeight) -> bool;
    fn split_into_batches(self: @ScanRange, batch_size: u64) -> Array<ScanRange>;
}

impl ScanRangeImpl of ScanRangeTrait {
    /// Create a new scan range
    fn new(start: BlockHeight, end: BlockHeight, priority: ScanPriority) -> ScanRange {
        ScanRange {
            start_height: start,
            end_height: end,
            priority: priority,
        }
    }

    /// Get the number of blocks in this range
    fn len(self: @ScanRange) -> u64 {
        if *self.end_height > *self.start_height {
            *self.end_height - *self.start_height
        } else {
            0
        }
    }

    /// Check if range is empty
    fn is_empty(self: @ScanRange) -> bool {
        self.len() == 0
    }

    /// Check if a block height is within this range
    fn contains(self: @ScanRange, height: BlockHeight) -> bool {
        height >= *self.start_height && height < *self.end_height
    }

    /// Split range into batches for processing
    fn split_into_batches(self: @ScanRange, batch_size: u64) -> Array<ScanRange> {
        let mut ranges = ArrayTrait::new();
        let mut current_start = *self.start_height;

        loop {
            if current_start >= *self.end_height {
                break;
            }

            let batch_end = if current_start + batch_size < *self.end_height {
                current_start + batch_size
            } else {
                *self.end_height
            };

            ranges.append(ScanRange {
                start_height: current_start,
                end_height: batch_end,
                priority: *self.priority,
            });

            current_start = batch_end;
        };

        ranges
    }
}

/// Summary of a scanning operation
#[derive(Drop, Serde, Debug)]
pub struct ScanSummary {
    /// Range that was scanned
    pub scanned_range: ScanRange,

    /// Number of spent Sapling notes found
    pub spent_sapling_notes: u32,

    /// Number of received Sapling notes found
    pub received_sapling_notes: u32,

    /// Number of spent Orchard notes found
    pub spent_orchard_notes: u32,

    /// Number of received Orchard notes found
    pub received_orchard_notes: u32,
}

pub trait ScanSummaryTrait {
    fn total_notes(self: @ScanSummary) -> u32;
    fn found_notes(self: @ScanSummary) -> bool;
}

impl ScanSummaryImpl of ScanSummaryTrait {
    /// Total notes discovered
    fn total_notes(self: @ScanSummary) -> u32 {
        *self.spent_sapling_notes + *self.received_sapling_notes
            + *self.spent_orchard_notes + *self.received_orchard_notes
    }

    /// Check if any notes were found
    fn found_notes(self: @ScanSummary) -> bool {
        self.total_notes() > 0
    }
}

/// Batch processing configuration
pub const SCAN_BATCH_SIZE: u64 = 100; // Process 100 blocks at a time