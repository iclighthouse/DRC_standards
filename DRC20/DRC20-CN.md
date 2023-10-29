***
DRC: 20  
Title: Dfinity Fungible Token Standard  
Author: Avida <avida.life@hotmail.com>, Simpson <icpstaking-wei@hotmail.com>  
Status: Stable version  
Category: Token DRC  
Created: 2021-11-03
***

## 摘要

DRC20是一个用于Dfinity代币的标准接口。该标准符合[ERC20](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md)的接口规范，并有一些改进以符合IC网络的特点。（注：下文中“token”、“代币”、“通证”、“令牌”是指同一个意思。）

## 解决什么问题

本标准描述了同质化Token接口，允许应用（链外应用和链上智能合约）进行交互。并解决了IC网络应用场景中代币的一些问题。

这个标准的核心理念是   
(1) 尽可能地保持去中心化。  
(2) 抽象提炼出通用接口，不必将个性化接口纳入规范。  

代币开发者可以根据需要对其进行扩展。

**改进的功能：** 

* 持有者账户格式的兼容性

    ICP Ledger使用account-id作为账户标识符，而其他大多数canister使用 principal-id作为账户标识符。这给用户带来了复杂性。本标准使用**account-id**作为账户标识，兼容使用"principal-id"，并支持 "subaccount"。

* 使用pub/sub模型来实现消息通知

    Dfinity没有现成的事件通知机制，通常做法是应用主动去查询事件。在有些场景下，应用Canister需要使用pub/sub模型来订阅Token Canister的消息并执行回调函数。因此，本标准增加了**subscribe()**方法，并且订阅者需要实现回调函数。订阅者未能收到消息（这种情况很少发生）或未成功处理消息时，可以使用txnQuery()查询历史记录作为补充。

* 交易记录的存储和查询

    Dfinity不像以太坊那样将智能合约的交易记录存储在区块中，代币Canister需要自己保存交易记录数据。Canister的存储空间是有限的，将所有交易记录存储在一个Canister里是不合适的。本标准将最近交易记录缓存在Token Canister中，更多的历史记录保存在外部可扩展的Canister中。

* Lock/execute模型提高原子性

    Canister的异步消息传递模型并没有为跨容器调用提供原子性保证。跨容器调用的非原子性是IC网络的技术特征之一，需要开发者在应用逻辑中去应对。例如，Saga模式，2PC模式。
    创建一个两阶段提交结构可以作为底层功能来提高原子性。因此，**lockTransfer()/lockTransferFrom()**和**executeTransfer()**方法被添加到标准中。

* 防止重复交易

    在发送交易时，可能存在两个风险：重复发送的风险；因遇上网络故障而无法知道交易状态的风险。本标准引入两个规则来解决：（1）可选使用nonce机制。发送者可以放心地重复发送交易，交易只会被执行一次（幂等性）。（2）交易id（txid）可在发送前计算。如果txid依赖于交易的返回结果，当异常发生时你将得不到txid和交易状态。本标准采用DRC202标准的txid计算方式。

* 防止canister cycles余额不足攻击

    根据IC网络规则，Canister的调用者不需要支付gas，而是由Canister支付gas，这可能会导致DDOS攻击。所以代币Canister应该要求caller支付gas。本标准增加了**gas()**方法，以帮助调用者查询gas成本。setGas方法不包括在标准中，由开发者决定，它可以是一个固定的费用，也可以通过外部治理设置。

* 解决恶意利用approve的问题

    为了防止approve的滥用，便于风险管理，本标准增加了**approvals()**方法，以方便持有人检查其approve情况。

* 时间加权余额

    在挖矿、空投等多种使用场景下，一个账户的余额持有时间被作为一项重要的考量因素。传统token需要通过快照、锁定等方式来解决，但也造成了复杂的业务流程和安全性问题。本标准引入“币秒”（CoinSeconds）概念，是账户余额的时间加权累计值，1 CoinSeconds表示1 token持有1秒钟时间，可被用于计算日均余额、时间加权余额比例等。

* 与不同Token标准的兼容性

   DRC20遵循[CTSNC](https://github.com/iclighthouse/DRC_standards/tree/main/CTSNC)，在与其他标准兼容时，所有方法提供了以命名空间“drc20_”前缀的方法别名。

**更多问题：**

* 不变性和去中心化

    保持代币去中心化有两个重要因素。  
    (1) Canister代码的不可更改性。如果有必要，Canister的控制者可以被设置为黑洞地址。  
    (2) 权利平等，没有特殊的许可角色。如果有管理Canister的需要，建议使用治理Canister来解决。

* 防止重入攻击

   Token canister对回调方法的调用存在重入攻击的风险。措施：要求发送方支付gas，使用pub/sub代替同步的callback或者notify，并在对外调用前更新状态。

* 需不需要mint和burn方法
    
    更好的做法是代币不包含mint()和burn()方法。代币发行者应考虑代币发行规则和经济模式。开发者如果需要，可以进行扩展。如果你只需要销毁代币，_807077e900000000000000000000000000000000000000000000000000000000_(这是一个带校验的0地址)可以作为黑洞地址。


## 规范

## Token

### Types

``` candid
type TxnResult = variant {
   err: record {
      code: variant {
         InsufficientAllowance;
         InsufficientBalance;
         InsufficientGas;
         NoLockedTransfer;
         DuplicateExecutedTransfer;
         LockedTransferExpired;
         NonceError;
         UndefinedError;
       };
      message: text;
    };
   ok: Txid;
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
type TxnQueryResponse = variant {
   getEvents: vec TxnRecord;
   getTxn: opt TxnRecord;
   lastTxids: vec Txid;
   lastTxidsGlobal: vec Txid;
   lockedTxns: record { lockedBalance: nat; txns: vec TxnRecord; };
   txnCount: nat;
   txnCountGlobal: nat;
};
type TxnQueryRequest = variant {
   getEvents: record {owner: opt Address;};
   getTxn: record {txid: Txid;};
   lastTxids: record {owner: Address;};
   lastTxidsGlobal;
   lockedTxns: record {owner: Address;};
   txnCount: record {owner: Address;};
   txnCountGlobal;
};
type Txid = blob;
type Transaction = record {
   data: opt blob;
   from: AccountId;
   operation: Operation;
   to: AccountId;
   value: nat;
};
type To = text;
type Timeout = nat32;
type Time = int;
type Subscription = record {
   callback: Callback;
   msgTypes: vec MsgType;
};
type Spender = text;
type Sa = vec nat8;
type Operation = variant {
   approve: record {allowance: nat;};
   executeTransfer: record { fallback: nat; lockedTxid: Txid; };
   lockTransfer: record { decider: AccountId; expiration: Time; locked: nat; };
   transfer: record {action: variant { burn; mint; send; };};
};
type Nonce = nat;
type MsgType = variant {
   onApprove;
   onExecute;
   onLock;
   onTransfer;
};
type Metadata = record { content: text; name: text; };
type InitArgs = record {
   decimals: nat8;
   founder: opt Address;
   fee: nat;
   metadata: opt vec Metadata;
   name: opt text;
   symbol: opt text;
   totalSupply: nat;
};
type Gas = variant { cycles: nat; noFee; token: nat; };
type From = text;
type ExecuteType = variant { fallback; send: nat; sendAll; };
type Decider = text;
type Data = blob;
type CoinSeconds = record { coinSeconds: nat; updateTime: int; };
type Callback = func (TxnRecord) -> ();
type Amount = nat;
type Allowance = record { remaining: nat; spender: AccountId; };
type Address = text;
type AccountId = blob;
type DRC20 = service {
   standard: () -> (text) query;
   drc20_allowance: (Address, Spender) -> (Amount) query;
   drc20_approvals: (Address) -> (vec Allowance) query;
   drc20_approve: (Spender, Amount, opt Nonce, opt Sa, opt Data) -> (TxnResult);
   drc20_balanceOf: (Address) -> (Amount) query;
   drc20_decimals: () -> (nat8) query;
   drc20_executeTransfer: (Txid, ExecuteType, opt To, opt Nonce, opt Sa, opt Data) -> (TxnResult);
   drc20_fee: () -> (Amount) query;
   drc20_lockTransfer: (To, Amount, Timeout, opt Decider, opt Nonce, opt Sa, opt Data) -> (TxnResult);
   drc20_lockTransferFrom: (From, To, Amount, Timeout, opt Decider, opt Nonce, opt Sa, opt Data) -> (TxnResult);
   drc20_metadata: () -> (vec Metadata) query;
   drc20_name: () -> (text) query;
   drc20_subscribe: (Callback, vec MsgType, opt Sa) -> (bool);
   drc20_subscribed: (Address) -> (opt Subscription) query;
   drc20_symbol: () -> (text) query;
   drc20_totalSupply: () -> (Amount) query;
   drc20_transfer: (To, Amount, opt Nonce, opt Sa, opt Data) -> (TxnResult);
   drc20_transferBatch : (vec To, vec Amount, opt Nonce, opt Sa, opt Data) -> (vec TxnResult);
   drc20_transferFrom: (From, To, Amount, opt Nonce, opt Sa, opt Data) -> (TxnResult);
   drc20_txnQuery: (TxnQueryRequest) -> (TxnQueryResponse) query;
   drc20_txnRecord : (Txid) -> (opt TxnRecord);
   drc20_getCoinSeconds: (opt Address) -> (CoinSeconds, opt CoinSeconds) query;
   drc20_dropAccount : (opt Sa) -> bool;
   drc20_holdersCount : () -> (nat, nat, nat) query;
 };
service : (args: InitArgs, enDebug: Bool) -> DRC20
```

### Methods

**NOTES**:
 - 以下规范使用Candid的语法。 
 - 可选参数`_nonce`用于指定交易的nonce。每个AccountId的nonce值从0开始，并在每个特定交易成功时增加1。如果调用者指定了一个错误的nonce值，交易将被拒绝。特定交易包括：approve(), transfer(), transferFrom(), lockTransfer(), lockTransferFrom(), executeTransfer()。
 - 可选参数`_sa`是调用者的子账户，它是一个32字节的nat8数组。如果`_sa`的长度小于32字节，它将以[0]作为前缀来补足。
 - 可选参数`_data`是调用者提供的自定义数据，可用于calldata, memo等。`_data`的长度应小于2KB（建议使用candid的编码格式，如4字节的方法名哈希+参数数据）。
 - 为了具有更好的兼容性，使用"drc20_"前缀的方法名。
 
#### standard

返回标准名称，小写字母，如果兼容多个标准以“; ”分割。例如：`"drc20"`。  
OPTIONAL - 这个方法可以用来提高可用性，但值可能不存在。
``` candid
standard: () -> (text) query;
```
#### drc20_name

返回代币的名称。例如：`"ICLighthouseToken"`。  
OPTIONAL - 这个方法可以用来提高可用性，但值可能不存在。
``` candid
drc20_name: () -> (text) query;
```
#### drc20_symbol
返回代币的符号。例如：`"ICL"`。  
OPTIONAL - 这个方法可以用来提高可用性，但值可能不存在。
``` candid
drc20_symbol: () -> (text) query;
```
#### drc20_decimals
返回代币使用的小数的位数。例如：`8`，意味着实际代币金额是用代币数量除以`100000000`。 
``` candid
drc20_decimals: () -> (nat8) query;
```
#### drc20_metadata
返回代币的扩展元数据信息，它是Metadata类型。 E.g. `'vec {record { name: "logo"; content: "data:img/jpg;base64,iVBOR....";}; }'`.    
OPTIONAL - 这个方法可以用来提高可用性，但值可能不存在。
``` candid
drc20_metadata: () -> (vec Metadata) query;
```
#### drc20_fee
返回代币的交易费设置值。例如：`"10000000"`。   
*注意* fee将从账户的余额中收取（而不是从转账的`_value`中收取）。transferFrom、lockTransferFrom从账户`_from`扣除fee，executeTransfer不收取fee，其他update方法都是从账户`caller`扣除fee。
``` candid
drc20_fee: () -> (Amount) query;
```
#### drc20_totalSupply
返回总的代币供应量。
``` candid
drc20_totalSupply: () -> (nat) query;
```
#### drc20_balanceOf
返回给定账户`_owner`的账户余额，不包括处于交易锁定状态的余额。
``` candid
drc20_balanceOf: (_owner: Address) -> (balance: nat) query;
```
#### drc20_getCoinSeconds
返回总币秒和给定账户`_owner`的币秒。币秒（CoinSeconds）是账户余额的时间加权累积值。CoinSeconds = Σ（balance_i * period_i）。   
在存储节约模式下，该功能将被关闭而无法查询CoinSeconds。  
OPTIONAL - 该方法可用于提高可用性，但该方法可能不存在。 
``` candid
drc20_getCoinSeconds: (opt Address) -> (totalCoinSeconds: CoinSeconds, accountCoinSeconds: opt CoinSeconds) query;
```
#### drc20_transfer
将`_value`数量的代币从调用者的账户转移到`_to`账户，返回`TxnResult`类型。  
成功时，返回的TxnResult包含txid。`txid`在交易中产生，在代币交易中是唯一的。推荐生成txid的方法（DRC202标准）：将代币的canisterId、调用者的accountId和调用者的nonce分别转换成[nat8]数组，并将它们连接起来作为`txInfo: [nat8]`。然后得到`txid`值为："00000000"(big-endian 4-bytes, `encode(caller.nonce)`) + "0000...00"(28-bytes, `sha224(txInfo)`)。    
*注意* 0值的转移须被视为正常转移。允许账户向自己转账。
``` candid
drc20_transfer: (_to: Address, _value: nat, _nonce: opt nat, _sa: opt vec nat8, _data: opt blob) -> (result: TxnResult);
```
#### drc20_transferBatch
批量发送交易，参数`_to`和`_value`是等长的数组，分别向`_to[i]`转移`_value[i]`数量的代币，返回`result[i]`结果。  
*注意* 如果提供`_nonce`参数，则用于校验第一笔交易的nonce值，如果出现`NonceError`错误，则拒绝发送所有交易。批量发送的每笔交易都会占用一个nonce值。
``` candid
drc20_transferBatch : (_to: vec Address, _value: vec nat, _nonce: opt nat, _sa: opt vec nat8, _data: opt blob) -> (result: vec TxnResult);
```
#### drc20_transferFrom
从账户`_from`向账户`_to`转移`value`数量的代币，返回类型`TxnResult`。  
`transferFrom`方法用于允许Canister代表`_from`转移代币。这可用于允许Canister代表`_from`转移代币和或收取费用。调用者是`spender`，他应该得到`_from`账户的授权，并且`allowance(_from, _spender)`值需大于`_value`。   
*注意* 0值的转账必须被视为正常转账。`_from`账户向自己转账是被允许的。
``` candid
drc20_transferFrom: (_from: Address, _to: Address, _value: nat, _nonce: opt nat, _sa: opt vec nat8, _data: opt blob) -> (result: TxnResult);
```
#### drc20_lockTransfer
锁定一个交易，指定一个可以决定该交易最终是否执行的`_decider`，并设置一个过期时间`_timeout`秒，过期后锁定的交易将被解锁。参数_timeout不应该大于64,000,000秒(约740天)。   
创建一个两阶段交易结构可以提高原子性。这个过程是，（1）所有者锁定交易；（2）决定者执行交易或过期后所有者回退交易。
``` candid
drc20_lockTransfer: (_to: Address, _value: nat, _timeout: nat32, _decider: opt Address, _nonce: opt nat, _sa: opt vec nat8, _data: opt blob) -> (result: TxnResult);
```
#### drc20_lockTransferFrom
`spender`锁定一个交易。
``` candid
drc20_lockTransferFrom: (_from: Address, _to: Address, _value: nat, _timeout: nat32, _decider: opt Address, _nonce: opt nat, _sa: opt vec nat8, _data: opt blob) -> (result: TxnResult);
```
#### drc20_executeTransfer
`decider`执行被锁定的交易`_txid`，或者`owner`在锁过期后回退被锁定的交易。如果锁定交易的接收者`_to`是decider自己，decider可以指定一个新的接收者`_to`。
``` candid
drc20_executeTransfer: (_txid: Txid, _executeType: ExecuteType, _to: opt Address, _nonce: opt nat, _sa: opt vec nat8, _data: opt blob) -> (result: TxnResult);
```
#### drc20_txnQuery
查询交易计数，以及查询缓存在Token Canister里的最近交易记录。  
查询类型 `_request`：   
#txnCountGlobal：返回全局交易数量统计。   
#txnCount：返回`owner`的交易数量。这也是他下一次交易的 "nonce"值。    
#getTxn: 返回ID为`txid`的交易的详细信息。   
#lastTxidsGlobal：返回全局的最新交易txids。   
#lastTxids：返回`owner`的最新交易txids。  
#lockedTxns：返回`owner`的锁定余额，以及被锁定未执行的交易记录。    
#getEvents：返回全局最新交易事件（如果不指定`owner`）或`owner`的交易事件（如果指定了`owner`）。  
``` candid
txnQuery: (_request: TxnQueryRequest) -> (response: TxnQueryResponse) query;
```
#### txnRecord
返回txn记录。这是一个update方法，如果要查询的txn记录在代币容器中不存在，将尝试在DRC202容器中找到txn记录。   
OPTIONAL - 该方法可用于提高可用性，但该方法可能不存在。
``` candid
drc20_txnRecord : (Txid) -> (opt TxnRecord);
```
#### drc20_subscribe
订阅token的消息，输入回调函数`_callback`和消息类型`_msgTypes`作为参数。消息类型有：`onTransfer`, `onLock`, `onExecute`, 和`onApprove`。订阅者只能接收与他们自己有关的消息（如订阅者是交易的_from, _to, _spender, 或_decider）。  
订阅者应该是一个Canister，要求其在代码中实现回调函数。  
OPTIONAL - 该方法可用于提高可用性，但该方法可能不存在。
``` candid
drc20_subscribe: (_callback: Callback, _msgTypes: vec MsgType, _sa: opt vec nat8) -> bool;
```
#### drc20_subscribed
返回订阅者`_owner`的订阅状态。   
OPTIONAL - 该方法可用于提高可用性，但该方法可能不存在。
``` candid
drc20_subscribed: (_owner: Address) -> (result: opt Subscription) query;
```
#### drc20_approve
允许`_spender`从你的账户中多次转移代币，最多到`_value`的金额。 如果这个函数被再次调用，它将用`_value`覆盖当前的值。   
每个账户最多可以存在50个授权（approval）记录。  
**注意**。当你执行`approve()`授权给spender，可能会引起安全问题，你可以执行`approve(_spender, 0, ...)`来取消授权。
``` candid
drc20_approve: (_spender: Address, _value: nat, _nonce: opt nat, _sa: opt vec nat8, _data: opt blob) -> (result: TxnResult);
```
#### drc20_allowance
返回仍然允许`_spender`可以从`_owner`转账的金额。 
``` candid
drc20_allowance: (_owner: Address, _spender: Address) -> (remaining: nat) query;
```
#### drc20_approvals
返回`_owner`的所有非零金额的对外授权（approval）。   
OPTIONAL - 该方法可用于提高可用性，但该方法可能不存在。
``` candid
drc20_approvals: (_owner: Address) -> (allowances: vec Allowance) query;
```
#### drc20_dropAccount
注销账户。仅在该账户余额不大于gas费的时候才可被账户所有者自己注销。   
OPTIONAL - 该方法可用于提高可用性，但该方法可能不存在。
``` candid
drc20_dropAccount : (opt Sa) -> bool;
```
#### drc20_holdersCount
返回余额不为0的账户数量、存在交易的账户数量、已注销的账户数量。   
OPTIONAL - 该方法可用于提高可用性，但该方法可能不存在。
``` candid
drc20_holdersCount : () -> (balances: nat, nonces: nat, dropedAccounts: nat) query;
```

### 关于存储节约模式

当canister存储空间接近存满时，Token合约将启用存储节约模式，它将实现如下操作： 
- 减少交易记录缓存时间；
- 关闭CoinSeconds功能，删除所有CoinSeconds记录；
- 删除所有nonce记录，账户的nonce重新从一个新值开始（如10000000）；
- 删除所有已注销的账户列表。
随着Token账户数量的增加，存储节约模式可以被重复升级激活，重新执行以上操作。

### 订阅者回调函数实现
#### tokenCallback (customizable)
Token订阅者应该实现一个回调函数callback来处理代币发布的消息。  
callback是通过调用token的`subscribe()`方法提供给token。
``` candid
type Callback = func (txn: TxnRecord) -> ();
```

## DRC20例子实现
注：不同的团队正在编写不同的实施方案。
#### Example implementations
- [ICLighthouse DRC20](https://github.com/iclighthouse/DRC_standards/tree/main/DRC20/examples/ICLighthouse/)
- [DIP20 Added DRC20 Extension](https://github.com/iclighthouse/DRC_standards/tree/main/DRC20/examples/dip20-drc20)  

## 参考
- [EIP-20 Token Standard](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md)
- [ERC-223 Token Standard](https://github.com/ethereum/EIPs/issues/223)
- [ERC-667 Token Standard](https://github.com/ethereum/EIPs/issues/677)
- [Thoughts on the token standard](https://forum.dfinity.org/t/thoughts-on-the-token-standard/4694/106)
- [dfinance-tech/ic-token](https://github.com/dfinance-tech/ic-token)
- [Toniq-Labs/extendable-token](https://github.com/Toniq-Labs/extendable-token)
- [enzoh/motoko-token](https://github.com/enzoh/motoko-token)
- [Psychedelic/standards](https://github.com/Psychedelic/standards)
- [dfinity-fungible-token-standard](https://github.com/Deland-Labs/dfinity-fungible-token-standard)
- [Candid](https://github.com/dfinity/candid/)
