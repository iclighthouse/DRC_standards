# Development Guide

DRC205Root Canister-id: lw5dr-uiaaa-aaaak-ae2za-cai   
ICHouse Explorer: https://ic.house/swaps

DRC205Proxy Canister-id (Test): lr4ff-zqaaa-aaaak-ae2zq-cai   
ICHouse Explorer (Test): https://ic.house/SwapsTest

About Txid: txid is a blob type, it is the key of a transaction record. if your txid is a nat type or other type, it needs to be converted to a blob type.

## 1. Developing a Dex in Motoko

If you are a Motoko developer working on a Dex, either AMM or OrderBook, you can integrate DRC205 into your Dex using the `DRC205 Module`, example: https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/examples/ICLighthouse/Example/Example.mo   

If you are developing a Dapp with Motoko and just need to query the transaction records, refer to the `How to query transaction records` section below.

## 2. Developing a Dex in Rust

If you are a Rust developer working on a Dex, either AMM or OrderBook, you can call DRC205Root, DRC205Proxy and DRC205Bucket APIs to implement it. 

**Storage of transaction records from your Dex to DRC205 Cansiter**

- Query current Proxy from Root

    Call proxyList() from DRC205Root to get the current Proxy.

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
/// returns events. Filters and returns the records from start `Time` to end `Time`.
drc205_events_filter: (opt Address, opt Time, opt Time) -> (vec TxnRecord, bool) query;
/// returns txn record. Query txn record in trading pair canister cache.
drc205_txn: (Txid) -> (opt TxnRecord) query;
/// returns txn record. It's an composite query method that will try to find txn record in the DRC205 canister if the record does not exist in this canister.
drc205_txn2 : (_txid: Txid) -> (opt TxnRecord) composite_query
/// Returns archived records. It's an composite query method.
drc205_archived_txns : (_start_desc: nat, _length: nat) -> (vec TxnRecord) composite_query;
/// Returns archived records based on AccountId. This is a composite query method that returns data for only the specified number of buckets.
drc205_archived_account_txns : (_buckets_offset: opt nat, _buckets_length: nat, _account: AccountId, _page: opt nat32, _size: opt nat32) -> ({data: vec record{principal; vec record{TxnRecord; Time}}; totalPage: nat; total: nat}) composite_query;
```

## 4. How to query transaction records

Whether you are a Rust, Motoko, or front-end developer, you need to provide the trading pair's appId (canister-id) and txid, index or accountId if you want to query the transaction records in DRC205.    
DRC205Root did: https://github.com/iclighthouse/DRC_standards/tree/main/DRC205/DRC205Root.did   
DRC205Proxy did: https://github.com/iclighthouse/DRC_standards/tree/main/DRC205/DRC205Proxy.did   
DRC205Bucket did: https://github.com/iclighthouse/DRC_standards/tree/main/DRC205/DRC205Bucket.did   

- Motoko Developers

    Use the get()/getEvents() method of the `DRC205 Module` to query the local cache of recent transaction records, and use the get2() method to query both cached and archived records.

- For all developers

    1. **Method 1**

    Querying transaction records by Dex with DRC205 implemented:.
    - drc205_events(), drc205_events_filter, drc205_txn(): Queries the latest transaction history of the current Dex cached.
    - drc205_txn2(), drc205_archived_txns(), drc205_archived_account_txns(): Queries the transaction history of the external Canister archives.

    2. **Method 2**

    Query the transaction records through the composite_query methods provided by DRC205Root:
    - getArchivedTxn(), getArchivedTxnByIndex(), getArchivedDexTxns(), getArchivedAccountTxns().
    - If custom types are used, use getArchivedTxnBytes().

    3. **Method 3**

    **Step 1**. Query the Proxy list by DRC205Root.

    **Step 2**. Get the bucket canister-id where the transaction record is stored by querying DRC205Proxy

    Call the `DRC205Proxy.location()` method to get the Bucket canister-id where the record is stored, if it returns `[]` it means the record does not exist.  
    Note: If the return value contains more than one Bucket, it means that the transaction record may exist in one of the Buckets, which is the case due to the BloomFilter technology.

    **Step 3**. Query the transaction record via DRC205Bucket

    1) If the trading pair uses the DRC205 TxnRecord type, call the `DRC205Bucket.txn()`, `DRC205Bucket.txnHistory()`, `DRC205Bucket.txnByIndex()` or `DRC205Bucket.txnByAccountId()` method to look up the record based on the Bucket canister-id obtained in the previous step.

    2) If the trading pair uses a custom type for records, call the `DRC205Bucket.txnBytes()` or `DRC205Bucket.txnBytesHistory()` method to look up the record based on the Bucket canister-id obtained in the previous step. 

## Standard specification

https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/DRC205.md