
# DRC20: Fungible Token Standard
A standard interface for Dfinity tokens

## Latest upgrade: 

2022-11-20: Add drc20_transferBatch() method; Modify the length of _data to a maximum of 2KB.  

2022-8-21: Use the "drc20_" prefix as the standard method name.

2022-8-17: Method fee() replaces gas(); Upgraded examples.

2022-8-14: Upgraded examples; Added storage saving mode; Added `drc20_dropAccount` and `drc20_holdersCount` methods.

2022-8-11: Examples are compatible with [ICRC-1 standard](https://github.com/dfinity/ICRC-1).

2022-3-25: Refactoring example code; Using Trie instead of HashMap; Implementing DRC202. (Notes: This version is not compatible with the previous version and upgrading will result in data loss.)
 
## Abstract
A standard interface for Dfinity tokens. The standard complies with ERC20 interface specification, and has some improvements to match IC network features.

## Improvements

* Compatible with Principal and Account-id as Address, sub-account supported

* Using the pub/sub model for message notifications

* Improving transaction atomicity with a lock/execute two-phase transfer structure

* Scalability of transaction records storage, temporary storage in token canister and permanent storage in external canisters

* Gas mechanism to preventing DDos attack

* Compatibility with different token standards using the [CTSNC](https://github.com/iclighthouse/DRC_standards/tree/main/CTSNC) specification

## Features

* Immutability

* Scalability

* Improved atomicity

* Idempotency

* Governability

* Compatibility


## Resources

Standard: [https://github.com/iclighthouse/DRC_standards/tree/main/DRC20/DRC20.md](https://github.com/iclighthouse/DRC_standards/tree/main/DRC20/DRC20.md)   
[https://github.com/iclighthouse/DRC_standards/tree/main/DRC20/DRC20-CN.md](https://github.com/iclighthouse/DRC_standards/tree/main/DRC20/DRC20-CN.md)   
Example: [https://github.com/iclighthouse/DRC_standards/tree/main/DRC20/examples/ICLighthouse](https://github.com/iclighthouse/DRC_standards/tree/main/DRC20/examples/ICLighthouse)  
Comments: [https://github.com/iclighthouse/DRC_standards/issues/1](https://github.com/iclighthouse/DRC_standards/issues/1);

## Community

Twitter: [@ICLighthouse](https://twitter.com/ICLighthouse)  
Medium: [https://medium.com/@ICLighthouse](https://medium.com/@ICLighthouse)   
Discord: [https://discord.gg/FQZFGGq7zv](https://discord.gg/FQZFGGq7zv)  