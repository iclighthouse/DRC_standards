# DRC20

* [DRC20](#drc20)
   * [Introduction](#introduction)
   * [Installation](#installation)
   * [Usages](#usages)
      * [1. Use with the dfx command](#1-use-with-the-dfx-command)
      * [2. Calling in the actor](#2-calling-in-the-actor)

## Introduction

A standard interface for Dfinity tokens. The standard complies with [ERC20](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md) interface specification, and has some improvements to match IC network features.

## Installation

**Navigate to a the sub directory and start a local development network**

````tex
dfx start --clean --background
````

**Create canisters**

````tex
dfx canister --no-wallet create --all 
````

**build code**

````tex
dfx build
````

**Install code for token canister**

````tex
dfx canister --no-wallet install Token --argument='(record { totalSupply=100000000; decimals=4; gas=variant{token=10}; name=opt "ICLTokenTest"; symbol=opt "ICLTest"; metadata=null; founder=null;})'
````

## Usages

### 1. Use with the dfx command

**transfer**

Transfers _value amount of tokens from caller's account to address _to, returns type TxnResult.

````tex
dfx canister call Token transfer '("3rpzj-jp7vd-zfai5-zhllw-pqqxi-7bfer-mds4c-5rrpo-nkgq7-3bkrg-oqe",1000,null)'
````

**approve**

Allows `_spender` to withdraw from your account multiple times, up to the `_value` amount.

````tex
dfx canister call Token approve '("3rpzj-jp7vd-zfai5-zhllw-pqqxi-7bfer-mds4c-5rrpo-nkgq7-3bkrg-oqe",500)'
````

**balanceOf**

Returns the account balance of the given account `_owner`, not including the locked balance.

````tex
dfx canister call Token balanceOf '("cqiyt-v33t3-d5en2-bkufw-tnjbo-z5oxw-hyclw-x7ew3-ybpxg-jomqj-lae")'
````

**allowance**

Returns the amount which `_spender` is still allowed to withdraw from `_owner`.

````tex
dfx canister call Token allowance '("3rpzj-jp7vd-zfai5-zhllw-pqqxi-7bfer-mds4c-5rrpo-nkgq7-3bkrg-oqe","cqiyt-v33t3-d5en2-bkufw-tnjbo-z5oxw-hyclw-x7ew3-ybpxg-jomqj-lae")'
````



### 2. Calling in the actor

````tex
import DRC20 "DRC20";

var token: DRC20.DRC20 = actor("xxxxx-xxxxx-xx");

public func testTransfer() {
	let res = await token.transfer(Principal.toText([user's principal]), [amount], null);

	switch(res){
        case(#ok(txid)){  .....  };
        case(_){  ....  };
    };
	...
};
````



   

