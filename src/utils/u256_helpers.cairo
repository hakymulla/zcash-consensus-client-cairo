/// u256 Utilities for Zcash Consensus
///
/// Provides conversion functions between byte arrays and u256 values,
/// required for difficulty validation and block hash comparison.
///
/// All conversions use little-endian byte order (Zcash/Bitcoin standard).

use core::array::ArrayTrait;

/// Convert 32-byte array to u256 (little-endian)
///
/// Used for:
/// - Converting block hashes to u256 for difficulty comparison
/// - Converting difficulty targets to u256
///
/// #### Arguments
/// * `bytes` - 32-byte array in little-endian order
///
/// #### Returns
/// * `u256` - 256-bit unsigned integer
///
/// #### Panics
/// * If bytes.len() != 32
pub fn bytes_to_u256_le(bytes: @Array<u8>) -> u256 {
    assert(bytes.len() == 32, 'Must be 32 bytes');

    let mut low: u128 = 0;
    let mut high: u128 = 0;

    // Build low 128 bits (bytes 0-15)
    let mut i: u32 = 0;
    while i < 16 {
        let byte_val: u128 = (*bytes[i]).into();
        low = low | (byte_val * pow2_u128(i * 8));
        i += 1;
    };

    // Build high 128 bits (bytes 16-31)
    i = 0;
    while i < 16 {
        let byte_val: u128 = (*bytes[16 + i]).into();
        high = high | (byte_val * pow2_u128(i * 8));
        i += 1;
    };

    u256 { low, high }
}

/// Helper: Calculate 2^n for u128 (for n <= 127)
fn pow2_u128(n: u32) -> u128 {
    let mut result: u128 = 1;
    let mut i: u32 = 0;
    while i < n {
        result = result * 2;
        i += 1;
    };
    result
}

/// Convert u256 to 32-byte array (little-endian)
///
/// Used for:
/// - Converting difficulty targets back to byte representation
/// - Serializing u256 values
///
/// #### Arguments
/// * `value` - 256-bit unsigned integer
///
/// #### Returns
/// * `Array<u8>` - 32-byte array in little-endian order
pub fn u256_to_bytes_le(value: u256) -> Array<u8> {
    let mut bytes = ArrayTrait::new();

    // Low 128 bits (16 bytes)
    let mut i: u32 = 0;
    while i < 16 {
        let byte = ((value.low / pow2_u128(i * 8)) & 0xFF);
        bytes.append(byte.try_into().unwrap());
        i += 1;
    };

    // High 128 bits (16 bytes)
    i = 0;
    while i < 16 {
        let byte = ((value.high / pow2_u128(i * 8)) & 0xFF);
        bytes.append(byte.try_into().unwrap());
        i += 1;
    };

    bytes
}

/// Compare two u256 values
///
/// Returns true if a < b
pub fn u256_lt(a: u256, b: u256) -> bool {
    if a.high < b.high {
        return true;
    }
    if a.high > b.high {
        return false;
    }
    // High parts are equal, compare low parts
    a.low < b.low
}

/// Compare two u256 values for equality
pub fn u256_eq(a: u256, b: u256) -> bool {
    a.high == b.high && a.low == b.low
}

#[cfg(test)]
mod tests {
    use super::{bytes_to_u256_le, u256_to_bytes_le, u256_lt, u256_eq};

    #[test]
    fn test_u256_roundtrip() {
        let original = u256 { low: 0x0123456789ABCDEF0123456789ABCDEF, high: 0xFEDCBA9876543210FEDCBA9876543210 };
        let bytes = u256_to_bytes_le(original);
        let recovered = bytes_to_u256_le(@bytes);

        assert(recovered.low == original.low, 'Low mismatch');
        assert(recovered.high == original.high, 'High mismatch');
    }

    #[test]
    fn test_u256_lt() {
        let a = u256 { low: 100, high: 0 };
        let b = u256 { low: 200, high: 0 };

        assert(u256_lt(a, b), 'a should be < b');
        assert(!u256_lt(b, a), 'b should not be < a');
    }

    #[test]
    fn test_u256_lt_high_bits() {
        let a = u256 { low: 200, high: 1 };
        let b = u256 { low: 100, high: 2 };

        assert(u256_lt(a, b), 'High bits should dominate');
    }

    #[test]
    fn test_u256_eq() {
        let a = u256 { low: 123, high: 456 };
        let b = u256 { low: 123, high: 456 };
        let c = u256 { low: 123, high: 457 };

        assert(u256_eq(a, b), 'Equal values');
        assert(!u256_eq(a, c), 'Unequal values');
    }

    #[test]
    fn test_bytes_to_u256_zero() {
        let mut bytes = ArrayTrait::new();
        let mut i: u32 = 0;
        while i < 32 {
            bytes.append(0);
            i += 1;
        };

        let value = bytes_to_u256_le(@bytes);
        assert(value.low == 0, 'Low should be 0');
        assert(value.high == 0, 'High should be 0');
    }

    #[test]
    fn test_bytes_to_u256_max() {
        let mut bytes = ArrayTrait::new();
        let mut i: u32 = 0;
        while i < 32 {
            bytes.append(0xFF);
            i += 1;
        };

        let value = bytes_to_u256_le(@bytes);
        assert(value.low == 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 'Low should be max');
        assert(value.high == 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 'High should be max');
    }

    #[test]
    fn test_little_endian_order() {
        let mut bytes = ArrayTrait::new();
        bytes.append(0x78);  // Least significant byte
        bytes.append(0x56);
        bytes.append(0x34);
        bytes.append(0x12);

        let mut i: u32 = 4;
        while i < 32 {
            bytes.append(0);
            i += 1;
        };

        let value = bytes_to_u256_le(@bytes);
        // In little-endian: 0x12345678
        assert(value.low == 0x12345678, 'LE byte order mismatch');
    }
}
