// Copyright 2022 OmniBTC Authors. Licensed under Apache-2.0 License.
module aptos_cid::token_helper {
    friend aptos_cid::cid;

    use aptos_framework::timestamp;
    use aptos_cid::config;
    use aptos_cid::utf8_utils;
    use aptos_token::token::{Self, TokenDataId, TokenId};
    use aptos_token::property_map;
    use std::signer;
    use std::string::{Self, String};
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_cid::utf8_utils::u64_to_string;

    const CID_SUFFIX: vector<u8> = b".aptos";

    /// The collection does not exist. This should never happen.
    const ECOLLECTION_NOT_EXISTS: u64 = 1;
    const ETOKEN_INSUFFICIENT_BALANCE: u64 = 2;
    const EREQUIRE_ALLOW_DIRECT_TRANSFER: u64 = 3;

    /// Tokens require a signer to create, so this is the signer for the collection
    struct CollectionCapabilityV1 has key, drop {
        capability: SignerCapability,
    }

    public fun allow_direct_transfer(
        account: &signer
    ) {
        token::initialize_token_store(account);
        token::opt_in_direct_transfer(account, true);
    }

    public fun token_transfer(
        from: &signer,
        fully_qualified_cid: String,
        to: address,
    ) acquires CollectionCapabilityV1 {
        let creator = get_token_signer_address();
        let token_data_id = token::create_token_data_id(
            creator,
            config::collection_name_v1(),
            fully_qualified_cid
        );
        let token_property_version = token::get_tokendata_largest_property_version(
            creator,
            token_data_id
        );
        let token_id = token::create_token_id(
            token_data_id,
            token_property_version
        );

        assert!(
            token::has_token_store(to),
            EREQUIRE_ALLOW_DIRECT_TRANSFER,
        );
        assert!(
            token::balance_of(signer::address_of(from), token_id) > 0,
            ETOKEN_INSUFFICIENT_BALANCE,
        );

        token::transfer(from, token_id, to, 1);
    }

    public fun transfer_with_opt_in(
        from: &signer,
        creator: address,
        collection_name: String,
        token_name: String,
        token_property_version: u64,
        to: address,
        amount: u64,
    ) {
        let token_id = token::create_token_id_raw(creator, collection_name, token_name, token_property_version);
        token::transfer(from, token_id, to, amount);
    }

    public fun get_token_signer_address(): address acquires CollectionCapabilityV1 {
        account::get_signer_capability_address(&borrow_global<CollectionCapabilityV1>(@aptos_cid).capability)
    }

    fun get_token_signer(): signer acquires CollectionCapabilityV1 {
        account::create_signer_with_capability(&borrow_global<CollectionCapabilityV1>(@aptos_cid).capability)
    }

    /// In the event of requiring operations via script, this allows root to get the registry signer
    public fun break_token_registry_glass(sign: &signer): signer acquires CollectionCapabilityV1 {
        config::assert_signer_is_admin(sign);
        get_token_signer()
    }

    public(friend) fun initialize(owner: &signer) {
        // Create the resource account for token creation, so we can get it as a signer later
        let registry_seed = utf8_utils::u128_to_string((timestamp::now_microseconds() as u128));
        string::append(&mut registry_seed, string::utf8(b"registry_seed"));
        let (token_resource, token_signer_cap) = account::create_resource_account(owner, *string::bytes(&registry_seed));

        move_to(owner, CollectionCapabilityV1 {
            capability: token_signer_cap,
        });

        let description = string::utf8(b".aptos names from the ComingChat Cid");
        let collection_uri = string::utf8(b"https://aptoscid.coming.chat");
        // This turns off supply tracking, which allows for parallel execution
        let maximum_supply = 0;
        // collection description mutable: true
        // collection URI mutable: true
        // collection max mutable: false
        let mutate_setting = vector<bool>[ true, true, false ];
        token::create_collection(&token_resource, config::collection_name_v1(), description, collection_uri, maximum_supply, mutate_setting);
    }

    public fun get_fully_qualified_cid(cid: u64): String {
        let cid_string = u64_to_string(cid);
        string::append_utf8(&mut cid_string, CID_SUFFIX);
        cid_string
    }

    public fun tokendata_exists(token_data_id: &TokenDataId): bool {
        let (creator, collection_name, token_name) = token::get_token_data_id_fields(token_data_id);
        token::check_tokendata_exists(creator, collection_name, token_name)
    }

    public fun build_tokendata_id(token_resource_address: address, cid: u64): TokenDataId {
        let collection_name = config::collection_name_v1();
        let fq_cid = get_fully_qualified_cid(cid);
        token::create_token_data_id(token_resource_address, collection_name, fq_cid)
    }

    public fun latest_token_id(token_data_id: &TokenDataId): TokenId {
        let (creator, _collection_name, _token_name) = token::get_token_data_id_fields(token_data_id);
        let largest_tokendata_property_version = token::get_tokendata_largest_property_version(creator, *token_data_id);
        token::create_token_id(*token_data_id, largest_tokendata_property_version)
    }

    /// gets or creates the token data for the given cid
    public(friend) fun ensure_token_data(cid: u64, type: String): TokenDataId acquires CollectionCapabilityV1 {
        let token_resource = &get_token_signer();

        let token_data_id = build_tokendata_id(signer::address_of(token_resource), cid);
        if (tokendata_exists(&token_data_id)) {
            token_data_id
        } else {
            create_token_data(token_resource, cid, type)
        }
    }

    fun create_token_data(token_resource: &signer, cid: u64, type: String): TokenDataId {
        // Set up the NFT
        let collection_name = config::collection_name_v1();
        assert!(
            token::check_collection_exists(
                signer::address_of(token_resource),
                collection_name
            ),
            ECOLLECTION_NOT_EXISTS
        );

        let fq_cid = get_fully_qualified_cid(cid);

        let nft_maximum: u64 = 0;
        let description = config::tokendata_description();
        let token_uri: string::String = config::tokendata_url_prefix();
        string::append(&mut token_uri, fq_cid);
        let royalty_payee_address: address = @aptos_cid;
        let royalty_points_denominator: u64 = 0;
        let royalty_points_numerator: u64 = 0;
        // tokan max mutable: false
        // token uri mutable: true
        // token description mutable: true
        // token royalty mutable: false
        // token properties mutable: true
        let token_mutate_config = token::create_token_mutability_config(&vector<bool>[ false, true, true, false, true ]);

        let type = property_map::create_property_value(&type);
        let now = property_map::create_property_value(&timestamp::now_seconds());

        let property_keys: vector<String> = vector[
            config::config_key_creation_time_sec(),
            config::config_key_type(),
        ];
        let property_values: vector<vector<u8>> = vector[
            property_map::borrow_value(&now),
            property_map::borrow_value(&type)
        ];
        let property_types: vector<String> = vector[
            property_map::borrow_type(&now),
            property_map::borrow_type(&type)
        ];


        token::create_tokendata(
            token_resource,
            collection_name,
            fq_cid,
            description,
            nft_maximum,
            token_uri,
            royalty_payee_address,
            royalty_points_denominator,
            royalty_points_numerator,
            token_mutate_config,
            property_keys,
            property_values,
            property_types
        )
    }

    public(friend) fun create_token(tokendata_id: TokenDataId): TokenId acquires CollectionCapabilityV1 {
        let token_resource = get_token_signer();

        // At this point, property_version is 0
        let (_creator, collection_name, _name) = token::get_token_data_id_fields(&tokendata_id);
        assert!(
            token::check_collection_exists(
                signer::address_of(&token_resource),
                collection_name
            ),
            ECOLLECTION_NOT_EXISTS
        );

        token::mint_token(&token_resource, tokendata_id, 1)
    }

    public(friend) fun set_token_props(token_owner: address, property_keys: vector<String>, property_values: vector<vector<u8>>, property_types: vector<String>, token_id: TokenId): TokenId acquires CollectionCapabilityV1 {
        let token_resource = get_token_signer();

        // At this point, property_version is 0
        // This will create a _new_ token with property_version == max_property_version of the tokendata, and with the properties we just set
        token::mutate_one_token(
            &token_resource,
            token_owner,
            token_id,
            property_keys,
            property_values,
            property_types
        )
    }

    public(friend) fun transfer_token_to(sign: &signer, token_id: TokenId) acquires CollectionCapabilityV1 {
        token::initialize_token_store(sign);
        token::opt_in_direct_transfer(sign, true);

        let token_resource = get_token_signer();
        token::transfer(&token_resource, token_id, signer::address_of(sign), 1);
    }

    #[test]
    fun test_get_fully_qualified_cid() {
        assert!(get_fully_qualified_cid(1000) == string::utf8(b"1000.aptos"), 1);
        assert!(get_fully_qualified_cid(9999) == string::utf8(b"9999.aptos"), 2);
    }
}
