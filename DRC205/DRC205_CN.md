***
DRC: 205  
Title: Swap Transaction Records Storage Standard   
Author: Avida <avida.life@hotmail.com>, Simpson <icpstaking-wei@hotmail.com>  
Status: Draft  
Category: Swap DRC  
Created: 2021-12-10
***

## 摘要

DRC205是一个可扩展的Swap交易记录存储及应用开发标准。支持多交易所存储，自动扩展创建存储容器（bucket），以及查询时支持自动路由。

![DRC205](drc205.jpg)

## 解决什么问题

Dex的交易记录需要被持久保存并且保持公开透明，因此需要开发一个可扩展的外部存储方案，交易记录可公开查询。

DRC205标准包含三部分：

* Swap交易记录数据结构（TxnRecord）：定义了一个通用型数据结构，适应AMM和OrderBook模式的Dex，兼顾数据透明和隐私保护。

* 可扩展性存储接口规范：可扩展存储机制是由一个入口合约Proxy和自动扩展的多个存储合约Bucket组成。根据实际的存储需求创建Bucket（当一个Bucket满了就创建一个新的Bucket），然后将交易记录压缩并存储在Bucket中。当你想查询一个代币交易记录时，你可以先从Proxy合约中查询记录存储的BucketId（使用BloomFilter技术进行路由，https://en.wikipedia.org/wiki/Bloom_filter ），然后再从指定的Bucket中查询交易记录。

* 应用开发指南（Motoko Module）：建议Dex开发者采用的交易记录处理规范，采取“当前Canister缓存近期记录+外部Canister持久化存储历史记录”的模式，并提供查询接口。

## 开发指南

DRC205Proxy Canister-id: 6ylab-kiaaa-aaaak-aacga-cai  
ICHouse浏览器: https://637g5-siaaa-aaaaj-aasja-cai.raw.ic0.app/swaps

DRC205Proxy Canister-id(测试): ix3cb-4iaaa-aaaak-aagbq-cai  
ICHouse浏览器(测试): https://637g5-siaaa-aaaaj-aasja-cai.raw.ic0.app/SwapsTest

关于Txid：txid是blob类型，属于每条交易记录的key。如果你的txid是nat类型或其他类型，需转换成blob类型。

### 1. Motoko开发者开发一个Dex

如果你是一个Motoko开发者，正在开发一个Dex，无论是AMM还是OrderBook，你可以使用`DRC205 Module`将DRC205整合到你的Dex中，例子：https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/examples/ICLighthouse/Example/Example.mo  

如果你正在用Motoko开发其他Dapp，只需要查询交易记录，请参照下文`如何查询交易记录`部分。

### 2. Rust开发者开发一个Dex

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

### 3. 在Dex中为IChouse浏览器实现查询接口

```
/// returns DRC205Proxy canister-id
drc205_canisterId: () -> (principal) query;
/// returns events. Address (Text type) is Principal or AccountId. If Address is not specified means to query all latest transaction records.
drc205_events: (opt Address) -> (vec TxnRecord) query;
/// returns txn record. Query txn record in trading pair canister cache.
drc205_txn: (Txid) -> (opt TxnRecord) query;
```

### 4. 如何查询交易记录

无论你是Rust、Motoko、还是前端开发者，需要查询在DRC205中的交易记录，需要提供交易对appId (canister-id)和txid。无法遍历查询所有记录。
DRC205Proxy did: https://github.com/iclighthouse/DRC_standards/tree/main/DRC205/DRC205Proxy.did   
DRC205Bucket did: https://github.com/iclighthouse/DRC_standards/tree/main/DRC205/DRC205Bucket.did   

- Motoko开发者

    如果你是Motoko开发者，可以使用`DRC205 Module`的get/get2方法查询交易记录。

- 其他开发者

    查询步骤：

    **Step 1**. 通过DRC205Proxy查询交易记录存储所在的bucket canister-id

    指定交易对appId和交易记录的txid，调用`DRC205Proxy.bucket()`方法查询得到该记录存储所在的Bucket canister-id，如果返回`null`表示记录不存在。
    注意：由于使用了BloomFilter技术，在极小概率（约1‰）情形下，记录并不存在于返回的Bucket中，这需要你`_step`参数+1后继续调用`DRC205Proxy.bucket()`方法查询。如果返回`null`表示记录一定不存在。

    **Step 2**. 通过DRC205Bucket查询交易记录

    1) 如果这个交易对使用了DRC205 TxnRecord类型，根据上一步得到的Bucket canister-id调用`DRC205Bucket.txn()`或`DRC205Bucket.txnHistory()`方法查询记录。如果返回`null`，则记录有极小可能存在于其他bucket中，你可以让`_step`参数+1后继续回到上一步进行操作。

    2) 如果这个交易对使用了自定义类型，根据上一步得到的Bucket canister-id调用`DRC205Bucket.txnBytes()`或`DRC205Bucket.txnBytesHistory()`方法查询记录。如果返回`null`，则记录有极小可能存在于其他bucket中，你可以让`_step`参数+1后继续回到上一步进行操作。


## 规范

**NOTES**:

- 以下规范使用candid语法。
- `Sid`是全局唯一的交易记录存储ID，Blob类型，32字节，由Proxy合约生成。
- `Txid`是Dex内唯一的交易记录ID，Blob类型，必须32字节，由Dex合约生成。推荐生成txid的方法是：[DRC205Types.generateTxid(_app: Principal, _caller: AccountId, _nonce: Nat)](https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/examples/ICLighthouse/Example/lib/DRC205Types.mo)。
- `AccountId`是Swap用户的身份ID，Blob类型，必须32字节，由Dex合约生成。如果使用Principal、[Nat8]等数据类型，则需要转换成32字节Blob。

### Transaction Record Types (TxnRecord)

这是一个建议数据结构，如果使用自定义数据结构，可以使用storeBytes和txnBytes方法满足兼容性需求。

``` candid
type Status = variant { Failed; Pending; Completed; PartiallyCompletedAndCancelled; Cancelled; };
type TxnRecord = record {
   account: AccountId;
   caller: AccountId;
   cyclesWallet: opt CyclesWallet;
   data: opt Data;
   details: vec record { counterparty: Txid; token0Value: BalanceChange; token1Value: BalanceChange; };
   fee: record { token0Fee: int; token1Fee: int; };
   index: nat;
   msgCaller: opt principal;
   nonce: Nonce;
   operation: OperationType;
   order: record { token0Value: opt BalanceChange; token1Value: opt BalanceChange; };
   orderMode: variant { AMM; OrderBook; };
   orderType: opt variant { LMT; FOK; FAK; MKT; };
   shares: ShareChange;
   status: Status;
   time: Time;
   token0: TokenType;
   token0Value: BalanceChange;
   token1: TokenType;
   token1Value: BalanceChange;
   txid: Txid;
 };
type Txid = blob;
type TokenType = variant { Cycles; Icp; Token: principal; };
type Time = int;
type Shares = nat;
type ShareChange = variant { Burn: Shares; Mint: Shares; NoChange; };
type OperationType = variant { AddLiquidity; Claim; RemoveLiquidity; Swap; };
type Nonce = nat;
type Data = blob;
type CyclesWallet = principal;
type BucketInfo = record { count: nat;cycles: nat; heap: nat; memory: nat; stableMemory: nat32; };
type Bucket = principal;
type BalanceChange = variant { CreditRecord: nat; DebitRecord: nat; NoChange; };
type AppInfo = record { count: nat; lastIndex: nat; lastTxid: Txid; };
type AppId = principal;
type AccountId = blob;
```

Types in Motoko:  https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/examples/ICLighthouse/Example/lib/DRC205Types.mo

字段解释见开发示例批注：https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/examples/ICLighthouse/Example/Example.mo

### 通用存储接口（Proxy和Bucket）

#### 1. DRC205Proxy

DRC205Proxy是一个用于交易记录存储的代理合约，可以自动创建和管理Bucket合约。

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
fee: () -> (_cycles: nat) query;
```

#### store

(@deprecated: 该方法将被弃用)  
存储一条交易记录`_txn`，其中`_txn.data`的数据长度最大允许64KB，超出部分会被截取。调用该方法时需要添加cycles作为费用（通过`fee()`方法查询）。

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
getLastTxns: () -> (vec record { index: nat; app: AppId; indexInApp: nat; txid: Txid; }) query;
```

#### bucket

返回指定`_app`的交易记录`_txid`所在的bucket（默认`_step`为0）。由于使用BloomFilter作为路由，这个查询不一定准确。如果目标交易记录不在该bucket中，你可以按`step+1`重新查询bucket，直到返回null (表示你要查询的记录不存在)。

``` candid
bucket: (_app: AppId, _txid: Txid, _step: nat, _version: opt nat8) -> (opt Bucket) query;
```

#### generateTxid

根据给定的`_app`, `_caller`, `_nonce`值生成txid。  
OPTIONAL - 该方法可用于提高可用性，但该方法可能不存在。

``` candid
generateTxid: (_app: AppId, _caller: AccountId, _nonce: nat) -> (Txid) query;
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

#### 2. DRC205Bucket

DRC205Bucket用于存储交易记录数据，并实现公共查询接口。

#### txn

返回指定`_app`和`_txid`的交易记录。

``` candid
txn: (_app: AppId, _txid: Txid) -> (opt record { TxnRecord; Time; }) query;
```

#### txnHistory

返回指定`_app`和`_txid`的交易记录，返回数组包含所有修改的历史记录。

``` candid
txnHistory: (_app: AppId, _txid: Txid) -> (vec record { TxnRecord; Time; }) query;
```

#### txnBytes

返回指定`_app`和`_txid`的交易记录的二进制数据。

``` candid
txnBytes: (_app: AppId, _txid: Txid) -> (opt record { vec nat8; Time; }) query;
```

#### txnBytesHistory

返回指定`_app`和`_txid`的交易记录的二进制数据，返回数组包含所有修改的历史记录。

``` candid
txnBytesHistory: (_app: AppId, _txid: Txid) -> (vec record { vec nat8; Time; }) query;
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
txnHash: (_app: AppId, _txid: Txid, _index: nat) -> (opt text) query;
```

#### txnBytesHash

计算指定Bytes数据记录的Hash值。     
OPTIONAL - 这个方法可以用来提高可用性，但该方法可能不存在。
``` candid
txnBytesHash: (_app: AppId, _txid: Txid, _index: nat) -> (opt text) query;
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

#### DRC205 Module

import DRC205 "lib/DRC205";

#### drc205

返回DRC205Proxy Canister对象。  

``` candid
drc205: () -> DRC205Types.Self;
```

#### drc205CanisterId

返回DRC205Proxy canister-id。 

``` candid
drc205CanisterId: () -> principal;
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

异步存储记录到可扩展DRC205的Bucket中。

``` candid
store : () -> ();
```

#### get2

从当前canister缓存查找指定`_txid`的记录，不存在则从外部扩展canister中查找记录。这是一个异步方法。  

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

返回drc205对象的数据，仅用于升级时的数据备份。  

``` candid
getData : () -> DataTemp;
```

#### setData

设置drc205对象的数据，仅用于升级。  

``` candid
setData : (_data: DataTemp) -> ();
```


#### 开发指南

Motoko开发示例：https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/examples/ICLighthouse/Example/Example.mo

**Step1** 引入Module文件

将https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/examples/ICLighthouse/Example/lib/文件导入项目所在目录。在你的代码文件中引入：
``` motoko
import Array "mo:base/Array";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import DRC205 "lib/DRC205";
``` 

**Step2** 编写代码

创建私有全局变量，如：
``` motoko
// Set EN_DEBUG=false in the production environment.
private var drc205 = DRC205.DRC205({EN_DEBUG = true; MAX_CACHE_TIME = 3 * 30 * 24 * 3600 * 1000000000; MAX_CACHE_NUMBER_PER = 100; MAX_STORAGE_TRIES = 2; });
``` 

生成Txid和TxnRecord，执行drc205.put(txn)把记录存入缓存，执行drc205.store()把记录存入DRC205存储容器，如：
``` motoko
    public shared(msg) func test(_n: Nat) : async DRC205.Txid{
        let caller = drc205.getAccountId(msg.caller, null);
        let txid = drc205.generateTxid(Principal.fromActor(this), caller, _n);
        var txn: DRC205.TxnRecord = {
            txid = txid; // Transaction id
            msgCaller = null; // Caller principal
            caller = caller; // Caller account (Blob)
            operation = #Swap; // { #AddLiquidity; #RemoveLiquidity; #Claim; #Swap; }
            account = caller; // Swap user account (Blob)
            cyclesWallet = null; // Cycles wallet principal, used only for one of trading pair tokens is cycles.
            token0 = #Token(Principal.fromText("ueghb-uqaaa-aaaak-aaioa-cai")); // Trading pair { #Cycles; #Icp; #Token: Principal; }
            token1 = #Token(Principal.fromText("udhbv-ziaaa-aaaak-aaioq-cai")); // Trading pair { #Cycles; #Icp; #Token: Principal; }
            token0Value = #DebitRecord(10000000000); // #DebitRecord indicates the amount of token0 spent for swapping.
            token1Value = #CreditRecord(20000000000); // #CreditRecord indicates the amount of token1 received from swapping.
            fee = {token0Fee = 0; token1Fee = 20000; }; // fee
            shares = #NoChange; // Liquidity shares change of user. { #Mint: Nat; #Burn: Nat; #NoChange; }
            time = Time.now(); // Timestamp (nanoseconds).
            index = _n;  // Global Index
            nonce = _n;  // Nonce of user
            orderType = #AMM; // Order Type  { #AMM; #OrderBook; }
            details = []; // Counterparty order list, for orderbook mode only.
            data = null; // Attached data (Blob)
        };
        drc205.put(txn); // Put txn to the current canister cache.
        let store = /*await*/ drc205.store(); // Store in the DRC205 scalable bucket.
        return txid;
    };
``` 

**Step3** 编写查询和升级函数

建议在你的dapp中实现以下方法：（方便ic.house浏览器查询记录）

* drc205_getConfig : () -> DRC205.Setting query
* drc205_canisterId : () -> principal query
* drc205_dexInfo : () -> async DRC205.DexInfo query
* drc205_events : (_account: opt DRC205.Address) -> vec DRC205.TxnRecord query
* drc205_txn : (_txid: DRC205.Txid) -> opt DRC205.TxnRecord query
* drc205_txn2 : (_txid: DRC205.Txid) -> opt DRC205.TxnRecord

如：
``` motoko
    /// returns setting
    public query func drc205_getConfig() : async DRC205.Setting{
        return drc205.getConfig();
    };
    public query func drc205_canisterId() : async Principal{
        return drc205.drc205CanisterId();
    };
    public query func drc205_dexInfo() : async DRC205.DexInfo{
        return {
            canisterId = Principal.fromActor(this);
            dexName = "icswap"; // your dex name
            pairName = "TEKENA/TOKENB"; // pair name
            token0 = (#Token(Principal.fromText("ueghb-uqaaa-aaaak-aaioa-cai")), #drc20); // token0 info
            token1 = (#Token(Principal.fromText("udhbv-ziaaa-aaaak-aaioq-cai")), #dip20); // token1 info
            feeRate = 0.005; // fee rate
        };
    };
    /// config
    // public shared(msg) func drc205_config(config: DRC205.Config) : async Bool{ 
    //     assert(msg.caller == owner);
    //     return drc205.config(config);
    // };
    /// returns events
    public query func drc205_events(_account: ?DRC205.Address) : async [DRC205.TxnRecord]{
        switch(_account){
            case(?(account)){ return drc205.getEvents(?drc205.getAccountId(Principal.fromText(account), null)); };
            case(_){return drc205.getEvents(null);}
        };
    };
    /// returns txn record. This is a query method that looks for record from this canister cache.
    public query func drc205_txn(_txid: DRC205.Txid) : async (txn: ?DRC205.TxnRecord){
        return drc205.get(_txid);
    };
    /// returns txn record. It's an update method that will try to find txn record in the DRC205 canister if the record does not exist in this canister.
    public shared func drc205_txn2(_txid: DRC205.Txid) : async (txn: ?DRC205.TxnRecord){
        return await drc205.get2(Principal.fromActor(this), _txid);
    };
    // upgrade
    private stable var __drc205Data: [DRC205.DataTemp] = [];
    system func preupgrade() {
        __drc205Data := Array.append(__drc205Data, [drc205.getData()]);
    };
    system func postupgrade() {
        if (__drc205Data.size() > 0){
            drc205.setData(__drc205Data[0]);
            __drc205Data := [];
        };
    };
```


## 实例

#### Implementations

- Storage Canister: https://github.com/iclighthouse/DRC_standards/tree/main/DRC205/examples/IClighthouse  
    DRC205 (Main): 6ylab-kiaaa-aaaak-aacga-cai  
    DRC205 (Test): ix3cb-4iaaa-aaaak-aagbq-cai 
    Notes: Use 6ylab-kiaaa-aaaak-aacga-cai to store swap records that can be queried through the ICHouse blockchain explorer (http://ic.house).

- Motoko Module: https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/examples/ICLighthouse/Example/lib/DRC205.mo 

- Development Example: https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/examples/ICLighthouse/Example/Example.mo   