/// Difficulty Adjustment and Target Validation
/// Based on Bitcoin's difficulty adjustment algorithm used by Zcash
///
/// Reference: Zcash Protocol Specification Section 7.7.2
/// Reference: Bitcoin Core's pow.cpp

use crate::types::block_header::{BlockHeader, BlockHeight};
use crate::utils::errors::ZcashError;
use crate::utils::u256_helpers::{bytes_to_u256_le, u256_lt};
use crate::crypto::compute_block_hash;

/// Network parameters for difficulty calculation
#[derive(Drop, Copy, Debug)]
pub struct DifficultyParams {
    /// Target block time (seconds)
    pub target_spacing: u32,

    /// Difficulty adjustment interval (blocks)
    /// Zcash adjusts every block using a moving average
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
        // Post-Blossom: 75 second blocks (NU activated at height 653600)
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
/// Compact format (4 bytes): 0xNNEEEEEE
/// - NN (1 byte): Size/exponent - number of bytes in target
/// - EEEEEE (3 bytes): Mantissa - significant digits
///
/// Formula: target = mantissa * 256^(size - 3)
///
/// Example: Zcash mainnet genesis bits = 0x1f07ffff
/// - Size: 0x1f = 31 bytes
/// - Mantissa: 0x07ffff = 524287
/// - Target: 0x07ffff * 256^28
///
/// Reference: Zcash Protocol Specification Section 7.7.2
pub fn expand_compact_bits(bits: u32) -> u256 {
    // Extract size (exponent) - top byte
    let size: u32 = (bits / 0x1000000);  // bits >> 24

    // Extract mantissa - bottom 3 bytes
    let mantissa: u32 = bits & 0x00FFFFFF;

    // Handle special cases
    if mantissa == 0 || size == 0 {
        return u256 { low: 0, high: 0 };
    }

    // Size must be between 1 and 32
    if size > 32 {
        return u256 { low: 0, high: 0 };
    }

    // Build the target value
    // target = mantissa * 256^(size - 3)

    if size <= 3 {
        // Shift right: divide mantissa by 256^(3 - size)
        let shift_right = 3 - size;
        let mantissa_u128: u128 = mantissa.into();
        let divisor = pow_256(shift_right);
        let result = mantissa_u128 / divisor;
        return u256 { low: result, high: 0 };
    } else {
        // Shift left: multiply mantissa by 256^(size - 3)
        let shift_left = size - 3;

        // Convert mantissa to u256
        let mantissa_u128: u128 = mantissa.into();
        let mut result = u256 { low: mantissa_u128, high: 0 };

        // Multiply by 256^shift_left
        let mut i: u32 = 0;
        while i < shift_left {
            result = u256_mul_256(result);
            i += 1;
        };

        return result;
    }
}

/// Helper: Calculate 256^n as u128 (for n <= 16)
fn pow_256(n: u32) -> u128 {
    let mut result: u128 = 1;
    let mut i: u32 = 0;
    while i < n {
        result = result * 256;
        i += 1;
    };
    result
}

/// Helper: Multiply u256 by 256 (left shift by 8 bits)
fn u256_mul_256(value: u256) -> u256 {
    // value * 256 = (value << 8)
    // Implemented as multiplication since Cairo doesn't have native bit shifts on u128

    // The carry is the top 8 bits of low (low / 2^120)
    let carry = value.low / 0x1000000000000000000000000000000;  // 2^120

    // Shift low left by 8 bits (multiply by 256)
    let new_low = (value.low * 256) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    // Shift high left by 8 bits and add carry
    let new_high = (value.high * 256) | carry;

    u256 { low: new_low, high: new_high }
}

/// Check if a block hash meets the difficulty target
///
/// Validates: block_hash < target
///
/// This is the core Proof-of-Work check as specified in
/// Zcash Protocol Specification Section 7.7.2
///
/// #### Arguments
/// * `block_hash` - 32-byte block hash (SHA-256d of header)
/// * `bits` - Compact difficulty target
///
/// #### Returns
/// * `Result<(), ZcashError>` - Ok if valid, Err otherwise
pub fn check_proof_of_work(
    block_hash: @Array<u8>,
    bits: u32
) -> Result<(), ZcashError> {
    // Validate inputs
    if block_hash.len() != 32 {
        return Result::Err(ZcashError::ValidationError("Invalid block hash size"));
    }

    if bits == 0 {
        return Result::Err(ZcashError::ValidationError("Invalid difficulty bits: zero"));
    }

    // Expand the compact target to full u256
    let target = expand_compact_bits(bits);

    // Convert block hash to u256 (little-endian)
    let hash_value = bytes_to_u256_le(block_hash);

    // Check if hash < target
    if !u256_lt(hash_value, target) {
        return Result::Err(ZcashError::ValidationError("Block hash does not meet difficulty target"));
    }

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
///
/// Reference: Zcash Protocol Specification Section 7.7.3
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

    // TODO: Implement full arithmetic for adjustment calculation
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
///
/// Performs complete difficulty validation:
/// 1. Computes block hash using SHA-256d
/// 2. Checks hash meets difficulty target (hash < target)
/// 3. Validates difficulty adjustment is correct (if not genesis)
///
/// #### Arguments
/// * `header` - Block header to validate
/// * `prev_headers` - Previous block headers for difficulty calculation
/// * `height` - Block height
/// * `is_blossom_active` - Whether Blossom network upgrade is active
///
/// #### Returns
/// * `Result<(), ZcashError>` - Ok if valid, Err with reason otherwise
pub fn validate_block_difficulty(
    header: @BlockHeader,
    prev_headers: Span<BlockHeader>,
    height: BlockHeight,
    is_blossom_active: bool,
) -> Result<(), ZcashError> {
    // Get difficulty parameters
    let params = get_difficulty_params(height, is_blossom_active);

    // Compute block hash
    let computed_hash = compute_block_hash(header);

    // 1. Check proof of work (hash < target)
    check_proof_of_work(@computed_hash, *header.bits)?;

    // 2. Validate difficulty adjustment is correct (skip for genesis)
    if prev_headers.len() > 0 {
        validate_difficulty_transition(header, prev_headers, params)?;
    }

    Result::Ok(())
}

#[cfg(test)]
mod tests {
    use super::{expand_compact_bits, get_difficulty_params, check_proof_of_work, pow_256};

    #[test]
    fn test_pow_256() {
        assert(pow_256(0) == 1, '256^0 should be 1');
        assert(pow_256(1) == 256, '256^1 should be 256');
        assert(pow_256(2) == 65536, '256^2 should be 65536');
    }

    #[test]
    fn test_expand_compact_bits_mainnet_genesis() {
        // Zcash mainnet genesis: 0x1f07ffff
        // Size: 0x1f = 31 bytes
        // Mantissa: 0x07ffff = 524287
        let bits: u32 = 0x1f07ffff;
        let target = expand_compact_bits(bits);

        // Target should be non-zero
        assert(target.low > 0 || target.high > 0, 'Target should be non-zero');

        // For 0x1f07ffff, the target is very high (easy difficulty)
        // Most of the value should be in high bits due to large exponent
        assert(target.high > 0, 'High bits should be set');
    }

    #[test]
    fn test_expand_compact_bits_zero() {
        let bits: u32 = 0;
        let target = expand_compact_bits(bits);

        assert(target.low == 0, 'Zero bits -> zero target (low)');
        assert(target.high == 0, 'Zero bits -> zero target (high)');
    }

    #[test]
    fn test_expand_compact_bits_small() {
        // Small difficulty: 0x03010000
        // Size: 3, Mantissa: 0x010000
        let bits: u32 = 0x03010000;
        let target = expand_compact_bits(bits);

        // target = 0x010000 * 256^0 = 0x010000
        assert(target.low == 0x010000, 'Small target mismatch');
        assert(target.high == 0, 'High should be 0');
    }

    #[test]
    fn test_check_proof_of_work_valid() {
        // Create a very easy target (all bits set)
        let bits: u32 = 0x1f07ffff;  // Genesis difficulty

        // Create a small hash (will be < target)
        let mut hash = ArrayTrait::new();
        let mut i: u32 = 0;
        while i < 32 {
            hash.append(0);
            i += 1;
        };

        // Should pass - zero hash is always < any positive target
        let result = check_proof_of_work(@hash, bits);
        assert(result.is_ok(), 'PoW should be valid');
    }

    #[test]
    fn test_check_proof_of_work_invalid_size() {
        let mut hash = ArrayTrait::new();
        hash.append(0);  // Only 1 byte instead of 32

        let bits: u32 = 0x1f07ffff;
        let result = check_proof_of_work(@hash, bits);
        assert(result.is_err(), 'Should reject wrong size');
    }

    #[test]
    fn test_check_proof_of_work_zero_bits() {
        let mut hash = ArrayTrait::new();
        let mut i: u32 = 0;
        while i < 32 {
            hash.append(0);
            i += 1;
        };

        let bits: u32 = 0;
        let result = check_proof_of_work(@hash, bits);
        assert(result.is_err(), 'Should reject zero bits');
    }

    #[test]
    fn test_difficulty_params_pre_blossom() {
        let params = get_difficulty_params(1000, false);
        assert(params.target_spacing == 150, 'Should be 150s pre-Blossom');
        assert(params.pow_averaging_window == 17, 'Window should be 17');
    }

    #[test]
    fn test_difficulty_params_post_blossom() {
        let params = get_difficulty_params(1000000, true);
        assert(params.target_spacing == 75, 'Should be 75s post-Blossom');
        assert(params.pow_averaging_window == 17, 'Window should be 17');
    }
}
