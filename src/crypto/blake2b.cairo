/// Blake2b hash implementation for Cairo
/// Required for key derivation and note encryption
///TODO INCOMPLETE
use core::array::ArrayTrait;
use core::integer::u128_byte_reverse;

/// Helper function for power of 2
fn pow(base: u64, exp: u32) -> u64 {
    if exp == 0 {
        return 1;
    }
    let mut result = base;
    let mut i = 1;
    loop {
        if i >= exp {
            break;
        }
        result = result * base;
        i += 1;
    };
    result
}

/// Blake2b context for streaming hash computation
#[derive(Drop)]
pub struct Blake2b {
    h: Array<u64>,      // State vector
    t: Array<u64>,      // Total bytes
    buffer: Array<u8>,  // Buffer for incomplete blocks
    buffer_len: usize,  // Current buffer length
    outlen: usize,      // Output length
}

/// Blake2b constants
const BLAKE2B_BLOCKBYTES: usize = 128;
const BLAKE2B_OUTBYTES: usize = 64;
const BLAKE2B_KEYBYTES: usize = 64;

/// IV for Blake2b-512
fn get_iv() -> Span<u64> {
    array![
        0x6a09e667f3bcc908,
        0xbb67ae8584caa73b,
        0x3c6ef372fe94f82b,
        0xa54ff53a5f1d36f1,
        0x510e527fade682d1,
        0x9b05688c2b3e6c1f,
        0x1f83d9abfb41bd6b,
        0x5be0cd19137e2179,
    ].span()
}

/// Trait for Blake2b operations
pub trait Blake2bTrait {
    fn new(outlen: usize) -> Blake2b;
    fn update(ref self: Blake2b, data: @Array<u8>);
    fn finalize(ref self: Blake2b) -> Array<u8>;
    fn compress(ref self: Blake2b, is_final: bool);
}

impl Blake2bImpl of Blake2bTrait {
    /// Initialize Blake2b with output length
    fn new(outlen: usize) -> Blake2b {
        assert(outlen > 0 && outlen <= BLAKE2B_OUTBYTES, 'Invalid output length');

        let iv = get_iv();
        let mut h = ArrayTrait::new();
        let mut i = 0;
        loop {
            if i >= 8 {
                break;
            }
            if i == 0 {
                // XOR first word with output length
                h.append(*iv[i] ^ 0x01010000 ^ outlen.into());
            } else {
                h.append(*iv[i]);
            }
            i += 1;
        };

        Blake2b {
            h,
            t: array![0, 0],
            buffer: ArrayTrait::new(),
            buffer_len: 0,
            outlen,
        }
    }

    /// Update hash with data
    fn update(ref self: Blake2b, data: @Array<u8>) {
        let data_span = data.span();
        let mut offset = 0;

        // Process any buffered data first
        if self.buffer_len > 0 {
            let to_copy = BLAKE2B_BLOCKBYTES - self.buffer_len;
            let copy_len = if to_copy > data_span.len() {
                data_span.len()
            } else {
                to_copy
            };

            let mut i = 0;
            loop {
                if i >= copy_len {
                    break;
                }
                self.buffer.append(*data_span[i]);
                i += 1;
            };

            self.buffer_len += copy_len;
            offset += copy_len;

            if self.buffer_len == BLAKE2B_BLOCKBYTES {
                self.compress(false);
                self.buffer = ArrayTrait::new();
                self.buffer_len = 0;
            }
        }

        // Process full blocks
        loop {
            if offset + BLAKE2B_BLOCKBYTES > data_span.len() {
                break;
            }

            let mut block = ArrayTrait::new();
            let mut i = 0;
            loop {
                if i >= BLAKE2B_BLOCKBYTES {
                    break;
                }
                block.append(*data_span[offset + i]);
                i += 1;
            };

            self.buffer = block;
            self.compress(false);
            self.buffer = ArrayTrait::new();

            offset += BLAKE2B_BLOCKBYTES;
        };

        // Buffer remaining data
        loop {
            if offset >= data_span.len() {
                break;
            }
            self.buffer.append(*data_span[offset]);
            self.buffer_len += 1;
            offset += 1;
        };
    }

    /// Finalize hash and return result
    fn finalize(ref self: Blake2b) -> Array<u8> {
        // Pad final block if needed
        loop {
            if self.buffer.len() >= BLAKE2B_BLOCKBYTES {
                break;
            }
            self.buffer.append(0);
        };

        // Final compression
        self.compress(true);

        // Extract output bytes
        let mut output = ArrayTrait::new();
        let mut i = 0;
        loop {
            if i >= self.outlen {
                break;
            }

            let word_idx = i / 8;
            let byte_idx = i % 8;
            let word = *self.h[word_idx];

            // Extract byte from word (little-endian)
            let shift_amount: u32 = (byte_idx * 8).try_into().unwrap();
            let shifted = word / pow(2, shift_amount);
            let byte = (shifted & 0xff).try_into().unwrap();
            output.append(byte);
            i += 1;
        };

        output
    }

    /// Compression function (simplified)
    fn compress(ref self: Blake2b, is_final: bool) {
        // This is a highly simplified version
        // Real implementation would need full Blake2b compression
        // Including G function, permutations, etc.

        // Update counter
        let block_len = if is_final {
            self.buffer_len
        } else {
            BLAKE2B_BLOCKBYTES
        };

        // Simplified mixing
        let mut new_h = ArrayTrait::new();
        let mut i = 0;
        loop {
            if i >= 8 {
                break;
            }

            let mut val = *self.h[i];
            if i < self.buffer.len() / 8 {
                // Mix with buffer data (simplified)
                let mut j = 0;
                loop {
                    if j >= 8 {
                        break;
                    }
                    let byte_idx = i * 8 + j;
                    if byte_idx < self.buffer.len() {
                        let shift_amount: u32 = (j * 8).try_into().unwrap();
                        let byte_val: u64 = (*self.buffer[byte_idx]).into();
                        val = val ^ (byte_val * pow(2, shift_amount));
                    }
                    j += 1;
                };
            }

            if is_final && i == 0 {
                val = val ^ 0xffffffffffffffff; // Final block flag
            }

            new_h.append(val);
            i += 1;
        };

        self.h = new_h;
    }
}

/// Compute Blake2b hash of data
pub fn blake2b(data: @Array<u8>, outlen: usize) -> Array<u8> {
    let mut hasher = Blake2bTrait::new(outlen);
    hasher.update(data);
    hasher.finalize()
}

/// Personal Blake2b for key derivation
pub fn blake2b_personal(
    data: @Array<u8>,
    personal: @ByteArray,
    outlen: usize
) -> Array<u8> {
    // Simplified - would need to set personalization in Blake2b init
    blake2b(data, outlen)
}