// Copyright 2022 OmniBTC Authors. Licensed under Apache-2.0 License.
#[test_only]
module aptos_cid::test_helper {
    use std::string::{Self, String};
    use std::option;
    use std::signer;
    use std::vector;

    use aptos_framework::account;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin;
    use aptos_framework::timestamp;

    use aptos_token::token;

    use aptos_cid::config;
    use aptos_cid::cid;
    use aptos_cid::price_model;
    use aptos_cid::test_utils;
    use aptos_cid::time_helper;
    use aptos_cid::token_helper;
    use aptos_cid::cid::start_time_sec;
    use aptos_cid::time_helper::months_to_seconds;
    use aptos_cid::price_model::price_for_cid_v1;

    // Ammount to mint to test accounts during the e2e tests
    const MINT_AMOUNT_APT: u64 = 500;

    // 500 APT
    public fun mint_amount(): u64 {
        MINT_AMOUNT_APT * config::octas()
    }

    public fun test_cid(): u64 {
        9999
    }

    public fun register_after_one_year_secs():u64 {
        start_time_sec() + months_to_seconds(12)
    }

    public fun fq_cid(): String {
        string::utf8(b"9999.aptos")
    }

    public fun e2e_test_setup(
        myself: &signer,
        user: signer,
        aptos: &signer,
        rando: signer,
        foundation: &signer
    ): vector<signer> {
        account::create_account_for_test(@aptos_cid);
        let new_accounts = setup_and_fund_accounts(aptos, foundation, vector[user, rando]);
        timestamp::set_time_has_started_for_testing(aptos);
        cid::init_module_for_test(myself);
        config::set_foundation_fund_address_test_only(signer::address_of(foundation));
        new_accounts
    }

    /// Register the cid, and verify the registration was done correctly
    public fun register_cid(
        user: &signer,
        cid: u64,
        registration_at_secs: u64,
        expected_fq_cid: String,
        expected_property_version: u64
    ) {
        let user_addr = signer::address_of(user);

        let user_balance_before = coin::balance<AptosCoin>(user_addr);
        let register_cid_event_v1_event_count_before = cid::get_register_cid_event_v1_count();
        let set_cid_address_event_v1_event_count_before = cid::get_set_cid_address_event_v1_count();

        cid::register_with_price(user, cid, price_for_cid_v1(registration_at_secs));

        // It should now be: not expired, registered, and not registerable
        assert!(!cid::cid_is_expired(cid), 1);
        assert!(!cid::cid_is_registerable(cid), 2);
        assert!(cid::cid_is_registered(cid), 3);

        let (is_owner, token_id) = cid::is_owner_of_cid(user_addr, cid);
        let (tdi_creator, tdi_collection, tdi_cid, tdi_property_version) = token::get_token_id_fields(&token_id);

        assert!(is_owner, 4);
        assert!(tdi_creator == token_helper::get_token_signer_address(), 5);
        assert!(tdi_collection == config::collection_name_v1(), 6);
        test_utils::print_actual_expected(b"tdi_cid: ", tdi_cid, expected_fq_cid, false);
        assert!(tdi_cid == expected_fq_cid, 7);
        test_utils::print_actual_expected(b"tdi_property_version: ", tdi_property_version, expected_property_version, false);
        assert!(tdi_property_version == expected_property_version, tdi_property_version);

        let expected_user_balance_after;
        let user_balance_after = coin::balance<AptosCoin>(user_addr);

        let cid_price = price_model::price_for_cid_v1(registration_at_secs);
        assert!(cid_price / config::octas() == 36, cid_price / config::octas());
        expected_user_balance_after = user_balance_before - cid_price;

        test_utils::print_actual_expected(b"user_balance_after: ", user_balance_after, expected_user_balance_after, false);
        assert!(user_balance_after == expected_user_balance_after, expected_user_balance_after);

        // Ensure the cid was registered correctly, with an expiration timestamp one year in the future
        let (property_version, expiration_time_sec, target_address) = cid::get_record_v1_props_for_cid(cid);
        let expect_months = time_helper::seconds_to_months(expiration_time_sec - timestamp::now_seconds());
        assert!(expect_months == 24, expect_months);

        // Should automatically point to the users address
        assert!(target_address == option::some(user_addr), 8);

        // And the property version is correct
        test_utils::print_actual_expected(b"property_version: ", property_version, expected_property_version, false);
        assert!(property_version == expected_property_version, 9);

        // Ensure the properties were set correctly
        let token_data_id = token_helper::build_tokendata_id(token_helper::get_token_signer_address(), cid);
        let (creator, collection_name, token_name) = token::get_token_data_id_fields(&token_data_id);
        assert!(creator == token_helper::get_token_signer_address(), 10);
        assert!(collection_name == string::utf8(b"Aptos Cid V1"), 11);
        assert!(token_name == token_name, 12);

        // Assert events have been correctly emmitted
        let register_cid_event_v1_num_emitted = cid::get_register_cid_event_v1_count() - register_cid_event_v1_event_count_before;
        let set_cid_address_event_v1_num_emitted = cid::get_set_cid_address_event_v1_count() - set_cid_address_event_v1_event_count_before;

        test_utils::print_actual_expected(b"register_cid_event_v1_num_emitted: ", register_cid_event_v1_num_emitted, 1, false);
        assert!(register_cid_event_v1_num_emitted == 1, register_cid_event_v1_num_emitted);

        // Should automatically point to the users address
        test_utils::print_actual_expected(b"set_cid_address_event_v1_num_emitted: ", set_cid_address_event_v1_num_emitted, 1, false);
        assert!(set_cid_address_event_v1_num_emitted == 1, set_cid_address_event_v1_num_emitted);
    }

    /// Set the cid address, and verify the address was set correctly
    public fun set_cid_address(
        user: &signer,
        cid: u64,
        expected_target_address: address
    ) {
        let register_cid_event_v1_event_count_before = cid::get_register_cid_event_v1_count();
        let set_cid_address_event_v1_event_count_before = cid::get_set_cid_address_event_v1_count();

        cid::set_cid_address(user, cid, expected_target_address);
        let (_property_version, _expiration_time_sec, target_address) = cid::get_record_v1_props_for_cid(cid);
        test_utils::print_actual_expected(b"set_cid_address: ", target_address, option::some(expected_target_address), false);
        assert!(target_address == option::some(expected_target_address), 1);

        // Assert events have been correctly emmitted
        let register_cid_event_v1_num_emitted = cid::get_register_cid_event_v1_count() - register_cid_event_v1_event_count_before;
        let set_cid_address_event_v1_num_emitted = cid::get_set_cid_address_event_v1_count() - set_cid_address_event_v1_event_count_before;

        test_utils::print_actual_expected(b"register_cid_event_v1_num_emitted: ", register_cid_event_v1_num_emitted, 0, false);
        assert!(register_cid_event_v1_num_emitted == 0, register_cid_event_v1_num_emitted);

        test_utils::print_actual_expected(b"set_cid_address_event_v1_num_emitted: ", set_cid_address_event_v1_num_emitted, 1, false);
        assert!(set_cid_address_event_v1_num_emitted == 1, set_cid_address_event_v1_num_emitted);
    }

    /// Clear the cid address, and verify the address was cleared
    public fun clear_cid_address(
        user: &signer,
        cid: u64
    ) {
        let register_cid_event_v1_event_count_before = cid::get_register_cid_event_v1_count();
        let set_cid_address_event_v1_event_count_before = cid::get_set_cid_address_event_v1_count();

        cid::clear_cid_address(user, cid);

        let (_property_version, _expiration_time_sec, target_address) = cid::get_record_v1_props_for_cid(cid);
        test_utils::print_actual_expected(b"clear_cid_address: ", target_address, option::none(), false);
        assert!(target_address == option::none(), 1);

        // Assert events have been correctly emmitted
        let register_cid_event_v1_num_emitted = cid::get_register_cid_event_v1_count() - register_cid_event_v1_event_count_before;
        let set_cid_address_event_v1_num_emitted = cid::get_set_cid_address_event_v1_count() - set_cid_address_event_v1_event_count_before;

        test_utils::print_actual_expected(b"register_cid_event_v1_num_emitted: ", register_cid_event_v1_num_emitted, 0, false);
        assert!(register_cid_event_v1_num_emitted == 0, register_cid_event_v1_num_emitted);

        test_utils::print_actual_expected(b"set_cid_address_event_v1_num_emitted: ", set_cid_address_event_v1_num_emitted, 1, false);
        assert!(set_cid_address_event_v1_num_emitted == 1, set_cid_address_event_v1_num_emitted);
    }

    /// Renew the cid, and verify the renewal was done correctly
    public fun renew_cid(
        user: &signer,
        cid: u64,
        expected_target_address: address,
        expected_expiration_time: u64,
    ) {
        let register_cid_event_v1_event_count_before = cid::get_register_cid_event_v1_count();
        let set_cid_address_event_v1_event_count_before = cid::get_set_cid_address_event_v1_count();

        cid::renew(user, cid);

        let (_property_version, expiration_time_sec, target_address) = cid::get_record_v1_props_for_cid(cid);
        test_utils::print_actual_expected(b"renew_cid: ", target_address, option::some(expected_target_address), false);
        assert!(target_address == option::some(expected_target_address), 1);
        assert!(expiration_time_sec == expected_expiration_time, expiration_time_sec);

        // Assert events have been correctly emmitted
        let register_cid_event_v1_num_emitted = cid::get_register_cid_event_v1_count() - register_cid_event_v1_event_count_before;
        let set_cid_address_event_v1_num_emitted = cid::get_set_cid_address_event_v1_count() - set_cid_address_event_v1_event_count_before;

        test_utils::print_actual_expected(b"register_cid_event_v1_num_emitted: ", register_cid_event_v1_num_emitted, 1, false);
        assert!(register_cid_event_v1_num_emitted == 1, register_cid_event_v1_num_emitted);

        test_utils::print_actual_expected(b"set_cid_address_event_v1_num_emitted: ", set_cid_address_event_v1_num_emitted, 0, false);
        assert!(set_cid_address_event_v1_num_emitted == 0, set_cid_address_event_v1_num_emitted);
    }

    public fun setup_and_fund_accounts(
        aptos: &signer,
        foundation: &signer,
        users: vector<signer>
    ): vector<signer> {
        let (burn_cap, mint_cap) = aptos_framework::aptos_coin::initialize_for_test(aptos);

        let len = vector::length(&users);
        let i = 0;
        while (i < len) {
            let user = vector::borrow(&users, i);
            let user_addr = signer::address_of(user);
            account::create_account_for_test(user_addr);
            coin::register<AptosCoin>(user);
            coin::deposit(user_addr, coin::mint<AptosCoin>(mint_amount(), &mint_cap));
            assert!(coin::balance<AptosCoin>(user_addr) == mint_amount(), 1);
            i = i + 1;
        };

        account::create_account_for_test(signer::address_of(foundation));
        coin::register<AptosCoin>(foundation);

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
        users
    }
}
