# aptos-cid
Decentralized identity on Aptos, the underlying account system of ComingChat

## Intro
ComingChat 4-digit cid is abbreviated as aptos-cid on aptos

- (1) aptos-cid ends with ".aptos", such as "1234.aptos".

- (2) aptos-cid is Aptos Token (equivalent to ERC721), 
  which can be freely circulated in the NFT market.

- (3) Limited release, the total amount is limited, 
  only 9000 ([1000, 9999]), first come first registration, the later the fee is higher.

- (4) Each cid is valid for 2 years. After it expires, anyone can register it again.

- (5) When the validity period of each cid is less than 6 months, 
 each cid can be renewed for 2 years.

## Features
- (1) Each cid can log in to ComingChat.
- (2) Each cid holder can enjoy preferential prices from ComingChat NFT partners.

## Price function
```txt
register_at_month = seconds_to_months((now - start_time_sec))
price = base_price * sqrt(register_at_month)
```

## Validity period
- Each cid is only valid for 2 years.
- Each registration and renewal adds 2 years of validity.

## Roles
- `owner`: aptos-cid contract deployer.
- `admin`: aptos-cid admin.
- `foundation`: aptos-cid contract revenue account.
- `user`: any user registered with aptos-cid.

## Entry functions
**cid module**:
- (1) `initialize`(owner): execute once to complete the contract configuration.
- (2) `register`(user): register aptos-cid and bind the address, valid for 2 years.
- (3) `renew`(user): the validity period is less than 6 months to operate, 
   and the validity period is increased by 2 years.
- (4) `set_cid_address`(user): rebind aptos-cid and address.
- (5) `clear_cid_address`(user): unbind aptos-cid and address.
- (6) `allow_direct_transfer`(user): allow sender transfer any nft to self.
- (7) `cid_token_transfer`(user): send cid nft to receiver.
- (8) `token_transfer`(user): send any nft to receiver.

**config module**:
- (1) `set_is_enabled`(owner/admin): whether to stop aptos-cid `register` and `renew`.
- (2) `set_fundation_address`(owner/admin): set the aptos-cid nft fundation address.
- (3) `set_admin_address`(owner/admin): set aptos-cid nft admin address.
- (4) `set_tokendata_description`(owner/admin): set aptos-cid nft description.
- (5) `set_tokendata_url_prefix`(owner/admin): set aptos-cid nft url prefix.
- (6) `set_cid_price`(owner/admin): set the base price of aptos-cid nft.

## Important notes
- (1) Only users holding cid can bind address, and can bind any address. 
  If the address of owner does not want to be bound to cid, then call `clear_cid_address`.

- (2) Users can complete the transfer of cid through `aptos_token`. 
  After the transfer, the new owner of the cid should call `clear_cid_address`
  or `set_cid_address` to complete the binding with the address.

- (3) Call `unchecked_cid_resolved_address` returns the address bound to cid, 
  this return value is not timely, because `clear_cid_address` or `set_cid_address` may not be called in time.
