#[test_only]
module aptos_cid::cid_e2e_tests {
    use std::signer;
    use std::vector;
    use aptos_framework::timestamp;
    use aptos_cid::cid;
    use aptos_cid::test_helper;
    use aptos_cid::time_helper::months_to_seconds;
    use aptos_cid::token_helper;

    #[test(myself = @aptos_cid, user = @0x077, aptos = @0x1, rando = @0x266f, foundation = @0xf01d)]
    fun happy_cid_e2e_test(
        myself: &signer,
        user: signer,
        aptos: signer,
        rando: signer,
        foundation: signer
    ) {
        let users = test_helper::e2e_test_setup(myself, user, &aptos, rando, &foundation);
        let user = vector::borrow(&users, 0);
        let rando = vector::borrow(&users, 1);

        let user_addr = signer::address_of(user);

        // Register the cid
        test_helper::register_cid(user, test_helper::test_cid(), test_helper::register_after_one_year_secs(), test_helper::fq_cid(), 1);

        // Set an address and verify it
        test_helper::set_cid_address(user, test_helper::test_cid(), user_addr);

        // Ensure the owner can clear the address
        test_helper::clear_cid_address(user, test_helper::test_cid());

        // And also can clear if the user is the registered address, but not owner
        test_helper::set_cid_address(user, test_helper::test_cid(), signer::address_of(rando));
        test_helper::clear_cid_address(rando, test_helper::test_cid());

        // Set it back for following tests
        test_helper::set_cid_address(user, test_helper::test_cid(), user_addr);
    }

    #[test(myself = @aptos_cid, user = @0x077, aptos = @0x1, rando = @0x266f, foundation = @0xf01d)]
    fun cid_are_registerable_after_expiry_e2e_test(
        myself: &signer,
        user: signer,
        aptos: signer,
        rando: signer,
        foundation: signer
    ) {
        let users = test_helper::e2e_test_setup(myself, user, &aptos, rando, &foundation);
        let user = vector::borrow(&users, 0);
        let rando = vector::borrow(&users, 1);

        // Register the cid
        test_helper::register_cid(user, test_helper::test_cid(), test_helper::register_after_one_year_secs(), test_helper::fq_cid(), 1);

        // Set the time past the cid's expiration time
        let (_, expiration_time_sec, _) = cid::get_record_v1_props_for_cid(test_helper::test_cid());
        timestamp::update_global_time_for_test_secs(expiration_time_sec + 5);

        // It should now be: expired, registered, AND registerable
        assert!(cid::cid_is_expired(test_helper::test_cid()), 1);
        assert!(cid::cid_is_registered(test_helper::test_cid()), 2);
        assert!(cid::cid_is_registerable(test_helper::test_cid()), 3);

        // Lets try to register it again, now that it is expired
        test_helper::register_cid(rando, test_helper::test_cid(), test_helper::register_after_one_year_secs(), test_helper::fq_cid(), 2);

        // And again!
        let (_, expiration_time_sec, _) = cid::get_record_v1_props_for_cid(test_helper::test_cid());
        timestamp::update_global_time_for_test_secs(expiration_time_sec + 5);

        // It should now be: expired, registered, AND registerable
        assert!(cid::cid_is_expired(test_helper::test_cid()), 4);
        assert!(cid::cid_is_registered(test_helper::test_cid()), 5);
        assert!(cid::cid_is_registerable(test_helper::test_cid()), 6);

        // Lets try to register it again, now that it is expired
        test_helper::register_cid(rando, test_helper::test_cid(), test_helper::register_after_one_year_secs(), test_helper::fq_cid(), 3);
    }

    #[test(myself = @aptos_cid, user = @0x077, aptos = @0x1, rando = @0x266f, foundation = @0xf01d)]
    #[expected_failure(abort_code = 196612)]
    fun dont_allow_double_cid_registrations_e2e_test(
        myself: &signer,
        user: signer,
        aptos: signer,
        rando: signer,
        foundation: signer
    ) {
        let users = test_helper::e2e_test_setup(myself, user, &aptos, rando, &foundation);
        let user = vector::borrow(&users, 0);

        // Register the cid
        test_helper::register_cid(user, test_helper::test_cid(), test_helper::register_after_one_year_secs(), test_helper::fq_cid(), 1);
        // Ensure we can't register it again
        test_helper::register_cid(user, test_helper::test_cid(), test_helper::register_after_one_year_secs(), test_helper::fq_cid(), 1);
    }

    #[test(myself = @aptos_cid, user = @0x077, aptos = @0x1, rando = @0x266f, foundation = @0xf01d)]
    #[expected_failure(abort_code = 327687)]
    fun dont_allow_rando_to_set_cid_address_e2e_test(
        myself: &signer,
        user: signer,
        aptos: signer,
        rando: signer,
        foundation: signer
    ) {
        let users = test_helper::e2e_test_setup(myself, user, &aptos, rando, &foundation);
        let user = vector::borrow(&users, 0);
        let rando = vector::borrow(&users, 1);

        // Register the cid
        test_helper::register_cid(user, test_helper::test_cid(), test_helper::register_after_one_year_secs(), test_helper::fq_cid(), 1);
        // Ensure we can't set it as a rando. The expected target address doesn't matter as it won't get hit
        test_helper::set_cid_address(rando, test_helper::test_cid(), @aptos_cid);
    }

    #[test(myself = @aptos_cid, user = @0x077, aptos = @0x1, rando = @0x266f, foundation = @0xf01d)]
    #[expected_failure(abort_code = 327682)]
    fun dont_allow_rando_to_clear_cid_address_e2e_test(
        myself: &signer,
        user: signer,
        aptos: signer,
        rando: signer,
        foundation: signer
    ) {
        let users = test_helper::e2e_test_setup(myself, user, &aptos, rando, &foundation);
        let user = vector::borrow(&users, 0);
        let rando = vector::borrow(&users, 1);

        // Register the cid, and set its address
        test_helper::register_cid(user, test_helper::test_cid(), test_helper::register_after_one_year_secs(), test_helper::fq_cid(), 1);
        test_helper::set_cid_address(user, test_helper::test_cid(), signer::address_of(user));

        // Ensure we can't clear it as a rando
        test_helper::clear_cid_address(rando, test_helper::test_cid());
    }

    #[test(myself = @aptos_cid, user = @0x077, aptos = @0x1, rando = @0x266f, foundation = @0xf01d)]
    fun owner_can_clear_cid_address_e2e_test(
        myself: &signer,
        user: signer,
        aptos: signer,
        rando: signer,
        foundation: signer
    ) {
        let users = test_helper::e2e_test_setup(myself, user, &aptos, rando, &foundation);
        let user = vector::borrow(&users, 0);
        let rando = vector::borrow(&users, 1);

        // Register the cid, and set its address
        test_helper::register_cid(user, test_helper::test_cid(), test_helper::register_after_one_year_secs(), test_helper::fq_cid(), 1);
        test_helper::set_cid_address(user, test_helper::test_cid(), signer::address_of(rando));

        // Ensure we can clear as owner
        test_helper::clear_cid_address(user, test_helper::test_cid());
    }

    #[test(myself = @aptos_cid, user = @0x077, aptos = @0x1, rando = @0x266f, foundation = @0xf01d)]
    fun owner_can_renew_cid_e2e_test(
        myself: &signer,
        user: signer,
        aptos: signer,
        rando: signer,
        foundation: signer
    ) {
        let users = test_helper::e2e_test_setup(myself, user, &aptos, rando, &foundation);
        let user = vector::borrow(&users, 0);
        let rando = vector::borrow(&users, 1);

        // Register the cid, and set its address
        test_helper::register_cid(user, test_helper::test_cid(), test_helper::register_after_one_year_secs(), test_helper::fq_cid(), 1);
        test_helper::set_cid_address(user, test_helper::test_cid(), signer::address_of(rando));

        // Ensure we can renew as owner in Renewable_Duration
        let (_, expiration_time_sec, _) = cid::get_record_v1_props_for_cid(test_helper::test_cid());
        timestamp::update_global_time_for_test_secs(expiration_time_sec - months_to_seconds(6));
        let expected_expiration_time = expiration_time_sec + months_to_seconds(24);

        test_helper::renew_cid(user, test_helper::test_cid(), signer::address_of(rando), expected_expiration_time);
    }

    #[test(myself = @aptos_cid, user = @0x077, aptos = @0x1, rando = @0x266f, foundation = @0xf01d)]
    fun owner_can_transfer_cid_nft_e2e_test(
        myself: &signer,
        user: signer,
        aptos: signer,
        rando: signer,
        foundation: signer
    ) {
        let users = test_helper::e2e_test_setup(myself, user, &aptos, rando, &foundation);
        let user = vector::borrow(&users, 0);
        let rando = vector::borrow(&users, 1);

        // Register the cid, and set its address
        test_helper::register_cid(user, test_helper::test_cid(), test_helper::register_after_one_year_secs(), test_helper::fq_cid(), 1);
        test_helper::set_cid_address(user, test_helper::test_cid(), signer::address_of(rando));

        token_helper::allow_direct_transfer(rando);
        token_helper::token_transfer(user, test_helper::fq_cid(), signer::address_of(rando));

        test_helper::set_cid_address(rando, test_helper::test_cid(), signer::address_of(user));
    }

    #[test(myself = @aptos_cid, user = @0x077, aptos = @0x1, rando = @0x266f, foundation = @0xf01d)]
    #[expected_failure(abort_code = 3)]
    fun owner_can_not_transfer_cid_nft_e2e_test(
        myself: &signer,
        user: signer,
        aptos: signer,
        rando: signer,
        foundation: signer
    ) {
        let users = test_helper::e2e_test_setup(myself, user, &aptos, rando, &foundation);
        let user = vector::borrow(&users, 0);
        let rando = vector::borrow(&users, 1);

        // Register the cid, and set its address
        test_helper::register_cid(user, test_helper::test_cid(), test_helper::register_after_one_year_secs(), test_helper::fq_cid(), 1);
        test_helper::set_cid_address(user, test_helper::test_cid(), signer::address_of(rando));

        token_helper::token_transfer(user, test_helper::fq_cid(), signer::address_of(rando));
    }

    #[test(myself = @aptos_cid, user = @0x077, aptos = @0x1, rando = @0x266f, foundation = @0xf01d)]
    #[expected_failure(abort_code = 2)]
    fun not_owner_can_not_transfer_cid_nft_e2e_test(
        myself: &signer,
        user: signer,
        aptos: signer,
        rando: signer,
        foundation: signer
    ) {
        let users = test_helper::e2e_test_setup(myself, user, &aptos, rando, &foundation);
        let user = vector::borrow(&users, 0);
        let rando = vector::borrow(&users, 1);

        // Register the cid, and set its address
        test_helper::register_cid(user, test_helper::test_cid(), test_helper::register_after_one_year_secs(), test_helper::fq_cid(), 1);
        test_helper::set_cid_address(user, test_helper::test_cid(), signer::address_of(rando));

        token_helper::allow_direct_transfer(rando);
        token_helper::token_transfer(rando, test_helper::fq_cid(), signer::address_of(rando));
    }
}
