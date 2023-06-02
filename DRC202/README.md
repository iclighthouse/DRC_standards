
# DRC202: Token Transaction Records Storage Standard
A standard interface for token transaction tecords scalable storage.

## Latest upgrade: 

2023-6-1: del txnBytesHash().  
2023-5-31: fix txnByAccountId().  
2023-5-22: add location(); modify Example.  
2023-5-17: Completed stable version.    
2023-5-17: add bucketList(); del bucketInfo(); modify Example.  
2023-2-2: fix type description; modify Example.  
2022-12-5: add txnBytesHash(); modify Example.  
2022-11-28: add txnHash().  
2022-11-20: upgrade store() for batch storage of records into Bucket of DRC202.  
2022-11-3: add txnHistory() and txnBytesHistory().  
2022-3-25: Improved some features; provided Motoko module; wrote sample code; improved documentation.  
 
## Abstract

DRC202 is a standard for scalable storage of token transaction records. It supports multi-token storage, automatic scaling to create storage canisters (buckets), and automatic routing of query records.

## Features

- Infinite scalability
- Automatic routing
- Multi-token support
- Transparency

## Resources

Standard: [https://github.com/iclighthouse/DRC_standards/tree/main/DRC202/DRC202.md](https://github.com/iclighthouse/DRC_standards/tree/main/DRC202/DRC202.md)   
Comments: [https://github.com/iclighthouse/DRC_standards/issues/4](https://github.com/iclighthouse/DRC_standards/issues/4);

**Public Storage Canister**
  
DRC202Proxy: https://github.com/iclighthouse/DRC_standards/tree/main/DRC202/examples/ICLighthouse/   
Main: y5a36-liaaa-aaaak-aacqa-cai    
Test: iq2ev-rqaaa-aaaak-aagba-cai   
Notes: Use y5a36-liaaa-aaaak-aacqa-cai to store token records that can be queried through the ICHouse blockchain explorer (http://ic.house).

**Motoko Module Package For Token Developer**

Motoko Module Package: https://github.com/iclighthouse/DRC_standards/blob/main/DRC202/examples/ICLighthouse/Example/lib/DRC202.mo 

Example: https://github.com/iclighthouse/DRC_standards/blob/main/DRC202/examples/ICLighthouse/Example/Example.mo   

The DRC20 standard has implemented the DRC202: https://github.com/iclighthouse/DRC_standards/blob/main/DRC20/examples/ICLighthouse/

The DIP20 standard has implemented the DRC202: https://github.com/iclighthouse/DRC_standards/blob/main/DRC202/examples/DIP20Example/


## Community

Twitter: [@ICLighthouse](https://twitter.com/ICLighthouse)  
Medium: [https://medium.com/@ICLighthouse](https://medium.com/@ICLighthouse)   
Discord: [https://discord.gg/FQZFGGq7zv](https://discord.gg/FQZFGGq7zv)  