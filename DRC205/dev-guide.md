# Development Guide

DRC205Proxy Canister-id: 6ylab-kiaaa-aaaak-aacga-cai   
ICHouse Explorer: https://637g5-siaaa-aaaaj-aasja-cai.raw.ic0.app/swaps

DRC205Proxy Canister-id (Test): ix3cb-4iaaa-aaaak-aagbq-cai  
ICHouse Explorer (Test): https://637g5-siaaa-aaaaj-aasja-cai.raw.ic0.app/SwapsTest

About Txid: txid is a blob type, it is the key of a transaction record. if your txid is a nat type or other type, it needs to be converted to a blob type.

## 1. Developing a Dex in Motoko

If you are a Motoko developer working on a Dex, either AMM or OrderBook, you can integrate DRC205 into your Dex using the `DRC205 Module`, example: https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/examples/ICLighthouse/Example/Example.mo   

If you are developing a Dapp with Motoko and just need to query the transaction records, refer to the `How to query transaction records` section below.

## 2. Developing a Dex in Rust

If you are a Rust developer working on a Dex, either AMM or OrderBook, you can call the DRC205Proxy and DRC205Bucket APIs to implement it.
DRC205Proxy did: https://github.com/iclighthouse/DRC_standards/tree/main/DRC205/DRC205Proxy.did   

**Storage of transaction records from your Dex to DRC205 Cansiter**

- Query storage fee

    When you call the storeBatch/storeBytesBatch method of DRC205Proxy, you need to pay the fee in Cycles and pay once for permanent storage. The `DRC205Proxy.fee()` method allows you to query the storage cost `fee` per record.

- Storing records using DRC205 TxnRecord type

    If you convert the transaction records to DRC205 TxnRecord type, you can call the `DRC205Proxy.storeBatch()` method for batch storage.
    ```
    storeBatch: (_txns: vec TxnRecord) -> ();
    ```
    Note: Calling this method requires adding `size(_txns) * fee` Cycles as a fee. To prevent overloading of DRC205, you need to call it only once at 20 second intervals. Please cache the records locally and call this method at intervals for batch storage.

- Storing records using custom type (Not recommended)

    If you are using custom types for your transaction records, you need to convert the records to Bytes (vec nat8) format first and then call the `DRC205Proxy.storeBytesBatch()` method for batch storage.
    ```
    storeBytesBatch: (_txns: vec record { Txid; vec nat8 }) -> ();
    ```
    Note: Calling this method requires adding `size(_txns) * fee` Cycles as a fee. To prevent overloading of DRC205, you need to call it only once at 20 second intervals. Please cache the records locally and call this method at intervals for batch storage.

**Query transaction records from DRC205 Cansiter**

If you need to query trading pair's transaction records in Dapp, refer to the `How to query transaction records` section below.

## 3. Implementing a interface in Dex for the IChouse Explorer

```
/// returns DRC205Proxy canister-id
drc205_canisterId: () -> (principal) query;
/// returns events. Address (Text type) is Principal or AccountId. If Address is not specified means to query all latest transaction records.
drc205_events: (opt Address) -> (vec TxnRecord) query;
/// returns txn record. Query txn record in trading pair canister cache.
drc205_txn: (Txid) -> (opt TxnRecord) query;
```

## 4. How to query transaction records

Whether you are a Rust, Motoko, or front-end developer, you need to provide the trading pair's appId (canister-id) and txid if you want to query the transaction records in DRC205. It is not possible to iterate through and query all records.  
DRC205Proxy did: https://github.com/iclighthouse/DRC_standards/tree/main/DRC205/DRC205Proxy.did   
DRC205Bucket did: https://github.com/iclighthouse/DRC_standards/tree/main/DRC205/DRC205Bucket.did   

- Motoko Developers

    If you are a Motoko developer, you can use the get/get2 method of the `DRC205 Module` to query transaction records.

- Other developers

    **Step 1**. Get the bucket canister-id where the transaction record is stored by querying DRC205Proxy

    Call the `DRC205Proxy.location()` method to get the Bucket canister-id where the record is stored, if it returns `[]` it means the record does not exist.  
    Note: If the return value contains more than one Bucket, it means that the transaction record may exist in one of the Buckets, which is the case due to the BloomFilter technology.

    **Step 2**. Query the transaction record via DRC205Bucket

    1) If the trading pair uses the DRC205 TxnRecord type, call the `DRC205Bucket.txn()`, `DRC205Bucket.txnHistory()`, `DRC205Bucket.txnByIndex()` or `DRC205Bucket.txnByAccountId()` method to look up the record based on the Bucket canister-id obtained in the previous step.

    2) If the trading pair uses a custom type for records, call the `DRC205Bucket.txnBytes()` or `DRC205Bucket.txnBytesHistory()` method to look up the record based on the Bucket canister-id obtained in the previous step. 

## Standard specification

https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/DRC205.md