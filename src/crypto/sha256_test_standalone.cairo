/// Standalone SHA-256d tests
///
/// This file can be used to test SHA-256d independently
/// Run with: scarb cairo-run --available-gas=20000000

use zcash_light_client::crypto::sha256::{sha256d, append_u32_le, append_i32_le};
use core::array::ArrayTrait;
use core::debug::PrintTrait;

fn main() {
    // Test 1: Empty hash
    let data = array![];
    let hash = sha256d(data);
    assert(hash.len() == 32, 'Hash should be 32 bytes');
    'Test 1 passed: Empty hash'.print();

    // Test 2: "hello" hash
    let data = array![0x68, 0x65, 0x6c, 0x6c, 0x6f];
    let hash = sha256d(data);
    assert(hash.len() == 32, 'Hash should be 32 bytes');
    'Test 2 passed: Hello hash'.print();

    // Test 3: u32 little-endian encoding
    let mut bytes = ArrayTrait::new();
    append_u32_le(ref bytes, 0x12345678);
    assert(bytes.len() == 4, 'Should be 4 bytes');
    assert(*bytes[0] == 0x78, 'Byte 0 should be 0x78');
    assert(*bytes[1] == 0x56, 'Byte 1 should be 0x56');
    assert(*bytes[2] == 0x34, 'Byte 2 should be 0x34');
    assert(*bytes[3] == 0x12, 'Byte 3 should be 0x12');
    'Test 3 passed: u32 LE encoding'.print();

    // Test 4: i32 negative number encoding
    let mut bytes = ArrayTrait::new();
    append_i32_le(ref bytes, -1);
    assert(bytes.len() == 4, 'Should be 4 bytes');
    assert(*bytes[0] == 0xFF, 'All bytes should be 0xFF');
    assert(*bytes[1] == 0xFF, 'All bytes should be 0xFF');
    assert(*bytes[2] == 0xFF, 'All bytes should be 0xFF');
    assert(*bytes[3] == 0xFF, 'All bytes should be 0xFF');
    'Test 4 passed: i32 negative encoding'.print();

    'All SHA-256d tests passed!'.print();
}
