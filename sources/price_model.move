// Copyright 2022 OmniBTC Authors. Licensed under Apache-2.0 License.
module aptos_cid::price_model {
    use aptos_cid::config;
    use aptos_cid::time_helper::seconds_to_months;

    const PRICE_SCALE: u64 = 1000000;

    /// The later the cid is registered for, the more expensive it is per month.
    /// The curve is exponential, with every month costing more than the previous
    fun scale_price_for_months(price: u64, months: u64): u64 {
        let months = months + 1;

        // price * sqrt(months)
        return price * sqrt(months * PRICE_SCALE) / sqrt(PRICE_SCALE)
    }

    /// There is a fixed cost per each tier of months,
    /// It scales exponentially with number of months to register
    public fun price_for_cid_v1(registration_at_seconds: u64): u64 {
        scale_price_for_months(config::cid_price(), seconds_to_months(registration_at_seconds))
    }

    /// Get a nearest lower integer Square Root for `x`. Given that this
    /// function can only operate with integers, it is impossible
    /// to get perfect (or precise) integer square root for some numbers.
    ///
    /// Example:
    /// ```
    /// math::sqrt(9) => 3
    /// math::sqrt(8) => 2 // the nearest lower square root is 4;
    /// ```
    ///
    /// In integer math, one of the possible ways to get results with more
    /// precision is to use higher values or temporarily multiply the
    /// value by some bigger number. Ideally if this is a square of 10 or 100.
    ///
    /// Example:
    /// ```
    /// math::sqrt(8) => 2;
    /// math::sqrt(8 * 10000) => 282;
    /// // now we can use this value as if it was 2.82;
    /// // but to get the actual result, this value needs
    /// // to be divided by 100 (because sqrt(10000)).
    ///
    ///
    /// math::sqrt(8 * 1000000) => 2828; // same as above, 2828 / 1000 (2.828)
    /// ```
    public fun sqrt(x: u64): u64 {
        let bit = 1u128 << 64;
        let res = 0u128;
        let x = (x as u128);

        while (bit != 0) {
            if (x >= res + bit) {
                x = x - (res + bit);
                res = (res >> 1) + bit;
            } else {
                res = res >> 1;
            };
            bit = bit >> 2;
        };

        (res as u64)
    }

    #[test_only]
    struct MonthPricePair has copy, drop {
        months: u64,
        expected_price: u64,
    }

    #[test(myself = @aptos_cid, framework = @0x1)]
    fun test_scale_price_for_months(myself: &signer, framework: &signer) {
        use aptos_framework::account;
        use std::signer;
        use std::vector;
        // If the price is 10 APT, for 1 month, the price should be 10 APT, etc
        let prices_and_months = vector[
            MonthPricePair { months: 0, expected_price: 10 },
            MonthPricePair { months: 1, expected_price: 14 },
            MonthPricePair { months: 2, expected_price: 17 },
            MonthPricePair { months: 3, expected_price: 20 },
            MonthPricePair { months: 4, expected_price: 22 },
            MonthPricePair { months: 5, expected_price: 24 },
            MonthPricePair { months: 6, expected_price: 26 },
            MonthPricePair { months: 7, expected_price: 28 },
            MonthPricePair { months: 8, expected_price: 30 },
            MonthPricePair { months: 9, expected_price: 31 },
            MonthPricePair { months: 10, expected_price: 33 },
            MonthPricePair { months: 11, expected_price: 34 },
            MonthPricePair { months: 12, expected_price: 36 },
            MonthPricePair { months: 24, expected_price: 50 },
            MonthPricePair { months: 48, expected_price: 70 },
            MonthPricePair { months: 100, expected_price: 100 },
            MonthPricePair { months: 112, expected_price: 106 },
            MonthPricePair { months: 1200, expected_price: 346 },
        ];

        account::create_account_for_test(signer::address_of(myself));
        account::create_account_for_test(signer::address_of(framework));

        while (vector::length(&prices_and_months) > 0) {
            let pair = vector::pop_back(&mut prices_and_months);
            let price = scale_price_for_months(10 * config::octas(), pair.months) / config::octas();
            assert!(price == pair.expected_price, price);
        };
    }
}
