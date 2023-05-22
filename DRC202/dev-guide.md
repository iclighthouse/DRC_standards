# DRC202 Development Guide

DRC202Proxy Canister-id: y5a36-liaaa-aaaak-aacqa-cai  
ICHouse Explorer: https://637g5-siaaa-aaaaj-aasja-cai.raw.ic0.app/tokens

DRC202Proxy Canister-id (Test): iq2ev-rqaaa-aaaak-aagba-cai  
ICHouse Explorer (Test): https://637g5-siaaa-aaaaj-aasja-cai.raw.ic0.app/TokensTest

About Txid: txid is a blob type, it is the key of a transaction record. if your txid is a nat type or other type, it needs to be converted to a blob type.

## 1. Developing a Token in Motoko

If you are a Motoko developer developing a token, e.g. DRC20, DIP20, ICRC1 standard tokens, you can integrate DRC202 into your token using the `DRC202 Module`, example: https://github.com/iclighthouse/DRC_standards/blob/main/DRC202/examples/ICLighthouse/Example/Example.mo   

If you are developing a Dapp with Motoko and just need to query the transaction records, refer to the `How to query transaction records` section below.

## 2. Developing a Token in Rust

If you are a Rust developer developing a token, such as DRC20, DIP20, ICRC1 standard tokens, you can call the DRC202Proxy and DRC202Bucket APIs to implement it.
DRC202Proxy did: https://github.com/iclighthouse/DRC_standards/tree/main/DRC202/DRC202Proxy.did   

**Storage of transaction records from your Token to DRC202 Cansiter**

- Query storage fee

    When you call the storeBatch/storeBytesBatch method of DRC202Proxy, you need to pay the fee in Cycles and pay once for permanent storage. The `dRC202Proxy.fee()` method allows you to query the storage cost `fee` per record.

- Storing records using DRC202 TxnRecord type

    If you convert the transaction records to DRC202 TxnRecord type, you can call the `DRC202Proxy.storeBatch()` method for batch storage.
    ```
    storeBatch: (_txns: vec TxnRecord) -> ();
    ```
    Note: Calling this method requires adding `size(_txns) * fee` Cycles as a fee. To prevent overloading of DRC202, you need to call it only once at 20 second intervals. Please cache the records locally and call this method at intervals for batch storage.

- Storing records using custom type (Not recommended)

    If you are using custom types for your transaction records, you need to convert the records to Bytes (vec nat8) format first and then call the `DRC202Proxy.storeBytesBatch()` method for batch storage.
    ```
    storeBytesBatch: (_txns: vec record { Txid; vec nat8 }) -> ();
    ```
    Note: Calling this method requires adding `size(_txns) * fee` Cycles as a fee. To prevent overloading of DRC202, you need to call it only once at 20 second intervals. Please cache the records locally and call this method at intervals for batch storage.

**Query transaction records from DRC202 Cansiter**

If you need to query Token's transaction records in canister, refer to the `How to query transaction records` section below.

## 3. Implement interface in Token for IChouse Explorer

```
/// returns DRC202Proxy canister-id
drc202_canisterId: () -> (principal) query;
/// returns events. Address (Text type) is Principal or AccountId. If Address is not specified means to query all latest transaction records.
drc202_events: (opt Address) -> (vec TxnRecord) query;
/// returns txn record. Query txn record in token canister cache.
drc202_txn: (Txid) -> (opt TxnRecord) query;
```

## 4. How to query transaction records

Whether you are a Rust, Motoko, or front-end developer, you need to provide the token's canister-id and txid if you want to query the transaction records in DRC202. It is not possible to iterate through and query all records.
DRC202Proxy did: https://github.com/iclighthouse/DRC_standards/tree/main/DRC202/DRC202Proxy.did   
DRC202Bucket did: https://github.com/iclighthouse/DRC_standards/tree/main/DRC202/DRC202Bucket.did   

- Motoko Developers

    If you are a Motoko developer, you can use the get/get2 method of the `DRC202 Module` to query transaction records.

- Other developers

    **Step 1**. Get the bucket canister-id where the transaction record is stored by querying DRC202Proxy

    Call `DRC202Proxy.bucket()` or `DRC202Proxy.bucketByIndex()` method to get the Bucket canister-id where the record is stored, if it returns `[]` means the record does not exist.  
    Note: If the return value contains more than one Bucket, it means that the transaction record may exist in one of the Buckets, which is the case due to the BloomFilter technology.

    **Step 2**. Query the transaction record via DRC202Bucket

    1) If this token uses the DRC202 TxnRecord type, call `DRC202Bucket.txn()`, `DRC202Bucket.txnHistory()`, `DRC202Bucket. txnByIndex()` or `DRC202Bucket.txnByAccountId()` methods to query the record.

    2) If this token uses a custom type, call the `DRC202Bucket.txnBytes()` or `DRC202Bucket.txnBytesHistory()` method to query the record based on the Bucket canister-id obtained in the previous step.

## Standard specification

https://github.com/iclighthouse/DRC_standards/blob/main/DRC202/DRC202.md