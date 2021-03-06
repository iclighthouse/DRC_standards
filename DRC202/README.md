
# DRC202: Token Transaction Records Storage Standard
A standard interface for token transaction tecords scalable storage.

## Latest upgrade: 
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