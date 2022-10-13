// Copyright 2022 OmniBTC Authors. Licensed under Apache-2.0 License.
module aptos_cid::utf8_utils {
    use std::string::{Self, String};
    use std::vector;

    /// This turns a u128 into its UTF-8 string equivalent.
    public fun u128_to_string(value: u128): String {
        if (value == 0) {
            return string::utf8(b"0")
        };
        let buffer = vector::empty<u8>();
        while (value != 0) {
            vector::push_back(&mut buffer, ((48 + value % 10) as u8));
            value = value / 10;
        };
        vector::reverse(&mut buffer);
        string::utf8(buffer)
    }

    /// This turns a u64 into its UTF-8 string equivalent.
    public fun u64_to_string(value: u64): String {
        if (value == 0) {
            return string::utf8(b"0")
        };
        let buffer = vector::empty<u8>();
        while (value != 0) {
            vector::push_back(&mut buffer, ((48 + value % 10) as u8));
            value = value / 10;
        };
        vector::reverse(&mut buffer);
        string::utf8(buffer)
    }

    #[test]
    fun tests() {
        assert!(u64_to_string(1000) == string::utf8(b"1000"), 1);
        assert!(u128_to_string(1000) == string::utf8(b"1000"), 2);

        let max_u128 = 340282366920938463463374607431768211455u128;

        assert!(
            u128_to_string(max_u128) == string::utf8(b"340282366920938463463374607431768211455"),
            3
        );
    }
}
