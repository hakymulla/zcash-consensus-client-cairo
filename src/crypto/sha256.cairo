/// SHA-256d (Double SHA-256) Implementation for Zcash
///
/// Used for:
/// - Block hash calculation (Section 7.6 of Zcash Protocol Spec)
/// - Transaction merkle tree construction
/// - Transaction ID computation
///
/// SHA-256d(x) = SHA-256(SHA-256(x))
///
/// This is identical to Bitcoin's double-SHA-256 construction.
/// Reference: Zcash Protocol Specification Section 5.4.1

use core::array::ArrayTrait;
use crate::types::block_header::BlockHeader;
use alexandria_bytes::byte_appender::{ByteAppender, ByteAppenderSupportTrait};

/// Compute SHA-256d (double SHA-256)
///
/// This is the core hash function used throughout Zcash consensus:
/// - Block hashes MUST use SHA-256d
/// - Transaction merkle tree MUST use SHA-256d for internal nodes
/// - Transaction IDs MUST use SHA-256d
///
/// #### Arguments
/// * `data` - Input data to hash
///
/// #### Returns
/// * `Array<u8>` - 32-byte SHA-256d hash
pub fn sha256d(data: Array<u8>) -> Array<u8> {
    // First SHA-256
    let first_hash = core::sha256::compute_sha256_byte_array(
        @bytes_to_byte_array(@data)
    );

    // Second SHA-256 (of the first hash)
    let second_hash = core::sha256::compute_sha256_byte_array(
        @sha256_output_to_byte_array(first_hash)
    );

    // Convert final hash to byte array (little-endian for Zcash)
    sha256_output_to_bytes_le(second_hash)
}

/// Convert byte array to ByteArray for Cairo's SHA-256
fn bytes_to_byte_array(bytes: @Array<u8>) -> ByteArray {
    let mut ba = "";
    let mut i = 0;
    while i < bytes.len() {
        ba.append_byte(*bytes[i]);
        i += 1;
    };
    ba
}

/// Convert SHA-256 output ([u32; 8]) to ByteArray
/// SHA-256 outputs 8 u32 words in big-endian order
fn sha256_output_to_byte_array(hash: [u32; 8]) -> ByteArray {
    let mut ba = "";

    // Unpack the 8 u32 words manually (fixed-size arrays can't be indexed in Cairo)
    let [w0, w1, w2, w3, w4, w5, w6, w7] = hash;

    // Process each word (big-endian)
    append_u32_be(ref ba, w0);
    append_u32_be(ref ba, w1);
    append_u32_be(ref ba, w2);
    append_u32_be(ref ba, w3);
    append_u32_be(ref ba, w4);
    append_u32_be(ref ba, w5);
    append_u32_be(ref ba, w6);
    append_u32_be(ref ba, w7);

    ba
}

/// Helper: Append u32 in big-endian format to ByteArray
fn append_u32_be(ref ba: ByteArray, word: u32) {
    ba.append_byte(((word / 16777216) & 0xFF).try_into().unwrap());
    ba.append_byte(((word / 65536) & 0xFF).try_into().unwrap());
    ba.append_byte(((word / 256) & 0xFF).try_into().unwrap());
    ba.append_byte((word & 0xFF).try_into().unwrap());
}

/// Convert SHA-256 output ([u32; 8]) to 32-byte array (little-endian)
/// This is the standard byte order for Zcash/Bitcoin hashes
fn sha256_output_to_bytes_le(hash: [u32; 8]) -> Array<u8> {
    let mut bytes = ArrayTrait::new();

    // Unpack the 8 u32 words manually (fixed-size arrays can't be indexed in Cairo)
    let [w0, w1, w2, w3, w4, w5, w6, w7] = hash;

    // Process each word in little-endian byte order
    append_u32_le_internal(ref bytes, w0);
    append_u32_le_internal(ref bytes, w1);
    append_u32_le_internal(ref bytes, w2);
    append_u32_le_internal(ref bytes, w3);
    append_u32_le_internal(ref bytes, w4);
    append_u32_le_internal(ref bytes, w5);
    append_u32_le_internal(ref bytes, w6);
    append_u32_le_internal(ref bytes, w7);

    bytes
}

/// Helper: Append u32 in little-endian format to Array<u8>
fn append_u32_le_internal(ref bytes: Array<u8>, word: u32) {
    bytes.append((word & 0xFF).try_into().unwrap());
    bytes.append(((word / 256) & 0xFF).try_into().unwrap());
    bytes.append(((word / 65536) & 0xFF).try_into().unwrap());
    bytes.append(((word / 16777216) & 0xFF).try_into().unwrap());
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
/// This is the standard byte order for Zcash/Bitcoin hashes
fn u256_to_bytes_le(value: u256) -> Array<u8> {
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

/// Helper: Append i32 in little-endian format (mutates array)
/// Uses Alexandria's ByteAppender trait for proper endianness handling
pub fn append_i32_le(ref bytes: Array<u8>, value: i32) {
    bytes.append_i32_le(value);
}

/// Helper: Append u32 in little-endian format (mutates array)
/// Uses Alexandria's ByteAppender trait for proper endianness handling
pub fn append_u32_le(ref bytes: Array<u8>, value: u32) {
    bytes.append_u32_le(value);
}

/// Helper: Append byte array (mutates array)
pub fn append_bytes(ref bytes: Array<u8>, data: @Array<u8>) {
    let mut i: u32 = 0;
    while i < data.len() {
        bytes.append(*data[i]);
        i += 1;
    };
}

/// Serialize block header for hashing (Zcash Protocol Section 7.6)
///
/// Serializes ALL block header fields in the order they appear in the protocol:
/// 1. version (i32, 4 bytes, little-endian)
/// 2. prev_block (32 bytes)
/// 3. merkle_root (32 bytes)
/// 4. final_sapling_root (32 bytes)
/// 5. time (u32, 4 bytes, little-endian)
/// 6. bits (u32, 4 bytes, little-endian)
/// 7. nonce (32 bytes)
/// 8. solution (1344 bytes for n=200, k=9)
///
/// The `hash` field is NOT included as it's the computed result of this serialization.
///
/// Total serialized size: 4 + 32 + 32 + 32 + 4 + 4 + 32 + 1344 = 1484 bytes
///
/// #### Arguments
/// * `header` - Block header to serialize
///
/// #### Returns
/// * `Array<u8>` - Serialized header bytes (1484 bytes)
pub fn serialize_header_for_hash(header: @BlockHeader) -> Array<u8> {
    let mut bytes = ArrayTrait::new();

    // 1. Version (i32, little-endian)
    append_i32_le(ref bytes, *header.version);

    // 2. Previous block hash (32 bytes)
    append_bytes(ref bytes, header.prev_block);

    // 3. Merkle root (32 bytes)
    append_bytes(ref bytes, header.merkle_root);

    // 4. Final Sapling root (32 bytes)
    append_bytes(ref bytes, header.final_sapling_root);

    // 5. Time (u32, little-endian)
    append_u32_le(ref bytes, *header.time);

    // 6. Bits (difficulty target, u32, little-endian)
    append_u32_le(ref bytes, *header.bits);

    // 7. Nonce (32 bytes)
    append_bytes(ref bytes, header.nonce);

    // 8. Equihash solution (1344 bytes)
    append_bytes(ref bytes, header.solution);

    bytes
}

/// Compute block hash from header using SHA-256d
///
/// This is the canonical way to compute a block's hash:
/// 1. Serialize the header (excluding the hash field)
/// 2. Apply SHA-256d
///
/// #### Arguments
/// * `header` - Block header to hash
///
/// #### Returns
/// * `Array<u8>` - 32-byte block hash
pub fn compute_block_hash(header: @BlockHeader) -> Array<u8> {
    let serialized = serialize_header_for_hash(header);
    sha256d(serialized)
}

#[cfg(test)]
mod tests {
    use super::{sha256d, append_i32_le, append_u32_le, u256_to_bytes_le, serialize_header_for_hash, compute_block_hash};
    use crate::types::block_header::BlockHeader;

    #[test]
    fn test_sha256d_empty() {
        let data = array![];
        let hash = sha256d(data);

        // Hash should always be 32 bytes
        assert(hash.len() == 32, 'Hash should be 32 bytes');
    }

    #[test]
    fn test_sha256d_hello() {
        // "hello" in ASCII
        let data = array![0x68, 0x65, 0x6c, 0x6c, 0x6f];
        let hash = sha256d(data);

        assert(hash.len() == 32, 'Hash should be 32 bytes');

        // SHA-256d("hello") is known value
        // Can be verified with: echo -n "hello" | sha256sum | xxd -r -p | sha256sum
    }

    #[test]
    fn test_append_u32_le() {
        let mut bytes = ArrayTrait::new();
        append_u32_le(ref bytes, 0x12345678);

        assert(bytes.len() == 4, 'Should be 4 bytes');
        assert(*bytes[0] == 0x78, 'Byte 0 should be 0x78');
        assert(*bytes[1] == 0x56, 'Byte 1 should be 0x56');
        assert(*bytes[2] == 0x34, 'Byte 2 should be 0x34');
        assert(*bytes[3] == 0x12, 'Byte 3 should be 0x12');
    }

    #[test]
    fn test_append_i32_le_positive() {
        let mut bytes = ArrayTrait::new();
        append_i32_le(ref bytes, 0x12345678);

        assert(bytes.len() == 4, 'Should be 4 bytes');
        assert(*bytes[0] == 0x78, 'Byte 0 should be 0x78');
    }

    #[test]
    fn test_append_i32_le_negative() {
        let mut bytes = ArrayTrait::new();
        append_i32_le(ref bytes, -1);

        assert(bytes.len() == 4, 'Should be 4 bytes');
        // -1 in two's complement is 0xFFFFFFFF
        assert(*bytes[0] == 0xFF, 'Byte 0 should be 0xFF');
        assert(*bytes[1] == 0xFF, 'Byte 1 should be 0xFF');
        assert(*bytes[2] == 0xFF, 'Byte 2 should be 0xFF');
        assert(*bytes[3] == 0xFF, 'Byte 3 should be 0xFF');
    }

    #[test]
    fn test_u256_to_bytes() {
        let value = u256 { low: 0x0123456789ABCDEF0123456789ABCDEF, high: 0 };
        let bytes = u256_to_bytes_le(value);

        assert(bytes.len() == 32, 'Should be 32 bytes');
        // Check little-endian encoding
        assert(*bytes[0] == 0xEF, 'First byte should be 0xEF');
    }

    // Helper to create empty arrays for testing
    fn empty_32_bytes() -> Array<u8> {
        let mut arr = ArrayTrait::new();
        let mut i: u32 = 0;
        while i < 32 {
            arr.append(0);
            i += 1;
        };
        arr
    }

    fn empty_solution() -> Array<u8> {
        let mut arr = ArrayTrait::new();
        let mut i: u32 = 0;
        while i < 1344 {
            arr.append(0);
            i += 1;
        };
        arr
    }

    #[test]
    fn test_serialize_header_size() {
        // Create a minimal block header
        let header = BlockHeader {
            version: 4,
            prev_block: empty_32_bytes(),
            merkle_root: empty_32_bytes(),
            final_sapling_root: empty_32_bytes(),
            time: 1234567890,
            bits: 0x1f07ffff,
            nonce: empty_32_bytes(),
            solution: empty_solution(),
            hash: empty_32_bytes(),
        };

        let serialized = serialize_header_for_hash(@header);

        // Total size should be: 4 + 32 + 32 + 32 + 4 + 4 + 32 + 1344 = 1484 bytes
        assert(serialized.len() == 1484, 'Serialized size should be 1484');
    }

    #[test]
    fn test_compute_block_hash_size() {
        // Create a minimal block header
        let header = BlockHeader {
            version: 4,
            prev_block: empty_32_bytes(),
            merkle_root: empty_32_bytes(),
            final_sapling_root: empty_32_bytes(),
            time: 1234567890,
            bits: 0x1f07ffff,
            nonce: empty_32_bytes(),
            solution: empty_solution(),
            hash: empty_32_bytes(),
        };

        let hash = compute_block_hash(@header);

        // Hash should always be 32 bytes (SHA-256d output)
        assert(hash.len() == 32, 'Block hash should be 32 bytes');
    }
}
