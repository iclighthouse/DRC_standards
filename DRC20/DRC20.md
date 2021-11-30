***
DRC: 20  
Title: Dfinity Fungible Token Standard  
Author: Avida <avida.life@hotmail.com>, Simpson <icpstaking-wei@hotmail.com>  
Status: Drafting  
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

* Consistency of holder's account-id.

    ICP Ledger canister uses account-id(address) as account identifier, while most other canisters use principal-id as account identifier. It brings complexity to users. This standard uses **account-id** as account identity, supports `subaccount`, and is compatible with the use of `principal-id`.

* Using the pub/sub model instead of the event mechanism.

    Dfinity does not have an effective event notification mechanism, and the off-chain SDK needs to actively query the network status. In another scenario, the application canister can use the publisher-subscriber model to subscribe to token canister’s messages and execute callback methods. Therefore, this standard adds **subscribe()** method. Subscribers need to implemente callback methods for **onTransfer**, **onLock**, **onExecute**, and **onApprove** messages. The query history records method can be used as a supplement when the subscriber fails to receive a message.

* Solving malicious exploits of approvals.

    In order to prevent the abuse of the approval method and facilitate risk management, this standard adds **approvals()** method to facilitate holders to check their approvals.

* Transaction records storage and query.

    Dfinity does not store smart contract transaction records in blocks like ethereum. Token canister needs to keep transaction record data by itself. The storage space of canister is limited and it is dangerous to store all transaction records in one canister. This standard provides the **txnQuery()** method for querying the recent transaction records.  It is recommended that only the recent records be kept in the token canister, and more history records can be stored in a separate canister. 

* Preventing canister cycles balance attack.

    According to IC network rules, the caller of canister is not required to pay gas, and it is up to canister to pay gas. It may lead to ddos attacks. So the token canister should ask the caller of the update call to pay gas. This standard adds the **gas()** method to help the caller estimate the cost of gas. The setGas method is not included in the standard, it is up to the developers to decide, it may be a fixed fee or set through an external governance canister. 

* Lock/execute model improves atomicity.

    Canister's asynchronous messaging model does not provide atomicity guarantees for cross-canister transfers. The non-atomicity of cross-canister transfers is one of the technical features of IC networks that cannot be solved at the system level and needs to consider designing for atomicity within the application logic. For example, creating logical locks, and escrowing token through a middleman.
    Creating a two-phase transfer structure can provide the underlying functionality to improve atomicity. Therefore, **lockTransfer()/lockTransferFrom()** and **executeTransfer()** methods are added to the standard. 

**More Issues:**

* Immutability and decentralization

    There are two important factors for keeping token decentralized.
    (1) The immutability of the Canister code. The controller of canister can be set to the blackhole address if necessary. 
    (2) Equal rights and no special permission roles. If there is a need to manage canister, it is recommended to use governance canister to solve. 

* Preventing re-entrance attacks

   Token canister calls to the callback method carry the risk of re-entrance attacks. Measures: Collect gas from the sender and update the canister state before the callback call. 

* Mint and burn methods
    
    Token distribution rules and economic models should be considered by the token issuer. It is better practice that the token does not contain the mint() and burn() methods. Developers can extend this if they really need to. If you just need the burn() method, _807077e900000000000000000000000000000000000000000000000000000000_(this's 0 address with checksum) can be used as the blackhole address.

## Specification

## Token

DRC20 Token Contract.

### Types

``` candid
type Metadata = record {
    name: text;
    content: text;
};
type Gas = variant {
    cycles: nat;
    token: nat;
    noFee;
};
/* Address: principal string or account-id hex */
type Address = text;
type AccountId = blob;
/* Txid:
   Require unique txid in a token. It is recommended to use DRC202 standard to generate txid.
*/
type Txid = blob;
type TxnResult = variant {
    ok: Txid;
    err: record { 
        code: variant {
            InsufficientBalance;
            InsufficientAllowance;
            InsufficientGas;
            LockedTransferExpired;
            UndefinedError;
        };
        message: text;
    };
};
type ExecuteType = variant {
    fallback;  /* operator with access: _decider(anytime), _from(when expired). */
    sendAll;  /* operator with access: _decider(when not expired). */
    send: nat;  /*  operator with access: _decider(when not expired). */
};
type Operation = variant {
    transfer: record {
        action: variant {
            send;
            mint;
            burn;
        };
    };
    lockTransfer: record {
        locked: nat;  /* be locked for the amount */
        expiration: int;  /* Expiration timestamp(Time.Time) = lockTransferTimestamp + _timeout */
        decider: AccountId; /* Who has access to execute the executeTransfer() before it expires */
    };
    executeTransfer: record {
        lockedTxid: Txid;
        fallback: nat; /* `from` receives back the amount */
    };
    approve: record {
        allowance: nat;
    };
};
type Transaction = record {
    from: AccountId;
    to: AccountId;
    value: nat;   /* `to` receives the amount (If lockTransfer operation, value SHOULD be 0)  */
    operation: Operation;
    data: opt blob;
};
type TxnRecord = record {
    txid: Txid;
    caller: principal; /* It could be: sender/spender/decider */
    timestamp: int;
    index: nat;
    nonce: nat;
    gas: Gas;
    transaction: Transaction;
};
type Callback = func (record: TxnRecord) -> ();
type MsgType = variant {
    onTransfer;
    onLock;
    onExecute;
    onApprove;
};
type Subscription = record {
    callback: Callback;
    msgTypes: vec MsgType;
};
type Allowance = record {
    spender: AccountId;
    remaining: nat;
};
type TxnQueryRequest = variant {
    txnCountGlobal;
    txnCount: record { owner: Address; };
    getTxn: record { txid: Txid; };
    lastTxidsGlobal;
    lastTxids: record { owner: Address; };
    lockedTxns: record { owner: Address; };
};
type TxnQueryResponse = variant {
    txnCountGlobal: nat;
    txnCount: nat;
    getTxn: opt TxnRecord;
    lastTxidsGlobal: vec Txid;
    lastTxids: vec Txid;
    lockedTxns: record { lockedBalance: nat; txns: vec TxnRecord; };
};
type InitArgs = record {
    totalSupply: nat;
    decimals: nat8;
    gas: Gas;
    name: opt text;
    symbol: opt text;
    metadata: opt vec Metadata;
    founder: opt Address;
};
```

### Methods

**NOTES**:
 - The following specifications use syntax from Candid 
 - The optional parameter `_sa` is the subaccount of the caller, which is a 32 bytes nat8 array. If length of `_sa` is less than 32 bytes, it will be prepended with [0] to make up.
 - The optional parameter `_data` is the custom data provided by the caller, which can be used for parameters of callback, memo, etc. The recommended specification is a _3-byte_ protocol name ("DRC", [68,82,67]) + _1-byte_ version (e.g., [1]) + _1-byte_ nonce-flag (0: no nonce; 1: filled nonce. e.g., [1]) + _4-byte_ caller's nonce (e.g., [0,0,0,1], if nonce-flag is 0, nonce is filled with [0,0,0,0]) + custom calldata no more than 65528 bytes (e.g., using candid encoding format, 4-byte method name hash + arguments data). The nonce value here is similar to the nonce in ethereum transactions. if the caller specifies a nonce according to the specification, the transaction will be rejected when given the wrong nonce.
 
#### standard

Returns standard name. E.g. `"DRC20 1.0"`.  
OPTIONAL - This method can be used to improve usability, but the value may not be present.
``` candid
standard: () -> (text) query;
```
#### name

Returns the name of the token. E.g. `"ICLighthouseToken"`.  
OPTIONAL - This method can be used to improve usability, but the value may not be present.
``` candid
name: () -> (text) query;
```
#### symbol
Returns the symbol of the token. E.g. `"ICL"`.  
OPTIONAL - This method can be used to improve usability, but the value may not be present.
``` candid
symbol: () -> (text) query;
```
#### decimals
Returns the number of decimals the token uses. E.g. `8`, means to divide the token amount by `100000000` to get its user representation.  
``` candid
decimals: () -> (nat8) query;
```
#### metadata
Returns the extend metadata info of the token, It's Metadata type. E.g. `'vec {record { name: "logo"; content: "data:img/jpg;base64,iVBOR....";}; }'`.    
OPTIONAL - This method can be used to improve usability, but the value may not be present.
``` candid
metadata: () -> (vec Metadata) query;
```
#### cyclesReceive
Sends/donates cycles to the token canister in `_account`'s name, and return cycles balance of the account. If the parameter `_account` is null, it means donation. 
OPTIONAL - This method can be used to improve usability, but the value may not be present.
``` candid
cyclesReceive: (_account: opt Address) -> (balance: nat);
```
#### cyclesBalanceOf
Returns the cycles balance of the given account `_owner` in the token.  
OPTIONAL - This method can be used to improve usability, but the value may not be present.
``` candid
cyclesBalanceOf: (_owner: Address) -> (balance: nat) query;
```
#### gas
Returns the transaction fee of the token. E.g. `"variant { token=10000000 }"`.  
*Note* Support `cycles`, `token` as gas charging method. If selected `token` as gas, it will be additionally charged from the balance of account `_from`, not be charged from the `_value` of transfer().
``` candid
gas: () -> (Gas) query;
```
#### totalSupply
Returns the total token supply.
``` candid
totalSupply: () -> (nat) query;
```
#### balanceOf
Returns the account balance of the given account `_owner`, not including the locked balance. 
``` candid
balanceOf: (_owner: Address) -> (balance: nat) query;
```
#### transfer
Transfers `_value` amount of tokens from caller's account to address `_to`, returns type `TxnResult`.  
On success, the returned TxnResult contains the txid. The `txid` is generated in the transaction, is unique in the token transactions. Recommended method of generating txid(DRC202 Standard): convert token's canisterId, caller's accountId, and caller's nonce into [nat8] arrays respectively, and join them together as `txInfo: [nat8]`. Then get the `txid` value as: "000000"(big-endian 4-bytes, `encode(caller.nonce)`) + "0000..00"(28-bytes,`sha224(txInfo)`).    
*Note* Transfers of 0 values MUST be treated as normal transfers. An account transfer to itself is ALLOWED. 
``` candid
transfer: (_to: Address, _value: nat, _sa: opt vec nat8, _data: opt blob) -> (result: TxnResult);
```
#### transferFrom
Transfers `_value` amount of tokens from address `_from` to address `_to`, returns type `TxnResult`.
The `transferFrom` method is used for allowing contracts to transfer tokens on your behalf. This can be used for example to allow a contract to transfer tokens on your behalf and/or to charge fees in sub-currencies. The caller is `spender` who SHOULD be authorized by the `_from` account and have an `allowance(_from, _spender)` value greater than `_value`.  
*Note* Transfers of 0 values MUST be treated as normal transfers. `_from` account transfer to itself is ALLOWED.
``` candid
transferFrom: (_from:Address, _to: Address, _value: nat, _sa: opt vec nat8, _data: opt blob) -> (result: TxnResult);
```
#### lockTransfer
Locks a transaction, specifies a `_decider` who can decide the execution of this transaction, and sets an expiration period `_timeout` seconds after which the locked transaction will be unlocked. The parameter _timeout SHOULD not be greater than 1000000 seconds.  
Creating a two-phase transfer structure can improve atomicity. The process is, (_owner) `lock the transaction` -- (_decider) `execute the transaction` or (_owner) `fallback the transaction when expired`
``` candid
lockTransfer: (_to: Address, _value: nat, _timeout: nat32, _decider: opt Address, _sa: opt vec nat8, _data: opt blob) -> (result: TxnResult);
```
#### lockTransferFrom
`spender` locks a transaction.
``` candid
lockTransferFrom: (_from: Address, _to: Address, _value: nat, _timeout: nat32, _decider: opt Address, _sa: opt vec nat8, _data: opt blob) -> (result: TxnResult);
```
#### executeTransfer
The `decider` executes the locked transaction `_txid`, or the `owner` can fallback the locked transaction after the lock has expired.
``` candid
executeTransfer: (_txid: Txid, _executeType: ExecuteType, _sa: opt vec nat8) -> (result: TxnResult);
```
#### txnQuery
Queries the transaction records information.  
Query type `_request`:  
#txnCountGlobal: returns global transaction count.  
#txnCount: returns `owner`'s transaction count. It is the nonce value of his next transaction.    
#getTxn: returns details of the transaction with id `txid`.  
#lastTxidsGlobal: returns the latest transaction txids of the global.   
#lastTxids: returns `owner`'s latest transaction txids.  
#lockedTxns: returns the locked balance of `owner`, and the locked transaction records.
``` candid
txnQuery: (_request: TxnQueryRequest) -> (response: TxnQueryResponse) query;
```
#### subscribe
Subscribes to the token's messages, giving the callback function and the types of messages as parameters. Subscribers will only receive messages that are related to them (the subscriber is transaction‘s _from, _to, _spender, or _decider).
The subscriber SHOULD be a canister, Implementing callback functions in the code.
``` candid
subscribe: (_callback: Callback, _msgTypes: vec MsgType, _sa: opt vec nat8) -> bool;
```
#### subscribed
Returns the subscription status of the subscriber `_owner`.  
OPTIONAL - This method can be used to improve usability, but the value may not be present.
``` candid
subscribed: (_owner: Address) -> (result: opt Subscription) query;
```
#### approve
Allows `_spender` to withdraw from your account multiple times, up to the `_value` amount.
If this function is called again it overwrites the current allowance with `_value`.  
**NOTE**: When you execute `approve()` to authorize the spender, it may cause security problems, you can execute `approve(_spender, 0)` to deauthorize.
``` candid
approve: (_spender: Address, _value: nat, _sa: opt vec nat8) -> (result: TxnResult);
```
#### allowance
Returns the amount which `_spender` is still allowed to withdraw from `_owner`.
``` candid
allowance: (_owner: Address, _spender: Address) -> (remaining: nat) query;
```
#### approvals
Returns all your approvals with a non-zero amount.
``` candid
approvals: (_owner: Address) -> (allowances: vec Allowance) query;
```
### Subscriber's Callback
#### tokenCallback (customizable)
Token canister subscribers should implement a callback function for handling token published messages.
Message types are: `onTransfer`, `onLock`, `onExecute`, and `onApprove`. The callback function is given as an argument by calling `subscribe()` of token.
``` candid
type Callback = func (txn: TxnRecord) -> ();
```

## Implementation
Different implementations are being written by various teams.
#### Example implementations
- [ICLighthouse](https://github.com/iclighthouse/DRC_standards/tree/main/DRC20/examples/ICLighthouse/)

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
