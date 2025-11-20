use core::num::traits::Bounded;
use core::num::traits::WideMul;
use alexandria_math::pow;

// https://github.com/keep-starknet-strange/alexandria/blob/a54e7be148e6385c7ecf1371c8711179e69f7c6a/packages/math/src/lib.cairo#L77
pub fn shr<T, +Sub<T>, +Mul<T>, +Div<T>, +Rem<T>, +PartialEq<T>, +Into<u8, T>, +Drop<T>, +Copy<T>> 
(x: T, n: T) -> T {
    x / pow(2_u8.into(), n)
}

// https://github.com/keep-starknet-strange/alexandria/blob/a54e7be148e6385c7ecf1371c8711179e69f7c6a/packages/math/src/lib.cairo#L101
pub fn shl(x: u64, n: u64) -> u64 {
        (WideMul::wide_mul(x, pow(2, n)) & Bounded::<u64>::MAX.into()).try_into().unwrap()
}

// https://github.com/keep-starknet-strange/alexandria/blob/a54e7be148e6385c7ecf1371c8711179e69f7c6a/packages/math/src/lib.cairo#L188
pub fn rotate_right(x: u64, n: u64) -> u64 {
    let step = pow(2, n);
    let (quotient, remainder) = DivRem::div_rem(x, step.try_into().unwrap());
    remainder * pow(2, 64 - n) + quotient
}

pub fn array_to_byte_array(bytes_span: Array<u8>) -> ByteArray{
    let mut byte_array: ByteArray = "";
    let mut i = 0;
    loop {
        if i == bytes_span.len() {
            break;
        }

        let byte = *bytes_span.at(i);
        byte_array.append_byte(byte);
        i += 1;
    };

    byte_array
}

// https://github.com/starkware-bitcoin/raito/blob/main/packages/utils/src/hex.cairo
pub fn to_hex(data: @ByteArray) -> ByteArray {
    let alphabet: @ByteArray = @"0123456789abcdef";
    let mut result: ByteArray = Default::default();

    let mut i = 0;
    while i != data.len() {
        let value: u32 = data[i].into();
        let (l, r) = core::traits::DivRem::div_rem(value, 16);
        result.append_byte(alphabet.at(l).unwrap());
        result.append_byte(alphabet.at(r).unwrap());
        i += 1;
    }

    result
}

// https://github.com/starkware-bitcoin/raito/blob/main/packages/utils/src/hex.cairo
pub fn hex_char_to_nibble(hex_char: u8) -> u8 {
    if hex_char >= 48 && hex_char <= 57 {
        // 0-9
        hex_char - 48
    } else if hex_char >= 65 && hex_char <= 70 {
        // A-F
        hex_char - 55
    } else if hex_char >= 97 && hex_char <= 102 {
        // a-f
        hex_char - 87
    } else {
        assert!(false, "Invalid hex character: {hex_char}");
        0
    }
}
