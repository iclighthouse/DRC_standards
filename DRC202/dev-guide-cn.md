# DRC202开发指南

DRC202Proxy Root: bffvb-aiaaa-aaaak-ae3ba-cai  
ICHouse浏览器: https://ic.house/tokens

DRC202Proxy Root(Test): bcetv-nqaaa-aaaak-ae3bq-cai  
ICHouse浏览器(Test): https://ic.house/TokensTest

关于Txid：txid是blob类型，属于每条交易记录的key。如果你的txid是nat类型或其他类型，需转换成blob类型。

## 1. Motoko开发者开发一个Token

如果你是一个Motoko开发者，正在开发一个Token Canister，例如DRC20、DIP20、ICRC1标准的代币，你可以使用`DRC202 Module`将DRC202整合到你的Token中，例子：https://github.com/iclighthouse/DRC_standards/blob/main/DRC202/examples/ICLighthouse/Example/Example.mo   

如果你正在用Motoko开发其他Dapp，只需要查询交易记录，请参照下文`如何查询交易记录`部分。

## 2. Rust开发者开发一个Token

如果你是一个Rust开发者，正在开发一个Token Canister，例如DRC20、DIP20、ICRC1标准的代币，你可以调用DRC202Root, DRC202Proxy和DRC202Bucket的API来实现。  

**从你的Token将交易记录存储到DRC202 Cansiter中**

- 查询存储费用

    调用DRC202Proxy的storeBatch/storeBytesBatch方法时，需要以Cycles支付费用，一次支付永久存储。通过`DRC202Proxy.fee()`方法可以查询每条记录的存储费用`fee`。

- 使用DRC202 TxnRecord类型存储记录

    如果你将交易记录转换成DRC202 TxnRecord类型，则可以调用`DRC202Proxy.storeBatch()`方法进行批量存储。
    ```
    storeBatch: (_txns: vec TxnRecord) -> ();
    ```
    注意：调用该方法需要添加 size(_txns) * fee Cycles作为费用。为了防止DRC202的访问过载，你需要间隔20秒才能调用一次。请在本地缓存记录，并间隔一段时间调用该方法进行批量存储。

- 使用自定义类型存储记录(不建议)

    如果你的交易记录使用自定义类型，需要先将记录转换成Bytes (vec nat8)格式，然后调用`DRC202Proxy.storeBytesBatch()`方法进行批量存储。
    ```
    storeBytesBatch: (_txns: vec record { Txid; vec nat8 }) -> ();
    ```
    注意：调用该方法需要添加 size(_txns) * fee Cycles作为费用。为了防止DRC202的访问过载，你需要间隔20秒才能调用一次。请在本地缓存记录，并间隔一段时间调用该方法进行批量存储。

**从DRC202 Cansiter中查询交易记录**

如果你在Canister中需要查询Token的交易记录，请参照下文`如何查询交易记录`部分。

## 3. 在Token中为IChouse浏览器实现查询接口

```
/// returns DRC202Proxy canister-id
drc202_canisterId: () -> (principal) query;
/// returns events. Address (Text type) is Principal or AccountId. If Address is not specified means to query all latest transaction records.
drc202_events: (opt Address) -> (vec TxnRecord) query;
/// returns events. Filters and returns the records from start `Time` to end `Time`.
drc202_events_filter: (opt Address, opt Time, opt Time) -> (vec TxnRecord, bool) query;
/// returns txn record. Query txn record in token canister cache.
drc202_txn: (Txid) -> (opt TxnRecord) query;
/// returns txn record. It's an composite query method that will try to find txn record in the DRC202 canister if the record does not exist in this canister.
drc202_txn2 : (_txid: Txid) -> (opt TxnRecord) composite_query
/// Returns archived records. It's an composite query method.
drc202_archived_txns : (_start_desc: nat, _length: nat) -> (vec TxnRecord) composite_query;
/// Returns archived records based on AccountId. This is a composite query method that returns data for only the specified number of buckets.
drc202_archived_account_txns : (_buckets_offset: opt nat, _buckets_length: nat, _account: AccountId, _page: opt nat32, _size: opt nat32) -> ({data: vec record{principal; vec record{TxnRecord; Time}}; totalPage: nat; total: nat}) composite_query;
```

## 4. 如何查询交易记录

无论你是Rust、Motoko、还是前端开发者，需要查询在DRC202中的交易记录，需要提供token的canister-id和txid、index或accountId。  
DRC202Root did: https://github.com/iclighthouse/DRC_standards/tree/main/DRC202/DRC202Root.did   
DRC202Proxy did: https://github.com/iclighthouse/DRC_standards/tree/main/DRC202/DRC202Proxy.did   
DRC202Bucket did: https://github.com/iclighthouse/DRC_standards/tree/main/DRC202/DRC202Bucket.did   

- Motoko开发者

    使用`DRC202 Module`的get()/getEvents()方法查询本地缓存的近期交易记录，使用get2()方法查询可以同时查询缓存和存档的记录。

- 适用所有开发者

    1. **方式1**

    通过实现了DRC202的Token查询交易记录:
    - drc202_events(), drc202_events_filter, drc202_txn(): 查询当前Token缓存的最新的交易记录。
    - drc202_txn2(), drc202_archived_txns(), drc202_archived_account_txns(): 查询外部Canister存档的交易记录。

    2. **方式2**

    通过DRC202Root提供的composite_query方法查询交易记录：
    - getArchivedTxn(), getArchivedTxnByIndex(), getArchivedDexTxns(), getArchivedAccountTxns().
    - 如果使用了自定义类型，使用getArchivedTxnBytes().

    3. **方式3**

    **Step 1**. 通过DRC202Proxy查询交易记录存储所在的bucket canister-id

    调用`DRC202Proxy.bucket()`或`DRC202Proxy.bucketByIndex()`方法查询得到该记录存储所在的Bucket canister-id，如果返回`[]`表示记录不存在。  
    注意：如果返回值是包含多个Bucket，则意味着交易记录可能存在于其中一个Bucket中，这是因为采用了BloomFilter技术而导致的情况。

    **Step 2**. 通过DRC202Bucket查询交易记录

    1) 如果这个token使用了DRC202 TxnRecord类型，根据上一步得到的Bucket canister-id调用`DRC202Bucket.txn()`、`DRC202Bucket.txnHistory()`、`DRC202Bucket.txnByIndex()`或`DRC202Bucket.txnByAccountId()`方法查询记录。

    2) 如果这个token使用了自定义类型，根据上一步得到的Bucket canister-id调用`DRC202Bucket.txnBytes()`或`DRC202Bucket.txnBytesHistory()`方法查询记录。


## DRC202标准规范

https://github.com/iclighthouse/DRC_standards/blob/main/DRC202/DRC202-CN.md