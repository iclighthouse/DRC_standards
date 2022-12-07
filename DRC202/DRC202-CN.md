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

![DRC202](202.jpg)

## 解决什么问题

由于Token的Canister的存储容量有限，因此需要开发一个可扩展的外部存储方案。

DRC202标准包含三部分：

* Token交易记录数据结构（TxnRecord）：定义了一个通用型数据结构，兼顾数据透明和隐私保护。

* 可扩展性存储接口规范：可扩展存储机制是由一个入口合约Proxy和自动扩展的多个存储合约Bucket组成。根据实际的存储需求创建Bucket（当一个Bucket满了就创建一个新的Bucket），然后将交易记录压缩并存储在Bucket中。当你想查询一个代币交易记录时，你可以先从Proxy合约中查询记录存储的BucketId（使用BloomFilter技术进行路由，https://en.wikipedia.org/wiki/Bloom_filter ），然后再从指定的Bucket中查询交易记录。

* 应用开发指南（Motoko Module）：建议Dex开发者采用的交易记录处理规范，采取“当前Canister缓存近期记录+外部Canister持久化存储历史记录”的模式，并提供查询接口。

## 开发指南

DRC202Proxy Canister-id: y5a36-liaaa-aaaak-aacqa-cai  
ICHouse浏览器: https://637g5-siaaa-aaaaj-aasja-cai.raw.ic0.app/tokens

DRC202Proxy Canister-id(测试): iq2ev-rqaaa-aaaak-aagba-cai  
ICHouse浏览器(测试): https://637g5-siaaa-aaaaj-aasja-cai.raw.ic0.app/TokensTest

关于Txid：txid是blob类型，属于每条交易记录的key。如果你的txid是nat类型或其他类型，需转换成blob类型。

### 1. Motoko开发者开发一个Token

如果你是一个Motoko开发者，正在开发一个Token Canister，例如DRC20、DIP20、ICRC1标准的代币，你可以使用`DRC202 Module`将DRC202整合到你的Token中，例子：https://github.com/iclighthouse/DRC_standards/blob/main/DRC202/examples/ICLighthouse/Example/Example.mo   

如果你正在用Motoko开发其他Dapp，只需要查询交易记录，请参照下文`如何查询交易记录`部分。

### 2. Rust开发者开发一个Token

如果你是一个Rust开发者，正在开发一个Token Canister，例如DRC20、DIP20、ICRC1标准的代币，你可以调用DRC202Proxy和DRC202Bucket的API来实现。  
DRC202Proxy did: https://github.com/iclighthouse/DRC_standards/tree/main/DRC202/DRC202Proxy.did   

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

### 3. 在Token中为IChouse浏览器实现查询接口

```
/// returns DRC202Proxy canister-id
drc202_canisterId: () -> (principal) query;
/// returns events. Address (Text type) is Principal or AccountId. If Address is not specified means to query all latest transaction records.
drc202_events: (opt Address) -> (vec TxnRecord) query;
/// returns txn record. Query txn record in token canister cache.
drc202_txn: (Txid) -> (opt TxnRecord) query;
```

### 4. 如何查询交易记录

无论你是Rust、Motoko、还是前端开发者，需要查询在DRC202中的交易记录，需要提供token的canister-id和txid。无法遍历查询所有记录。
DRC202Proxy did: https://github.com/iclighthouse/DRC_standards/tree/main/DRC202/DRC202Proxy.did   
DRC202Bucket did: https://github.com/iclighthouse/DRC_standards/tree/main/DRC202/DRC202Bucket.did   

- Motoko开发者

    如果你是Motoko开发者，可以使用`DRC202 Module`的get/get2方法查询交易记录。

- 其他开发者

    查询步骤：

    **Step 1**. 通过DRC202Proxy查询交易记录存储所在的bucket canister-id

    指定token canister-id和交易记录的txid，调用`DRC202Proxy.bucket()`方法查询得到该记录存储所在的Bucket canister-id，如果返回`null`表示记录不存在。
    注意：由于使用了BloomFilter技术，在极小概率（约1‰）情形下，记录并不存在于返回的Bucket中，这需要你`_step`参数+1后继续调用`DRC202Proxy.bucket()`方法查询。如果返回`null`表示记录一定不存在。

    **Step 2**. 通过DRC202Bucket查询交易记录

    1) 如果这个token使用了DRC202 TxnRecord类型，根据上一步得到的Bucket canister-id调用`DRC202Bucket.txn()`或`DRC202Bucket.txnHistory()`方法查询记录。如果返回`null`，则记录有极小可能存在于其他bucket中，你可以让`_step`参数+1后继续回到上一步进行操作。

    2) 如果这个token使用了自定义类型，根据上一步得到的Bucket canister-id调用`DRC202Bucket.txnBytes()`或`DRC202Bucket.txnBytesHistory()`方法查询记录。如果返回`null`，则记录有极小可能存在于其他bucket中，你可以让`_step`参数+1后继续回到上一步进行操作。



## 规范

**NOTES**:

- 以下规范使用Candid语法。
- `Sid`是全局唯一的交易记录存储ID，32字节的Blob类型，由Proxy合约生成。
- `Txid`是Token内唯一的交易记录ID，必须是32字节的Blob类型，由Token合约生成。推荐生成txid的方法是：[DRC202Types.generateTxid(_token: Principal, _caller: AccountId, _nonce: Nat)](https://github.com/iclighthouse/DRC_standards/blob/main/DRC202/examples/ICLighthouse/Example/lib/DRC202Types.mo)。
- `AccountId`是Token用户的身份ID，必须是32字节的Blob类型，由Token合约生成。如果使用Principal、[Nat8]等数据类型，则需要转换成32字节的Blob。

### Types (DID)

``` candid
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
type AccountId = blob;
type Txid = blob;
type TokenInfo = record {count: nat; lastIndex: nat; lastTxid: Txid; };
type Token = principal;
type Time = int;
type Gas = variant { cycles: nat; noFee; token: nat;};
type BucketInfo = record {
   count: nat;
   cycles: nat;
   heap: nat;
   memory: nat;
   stableMemory: nat32;
};
type Bucket = principal;
```

Types in Motoko:  https://github.com/iclighthouse/DRC_standards/blob/main/DRC202/examples/ICLighthouse/Example/lib/DRC202Types.mo

字段解释见开发示例批注：https://github.com/iclighthouse/DRC_standards/blob/main/DRC202/examples/ICLighthouse/Example/Example.mo

### 通用存储接口（Proxy和Bucket）

#### 1. DRC202Proxy

DRC202Proxy是一个用于交易记录存储的代理合约，可以自动创建和管理Bucket合约。

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

返回存储一条交易记录所需支付的费用（cycles），一次付费永久存储。

``` candid
fee: () -> (cycles: nat) query;
```

#### store

(@deprecated: 该方法将被弃用)  
存储一条交易记录`_txn`，其中`_txn.transaction.data`的数据长度最大允许64KB，超出部分会被截取。调用该方法时需要添加cycles作为费用（通过`fee()`方法查询）。

``` candid
store: (_txn: TxnRecord) -> ();
```
#### storeBatch

批量存储交易记录, 允许每间隔20秒以上存储一次. 调用该方法时需要添加cycles作为费用（通过`fee()`方法查询），批量存储n条消息需要支付n*fee Cycles。

``` candid
storeBatch: (_txns: vec TxnRecord) -> ();
```

#### storeBytes

(@deprecated: 该方法将被弃用)  
以二进制数据格式存储一条交易记录`_data`, 允许的最大数据128KB。调用该方法时需要添加cycles作为费用（通过`fee()`方法查询）。

``` candid
storeBytes: (_txid: Txid, _data: vec nat8) -> ();
```
#### storeBytesBatch

批量存储二进制记录, 允许每间隔20秒以上存储一次. 调用该方法时需要添加cycles作为费用（通过`fee()`方法查询），批量存储n条消息需要支付n*fee Cycles。

``` candid
storeBytesBatch: (_txns: vec record { Txid; vec nat8 }) -> ();
```

#### getLastTxns

返回最新存储的交易记录。

``` candid
getLastTxns: () -> (vec record { index: nat; token: Token; indexInToken: nat; txid: Txid; }) query;
```

#### bucket

返回指定`_token`的交易记录`_txid`所在的bucket（默认`_step`为0）。由于使用BloomFilter作为路由，这个查询不一定准确。如果目标交易记录不在该bucket中，你可以按`step+1`重新查询bucket，直到返回null (表示你要查询的记录不存在)。

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

#### setStd

设置`_token`实现的标准名称，如"dip20; drc20", 小写字母，多个标准名称用"; "分割，遵循[CTSNC](https://github.com/iclighthouse/DRC_standards/tree/main/CTSNC)规则。
``` candid
setStd(_stds: Text) : async ()
```

#### tokenInfo

返回关于`_token`的标准名称及统计数据。   
OPTIONAL - 该方法可用于提高可用性，但该方法可能不存在。

``` candid
tokenInfo : (_token: Token) -> (opt text, opt TokenInfo) query;
```


#### 2. DRC202Bucket

DRC202Bucket用于存储交易记录数据并实现公共查询接口。

#### txn

返回指定`_token`和`_txid`的交易记录。

``` candid
txn: (_token: Token, _txid: Txid) -> (opt record { TxnRecord; Time; }) query;
```

#### txnHistory

返回指定`_token`和`_txid`的交易记录，返回数组包含所有修改的历史记录。

``` candid
txnHistory: (_token: Token, _txid: Txid) -> (vec record { TxnRecord; Time; }) query;
```

#### txnBytes

返回指定`_token`和`_txid`的交易记录的二进制数据。

``` candid
txnBytes: (_token: Token, _txid: Txid) -> (opt record { vec nat8; Time; }) query;
```

#### txnBytesHistory

返回指定`_token`和`_txid`的交易记录的二进制数据，返回数组包含所有修改的历史记录。

``` candid
txnBytesHistory: (_token: Token, _txid: Txid) -> (vec record { vec nat8; Time; }) query;
```

#### txnBytes2

返回指定`_sid`的交易记录的二进制数据。     
OPTIONAL - 这个方法可以用来提高可用性，但该方法可能不存在。

``` candid
txnBytes2: (_sid: Sid) -> (opt record { vec nat8; Time; }) query;
```

#### txnHash

计算指定交易记录的Hash值。     
OPTIONAL - 这个方法可以用来提高可用性，但该方法可能不存在。
``` candid
txnHash: (_token: Token, _txid: Txid, _index: nat) -> (opt text) query;
```

#### txnBytesHash

计算指定Bytes数据记录的Hash值。     
OPTIONAL - 这个方法可以用来提高可用性，但该方法可能不存在。
``` candid
txnBytesHash: (_token: Token, _txid: Txid, _index: nat) -> (opt text) query;
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

### 开发包(Motoko Module)及指南

#### DRC202 Module

import DRC202 "lib/DRC202";

#### drc202

返回DRC202Proxy Canister对象。  

``` candid
drc202: () -> DRC202Types.Self;
```

#### drc202CanisterId

返回DRC202Proxy canister-id。 

``` candid
drc202CanisterId: () -> principal;
```

#### config

配置EN_DEBUG、MAX_CACHE_TIME、MAX_CACHE_NUMBER_PER、MAX_STORAGE_TRIES等属性。 

``` candid
config: (_config: Config) -> bool;
```

#### getConfig

返回配置信息。 

``` candid
getConfig: () -> Setting;
```

#### generateTxid

生成txid。 

``` candid
generateTxid : (_app: principal, _caller: AccountId, _nonce: nat) -> Txid;
```

#### pushLastTxn

保存交易相关用户的txid记录。 

``` candid
pushLastTxn : (_as: vec AccountId, _txid: Txid) -> ();
```

#### inLockedTxns

判断`_txid`是否在指定账户的已锁定交易列表中。 

``` candid
inLockedTxns : (_txid: Txid, _a: AccountId) -> bool;
```

#### getLockedTxns

返回指定账户`_account`的已锁定交易txid列表。 

``` candid
getLockedTxns : (_account: AccountId) -> vec Txid;
```

#### appendLockedTxn

保存账户`_account`的已锁定交易的txid。 

``` candid
appendLockedTxn : (_account: AccountId, _txid: Txid) -> ();
```

#### dropLockedTxn

从列表中删除账户`_account`的已锁定交易的txid。 

``` candid
dropLockedTxn : (_account: AccountId, _txid: Txid) -> ();
```

#### get

从当前canister缓存查找指定`_txid`的记录，不存在则返回null。 

``` candid
get : (_txid: Txid) -> opt TxnRecord;
```

#### put

缓存一条记录。 

``` candid
put : (_txn: TxnRecord) -> ();
```

#### store

异步存储记录到扩展Canister中。 

``` candid
store : () -> ();
```
#### get2

从当前canister缓存查找指定`_txid`的记录，不存在则从外部扩展的DRC202 canister中查找记录。这是一个异步方法。  

``` candid
get : (_txid: Txid) -> opt TxnRecord;
```

#### getLastTxns

返回用户`_account`最近发生的记录txid列表。  

``` candid
getLastTxns : (_account: opt AccountId) -> vec Txid;
```

#### getEvents

返回用户`_account`最近发生的记录详情列表。  

``` candid
getEvents : (_account: opt AccountId) -> vec TxnRecord;
```

#### getData

返回drc202对象的数据，仅用于升级时的数据备份。  

``` candid
getData : () -> DataTemp;
```

#### setData

设置drc202对象的数据，仅用于升级。  

``` candid
setData : (_data: DataTemp) -> ();
```


#### 开发指南

Motoko开发示例：https://github.com/iclighthouse/DRC_standards/blob/main/DRC202/examples/ICLighthouse/Example/Example.mo

**Step1** 引入Module文件

将https://github.com/iclighthouse/DRC_standards/blob/main/DRC202/examples/ICLighthouse/Example/lib/ 文件导入项目所在目录。在你的代码中引入：
``` motoko
import Array "mo:base/Array";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import DRC202 "lib/DRC202";
``` 

**Step2** 编写代码

创建私有全局变量，如：
``` motoko
// Set EN_DEBUG=false in the production environment.
private var drc202 = DRC202.DRC202({EN_DEBUG = true; MAX_CACHE_TIME = 3 * 30 * 24 * 3600 * 1000000000; MAX_CACHE_NUMBER_PER = 100; MAX_STORAGE_TRIES = 2; });
``` 

生成Txid和TxnRecord，执行drc202.put(txn)把记录存入缓存，执行drc202.store()把记录存入DRC202存储容器，如：
``` motoko
    public shared(msg) func test(_n: Nat) : async DRC202.Txid{
        let caller = drc202.getAccountId(msg.caller, null);
        let from = drc202.getAccountId(msg.caller, null);
        let to = drc202.getAccountId(Principal.fromText("aaaaa-aa"), null);
        let txid = drc202.generateTxid(Principal.fromActor(this), caller, _n);
        var txn: DRC202.TxnRecord = {
            txid = txid; // Transaction id
            transaction = {
                from = from; // from
                to = to; //to
                value = 100000000; // amount
                operation = #transfer({ action = #send }); // DRC202.Operation;
                data = null; // attached data(Blob)
            };
            gas = #token(10000); // gas
            msgCaller = null;  // Caller principal
            caller = caller; // Caller account (Blob)
            index = _n; // Global Index
            nonce = _n; // Nonce of user
            timestamp = Time.now(); // Timestamp (nanoseconds).
        };
        drc202.put(txn); // Put txn to the current canister cache.
        drc202.pushLastTxn([from, to], txid); // Put txid to LastTxn cache.
        let store = /*await*/ drc202.store(); // Store in the DRC202 scalable bucket.
        return txid;
    };
``` 

**Step3** 编写查询和升级函数

建议在你的dapp中实现以下方法：（方便ic.house浏览器查询记录）

* drc202_getConfig : () -> DRC202.Setting query
* drc202_canisterId : () -> principal query
* drc202_events : (_account: opt DRC202.Address) -> vec DRC202.TxnRecord query
* drc202_txn : (_txid: DRC202.Txid) -> opt DRC202.TxnRecord query
* drc202_txn2 : (_txid: DRC202.Txid) -> opt DRC202.TxnRecord

如：
``` motoko
    public query func drc202_getConfig() : async DRC202.Setting{
        return drc202.getConfig();
    };
    public query func drc202_canisterId() : async Principal{
        return drc202.drc202CanisterId();
    };
    /// config
    // public shared(msg) func drc202_config(config: DRC202.Config) : async Bool{ 
    //     assert(msg.caller == owner);
    //     return drc202.config(config);
    // };
    /// returns events
    public query func drc202_events(_account: ?DRC202.Address) : async [DRC202.TxnRecord]{
        switch(_account){
            case(?(account)){ return drc202.getEvents(?drc202.getAccountId(Principal.fromText(account), null)); };
            case(_){return drc202.getEvents(null);}
        };
    };
    /// returns txn record. It's an query method that will try to find txn record in token canister cache.
    public query func drc202_txn(_txid: DRC202.Txid) : async (txn: ?DRC202.TxnRecord){
        return drc202.get(_txid);
    };
    /// returns txn record. It's an update method that will try to find txn record in the DRC202 canister if the record does not exist in this canister.
    public shared func drc202_txn2(_txid: DRC202.Txid) : async (txn: ?DRC202.TxnRecord){
        return await drc202.get2(Principal.fromActor(this), _txid);
    };
    // upgrade
    private stable var __drc202Data: [DRC202.DataTemp] = [];
    system func preupgrade() {
        __drc202Data := Array.append(__drc202Data, [drc202.getData()]);
    };
    system func postupgrade() {
        if (__drc202Data.size() > 0){
            drc202.setData(__drc202Data[0]);
            __drc202Data := [];
        };
    };
```

## 实例

#### Example implementations

- Storage Canister: https://github.com/iclighthouse/DRC_standards/tree/main/DRC202/examples/ICLighthouse  
    ICTokens DRC202 (Main): y5a36-liaaa-aaaak-aacqa-cai  
    ICTokens DRC202 (Test): iq2ev-rqaaa-aaaak-aagba-cai  
    Notes: Use y5a36-liaaa-aaaak-aacqa-cai to store token records that can be queried through the ICHouse blockchain explorer (http://ic.house).

- Motoko Module: https://github.com/iclighthouse/DRC_standards/blob/main/DRC202/examples/ICLighthouse/Example/lib/DRC202.mo 

- Development Example: https://github.com/iclighthouse/DRC_standards/blob/main/DRC202/examples/ICLighthouse/Example/Example.mo  