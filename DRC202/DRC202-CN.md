***
DRC: 202  
Title: Token Transaction Records Storage Standard  
Author: Avida <avida.life@hotmail.com>, Simpson <icpstaking-wei@hotmail.com>  
Status: Draft  
Category: Token DRC  
Created: 2021-12-10
***

## 摘要

DRC202是一个可扩展的Token交易记录存储标准。支持多token存储，自动扩展创建存储容器（bucket），以及查询记录的自动路由。

## 解决什么问题

由于Token的Canister的存储容量有限（目前只有4G），因此需要开发一个可扩展的外部存储方案。

DRC202标准的存储机制是由一个入口合约Proxy和自动扩展的多个存储合约Bucket组成。根据实际的存储需求创建Bucket（当一个Bucket满了就创建一个新的Bucket），然后将交易记录压缩并存储在Bucket中。当你想查询一个代币交易记录时，你可以先从Proxy合约中查询记录存储的BucketId（使用BloomFilter技术进行路由，https://en.wikipedia.org/wiki/Bloom_filter ），然后再从指定的Bucket中查询交易记录。

![DRC202](202.jpg)

## 规范

**NOTES**:

- 以下规范使用Candid语法。
- `sid`是全局唯一的交易记录存储ID，由Proxy合约生成。
- `txid`是Token内唯一的交易记录ID，由Token合约生成。推荐生成txid的方法是：将token的canisterId、caller的accountId和caller的nonce（即txn索引）分别转换成[nat8]数组，并将它们连接起来作为`txInfo: [nat8]`。然后得到 "txid "值为 "00000000"(big-endian 4-bytes, `encode(caller.nonce)`)+"0000...00"(28-bytes, `sha224(txInfo)`)。

### Types (DID)

``` candid
type Token = principal;
type Txid = blob;
type Time = int;
type Bucket = principal;
type AccountId = blob;
type Sid = blob;
type Gas = variant {
   cycles: nat;
   noFee;
   token: nat;
};
type TxnRecord = record {
   caller: AccountId;
   gas: Gas;
   index: nat;
   msgCaller: opt principal;
   nonce: nat;
   timestamp: Time;
   transaction: Transaction;
   txid: Txid;
};
type Transaction = record {
   data: opt blob;
   from: AccountId;
   operation: Operation;
   to: AccountId;
   value: nat;
};
type Operation = variant {
   approve: record {allowance: nat;};
   executeTransfer: record { fallback: nat; lockedTxid: Txid; };
   lockTransfer: record { decider: AccountId; expiration: Time; locked: nat; };
   transfer: record {action: variant { burn; mint; send; };};
};
type TokenInfo = record {
   count: nat;
   lastIndex: nat;
   lastTxid: Txid;
};
type BucketInfo = record {
   count: nat;
   cycles: nat;
   heap: nat;
   memory: nat;
   stableMemory: nat32;
};
type ProxyActor = service {
   bucket: (Token, Txid, nat, opt nat8) -> (opt Bucket) query;
   bucketInfo: (opt Bucket) -> (Bucket, BucketInfo);
   fee: () -> (nat) query;
   generateTxid: (Token, AccountId, nat) -> (Txid) query;
   getLastTxns: () -> (vec record { nat; Token; nat; Txid; }) query;
   maxBucketMemory: () -> (nat) query;
   setFee: (nat) -> (bool);
   setMaxMemory: (nat) -> (bool);
   standard: () -> (text) query;
   stats: () -> (record {
       bucketCount: nat;
       errCount: nat;
       storeErrPool: nat;
       tokenCount: nat;
       txnCount: nat;
   }) query;
   store: (TxnRecord) -> ();
   storeBytes: (Txid, vec nat8) -> ();
   version: () -> (nat8) query;
};

type BucketActor = service {
   bucketInfo: () -> (BucketInfo) query;
   last: () -> (Sid, Time) query;
   txn: (Token, Txid) -> (opt record { TxnRecord; Time; }) query;
   txnBytes: (Token, Txid) -> (opt record { vec nat8; Time; }) query;
   txnBytes2: (Sid) -> (opt record { vec nat8; Time; }) query;
};
```

### DRC202.ProxyActor

ProxyActor是一个用于交易记录存储的代理合约，可以自动创建和管理Bucket合约。

#### standard

返回标准名称。   
OPTIONAL - 该方法可用于提高可用性，但该方法可能不存在。

``` candid
standard: () -> (text) query;
```

#### version

返回版本值。    
OPTIONAL - 该方法可用于提高可用性，但该方法可能不存在。

``` candid
version: () -> (nat8) query;
```

#### fee

返回存储一条交易记录所需支付的费用（cycles）。

``` candid
fee: () -> (cycles: nat) query;
```

#### store

存储一条交易记录`_txn`，其中`_txn.transaction.data`的数据长度最大允许64KB，超出部分会被截取。

``` candid
store: (_txn: TxnRecord) -> ();
```

#### storeBytes

以二进制数据格式存储一条交易记录`_data`, 允许的最大数据128KB。

``` candid
storeBytes: (_txid: Txid, _data: vec nat8) -> ();
```
#### getLastTxns

返回最新存储的交易记录。

``` candid
getLastTxns: () -> (vec record { index: nat; token: Token; indexInToken: nat; txid: Txid; }) query;
```

#### bucket

返回指定`_token`的交易记录`_txid`所在的bucket（默认`_step`为0）。由于使用BloomFilter作为路由，这个查询不一定准确。如果目标交易记录不在该bucket中，你可以按`step+1`重新查询bucket，直到返回null。

``` candid
bucket: (_token: Token, _txid: Txid, _step: nat, _version: opt nat8) -> (opt Bucket) query;
```

#### generateTxid

根据给定的`_token`, `_caller`, `_nonce`值生成txid。  
OPTIONAL - 该方法可用于提高可用性，但该方法可能不存在。

``` candid
generateTxid: (_token: Token, _caller: AccountId, _nonce: nat) -> (Txid) query;
```

#### stats

返回统计数据。  
OPTIONAL - 该方法可用于提高可用性，但该方法可能不存在。

``` candid
stats: () -> (record { bucketCount: nat; errCount: nat; storeErrPool: nat; tokenCount: nat; txnCount: nat; }) query;
```

#### bucketInfo

返回关于`_bucket`的信息。如果没有指定`_bucket`，则返回当前bucket的信息。   
OPTIONAL - 该方法可用于提高可用性，但该方法可能不存在。

``` candid
bucketInfo: (_bucket: opt Bucket) -> (Bucket, BucketInfo);
```
#### maxBucketMemory

返回已设置的每个bucket的最大允许存储容量。   
OPTIONAL - 该方法可用于提高可用性，但该方法可能不存在。

``` candid
maxBucketMemory: () -> (nat) query;
```

#### setMaxMemory

设置每个bucket的最大允许存储容量`_memory`。 
OPTIONAL - 该方法可用于提高可用性，但该方法可能不存在。

``` candid
setMaxMemory: (_memory: nat) -> (bool);
```

#### setFee

设置每条交易记录存储需要支付的cycles金额`_fee`。   
OPTIONAL - 该方法可用于提高可用性，但该方法可能不存在。

``` candid
setFee: (_fee: nat) -> (bool);
```


### DRC202.BucketActor

BucketActor用于存储交易记录数据并实现公共查询接口。

#### txn

返回指定`_token`和`_txid`的交易记录。

``` candid
txn: (_token: Token, _txid: Txid) -> (opt record { TxnRecord; Time; }) query;
```

#### txnBytes

返回指定`_token`和`_txid`的交易记录的二进制数据。

``` candid
txnBytes: (_token: Token, _txid: Txid) -> (opt record { vec nat8; Time; }) query;
```

#### bucketInfo 

返回关于当前bucket的信息。    
OPTIONAL - 这个方法可以用来提高可用性，但该方法可能不存在。

``` candid
bucketInfo: () -> (BucketInfo) query;
```

#### last

返回最后存储记录的sid和时间戳。   
OPTIONAL - 这个方法可以用来提高可用性，但该方法可能不存在。

``` candid
last: () -> (Sid, Time) query;
```

#### txnBytes2

返回指定`_sid`的交易记录的二进制数据。     
OPTIONAL - 这个方法可以用来提高可用性，但该方法可能不存在。

``` candid
txnBytes2: (_sid: Sid) -> (opt record { vec nat8; Time; }) query;
```


## 实例

不同的团队正在编写不同的实施方案。

#### Example implementations

- [ICLighthouse](https://github.com/iclighthouse/DRC_standards/tree/main/DRC202/examples/IClighthouse)
    ICTokens DRC202: y5a36-liaaa-aaaak-aacqa-cai
