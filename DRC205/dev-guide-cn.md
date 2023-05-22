
# 开发指南

DRC205Proxy Canister-id: 6ylab-kiaaa-aaaak-aacga-cai  
ICHouse浏览器: https://637g5-siaaa-aaaaj-aasja-cai.raw.ic0.app/swaps

DRC205Proxy Canister-id(测试): ix3cb-4iaaa-aaaak-aagbq-cai  
ICHouse浏览器(测试): https://637g5-siaaa-aaaaj-aasja-cai.raw.ic0.app/SwapsTest

关于Txid：txid是blob类型，属于每条交易记录的key。如果你的txid是nat类型或其他类型，需转换成blob类型。

## 1. Motoko开发者开发一个Dex

如果你是一个Motoko开发者，正在开发一个Dex，无论是AMM还是OrderBook，你可以使用`DRC205 Module`将DRC205整合到你的Dex中，例子：https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/examples/ICLighthouse/Example/Example.mo  

如果你正在用Motoko开发其他Dapp，只需要查询交易记录，请参照下文`如何查询交易记录`部分。

## 2. Rust开发者开发一个Dex

如果你是一个Rust开发者，正在开发一个Dex，无论是AMM还是OrderBook，你可以调用DRC205Proxy和DRC205Bucket的API来实现。  
DRC205Proxy did: https://github.com/iclighthouse/DRC_standards/tree/main/DRC205/DRC205Proxy.did   

**从你的Dex将交易记录存储到DRC205 Cansiter中**

- 查询存储费用

    调用DRC205Proxy的storeBatch/storeBytesBatch方法时，需要以Cycles支付费用，一次支付永久存储。通过`DRC205Proxy.fee()`方法可以查询每条记录的存储费用`fee`。

- 使用DRC205 TxnRecord类型存储记录

    如果你将交易记录转换成DRC205 TxnRecord类型，则可以调用`DRC205Proxy.storeBatch()`方法进行批量存储。
    ```
    storeBatch: (_txns: vec TxnRecord) -> ();
    ```
    注意：调用该方法需要添加 size(_txns) * fee Cycles作为费用。为了防止DRC205的访问过载，你需要间隔20秒才能调用一次。请在本地缓存记录，并间隔一段时间调用该方法进行批量存储。

- 使用自定义类型存储记录(不建议)

    如果你的交易记录使用自定义类型，需要先将记录转换成Bytes (vec nat8)格式，然后调用`DRC205Proxy.storeBytesBatch()`方法进行批量存储。
    ```
    storeBytesBatch: (_txns: vec record { Txid; vec nat8 }) -> ();
    ```
    注意：调用该方法需要添加 size(_txns) * fee Cycles作为费用。为了防止DRC205的访问过载，你需要间隔20秒才能调用一次。请在本地缓存记录，并间隔一段时间调用该方法进行批量存储。

**从DRC205 Cansiter中查询交易记录**

如果你在Dapp中需要查询Dex的交易记录，请参照下文`如何查询交易记录`部分。

## 3. 在Dex中为IChouse浏览器实现查询接口

```
/// returns DRC205Proxy canister-id
drc205_canisterId: () -> (principal) query;
/// returns events. Address (Text type) is Principal or AccountId. If Address is not specified means to query all latest transaction records.
drc205_events: (opt Address) -> (vec TxnRecord) query;
/// returns txn record. Query txn record in trading pair canister cache.
drc205_txn: (Txid) -> (opt TxnRecord) query;
```

## 4. 如何查询交易记录

无论你是Rust、Motoko、还是前端开发者，需要查询在DRC205中的交易记录，需要提供交易对appId (canister-id)和txid。无法遍历查询所有记录。
DRC205Proxy did: https://github.com/iclighthouse/DRC_standards/tree/main/DRC205/DRC205Proxy.did   
DRC205Bucket did: https://github.com/iclighthouse/DRC_standards/tree/main/DRC205/DRC205Bucket.did   

- Motoko开发者

    如果你是Motoko开发者，可以使用`DRC205 Module`的get/get2方法查询交易记录。

- 其他开发者

    **Step 1**. 通过DRC205Proxy查询交易记录存储所在的bucket canister-id

    调用`DRC205Proxy.location()`方法查询得到该记录存储所在的Bucket canister-id，如果返回`[]`表示记录不存在。
    注意：如果返回值是包含多个Bucket，则意味着交易记录可能存在于其中一个Bucket中，这是因为采用了BloomFilter技术而导致的情况。

    **Step 2**. 通过DRC205Bucket查询交易记录

    1) 如果这个交易对使用了DRC205 TxnRecord类型，根据上一步得到的Bucket canister-id调用`DRC205Bucket.txn()`、`DRC205Bucket.txnHistory()`、`DRC205Bucket.txnByIndex()`或`DRC205Bucket.txnByAccountId()`方法查询记录。

    2) 如果这个交易对使用了自定义类型，根据上一步得到的Bucket canister-id调用`DRC205Bucket.txnBytes()`或`DRC205Bucket.txnBytesHistory()`方法查询记录。

## DRC205标准规范

https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/DRC205-CN.md