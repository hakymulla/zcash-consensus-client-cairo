/// Difficulty Adjustment and Target Validation
/// Based on Bitcoin's difficulty adjustment algorithm used by Zcash
///
/// Reference: Bitcoin Core's pow.cpp and Zcash's validation logic

use crate::types::block_header::{BlockHeader, BlockHeight};
use crate::utils::errors::ZcashError;

/// Difficulty target representation
/// The target is a 256-bit number that the block hash must be below
#[derive(Drop, Copy, Debug)]
pub struct Target {
    /// 256-bit target represented as 4 u64 values (little-endian)
    /// target = [low, mid_low, mid_high, high]
    pub value: (u64, u64, u64, u64),
}

/// Network parameters for difficulty calculation
#[derive(Drop, Copy, Debug)]
pub struct DifficultyParams {
    /// Target block time (seconds)
    pub target_spacing: u32,

    /// Difficulty adjustment interval (blocks)
    /// Zcash adjusts every block, so this is 1
    pub pow_averaging_window: u32,

    /// Maximum adjustment ratio
    pub pow_max_adjust_down: u32,
    pub pow_max_adjust_up: u32,
}

impl DifficultyParamsTrait of Clone<DifficultyParams> {
    fn clone(self: @DifficultyParams) -> DifficultyParams {
        DifficultyParams {
            target_spacing: *self.target_spacing,
            pow_averaging_window: *self.pow_averaging_window,
            pow_max_adjust_down: *self.pow_max_adjust_down,
            pow_max_adjust_up: *self.pow_max_adjust_up,
        }
    }
}

/// Get difficulty parameters for different network upgrades
pub fn get_difficulty_params(height: BlockHeight, is_blossom_active: bool) -> DifficultyParams {
    if is_blossom_active {
        // Post-Blossom: 75 second blocks
        DifficultyParams {
            target_spacing: 75,
            pow_averaging_window: 17,
            pow_max_adjust_down: 32,  // 32% max decrease
            pow_max_adjust_up: 16,    // 16% max increase
        }
    } else {
        // Pre-Blossom: 150 second blocks
        DifficultyParams {
            target_spacing: 150,
            pow_averaging_window: 17,
            pow_max_adjust_down: 32,
            pow_max_adjust_up: 16,
        }
    }
}

/// Expand compact "bits" representation to full 256-bit target
///
/// Compact format: 0xNNEEEEEE
/// - NN: Exponent (number of bytes)
/// - EEEEEE: Mantissa (3 bytes)
///
/// Formula: target = mantissa * 256^(exponent - 3)
///
/// Example: 0x1d00ffff
/// - Exponent: 0x1d = 29
/// - Mantissa: 0x00ffff = 65535
/// - Target: 0x00ffff * 256^(29-3) = 0x00ffff * 256^26
pub fn expand_compact_bits(bits: u32) -> Target {
    // Extract exponent and mantissa
    let exponent = ((bits >> 24) & 0xFF) as u8;
    let mantissa = bits & 0x00FFFFFF;

    // Handle special cases
    if mantissa == 0 || exponent == 0 {
        return Target { value: (0, 0, 0, 0) };
    }

    // Calculate target
    // For now, return a simplified version
    // TODO: Implement full 256-bit arithmetic when hash functions are ready
    Target {
        value: (
            mantissa.into(),  // Low 64 bits
            0,                // Mid-low 64 bits
            0,                // Mid-high 64 bits
            0,                // High 64 bits
        )
    }
}

/// Compress a 256-bit target to compact "bits" representation
pub fn compact_target(target: @Target) -> u32 {
    // TODO: Implement full compression
    // For now, return a placeholder
    0x1d00ffff
}

/// Check if a block hash meets the difficulty target
///
/// Valid if: block_hash < target
pub fn check_proof_of_work(
    block_hash: @Array<u8>,
    bits: u32
) -> Result<(), ZcashError> {
    // Expand the target
    let target = expand_compact_bits(bits);

    // TODO: Implement when SHA-256d is ready
    // For now, we'll validate the structure
    if block_hash.len() != 32 {
        return Result::Err(ZcashError::ValidationError("Invalid block hash size"));
    }

    if bits == 0 {
        return Result::Err(ZcashError::ValidationError("Invalid difficulty bits"));
    }

    // Placeholder: Will implement full comparison when hash functions ready
    Result::Ok(())
}

/// Calculate the next difficulty target
///
/// Zcash uses a moving average of the last N blocks' solve times
/// to adjust difficulty every block (unlike Bitcoin's 2016 block adjustment)
///
/// Algorithm:
/// 1. Calculate average solve time over averaging window
/// 2. Compare to target spacing
/// 3. Adjust difficulty proportionally (with limits)
pub fn calculate_next_difficulty(
    prev_headers: Span<BlockHeader>,
    params: DifficultyParams,
) -> Result<u32, ZcashError> {
    let window_size = params.pow_averaging_window;

    if prev_headers.len() < window_size.into() {
        return Result::Err(
            ZcashError::ValidationError("Not enough blocks for difficulty calculation")
        );
    }

    // Get the first and last block in the averaging window
    let first_block = prev_headers[0];
    let last_block = prev_headers[prev_headers.len() - 1];

    // Calculate actual time span
    let actual_timespan = *last_block.time - *first_block.time;

    // Calculate expected time span
    let expected_timespan = params.target_spacing * (window_size - 1);

    // Calculate adjustment ratio (with bounds)
    // new_target = old_target * (actual_time / expected_time)
    // Bounded by max_adjust_down and max_adjust_up

    // TODO: Implement full arithmetic when ready
    // For now, return the last block's bits
    Result::Ok(*last_block.bits)
}

/// Validate difficulty transition is correct
pub fn validate_difficulty_transition(
    curr_header: @BlockHeader,
    prev_headers: Span<BlockHeader>,
    params: DifficultyParams,
) -> Result<(), ZcashError> {
    // Calculate expected difficulty
    let expected_bits = calculate_next_difficulty(prev_headers, params)?;

    // Check if current block's bits match expected
    if *curr_header.bits != expected_bits {
        return Result::Err(
            ZcashError::ValidationError("Incorrect difficulty adjustment")
        );
    }

    Result::Ok(())
}

/// Full difficulty validation for a block
pub fn validate_block_difficulty(
    header: @BlockHeader,
    prev_headers: Span<BlockHeader>,
    height: BlockHeight,
    is_blossom_active: bool,
) -> Result<(), ZcashError> {
    // Get difficulty parameters
    let params = get_difficulty_params(height, is_blossom_active);

    // 1. Check proof of work (hash < target)
    check_proof_of_work(@header.hash, *header.bits)?;

    // 2. Validate difficulty adjustment is correct
    if prev_headers.len() > 0 {
        validate_difficulty_transition(header, prev_headers, params)?;
    }

    Result::Ok(())
}

#[cfg(test)]
mod tests {
    use super::{expand_compact_bits, compact_target, Target, get_difficulty_params};

    #[test]
    fn test_expand_compact_bits_mainnet_genesis() {
        // Mainnet genesis: 0x1f07ffff
        let bits: u32 = 0x1f07ffff;
        let target = expand_compact_bits(bits);

        // Should have mantissa in low bits
        assert!(target.value.0 > 0, "Target should have non-zero mantissa");
    }

    #[test]
    fn test_expand_compact_bits_testnet() {
        // Testnet: 0x2007ffff
        let bits: u32 = 0x2007ffff;
        let target = expand_compact_bits(bits);

        assert!(target.value.0 > 0, "Target should have non-zero mantissa");
    }

    #[test]
    fn test_difficulty_params_pre_blossom() {
        let params = get_difficulty_params(1000, false);
        assert!(params.target_spacing == 150, "Should be 150s pre-Blossom");
    }

    #[test]
    fn test_difficulty_params_post_blossom() {
        let params = get_difficulty_params(1000000, true);
        assert!(params.target_spacing == 75, "Should be 75s post-Blossom");
    }
}
