# DRC20

DRC20 Token Factory: http://ictokens.com  

## Update:

[2023-3-20] modify Example.  

[2023-2-2] modify Example.  

[2022-12-5] Add txnBytesHash(); Upgraded Example.  

[2022-11-20] Add drc20_transferBatch() method; Modified ICPubSub and DRC202; Modify the length of _data to a maximum of 2KB.  

[2022-8-17] Method fee() replaces gas(); Upgraded examples.

[2022-8-14] Upgraded the example.

[2022-8-11] Compatible with [ICRC-1 standard](https://github.com/dfinity/ICRC-1).

## Introduction

A standard interface for Dfinity tokens. The standard complies with [ERC20](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md) interface specification, and has some improvements to match IC network features.

## Installation

**Navigate to a the sub directory and start a local development network**

````
dfx start --clean --background
````

**Create canisters**

````
dfx canister --no-wallet create --all 
````

**build code**

````
dfx build
````

**Install code for token canister**

````
dfx canister --no-wallet install Token --argument='(record { totalSupply=100000000; decimals=4; gas=variant{token=10}; name=opt "ICLTokenTest"; symbol=opt "ICLTest"; metadata=null; founder=null;})'
````

## Usages

### 1. Use with the dfx command

**transfer**

Transfers _value amount of tokens from caller's account to address _to, returns type TxnResult.

````
dfx canister call Token transfer '("<to_account>",<amount>,null,null,null)'
````

**approve**

Allows `_spender` to withdraw from your account multiple times, up to the `_value` amount.

````
dfx canister call Token approve '("<spender_account>",<amount>,null,null,null)'
````

**balanceOf**

Returns the account balance of the given account `_owner`, not including the locked balance.

````
dfx canister call Token balanceOf '("<owner_account>")'
````

**allowance**

Returns the amount which `_spender` is still allowed to withdraw from `_owner`.

````
dfx canister call Token allowance '("<owner_account>","<spender_account>")'
````



### 2. Calling in the actor

````
import DRC20 "DRC20";
import Principal "mo:base/Principal";

actor {
    var token: DRC20.DRC20 = actor("xxxxx-xxxxx-xx");

    public func testTransfer() : async () {

	let res = await token.transfer(Principal.toText([user's principal]), [amount], null, null, null);

	switch(res){
            case(#ok(txid)){  .....  };
            case(_){  ....  };
        };
	...
    };
}
````



   

