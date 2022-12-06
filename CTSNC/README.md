
# Compatibility token standard namespace convention

To avoid naming conflicts between different standards.
 
## Abstract

There are multiple different implementations of the Dfinity token (Fungible Token and Non-Fungible Token) standards and no consensus can be formed. This will be detrimental to the development of Defi on IC network.

IC Canister's methods are not allowed polymorphism, which creates a barrier to token compatibility.

CTSNC is a compatibility token standard namespace convention that provides compatibility and interoperability for different standards implementations. This is a convention (not mandatory) and is minimally intrusive for different implementations.

## Motivation

It enables compatibility between different token standards through namespace conventions and specifications.

## Features

- Forward Compatible
- Horizontally Compatible
- Scalable
- Minimally Intrusive

## Specification

The main interface implements a standard scheme with method names plus a namespace (prefixed with `xxx_`).
Optional compatible interfaces implement the standard scheme using the ERC20 method names, and/or the standard scheme using other standard prefixed method names.

### Specific public methods

Returns the list of supported token standards (standard name i. e. namespace), in lowercase letters, separated by "`; `". The format is similar to "`main_standard; compatible_standard1; compatible_standard2`". E.g. "`dip20; drc20`", "`dft`".  

``` candid
standard: () -> (text) query;
```

## Multi-standard compatibility example

### Main interface

Use the method names prefixed with standard name "xxx_" to implement the main standard of your choice.

``` candid
For example:

drc20_name: () -> (text) query;
drc20_symbol: () -> (text) query;
drc20_decimals: () -> (nat8) query;
drc20_totalSupply: () -> (nat) query;
drc20_balanceOf: (...) -> (...) query;
drc20_transfer: (...) -> (...);
drc20_transferFrom: (...) -> (...);
drc20_approve: (...) -> (...);
drc20_allowance: (...) -> (...);
...
```

### Optional compatibility interface

``` candid
For example 1:

name: () -> (text) query;
symbol: () -> (text) query;
decimals: () -> (nat8) query;
totalSupply: () -> (nat) query;
balanceOf: (...) -> (...) query;
transfer: (...) -> (...);
transferFrom: (...) -> (...);
approve: (...) -> (...);
allowance: (...) -> (...);
...

// dft
dft_name: () -> (text) query;
dft_symbol: () -> (text) query;
dft_decimals: () -> (nat8) query;
dft_totalSupply: () -> (nat) query;
dft_balanceOf: (...) -> (...) query;
dft_transfer: (...) -> (...);
dft_transferFrom: (...) -> (...);
dft_approve: (...) -> (...);
dft_allowance: (...) -> (...);
...
```

## Standard List
(Welcome to add new token standards!)

### Fungible Token

- dip20: https://github.com/Psychedelic/DIP20
- dft: https://github.com/Deland-Labs/dfinity-fungible-token-standard
- drc20: https://github.com/iclighthouse/DRC_standards/tree/main/DRC20
- ext: https://github.com/Toniq-Labs/extendable-token
- motokotoken: https://github.com/enzoh/motoko-token
- is20: https://github.com/infinity-swap/IS20
- ICRC-1: https://github.com/dfinity/ICRC-1/tree/main/standards/ICRC-1
- ICRC-2: https://github.com/dfinity/ICRC-1/tree/main/standards/ICRC-2

### Non-Fungible Token

- departureLabsnft: https://github.com/DepartureLabsIC/non-fungible-token
- ext: https://github.com/Toniq-Labs/extendable-token
- dip721: https://github.com/SuddenlyHazel/DIP721
- c3nft: https://github.com/C3-Protocol/NFT-standards

## Implementation

- DRC20: https://github.com/iclighthouse/DRC_standards/tree/main/DRC20/examples/ICLighthouse
- DIP20 Added DRC20 Extension: https://github.com/iclighthouse/DRC_standards/tree/main/DRC20/examples/dip20-drc20