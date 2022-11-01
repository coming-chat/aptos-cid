// Copyright 2022 OmniBTC Authors. Licensed under Apache-2.0 License.
module aptos_cid::cid {
    use std::error;
    use std::option::{Self, Option};
    use std::signer;
    use std::string::String;

    use aptos_framework::account;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use aptos_framework::event;
    use aptos_std::table::{Self, Table};
    use aptos_token::property_map;
    use aptos_token::token::{Self, TokenId};

    use aptos_cid::config;
    use aptos_cid::price_model;
    use aptos_cid::time_helper;
    use aptos_cid::token_helper;

    /// The cid service contract is not enabled
    const ENOT_ENABLED: u64 = 1;
    /// The caller is not authorized to perform this operation
    const ENOT_AUTHORIZED: u64 = 2;
    /// The cid is invalid. only support [1000, 9999].
    const ECID_INVALID: u64 = 3;
    /// The cid is not available, as it has already been registered
    const ECID_NOT_AVAILABLE: u64 = 4;
    /// The cid does not exist, it is not registered
    const ECID_NOT_EXIST: u64 = 5;
    /// The cid can not renew, only renew in last 6 month with 24 months validity period
    const ECID_NOT_RENEWABLE: u64 = 6;
    /// The caller is not the owner of the cid, and is not authorized to perform the action
    const ENOT_OWNER_OF_CID: u64 = 7;


    struct CidRecordKeyV1 has copy, drop, store {
        cid: u64,
    }

    struct CidRecordV1 has copy, drop, store {
        // This is the property version of the NFT that this cid record represents.
        // This is required to tell expired vs current NFTs apart.
        // if `property_version == 0`, burn origin token and mint new token
        // if `property_version > 0`, update token only
        property_version: u64,
        // The time, in seconds, when the cid is considered expired
        expiration_time_sec: u64,
        // The address this cid is set to point to
        target_address: Option<address>,
    }

    /// The start timestmp of aptos cid service
    struct Genesis has key {
        start_time_sec: u64
    }

    /// The main registry: keeps a mapping of CidRecordKeyV1 (cid) to CidRecordV1
    struct CidRegistryV1 has key, store {
        // A mapping from cid to an address
        registry: Table<CidRecordKeyV1, CidRecordV1>,
    }

    /// Handler for `SetCidAddressEventsV1` events
    struct SetCidAddressEventsV1 has key, store {
        set_cid_events: event::EventHandle<SetCidAddressEventV1>,
    }

    /// Handler for `RegisterCidEventsV1` events
    struct RegisterCidEventsV1 has key, store {
        register_cid_events: event::EventHandle<RegisterCidEventV1>,
    }

    /// A cid's address has changed
    /// This could be to a new address, or it could have been cleared
    struct SetCidAddressEventV1 has drop, store {
        cid: u64,
        property_version: u64,
        expiration_time_secs: u64,
        new_address: Option<address>,
    }

    /// A cid has been registered on chain
    /// Includes the the fee paid for the registration, and the expiration time
    /// Also includes the property_version, so we can tell which version of a given cid NFT is the latest
    struct RegisterCidEventV1 has drop, store {
        cid: u64,
        registration_fee_octas: u64,
        property_version: u64,
        expiration_time_secs: u64,
    }

    /// Call by @aptos_cid who is owner only
    public entry fun initialize(owner: &signer) {
        use aptos_framework::aptos_account;

        assert!(signer::address_of(owner) == @aptos_cid, error::permission_denied(ENOT_AUTHORIZED));

        if (!account::exists_at(@admin)) {
            aptos_account::create_account(@admin);
        };

        if (!account::exists_at(@foundation)) {
            aptos_account::create_account(@foundation);
        };

        config::initialize_v1(owner);

        move_to(
            owner,
            Genesis {
                start_time_sec: timestamp::now_seconds()
            }
        );

        move_to(
            owner,
            CidRegistryV1 {
                registry: table::new(),
            }
        );

        move_to(
            owner,
            SetCidAddressEventsV1 {
                set_cid_events: account::new_event_handle<SetCidAddressEventV1>(owner),
            }
        );

        move_to(
            owner,
            RegisterCidEventsV1 {
                register_cid_events: account::new_event_handle<RegisterCidEventV1>(owner),
            }
        );

        token_helper::initialize(owner);
    }

    /// Call by user for renting a cid with 24 months
    public entry fun register(
        user: &signer,
        cid: u64,
    ) acquires CidRegistryV1, RegisterCidEventsV1, SetCidAddressEventsV1, Genesis {
        assert!(config::is_enabled(), error::unavailable(ENOT_ENABLED));
        assert!(cid_is_registerable(cid), error::invalid_state(ECID_NOT_AVAILABLE));

        // Conver 24 months to its seconds representation for the inner method
        let registration_duration_secs: u64 = time_helper::validity_duration_seconds();
        // Current timestamp and price are related
        let price = price_model::price_for_cid_v1(start_duration_sec());
        coin::transfer<AptosCoin>(user, config::foundation_fund_address(), price);

        register_cid_internal(user, cid, registration_duration_secs, price);
        // Automatically set the cid to point to the sender's address
        set_cid_address_internal(cid, signer::address_of(user));
    }

    /// Call by user for cid renewal with new 24 months
    /// Require the owner of cid
    public entry fun renew(
        user: &signer,
        cid: u64,
    ) acquires CidRegistryV1, RegisterCidEventsV1, Genesis {
        assert!(config::is_enabled(), error::unavailable(ENOT_ENABLED));
        assert!(config::is_valid(cid), error::invalid_argument(ECID_INVALID));
        assert!(cid_is_renewable(cid), error::invalid_state(ECID_NOT_RENEWABLE));

        let user_addr = signer::address_of(user);
        let (is_owner, token_id) = is_owner_of_cid(user_addr, cid);
        assert!(is_owner, error::permission_denied(ENOT_OWNER_OF_CID));

        let cid_record_key = create_cid_record_key_v1(cid);
        let aptos_cid = borrow_global_mut<CidRegistryV1>(@aptos_cid);
        let cid_record = table::borrow_mut(&mut aptos_cid.registry, cid_record_key);
        let (property_version, expiration_time_sec, _target_address) = get_cid_record_v1_props(cid_record);

        // Conver 24 months to its seconds representation for the inner method
        let registration_duration_secs: u64 = time_helper::validity_duration_seconds();
        // Current timestamp and price are related
        let price = price_model::price_for_cid_v1(start_duration_sec());
        coin::transfer<AptosCoin>(user, config::foundation_fund_address(), price);
        let renew_expiration_time_sec = expiration_time_sec + registration_duration_secs;

        cid_record.expiration_time_sec = renew_expiration_time_sec;

        event::emit_event<RegisterCidEventV1>(
            &mut borrow_global_mut<RegisterCidEventsV1>(@aptos_cid).register_cid_events,
            RegisterCidEventV1 {
                cid,
                registration_fee_octas: price,
                property_version,
                expiration_time_secs: renew_expiration_time_sec,
            },
        );

        let (property_keys, property_values, property_types) = get_cid_property_map(renew_expiration_time_sec);
        token_helper::set_token_props(user_addr, property_keys, property_values, property_types, token_id);
    }

    /// Call by user for binding cid and address
    /// Require the owner of cid
    public entry fun set_cid_address(
        user: &signer,
        cid: u64,
        new_address: address
    ) acquires CidRegistryV1, SetCidAddressEventsV1 {
        let user_addr = signer::address_of(user);
        let (is_owner, token_id) = is_owner_of_cid(user_addr, cid);
        assert!(is_owner, error::permission_denied(ENOT_OWNER_OF_CID));

        let cid_record = set_cid_address_internal(cid, new_address);
        let (_property_version, expiration_time_sec, _target_address) = get_cid_record_v1_props(&cid_record);
        let (property_keys, property_values, property_types) = get_cid_property_map(expiration_time_sec);
        token_helper::set_token_props(user_addr, property_keys, property_values, property_types, token_id);
    }

    /// Call by user for clearing the address of cid
    /// Require the owner of cid or signer of address
    public entry fun clear_cid_address(
        user: &signer,
        cid: u64
    ) acquires CidRegistryV1, SetCidAddressEventsV1 {
        assert!(config::is_valid(cid), error::invalid_argument(ECID_INVALID));
        assert!(cid_is_registered(cid), error::not_found(ECID_NOT_EXIST));

        let user_addr = signer::address_of(user);
        // Only the owner or the registered address can clear the address
        let (is_owner, token_id) = is_owner_of_cid(user_addr, cid);
        let is_cid_resolved_address = unchecked_cid_resolved_address(cid) == option::some<address>(user_addr);

        assert!(is_owner || is_cid_resolved_address, error::permission_denied(ENOT_AUTHORIZED));

        let cid_record_key = create_cid_record_key_v1(cid);
        let aptos_cid = borrow_global_mut<CidRegistryV1>(@aptos_cid);
        let cid_record = table::borrow_mut(&mut aptos_cid.registry, cid_record_key);
        let (property_version, expiration_time_sec, _target_address) = get_cid_record_v1_props(cid_record);
        cid_record.target_address = option::none();

        emit_set_cid_address_event_v1(
            cid,
            property_version,
            expiration_time_sec,
            option::none(),
        );

        if (is_owner) {
            let (_property_version, expiration_time_sec, _target_address) = get_cid_record_v1_props(cid_record);
            let (property_keys, property_values, property_types) = get_cid_property_map(expiration_time_sec);
            token_helper::set_token_props(user_addr, property_keys, property_values, property_types, token_id);
        };
    }

    /// Helper function for transfer any nft
    /// For receiver
    public entry fun allow_direct_transfer(
        account: &signer
    ) {
        token_helper::allow_direct_transfer(account)
    }

    /// Helper function for transfer cid nft
    /// For sender
    public entry fun cid_token_transfer(
        from: &signer,
        fully_qualified_cid: String,
        to: address,
    ) {
        if (signer::address_of(from) != to) {
            token_helper::token_transfer(from, fully_qualified_cid, to)
        }
    }

    /// Helper function for transfer any nft
    /// For sender
    public entry fun token_trasfer(
        from: &signer,
        creator: address,
        collection_name: String,
        token_name: String,
        token_property_version: u64,
        to: address,
        amount: u64,
    ) {
        if (signer::address_of(from) != to) {
            token_helper::transfer_with_opt_in(
                from,
                creator,
                collection_name,
                token_name,
                token_property_version,
                to,
                amount
            )
        }
    }

    public fun start_time_sec(): u64 acquires Genesis {
        borrow_global<Genesis>(@aptos_cid).start_time_sec
    }

    public fun start_duration_sec(): u64 acquires Genesis {
        timestamp::now_seconds() - borrow_global<Genesis>(@aptos_cid).start_time_sec
    }

    /// Register a cid with 24 months validity period
    fun register_cid_internal(
        user: &signer,
        cid: u64,
        registration_duration_secs: u64,
        price: u64
    ) acquires CidRegistryV1, RegisterCidEventsV1 {
        assert!(config::is_valid(cid), error::invalid_argument(ECID_INVALID));

        let aptos_cid = borrow_global_mut<CidRegistryV1>(@aptos_cid);

        let cid_expiration_time_secs = timestamp::now_seconds() + registration_duration_secs;

        // Create the token, and transfer it to the user
        let tokendata_id = token_helper::ensure_token_data(cid, config::cid_type());
        let token_id = token_helper::create_token(tokendata_id);

        let (property_keys, property_values, property_types) = get_cid_property_map(cid_expiration_time_secs);
        token_id = token_helper::set_token_props(token_helper::get_token_signer_address(), property_keys, property_values, property_types, token_id);
        token_helper::transfer_token_to(user, token_id);

        // Add this cid to the registry
        let (_creator, _collection, _fully_qualified_cid, property_version) = token::get_token_id_fields(&token_id);
        let cid_record_key = create_cid_record_key_v1(cid);
        let cid_record = create_cid_record_v1(property_version, cid_expiration_time_secs, option::none());

        table::upsert(&mut aptos_cid.registry, cid_record_key, cid_record);

        event::emit_event<RegisterCidEventV1>(
            &mut borrow_global_mut<RegisterCidEventsV1>(@aptos_cid).register_cid_events,
            RegisterCidEventV1 {
                cid,
                registration_fee_octas: price,
                property_version,
                expiration_time_secs: cid_expiration_time_secs,
            },
        );
    }

    /// Checks for the cid not existing, or being expired
    /// Returns true if the cid is available for registration
    /// Doesn't use the `cid_is_expired` or `cid_is_registered` internally to share the borrow
    public fun cid_is_registerable(cid: u64): bool acquires CidRegistryV1 {
        assert!(config::is_valid(cid), error::invalid_argument(ECID_INVALID));

        // Check to see if the cid is registered, or expired
        let aptos_cid = borrow_global<CidRegistryV1>(@aptos_cid);
        let cid_record_key = create_cid_record_key_v1(cid);
        !table::contains(&aptos_cid.registry, cid_record_key) || cid_is_expired(cid)
    }

    /// Returns true if the cid is registered, and is expired.
    /// If the cid does not exist, raises an error
    public fun cid_is_expired(cid: u64): bool acquires CidRegistryV1 {
        let aptos_cid = borrow_global<CidRegistryV1>(@aptos_cid);
        let cid_record_key = create_cid_record_key_v1(cid);
        assert!(table::contains(&aptos_cid.registry, cid_record_key), error::not_found(ECID_NOT_EXIST));

        let cid_record = table::borrow(&aptos_cid.registry, cid_record_key);
        let (_property_version, expiration_time_sec, _target_address) = get_cid_record_v1_props(cid_record);
        time_is_expired(expiration_time_sec)
    }

    /// Returns true if the cid is renewable
    /// If the cid does not exist, raises an error
    public fun cid_is_renewable(cid: u64): bool acquires CidRegistryV1 {
        let aptos_cid = borrow_global<CidRegistryV1>(@aptos_cid);
        let cid_record_key = create_cid_record_key_v1(cid);
        assert!(table::contains(&aptos_cid.registry, cid_record_key), error::not_found(ECID_NOT_EXIST));

        let cid_record = table::borrow(&aptos_cid.registry, cid_record_key);
        let (_property_version, expiration_time_sec, _target_address) = get_cid_record_v1_props(cid_record);

        time_is_expired(expiration_time_sec - time_helper::months_to_seconds(6))
    }

    /// Returns true if the cid is registered
    /// If the cid does not exist, returns false
    public fun cid_is_registered(cid: u64): bool acquires CidRegistryV1 {
        let aptos_cid = borrow_global<CidRegistryV1>(@aptos_cid);
        let cid_record_key = create_cid_record_key_v1(cid);
        table::contains(&aptos_cid.registry, cid_record_key)
    }

    /// Given a cid, returns the cid record
    public fun get_cid_record_v1(cid: u64): CidRecordV1 acquires CidRegistryV1 {
        assert!(cid_is_registered(cid), error::not_found(ECID_NOT_EXIST));

        let aptos_cid = borrow_global<CidRegistryV1>(@aptos_cid);
        let cid_record_key = create_cid_record_key_v1(cid);
        *table::borrow(&aptos_cid.registry, cid_record_key)
    }

    /// Given a cid, returns the cid record properties
    public fun get_record_v1_props_for_cid(cid: u64): (u64, u64, Option<address>) acquires CidRegistryV1 {
        assert!(cid_is_registered(cid), error::not_found(ECID_NOT_EXIST));

        let aptos_cid = borrow_global<CidRegistryV1>(@aptos_cid);
        let cid_record_key = create_cid_record_key_v1(cid);
        get_cid_record_v1_props(table::borrow(&aptos_cid.registry, cid_record_key))
    }

    /// Check if the address is the owner of the given cid
    /// If the cid does not exist, returns false
    public fun is_owner_of_cid(
        owner_address: address,
        cid: u64
    ): (bool, TokenId) {
        assert!(config::is_valid(cid), error::invalid_argument(ECID_INVALID));

        let token_data_id = token_helper::build_tokendata_id(token_helper::get_token_signer_address(), cid);
        let token_id = token_helper::latest_token_id(&token_data_id);
        (token::balance_of(owner_address, token_id) > 0, token_id)
    }

    /// Gets the address pointed to by a given cid
    /// Is `Option<address>` because the cid may not be registered,
    /// Or it may not have an address associated with it
    /// Or it may not be updated after cid nft transfer
    public fun unchecked_cid_resolved_address(cid: u64): Option<address> acquires CidRegistryV1 {
        let aptos_cid = borrow_global<CidRegistryV1>(@aptos_cid);
        let cid_record_key = create_cid_record_key_v1(cid);
        if (table::contains(&aptos_cid.registry, cid_record_key)) {
            let cid_record = table::borrow(&aptos_cid.registry, cid_record_key);
            let (_property_version, _expiration_time_sec, target_address) = get_cid_record_v1_props(cid_record);
            target_address
        } else {
            option::none<address>()
        }
    }

    fun set_cid_address_internal(
        cid: u64,
        new_address: address
    ): CidRecordV1 acquires CidRegistryV1, SetCidAddressEventsV1 {
        assert!(cid_is_registered(cid), error::not_found(ECID_NOT_EXIST));
        assert!(config::is_valid(cid), error::invalid_argument(ECID_INVALID));

        let cid_record_key = create_cid_record_key_v1(cid);
        let aptos_cid = borrow_global_mut<CidRegistryV1>(@aptos_cid);
        let cid_record = table::borrow_mut(&mut aptos_cid.registry, cid_record_key);
        let (property_version, expiration_time_sec, _target_address) = get_cid_record_v1_props(cid_record);
        cid_record.target_address = option::some(new_address);

        emit_set_cid_address_event_v1(
            cid,
            property_version,
            expiration_time_sec,
            option::some(new_address),
        );

        *cid_record
    }

    fun emit_set_cid_address_event_v1(
        cid: u64,
        property_version: u64,
        expiration_time_secs: u64,
        new_address: Option<address>
    ) acquires SetCidAddressEventsV1 {
        let event = SetCidAddressEventV1 {
            cid,
            property_version,
            expiration_time_secs,
            new_address,
        };

        event::emit_event<SetCidAddressEventV1>(
            &mut borrow_global_mut<SetCidAddressEventsV1>(@aptos_cid).set_cid_events,
            event,
        );
    }

    public fun get_cid_property_map(expiration_time_sec: u64): (vector<String>, vector<vector<u8>>, vector<String>) {
        let type = property_map::create_property_value(&config::cid_type());
        let expiration_time_sec = property_map::create_property_value(&expiration_time_sec);

        let property_keys: vector<String> = vector[
            config::config_key_type(),
            config::config_key_expiration_time_sec()
        ];
        let property_values: vector<vector<u8>> = vector[
            property_map::borrow_value(&type),
            property_map::borrow_value(&expiration_time_sec)
        ];
        let property_types: vector<String> = vector[
            property_map::borrow_type(&type),
            property_map::borrow_type(&expiration_time_sec)
        ];

        (property_keys, property_values, property_types)
    }

    public fun create_cid_record_v1(property_version: u64, expiration_time_sec: u64, target_address: Option<address>): CidRecordV1 {
        CidRecordV1 {
            property_version,
            expiration_time_sec,
            target_address,
        }
    }

    public fun get_cid_record_v1_props(cid_record: &CidRecordV1): (u64, u64, Option<address>) {
        (cid_record.property_version, cid_record.expiration_time_sec, cid_record.target_address)
    }

    public fun create_cid_record_key_v1(cid: u64): CidRecordKeyV1 {
        assert!(config::is_valid(cid), error::invalid_argument(ECID_INVALID));

        CidRecordKeyV1 {
            cid,
        }
    }

    /// Given a time, returns true if that time is in the past, false otherwise
    public fun time_is_expired(expiration_time_sec: u64): bool {
        timestamp::now_seconds() >= expiration_time_sec
    }

    public fun get_cid_record_key_v1_props(cid_record_key: &CidRecordKeyV1): u64 {
        cid_record_key.cid
    }

    #[test_only]
    public fun init_module_for_test(owner: &signer) {
        initialize(owner)
    }

    #[test_only]
    public fun register_with_price(
        user: &signer,
        cid: u64,
        price: u64,
    ) acquires CidRegistryV1, RegisterCidEventsV1, SetCidAddressEventsV1 {
        assert!(config::is_enabled(), error::unavailable(ENOT_ENABLED));
        assert!(cid_is_registerable(cid), error::invalid_state(ECID_NOT_AVAILABLE));

        // Conver 24 months to its seconds representation for the inner method
        let registration_duration_secs: u64 = time_helper::validity_duration_seconds();
        coin::transfer<AptosCoin>(user, config::foundation_fund_address(), price);

        register_cid_internal(user, cid, registration_duration_secs, price);
        // Automatically set the cid to point to the sender's address
        set_cid_address_internal(cid, signer::address_of(user));
    }
    #[test_only]
    public fun get_set_cid_address_event_v1_count(): u64 acquires SetCidAddressEventsV1 {
        event::counter(&borrow_global<SetCidAddressEventsV1>(@aptos_cid).set_cid_events)
    }

    #[test_only]
    public fun get_register_cid_event_v1_count(): u64 acquires RegisterCidEventsV1 {
        event::counter(&borrow_global<RegisterCidEventsV1>(@aptos_cid).register_cid_events)
    }

    #[test(aptos = @0x1)]
    fun test_time_is_expired(aptos: &signer) {
        timestamp::set_time_has_started_for_testing(aptos);
        // Set the time to a nonzero value to avoid subtraction overflow.
        timestamp::update_global_time_for_test_secs(100);

        // If the expiration time is after the current time, we should return not expired
        assert!(!time_is_expired(timestamp::now_seconds() + 1), 1);

        // If the current time is equal to expiration time, consider it expired
        assert!(time_is_expired(timestamp::now_seconds()), 2);

        // If the expiration time is earlier than the current time, we should return expired
        assert!(time_is_expired(timestamp::now_seconds() - 1), 3);
    }
}
