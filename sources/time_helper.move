// Copyright 2022 OmniBTC Authors. Licensed under Apache-2.0 License.
module aptos_cid::time_helper {
    /// Cid Time Duration
    /// Validity_Duration = 24 months
    /// Renewable_Duration = 6 months
    ///           |-------------------------------Validity_Duration--------------------------------|
    ///  Time >---|-----------------6|------------------12|-----------------18|------------------24|--Expiration-->
    ///                                                                       |-Renewable_Duration-|

    const SECONDS_PER_MONTH: u64 = 60 * 60 * 24 * 30;

    public fun validity_duration_seconds(): u64 {
        // two years
        months_to_seconds(24)
    }

    public fun months_to_seconds(months: u64): u64 {
        SECONDS_PER_MONTH * months
    }

    public fun seconds_to_months(seconds: u64): u64 {
        seconds / SECONDS_PER_MONTH
    }
}
