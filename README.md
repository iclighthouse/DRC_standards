
# DRC_standards
Dfinity Request for Comments

## Compatibility Token Standard Namespace Convention
2022-3-2: Drafted.  
2022-12-5: Stable standard.  
Specification: https://github.com/iclighthouse/DRC_standards/tree/main/CTSNC
 
## DRC20: Fungible Token Standard 
2021-11-13: Drafted standard.  
2021-11-23: Implemented the example with motoko.  
2022-3-2: Improved compatibility, implemented DIP20 compatible example; added upgrade function.  
2022-3-25: Refactoring example code; Using Trie instead of HashMap; Implementing DRC202. (Notes: This version is not compatible with the previous version and upgrading will result in data loss.)  
2022-8-11: Examples are compatible with [ICRC-1 standard](https://github.com/dfinity/ICRC-1).  
2022-8-17: Method fee() replaces gas(); Upgraded examples.  
2022-8-21: Use the "drc20_" prefix as the standard method name.  
2022-11-20: Add drc20_transferBatch() method; Modify the length of _data to a maximum of 2KB; Modified Example.   
2022-12-5: Modified Example.  
2022-12-6: Stable standard.  

Standard: [https://github.com/iclighthouse/DRC_standards/tree/main/DRC20](https://github.com/iclighthouse/DRC_standards/tree/main/DRC20)  
Example: [https://github.com/iclighthouse/DRC_standards/tree/main/DRC20/examples/ICLighthouse](https://github.com/iclighthouse/DRC_standards/tree/main/DRC20/examples/ICLighthouse)  
Comments: [https://github.com/iclighthouse/DRC_standards/issues/1](https://github.com/iclighthouse/DRC_standards/issues/1);  

## DRC201: Governable Token Standard

TODO: Standard drafting and motoko example implementation

## DRC202: Token Transaction Records Storage Standard 

2022-1-3: Drafted standard.   
2022-1-17: Implemented the example with motoko.   
2022-3-25: Improved some features; provided Motoko module; wrote sample code; improved documentation.   
2022-8-11: Upgrade examples.  
2022-11-3: Add txnHistory() and txnBytesHistory().  
2022-11-20: Upgrade store() for batch storage of records into Bucket of DRC202.  
2022-11-28: Add txnHash().  
2022-12-5: Add txnBytesHash(); Modify Example.  

Standard: [https://github.com/iclighthouse/DRC_standards/tree/main/DRC202](https://github.com/iclighthouse/DRC_standards/tree/main/DRC202)  
Example: [https://github.com/iclighthouse/DRC_standards/tree/main/DRC202/examples/ICLighthouse](https://github.com/iclighthouse/DRC_standards/tree/main/DRC202/examples/ICLighthouse)  
Comments: [https://github.com/iclighthouse/DRC_standards/issues/4](https://github.com/iclighthouse/DRC_standards/issues/4);  

## DRC203: Token Mining Standard

TODO: Standard drafting and motoko example implementation

## DRC204: Token Swap Standard

TODO: Standard drafting and motoko example implementation

## DRC205: Swap Transaction Records Storage Standard

2022-3-10: Drafted standard.   
2022-3-25: Implemented the example with motoko.   
2022-8-11: Upgrade examples. 
2022-9-20: Update the data structure TxnRecord.  
2022-11-3: Add txnHistory() and txnBytesHistory().  
2022-11-20: Upgrade store() for batch storage of records into Bucket of DRC205.  
2022-11-28: Add txnHash(); fix bugs.  
2022-12-5: Add txnBytesHash(); Modify Example.  

Standard: [https://github.com/iclighthouse/DRC_standards/tree/main/DRC205](https://github.com/iclighthouse/DRC_standards/tree/main/DRC205)  
Example: [https://github.com/iclighthouse/DRC_standards/tree/main/DRC205/examples/ICLighthouse](https://github.com/iclighthouse/DRC_standards/tree/main/DRC205/examples/ICLighthouse)  



## DRC207: Monitorable Canister standards

2022-9-20: Implemented the example with motoko.   

## Community

Twitter: [@ICLighthouse](https://twitter.com/ICLighthouse)  
Medium: [https://medium.com/@ICLighthouse](https://medium.com/@ICLighthouse)   
Discord: [https://discord.gg/FQZFGGq7zv](https://discord.gg/FQZFGGq7zv)  