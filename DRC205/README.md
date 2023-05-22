
# DRC205: Swap Transaction Records Storage Standard
A common swap transaction record data type and scalability storage specification.
 
## Latest upgrade: 

2023-5-22: add location(); modify Example.  
2023-5-17: add bucketList(); del bucketInfo(); modify Example.  
2023-2-2: fix type description; modify Example.  
2022-12-5: add txnBytesHash(); modify Example.  
2022-11-28: add txnHash(); fix bugs.   
2022-11-20: upgrade store() for batch storage of records into Bucket of DRC205.  
2022-11-3: add txnHistory() and txnBytesHistory().

## Abstract
The DRC205 standard defines swap transaction record data structures, scalable storage interfaces, and swap application storage and query specifications.

## Features

* Generality
Suitable for multiple spot swap Dex to store transaction records.

* Scalability
Automatically and infinitely scalable according to canister storage capacity limit, using Bloom filter to solve the storage limit of index canister, easy to find records.

* Transparency
Stored transaction records are open and queryable, maintaining the transparency of the Dex.


## Resources

Standard: https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/DRC205.md   

**Public Storage Canister**

DRC205Proxy: https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/examples/ICLighthouse/  
Main: 6ylab-kiaaa-aaaak-aacga-cai   
Test: ix3cb-4iaaa-aaaak-aagbq-cai  
Notes: Use 6ylab-kiaaa-aaaak-aacga-cai to store swap records that can be queried through the ICHouse blockchain explorer (http://ic.house).

**Motoko Module Package For Dex Developer**

Motoko Module Package: https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/examples/ICLighthouse/Example/lib/DRC205.mo

Example: https://github.com/iclighthouse/DRC_standards/blob/main/DRC205/examples/ICLighthouse/Example/Example.mo  

## Community

Twitter: [@ICLighthouse](https://twitter.com/ICLighthouse)  
Medium: [https://medium.com/@ICLighthouse](https://medium.com/@ICLighthouse)   
Discord: [https://discord.gg/FQZFGGq7zv](https://discord.gg/FQZFGGq7zv)  