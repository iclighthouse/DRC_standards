***
DRC: 20  
Title: Dfinity Fungible Token Standard  
Author: Avida <avida.life@hotmail.com>, Simpson <icpstaking-wei@hotmail.com>  
Status: Draft (PR version)  
Category: Token DRC  
Created: 2021-11-03
***

## Abstract

A standard interface for Dfinity tokens. The standard complies with [ERC20](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md) interface specification, and has some improvements to match IC network features.

## Motivation

This standard describes fungible token interface that allows to be interacted by applications(off-chain applications and on-chain smartcontracts). And solve some problems of tokens in IC network application scenarios.

The core concept of this standard is: 
(1) to keep it as decentralized as possible; 
(2) to abstract the generic interfaces and not to include non-essential and individual functional interfaces into the specification.

Token developers can extend it as needed.

**Improved features:** 

* Account ID format compatibility.

    ICP Ledger canister uses account-id(address) as account identifier, while most other canisters use principal-id as account identifier. It brings complexity to users. This standard uses **account-id** as account identity, supports `subaccount`, and is compatible with the use of `principal-id`.

* Using the pub/sub model to implement message notifications.

    Dfinity does not have an established event notification mechanism and the usual practice is for dapp to actively query for events. In some scenarios, the application canister needs to use the pub/sub model to subscribe to token canister messages and execute callback functions. Therefore, this standard adds the **subscribe()** method and subscribers need to implement callback function. When a subscriber fails to receive a message (which rarely happens), the txnQuery() method can be used as a supplement.

* Transaction records storage and query.

    Dfinity does not store smart contract transaction records in blocks like ethereum. Token canister needs to keep transaction record data by itself. The storage space of canister is limited and it is dangerous to store all transaction records in one canister. This standard specifies that recent transactions are cached in the token canister and historical records are stored in externally scalable canisters.

* Lock/execute model improves atomicity.

    Canister's asynchronous messaging model does not provide atomicity guarantees for cross-canister transfers. The non-atomicity of cross-canister transfers is one of the technical features of IC networks that cannot be solved at the system level and needs to consider designing for atomicity within the application logic. For example, Saga mode, 2PC mode.
    Creating a two-phase transfer structure can provide the underlying functionality to improve atomicity. Therefore, **lockTransfer()/lockTransferFrom()** and **executeTransfer()** methods are added to the standard. 

* Preventing Duplicate Transaction.

   There are two possible risks when sending a transaction: the risk of sending duplicate transactions and the risk of not knowing the status of the transaction due to a network failure. 
   This standard introduces two rules to solve this trouble: (1) the optional use of the nonce mechanism. The sender can be assured that the transaction will only be executed once (idempotency). (2) The transaction id (txid) can be calculated before it is sent. If the txid depends on the return of the transaction execution, you will not get the txid and the status of the transaction when an exception is thrown. This standard uses the DRC202 standard for txid calculation.

* Preventing canister cycles balance attack.

    According to IC network rules, the caller of canister is not required to pay gas, and it is up to canister to pay gas. It may lead to ddos attacks. So the token canister should ask the caller of the update call to pay gas. This standard adds the **gas()** method to help the caller estimate the cost of gas. The setGas method is not included in the standard, it is up to the developers to decide, it may be a fixed fee or set through an external governance canister. 

* Solving malicious exploits of approvals.

    In order to prevent the abuse of the approval method and facilitate risk management, this standard adds **approvals()** method to facilitate holders to check their approvals.

* Time weighted balance.

    The length of time an account's balance is held is taken as an important consideration in a variety of usage scenarios such as mining and airdrops. Traditional token solutions such as snapshots and locking have resulted in complex business processes and security issues. This standard introduces the concept of "CoinSeconds", which is a time-weighted cumulative value of an account's balance. 1 CoinSeconds means 1 token held for 1 second. It can be used to calculate average daily balances, time-weighted balance ratios, etc.

* Compatibility with different token standards.

   DRC20 follows the [CTSNC](https://github.com/iclighthouse/DRC_standards/tree/main/CTSNC), and for compatibility with other standards, provides method aliases with namespace "drc20_" as prefix

**More Issues:**

* Immutability and decentralization

    There are two important factors for keeping token decentralized.
    (1) The immutability of the Canister code. The controller of canister can be set to the blackhole address if necessary. 
    (2) Equal rights and no special permission roles. If there is a need to manage canister, it is recommended to use governance canister to solve. 

* Preventing re-entrance attacks

   Token canister calls to the callback method carry the risk of re-entrance attacks. Measures: The caller is required to pay gas. It uses pub/sub instead of synchronous callback or notify, and updates the state before the external call.

* Mint and burn methods
    
    It is better practice that the token does not contain the mint() and burn() methods. Token distribution rules and economic models should be considered by the token issuer. Developers can extend this if they really need to. If you just need the burn() method, _807077e900000000000000000000000000000000000000000000000000000000_(this's 0 address with checksum) can be used as the blackhole address.

## Specification

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
   drc20_transferFrom: (From, To, Amount, opt Nonce, opt Sa, opt Data) -> (TxnResult);
   drc20_txnQuery: (TxnQueryRequest) -> (TxnQueryResponse) query;
   drc20_txnRecord : (Txid) -> (opt TxnRecord);
   drc20_getCoinSeconds: (opt Address) -> (CoinSeconds, opt CoinSeconds) query;
   drc20_dropAccount : (opt Sa) -> bool;
   drc20_holdersCount : () -> (nat, nat, nat) query;
 };
service : (InitArgs) -> DRC20
```

### Methods

**NOTES**:
 - The following specifications use syntax from Candid.
 - The optional parameter `_nonce` is used to specify the nonce of the transaction. The nonce value for each AccountId starts at 0 and is incremented by 1 on the success of each specific transaction. If the caller specifies an incorrect nonce value, the transaction will be rejected. The specific transactions include: approve(), transfer(), transferFrom(), lockTransfer(), lockTransferFrom(), executeTransfer().
 - The optional parameter `_sa` is the subaccount of the caller, which is a 32 bytes nat8 array. If length of `_sa` is less than 32 bytes, it will be prepended with [0] to make up.
 - The optional parameter `_data` is the custom data provided by the caller, which can be used for calldata, memo, etc. The length of `_data` should be less than 65536 bytes (It is recommended to use candid encoding format, e.g. 4-byte method name hash + arguments data). 
 - For better compatibility, use method names prefixed with "drc20_".
 
#### standard

Returns standard name, in lowercase letters, compatible with multiple standards separated by ";". E.g. `"drc20"`.  
OPTIONAL - This method can be used to improve usability, but the value may not be present.
``` candid
standard: () -> (text) query;
```

#### drc20_name
Returns the name of the token. E.g. `"ICLighthouseToken"`.  
OPTIONAL - This method can be used to improve usability, but the value may not be present.
``` candid
drc20_name: () -> (text) query;
```
#### drc20_symbol
Returns the symbol of the token. E.g. `"ICL"`.  
OPTIONAL - This method can be used to improve usability, but the value may not be present.
``` candid
drc20_symbol: () -> (text) query;
```
#### drc20_decimals
Returns the number of decimals the token uses. E.g. `8`, means to divide the token amount by `100000000` to get its user representation.  
``` candid
drc20_decimals: () -> (nat8) query;
```
#### drc20_metadata
Returns the extend metadata info of the token, It's Metadata type. E.g. `'vec {record { name: "logo"; content: "data:img/jpg;base64,iVBOR....";}; }'`.    
OPTIONAL - This method can be used to improve usability, but the value may not be present.
``` candid
drc20_metadata: () -> (vec Metadata) query;
```
#### drc20_fee
Returns the transaction fee of the token. E.g. `"10000000"`.  
*Note* The fee will be charged from the balance of the account, not be charged from the `_value` of the transfer. 
transferFrom, lockTransferFrom charge fee from account `_from`, executeTransfer does not charge fee, all other update methods charge fee from account `caller`.
``` candid
drc20_fee: () -> (Amount) query;
```
#### drc20_totalSupply
Returns the total token supply.
``` candid
drc20_totalSupply: () -> (nat) query;
```
#### drc20_balanceOf
Returns the account balance of the given account `_owner`, not including the locked balance. 
``` candid
drc20_balanceOf: (_owner: Address) -> (balance: nat) query;
```
#### drc20_getCoinSeconds
Returns total `CoinSeconds` and the given account `_owner`s `CoinSeconds`. CoinSeconds is the time-weighted cumulative value of the account balance. CoinSeconds = Σ(balance_i * period_i).   
In storage saving mode, this function will be disabled and CoinSeconds cannot be queried.  
OPTIONAL - This method can be used to improve usability, but the method may not be present.  
``` candid
drc20_getCoinSeconds: (opt Address) -> (totalCoinSeconds: CoinSeconds, accountCoinSeconds: opt CoinSeconds) query;
```
#### drc20_transfer
Transfers `_value` amount of tokens from caller's account to address `_to`, returns type `TxnResult`.  
On success, the returned TxnResult contains the txid. The `txid` is generated in the transaction, is unique in the token transactions. Recommended method of generating txid(DRC202 Standard): convert token's canisterId, caller's accountId, and caller's nonce into [nat8] arrays respectively, and join them together as `txInfo: [nat8]`. Then get the `txid` value as: "000000"(big-endian 4-bytes, `encode(caller.nonce)`) + "0000..00"(28-bytes,`sha224(txInfo)`).    
*Note* Transfers of 0 values MUST be treated as normal transfers. An account transfer to itself is ALLOWED. 
``` candid
drc20_transfer: (_to: Address, _value: nat, _nonce: opt nat, _sa: opt vec nat8, _data: opt blob) -> (result: TxnResult);
```
#### drc20_transferFrom
Transfers `_value` amount of tokens from address `_from` to address `_to`, returns type `TxnResult`.
The `transferFrom` method is used for allowing contracts to transfer tokens on your behalf. This can be used for example to allow a contract to transfer tokens on your behalf and/or to charge fees. The caller is `spender` who SHOULD be authorized by the `_from` account and have an `allowance(_from, _spender)` value greater than `_value`.  
*Note* Transfers of 0 values MUST be treated as normal transfers. `_from` account transfer to itself is ALLOWED.
``` candid
drc20_transferFrom: (_from:Address, _to: Address, _value: nat, _nonce: opt nat, _sa: opt vec nat8, _data: opt blob) -> (result: TxnResult);
```
#### drc20_lockTransfer
Locks a transaction, specifies a `_decider` who can decide the execution of this transaction, and sets an expiration period `_timeout` seconds after which the locked transaction will be unlocked. The parameter _timeout SHOULD not be greater than 64,000,000 seconds.  
Creating a two-phase transfer structure can improve atomicity. The process is that (1) the owner locks the transaction and (2) the decider executes the transaction or the owner fallback the transaction after it has expired.
``` candid
drc20_lockTransfer: (_to: Address, _value: nat, _timeout: nat32, _decider: opt Address, _nonce: opt nat, _sa: opt vec nat8, _data: opt blob) -> (result: TxnResult);
```
#### drc20_lockTransferFrom
`spender` locks a transaction.
``` candid
drc20_lockTransferFrom: (_from: Address, _to: Address, _value: nat, _timeout: nat32, _decider: opt Address, _nonce: opt nat, _sa: opt vec nat8, _data: opt blob) -> (result: TxnResult);
```
#### drc20_executeTransfer
The `decider` executes the locked transaction `_txid`, or the `owner` can fallback the locked transaction after the lock has expired. If the recipient of the locked transaction `_to` is decider, the decider can specify a new recipient `_to`.
``` candid
drc20_executeTransfer: (_txid: Txid, _executeType: ExecuteType, _to: opt Address, _nonce: opt nat, _sa: opt vec nat8, _data: opt blob) -> (result: TxnResult);
```
#### drc20_txnQuery
Queries transaction counts and recent transaction records cached in token canister.   
Query type `_request`:  
#txnCountGlobal: returns global transaction count.  
#txnCount: returns `owner`s transaction count. It is the `nonce` value of his next transaction.    
#getTxn: returns details of the transaction with id `txid`.  
#lastTxidsGlobal: returns global latest transaction txids.   
#lastTxids: returns `owner`s latest transaction txids.  
#lockedTxns: returns the locked balance of `owner`, and the locked transaction records.   
#getEvents: returns global latest transaction events or `owner`s transaction events.   
``` candid
drc20_txnQuery: (_request: TxnQueryRequest) -> (response: TxnQueryResponse) query;
```
#### drc20_txnRecord
returns txn record. It's an update method that will try to find txn record in the DRC202 canister if the record does not exist in the token canister.   
OPTIONAL - This method can be used to improve usability, but the method may not be present.
``` candid
drc20_txnRecord : (Txid) -> (opt TxnRecord);
```
#### drc20_subscribe
Subscribes to the token's messages, giving the `_callback` function and the `_msgTypes` as parameters. Message types are `onTransfer`, `onLock`, `onExecute`, and `onApprove`. Subscribers will only receive messages that are related to them (the subscriber is transaction‘s _from, _to, _spender, or _decider).
The subscriber SHOULD be a canister, Implementing callback functions in the code.  
OPTIONAL - This method can be used to improve usability, but the method may not be present.
``` candid
drc20_subscribe: (_callback: Callback, _msgTypes: vec MsgType, _sa: opt vec nat8) -> bool;
```
#### drc20_subscribed
Returns the subscription status of the subscriber `_owner`.  
OPTIONAL - This method can be used to improve usability, but the method may not be present.
``` candid
drc20_subscribed: (_owner: Address) -> (result: opt Subscription) query;
```
#### drc20_approve
Allows `_spender` to withdraw from your account multiple times, up to the `_value` amount. If this function is called again it overwrites the current allowance with `_value`.   
A maximum of 50 approvals can exist per account.   
**NOTE**: When you execute `approve()` to authorize the spender, it may cause security problems, you can execute `approve(_spender, 0, ...)` to deauthorize.
``` candid
drc20_approve: (_spender: Address, _value: nat, _nonce: opt nat, _sa: opt vec nat8, _data: opt blob) -> (result: TxnResult);
```
#### drc20_allowance
Returns the amount which `_spender` is still allowed to withdraw from `_owner`.
``` candid
drc20_allowance: (_owner: Address, _spender: Address) -> (remaining: nat) query;
```
#### drc20_approvals
Returns all `_owner`s approvals with a non-zero amount.  
OPTIONAL - This method can be used to improve usability, but the method may not be present.
``` candid
drc20_approvals: (_owner: Address) -> (allowances: vec Allowance) query;
```
#### drc20_dropAccount
Closes the account. The account can only be closed if the balance of the account is not greater than the GAS fee.   
OPTIONAL - This method can be used to improve usability, but the method may not be present.
``` candid
drc20_dropAccount : (opt Sa) -> bool;
```
#### drc20_holdersCount
Returns the number of accounts with a non-zero balance, the number of accounts with existing transactions, and the number of accounts that have been dropped. 
OPTIONAL - This method can be used to improve usability, but the method may not be present.
``` candid
drc20_holdersCount : () -> (balances: nat, nonces: nat, dropedAccounts: nat) query;
```

### About Storage Saving Mode

When the number of accounts exceeds a specified number (e.g. 1 million) or when the canister storage space is close to being full, the Token contract will enable storage saving mode, which will achieve the following.   
- Reduce the transaction record cache time.
- Disable the CoinSeconds function and delete all CoinSeconds records.
- Delete all nonce records, with the account's nonce restarting at a new value (e.g. 10000000).
- Delete all dropped account list records.
As the number of Token accounts increases, the storage saving mode can be activated by repeated upgrades to perform the above operations again.

### Subscriber's Callback
#### tokenCallback (customizable)
Token canister subscribers should implement a callback function for handling token published messages.
The callback function is given as an argument by calling `subscribe()` of token.
``` candid
type Callback = func (txn: TxnRecord) -> ();
```

## Implementation
Different implementations are being written by various teams.
#### Example implementations
- [ICLighthouse DRC20](https://github.com/iclighthouse/DRC_standards/tree/main/DRC20/examples/ICLighthouse/)
- [DIP20 Added DRC20 Extension](https://github.com/iclighthouse/DRC_standards/tree/main/DRC20/examples/dip20-drc20)  

## References
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
