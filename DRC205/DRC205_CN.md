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

* 可扩展性存储接口规范：可扩展存储机制是由一个Root合约，自动扩展的入口合约Proxy（存储布隆过滤器数据）和自动扩展的多个存储合约Bucket（存储交易记录数据）组成。根据实际的存储需求创建Bucket（当一个Bucket满了就创建一个新的Bucket），然后将交易记录压缩并存储在Bucket中。当你想查询一个交易对的交易记录时，你可以先从Proxy合约中查询记录存储的BucketId（使用BloomFilter技术进行路由，https://en.wikipedia.org/wiki/Bloom_filter ），然后再从指定的Bucket中查询交易记录。

* Motoko开发包（Motoko Module）：建议Dex开发者采用的交易记录处理规范，采取“当前Canister缓存近期记录+外部Canister持久化存储历史记录”的模式，并提供查询接口。


## 开发指南

https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/dev-guide-cn.md



## 规范

**NOTES**:

- 以下规范使用candid语法。
- `Sid`是全局唯一的交易记录存储ID，Blob类型，28字节，由Proxy合约生成。
- `Txid`是Dex内唯一的交易记录ID，Blob类型，必须8或32字节，由Dex合约生成。推荐生成txid的方法是：[DRC205Types.generateTxid(_app: Principal, _caller: AccountId, _nonce: Nat)](https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/examples/ICLighthouse/Example/lib/DRC205Types.mo)。
    如果你使用Nat作为txid，请将Nat转换为Nat64，然后使用大端序编码，生成8字节的bytes。
- `AccountId`是用户的身份ID，通常是32字节的Blob类型，由Token合约生成。如果使用Principal、[Nat8]等数据类型，则需要转换成AccountId(Blob)。如果交易的token是ICRC1标准的Account类型，需要转换成AccountId(Blob)，交易记录结构TxnRecord中的msgCaller字段填入交易者的`owner`, caller字段填入交易者的`subaccount`。

### Transaction Record Types (TxnRecord)

这是一个建议数据结构，如果使用自定义数据结构，可以使用`storeBytesBatch`满足兼容性需求。

``` candid
type Status = variant { Failed; Pending; Completed; PartiallyCompletedAndCancelled; Cancelled; };
type TxnRecord = record {
   account: AccountId;
   caller: AccountId;
   cyclesWallet: opt CyclesWallet;
   data: opt Data;
   details: vec record {
       counterparty: Txid;
       time: Time;
       token0Value: BalanceChange;
       token1Value: BalanceChange;
     };
   fee: record { token0Fee: int; token1Fee: int; };
   filled: record { token0Value: BalanceChange; token1Value: BalanceChange; };
   index: nat;
   msgCaller: opt principal;
   nonce: Nonce;
   operation: OperationType;
   order: record { token0Value: opt BalanceChange; token1Value: opt BalanceChange; };
   orderMode: variant { AMM; OrderBook; };
   orderType: opt variant { FAK; FOK; LMT; MKT; };
   shares: ShareChange;
   status: Status;
   time: Time;
   token0: TokenType;
   token1: TokenType;
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

### 通用存储接口 (Root, Proxy和Bucket)

#### 0. DRC205Root

#### proxyList

返回Proxy列表及当前Proxy。    

``` candid
proxyList : () -> (record {root: principal; list: vec record {principal; Time, nat}; current: opt record {principal; Time, nat} }) query;
```

#### getTxnHash (composite_query)

返回交易记录的Hash值。由于一个订单可能存在多次匹配成交的情况，可能一个`_txid`存在多次记录副本，指定`_merge`为true，意味着将同一个订单的多个成交进行合并。如果存在多个订单记录，则返回多个Hash值。    
OPTIONAL - 该方法可用于提高可用性，但该方法可能不存在。

``` candid
getTxnHash : (_app: AppId, _txid: Txid, _merge: bool) -> (vec Hex) composite_query;
```

#### getArchivedTxnBytes (composite_query)

返回指定交易对和Txid的存档交易记录的二进制值。如果存在多个记录，则返回多个值。      
OPTIONAL - 该方法可用于提高可用性，但该方法可能不存在。

``` candid
getArchivedTxnBytes : (_app: AppId, _txid: Txid) -> (vec record{ vec nat8; Time }) composite_query;
```

#### getArchivedTxn (composite_query)

返回指定交易对和Txid的存档交易记录。 如果存在多个记录，则返回多个值。     
OPTIONAL - 该方法可用于提高可用性，但该方法可能不存在。

``` candid
getArchivedTxn : (_app: AppId, _txid: Txid) -> (vec record{ TxnRecord; Time }) composite_query;
```

#### getArchivedTxnByIndex (composite_query)

返回指定交易对及其区块索引的存档交易记录。 如果存在多个记录，则返回多个值。     
OPTIONAL - 该方法可用于提高可用性，但该方法可能不存在。

``` candid
getArchivedTxnByIndex : (_app: AppId, _tokenBlockIndex: nat) -> (vec record{ TxnRecord; Time }) composite_query;
```

#### getArchivedDexTxns (composite_query)

返回指定交易对的交易记录列表，`_start_desc`表示开始的区块索引号，降序进行查询，`_length`表示每次获取的条数。        
OPTIONAL - 该方法可用于提高可用性，但该方法可能不存在。

``` candid
getArchivedDexTxns : (_app: AppId, _start_desc: nat, _length: nat) -> (vec TxnRecord) composite_query;
```

#### getArchivedAccountTxns (composite_query)

返回指定`AccountId`的交易记录列表。因为记录可能保存在不同的Proxy和Bucket中，它将从最新的Proxy中的最新的Bucket进行查找，`_buckets_offset`表示跳过开始的多少个bucket，`_buckets_length`表示一次查找多少个bucket，`_app`可选指定交易对，`_page`(从1开始)和`_size`对查询到的数据集进行分页。        
OPTIONAL - 该方法可用于提高可用性，但该方法可能不存在。

``` candid
getArchivedAccountTxns : (_buckets_offset: opt nat, _buckets_length: nat, _account: AccountId, _app: opt AppId, _page: opt nat32, _size: opt nat32)
 -> (record {data: vec record{ principal; vec record{ TxnRecord; Time } }; totalPage: nat; total: nat});
```


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

#### storeBatch

批量存储交易记录, 允许每间隔20秒以上存储一次. 调用该方法时需要添加cycles作为费用（通过`fee()`方法查询），批量存储n条消息需要支付n*fee Cycles。

``` candid
storeBatch: (_txns: vec TxnRecord) -> ();
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

#### location

返回给定的_app和_arg(可以使用txid，index，accountId进行查询)的交易记录所在的Bucket。如果不存在返回空数组；如果返回数组包含多个值，意味着交易记录可能保存在其中一个Bucket中，可遍历寻找它。

``` candid
location: (_app: AppId, _arg: variant{ txid: Txid; index: nat; account: AccountId}, _version: opt nat8) -> (vec Bucket) query;
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

#### bucketListSorted

返回bucket列表.  
OPTIONAL - 该方法可用于提高可用性，但该方法可能不存在。

``` candid
bucketListSorted : () -> (vec record {Bucket, Time, nat}) query;
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

#### txnByIndex

返回指定`_token`和`_blockIndex`的交易历史记录集。     
OPTIONAL - 这个方法可以用来提高可用性，但该方法可能不存在。

``` candid
txnByIndex: (_app: AppId, _blockIndex: nat) -> (vec record{TxnRecord; Time}) query;
```

#### txnByAccountId

返回指定`_accountId`和`_token`的交易记录列表。注：_page从1开始。          
OPTIONAL - 这个方法可以用来提高可用性，但该方法可能不存在。

``` candid
txnByAccountId: (_accountId: AccountId, _app: opt AppId, _page: opt nat32, _size: opt nat32) -> (record{data: vec record{AppId; vec record{TxnRecord; Time}}; totalPage: nat; total: nat}) query;
```

#### txnHash

计算指定交易记录历史的所有Hash值。指定`_merge`为true表示将同一个交易的多个成交合并成一个交易记录，然后计算Hash值。      
OPTIONAL - 这个方法可以用来提高可用性，但该方法可能不存在。
``` candid
txnHash: (AppId, Txid, _merge: bool) -> (vec Hex) query;
```

#### bucketInfo 

返回关于当前bucket的信息。    
OPTIONAL - 这个方法可以用来提高可用性，但该方法可能不存在。

``` candid
bucketInfo: () -> (BucketInfo) query;
```


#### 3. Trading Pair Interface (Implementation)

Dex开发者需要在交易对中实现以下接口，方便查询交易记录。

#### drc205_canisterId

返回Root的canister-id。

``` candid
drc205_canisterId: () -> (principal) query;
```

#### drc205_events

返回指定账户`Address`的交易记录，如果未指定则返回全局的最近交易记录。Address是Text类型， 是Principal或者AccountId，如"tqnrp-pjc3b-jzsc2-fg5tr-...-ts5ax-lbebt-uae", "1af2d0af449ab5a13e30...ee1f99a9ece5ceaf8fe4"。

``` candid
drc205_events: (opt Address) -> (vec TxnRecord) query;
```

#### drc205_events_filter

返回指定账户`Address`, 并且过滤指定开始时间`Time`到结束时间`Time`(纳秒)的交易记录，如果未指定则返回全局的最近交易记录。Address是Text类型， 是Principal或者AccountId，如"tqnrp-pjc3b-jzsc2-fg5tr-...-ts5ax-lbebt-uae", "1af2d0af449ab5a13e30...ee1f99a9ece5ceaf8fe4"。

``` candid
drc205_events_filter: (opt Address, opt Time, opt Time) -> (vec TxnRecord, bool) query;
```

#### drc205_txn

返回指定`Txid`的缓存的交易记录，如果要查询DRC205中存储的交易记录，使用[开发指南](https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/dev-guide-cn.md)中的查询方法。

``` candid
drc205_txn: (Txid) -> (opt TxnRecord) query;
```


### 开发包(Motoko Module)及指南

#### DRC205 Module

import DRC205 "lib/DRC205";

#### root

返回DRC205Root actor。  

``` candid
root: () -> DRC205Types.Root;
```

#### proxy

返回DRC205Proxy actor。  

``` candid
proxy: () -> DRC205Types.Proxy;
```

#### drc205CanisterId

返回Root canister-id。 

``` candid
drc205CanisterId: () -> principal;
```

#### getProxyList

返回Proxy列表。 

``` candid
getProxyList: () -> vec {principal; Time; nat};
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
get2 : (_txid: Txid) -> opt TxnRecord;
```

#### getLastTxns

返回用户`_account`最近发生的记录txid列表。  

``` candid
getLastTxns : (_account: opt AccountId) -> vec Txid;
```

#### getEvents

返回用户`_account`最近发生的记录详情列表。  

``` candid
getEvents : (_account: opt AccountId, _startTime: opt Time, _endTime: opt Time) -> (vec TxnRecord, bool);
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


#### Rust开发者指南

DRC205 Root (Main): lw5dr-uiaaa-aaaak-ae2za-cai   
DRC205 Root (Test): lr4ff-zqaaa-aaaak-ae2zq-cai  

请参考Candid文件接口：

https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/DRC205Root.did  
https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/DRC205Proxy.did  
https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/DRC205Bucket.did  

请调用storeBatch或storeBytesBatch方法进行批量存储，注意需要添加Cycles以及调用的时间间隔。

#### Motoko开发包(Motoko Module)及指南

DRC205 Root (Main): lw5dr-uiaaa-aaaak-ae2za-cai   
DRC205 Root (Test): lr4ff-zqaaa-aaaak-ae2zq-cai  

Motoko开发示例：https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/examples/ICLighthouse/Example/Example.mo

**Step1** 引入Module文件

将https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/examples/ICLighthouse/Example/lib/ 文件导入项目所在目录。在你的代码文件中引入：
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

* drc205_getConfig : () -> (Setting) query;
* drc205_canisterId : () -> (principal) query;
* drc205_dexInfo : () -> (DexInfo) query;
* drc205_events : (_account: opt DRC205.Address) -> (vec TxnRecord) query;
* drc205_events_filter: (opt Address, opt Time, opt Time) -> (vec TxnRecord, bool) query;
* drc205_txn : (_txid: Txid) -> (opt TxnRecord) query;

如：https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/examples/ICLighthouse/Example/Example.mo

## 实例

#### Implementations

- Storage Canister: https://github.com/iclighthouse/DRC_standards/tree/main/DRC205/examples/IClighthouse   

- Motoko Module: https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/examples/ICLighthouse/Example/lib/DRC205.mo 

- Development Example: https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/examples/ICLighthouse/Example/Example.mo   