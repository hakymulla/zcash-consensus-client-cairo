use core::array::{ArrayTrait, SpanTrait};
use core::option::OptionTrait;
#[feature("corelib-internal-use")]
use core::integer::u64_wrapping_add;
use core::num::traits::{Bounded, OverflowingAdd};
use crate::utils::blake_utils::{to_hex, array_to_byte_array, shr, shl, rotate_right};

use alexandria_data_structures::vec::{Felt252Vec, VecTrait};

const BLOCK_BYTES: usize = 128;
const KEY_BYTES: usize = 64;
const OUT_BYTES: usize = 64;

// Initialization Vector.
fn IV() -> Span<u64> {
    array![
        0x6a09e667f3bcc908,
        0xbb67ae8584caa73b,
        0x3c6ef372fe94f82b,
        0xa54ff53a5f1d36f1,
        0x510e527fade682d1,
        0x9b05688c2b3e6c1f,
        0x1f83d9abfb41bd6b,
        0x5be0cd19137e2179,
    ]
        .span()
}

// Message word permutations
fn SIGMA() -> Span<Span<usize>> {
    array![
        array![0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15].span(),
        array![14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3].span(),
        array![11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4].span(),
        array![7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8].span(),
        array![9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13].span(),
        array![2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9].span(),
        array![12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11].span(),
        array![13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10].span(),
        array![6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5].span(),
        array![10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0].span(),
        array![  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15 ].span(),
        array![ 14, 10,  4,  8,  9, 15, 13,  6,  1, 12,  0,  2, 11,  7,  5,  3 ].span(),
    ]
        .span()
}

#[derive(Clone, Drop)]
pub struct Blake2b {
    h: Span<u64>, // state vector
    t: Span<u64>, // 2w-bit offset counter
    f: Span<u64>, //  final block indicator flag
    buf: Span<u8>,
    buf_len: usize,
}

#[generate_trait]
impl Blake2bImpl of Blake2bTrait {
    fn new(size: u8) -> Blake2b {
        assert!(size > 0 && size.into() <= OUT_BYTES);
        let mut param = encode_params(size.into(), 0).span();
        let mut state = IV();
        let mut res_state = ArrayTrait::<u64>::new();

        let my_span = state;
        let mut index: usize = 0;
        let limit: usize = 8;

        for i in 0..limit {
            let curr_state = *my_span[i];
            for _ in 0..limit {
                if i!= 0 {
                    param.pop_front().unwrap();
                }
            }

            let loaded = load64(ref param);
            let som = curr_state ^ loaded;
            res_state.append(som);
            index = 0;
        }

        let mut buf: Array<u8> = ArrayTrait::new();
        let mut i = 0;
        loop {
            if i == 256 {
                break;
            }
            buf.append(0);
            i += 1;
        };

        Blake2b{
            h: res_state.span(),
            t: array![0, 0].span(),
            f: array![0, 0].span(),
            buf: buf.span(),
            buf_len: 0,
        }
    }

    fn update(ref self: Blake2b, ref m: Span<u8>) {
        let mut m = m;

        while m.len() > 0 {
            let left = self.buf_len;
            let fill = 2 * BLOCK_BYTES - left;

            if m.len() > fill {
                for i in 0..fill {
                    self.buf = replace_at_index(self.buf, left+i, *m[i]).span();
                }
                self.buf_len += fill;
                let i = 0;
                for _ in 0..fill {
                    if i != fill {
                        m.pop_front().unwrap();
                    }
                }

                self.increment_counter(BLOCK_BYTES.into());
                self.compress();
                for i in 0..BLOCK_BYTES {
                    let val = *self.buf[i+BLOCK_BYTES];
                    self.buf = replace_at_index(self.buf, i.into(), val.into()).span();
                }
                self.buf_len -= BLOCK_BYTES;
            } else {
                for i in 0..m.len() {
                    self.buf = replace_at_index(self.buf, left+i, *m[i].into()).span();
                }
                self.buf_len += m.len();
                m = reset_span(m);
            }
        }
    }

    fn finalize(ref self: Blake2b) -> Array<u8> {
        let mut out = ArrayTrait::<u8>::new();
        for _ in 0..OUT_BYTES {
            out.append(0);
        }

        let mut buf = out.clone();
        
        if self.buf_len > BLOCK_BYTES {
            self.increment_counter(BLOCK_BYTES.into());
            self.compress();
            for i in 0..BLOCK_BYTES {
                let val = *self.buf[i+BLOCK_BYTES];
                self.buf = replace_at_index(self.buf, i.into(), val.into()).span();
            }
            self.buf_len -= BLOCK_BYTES;
        }        

        let n: u64 = self.buf_len.into();
        self.increment_counter(n);

        self.f = replace_at_index(self.f, 0, Bounded::<u64>::MAX).span();

        for i in self.buf_len..self.buf.len() {
            self.buf = replace_at_index(self.buf, i, 0).span();
        }

        self.compress();

        let mut index: usize = 0;
        let limit: usize = self.h.len();
        let mut buf = buf.span();
        let mut buf_copy = ArrayTrait::<u8>::new();

        for i in 0..limit {
            for _ in 0..limit {
                if i!= 0 {
                    buf.pop_front().unwrap();
                }
            }

            store64(ref buf, *self.h[i]);
            index = 0;
            for i in 0..limit {
                buf_copy.append(*buf[i]);
            }
        }
        let out_len = out.len();
        let limit: usize = if out_len < OUT_BYTES {
            out_len
        } else {
            OUT_BYTES
        };

        for i in 0..limit {
            out = replace_at_index(out.span(), i, *buf_copy[i]);
        }
        out
    }

    fn compress(ref self: Blake2b) {
        let mut m = array![0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0].span();
        let mut v = VecTrait::<Felt252Vec, u64>::new();
        let mut i = 0;
        loop {
            if i == 16 {
                break;
            }
            v.push(0);

            i += 1;
        };

        let mut block = self.buf;
        assert!(block.len() >= BLOCK_BYTES);

        let mut index: usize = 0;
        let limit: usize = 8;
        for i in 0..m.len() {
            for _ in 0..limit {
                if i!= 0 {
                    block.pop_front().unwrap();
                }
            }
            let loaded = load64(ref block);
            m = replace_at_index(m, i, loaded).span();
            index = 0;
        }

        for i in 0..limit {
            v.set(i, *self.h[i]);
        }
       
        let iv = IV();
        v.set(8, *iv[0]);
        v.set(9, *iv[1]);
        v.set(10, *iv[2]);
        v.set(11, *iv[3]);

        v.set(12,(*self.t[0] ^ *iv[4]));
        v.set(13,(*self.t[1] ^ *iv[5]));
        v.set(14,(*self.f[0] ^ *iv[6]));
        v.set(15,(*self.f[1] ^ *iv[7]));

        let round_l: usize = 12;
        for i in 0..round_l {
            round(i, ref v, ref m);
        }

        let new_limit: usize = 8;
        for i in 0..new_limit {
            self.h = replace_at_index(self.h, i, (*self.h[i] ^ v[i].into() ^ v[i+8].into())).span();
        }
    }

    fn increment_counter(ref self: Blake2b, inc: u64) {
        let t0 = *self.t.at(0);
        let t1 = *self.t.at(1);

        let (new_t0, overflow) = t0.overflowing_add(inc);
        let carry: u64 = if overflow { 1_u64 } else { 0_u64 };
        let new_t1 = t1 + carry;
        let new_t = array![new_t0, new_t1].span();
        self.t = new_t;
    }
}

fn round(r: usize, ref v: Felt252Vec<u64>, ref m: Span<u64>) {
    g(r, 0,  0,  4,  8, 12, ref v, ref m,);
    g(r, 1,  1,  5,  9, 13, ref v, ref m,);
    g(r, 2,  2,  6, 10, 14, ref v, ref m,);
    g(r, 3,  3,  7, 11, 15, ref v, ref m,);
    g(r, 4,  0,  5, 10, 15, ref v, ref m,);
    g(r, 5,  1,  6, 11, 12, ref v, ref m,);
    g(r, 6,  2,  7,  8, 13, ref v, ref m,);
    g(r, 7,  3,  4,  9, 14, ref v, ref m,);
}

fn reset_span(mut m: Span<u8>) -> Span<u8> {
    let len = m.len();
    m = m.slice(len, 0);
    m
}

fn g(r: u32, i: usize, a: usize, b: usize, c: usize, d: usize, ref v: Felt252Vec<u64>, ref m: Span<u64>) {
    
    let mut v_a = v[a];
    let mut v_b = v[b];
    let mut v_c = v[c];
    let mut v_d = v[d];
    let sigma = SIGMA();
    let sigma_r_i0 = *sigma.at(r.into()).at((2*i+0).into());
    let sigma_r_i1 = *sigma.at(r.into()).at((2*i+1).into());
    let m_sigma_r_i0 = *m.at(sigma_r_i0);
    let m_sigma_r_i1 =  *m.at(sigma_r_i1);

    v_a = u64_wrapping_add(v_a, u64_wrapping_add(v_b, m_sigma_r_i0));
    v_d = rotate_right((v_d ^ v_a), 32);
    v_c = u64_wrapping_add(v_c, v_d);
    v_b = rotate_right((v_b ^ v_c), 24);
    v_a = u64_wrapping_add(v_a, u64_wrapping_add(v_b,m_sigma_r_i1));
    v_d = rotate_right((v_d ^ v_a), 16);
    v_c = u64_wrapping_add(v_c, v_d);
    v_b = rotate_right((v_b ^ v_c), 63);

    v.set(a, v_a);
    v.set(b, v_b);
    v.set(c, v_c);
    v.set(d, v_d);
}

fn encode_params(size: u8, keylen: u8) -> Array<u8> {
    let mut param: Array<u8> = array![];
    param.append(size);
    param.append(keylen);
    param.append(1); // fanout
    param.append(1); // depth

   let mut index:usize = 0;

    while index != 60 {
        param.append(0);
        index += 1;
    }
    param
}

fn load64(ref b: Span<u8> ) -> u64 {
    let mut v: u64 = 0;
    let l:usize = 8;
    for i in 0..l {
        let res: u64 = shl((*b[i]).into(), (8*i).into()).try_into().unwrap();
        let som = v | res;
        v = som;
    }
    v
}

fn store64(ref b: Span<u8>, v: u64) {
    let mut w = v;
    for i in 0..b.len() {
        let w8 = w % 256;
        b = replace_at_index(b, i, w8.try_into().unwrap()).span();
        let res = shr(w, 8);
        w = res.try_into().unwrap();
    }
}

fn replace_at_index<T, +core::traits::Drop<T>, +core::traits::Copy<T>>
    (span: Span<T>, index: usize, new_value: T) -> Array<T> {
    let mut new_arr = ArrayTrait::<T>::new();
    let mut i = 0;
    let length = span.len();

    loop {
        if i >= length {
            break;
        }

        let current_value = *span.at(i);

        if i == index {
            new_arr.append(new_value);
        } else {
            new_arr.append(current_value);
        }

        i += 1;
    };

    new_arr
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn test_finalize_hello_world() {
        let mut blake_state = Blake2bTrait::new(64);
        let mut value = array![104, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100].span();
        blake_state.update(ref value);
        assert_eq!(blake_state.h, array![7640891576939301192, 13503953896175478587, 4354685564936845355, 11912009170470909681, 5840696475078001361, 11170449401992604703, 2270897969802886507, 6620516959819538809].span());
        assert_eq!(blake_state.t, array![0, 0].span());
        assert_eq!(blake_state.f, array![0, 0].span());
        assert_eq!(blake_state.buf, array![104, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0].span());
        assert_eq!(blake_state.buf_len, 11);

        let out = blake_state.finalize();
        assert_eq!(out, array![2, 28, 237, 135, 153, 41, 108, 236, 165, 87, 131, 42, 185, 65, 165, 11, 74, 17, 248, 52, 120, 207, 20, 31, 81, 249, 51, 246, 83, 171, 159, 188, 192, 90, 3, 124, 221, 190, 208, 110, 48, 155, 243, 52, 148, 44, 78, 88, 205, 241, 164, 110, 35, 121, 17, 204, 215, 252, 249, 120, 124, 188, 127, 208]);

    }

      #[test]
    fn test_finalize() {
        // 'the crazy red fox moved right pass the less red right road in lagos'
        let mut blake_state = Blake2bTrait::new(64);
        let mut value = array![116, 104, 101, 32, 99, 114, 97, 122, 121, 32, 114, 101, 100, 32, 102, 111, 120, 32, 109, 111, 118, 101, 100, 32, 114, 105, 103, 104, 116, 32, 112, 97, 115, 115, 32, 116, 104, 101, 32, 108, 101, 115, 115, 32, 114, 101, 100, 32, 114, 105, 103, 104, 116, 32, 114, 111, 97, 100, 32, 105, 110, 32, 108, 97, 103, 111, 115].span();
        
        blake_state.update(ref value);

        let out = blake_state.finalize();
        assert_eq!(out, array![24, 173, 18, 86, 213, 8, 168, 239, 85, 149, 100, 49, 105, 83, 0, 233, 102, 158, 157, 247, 49, 90, 67, 54, 62, 52, 179, 159, 242, 142, 77, 124, 212, 244, 186, 142, 181, 127, 169, 215, 166, 205, 11, 122, 240, 244, 4, 155, 93, 67, 59, 98, 231, 220, 166, 182, 154, 163, 25, 97, 139, 219, 146, 225]);
        let byte = array_to_byte_array(out);
        assert_eq!(to_hex(@byte), "18ad1256d508a8ef55956431695300e9669e9df7315a43363e34b39ff28e4d7cd4f4ba8eb57fa9d7a6cd0b7af0f4049b5d433b62e7dca6b69aa319618bdb92e1")
    }

     #[test]
    fn test_finalize_0() {
        let mut blake_state = Blake2bTrait::new(64);
        let mut value = array![66, 108, 97, 107, 101, 50, 98, 53, 49, 50, 32, 97, 110, 100, 32, 66, 108, 97, 107, 101, 50, 115, 50, 53, 54, 32, 99, 97, 110, 32, 98, 101, 32, 117, 115, 101, 100, 32, 105, 110, 32, 116, 104, 101, 32, 102, 111, 108, 108, 111, 119, 105, 110, 103, 32, 119, 97, 121, 58].span();
        
        blake_state.update(ref value);
        let out = blake_state.finalize();
        let byte = array_to_byte_array(out);
        assert_eq!(to_hex(@byte), "7402cec144ca5861962475fa88e654676387d1839ecbc239b495609ce85ae2e07e99bf879aa0b58d016e5052f62a079474281b6ecb172ceef8f906e9dd7c2a17")
    }

    #[test]
    fn test_finalize_1() {
        let mut blake_state = Blake2bTrait::new(64);
        let mut value = array![67, 111, 110, 118, 101, 110, 105, 101, 110, 99, 101, 32, 119, 114, 97, 112, 112, 101, 114, 32, 116, 114, 97, 105, 116, 32, 99, 111, 118, 101, 114, 105, 110, 103, 32, 102, 117, 110, 99, 116, 105, 111, 110, 97, 108, 105, 116, 121, 32, 111, 102, 32, 99, 114, 121, 112, 116, 111, 103, 114, 97, 112, 104, 105, 99, 32, 104, 97, 115, 104, 32, 102, 117, 110, 99, 116, 105, 111, 110, 115, 32, 119, 105, 116, 104, 32, 102, 105, 120, 101, 100, 32, 111, 117, 116, 112, 117, 116, 32, 115, 105, 122, 101, 46].span();
        
        blake_state.update(ref value);
        let out = blake_state.finalize();
        let byte = array_to_byte_array(out);
        assert_eq!(to_hex(@byte), "130b3cc98a479de1f0b1f46a46d081f738f75b9513f97dccf9e0d5942df4d519de95af834539cc5789e9673ef80bf15e8f2cd879a008bc97f6467947bb21b277")
    }

    #[test]
    fn test_finalize_2() {
        let mut blake_state = Blake2bTrait::new(64);
        let mut value = array![67, 111, 114, 101, 32, 104, 97, 115, 104, 101, 114, 32, 115, 116, 97, 116, 101, 32, 111, 102, 32, 66, 76, 65, 75, 69, 50, 98, 32, 103, 101, 110, 101, 114, 105, 99, 32, 111, 118, 101, 114, 32, 111, 117, 116, 112, 117, 116, 32, 115, 105, 122, 101, 46].span();
        
        blake_state.update(ref value);
        let out = blake_state.finalize();
        let byte = array_to_byte_array(out);
        assert_eq!(to_hex(@byte), "211ea8469133078febe9797299255c6c55459be9629186ced46419a5c321421608326ba3a72bafe8441511bed2879857ad77fc30e969e07d81f88f7e0cf447b6")
    }

    #[test]
    fn test_finalize_3() {
        let mut blake_state = Blake2bTrait::new(64);
        let mut value = array![97, 32, 110, 101, 119, 32, 99, 111, 110, 116, 101, 120, 116, 32, 119, 105, 116, 104, 32, 116, 104, 101, 32, 102, 117, 108, 108, 32, 115, 101, 116, 32, 111, 102, 32, 115, 101, 113, 117, 101, 110, 116, 105, 97, 108, 45, 109, 111, 100, 101].span();
        
        blake_state.update(ref value);
        let out = blake_state.finalize();
        let byte = array_to_byte_array(out);
        assert_eq!(to_hex(@byte), "2bd5ffb1b501ebd836fccea8fe8d6e315265591eb3a1dc8253c390ab553437db6922996dc9933cee57595f235ec63004bf4387626326bad026640db136bd24a8")
    }
}
