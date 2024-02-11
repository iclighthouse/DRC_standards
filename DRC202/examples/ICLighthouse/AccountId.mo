import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import Nat8 "mo:base/Nat8";
import Trie "mo:base/Trie";
import Option "mo:base/Option";
import Cycles "mo:base/ExperimentalCycles";
import Tools "mo:icl/Tools";
actor {
    type AccountId = Blob;
    type Account = { owner: Principal; subaccount: ?[Nat8] };
    type Index = Nat64;
    private let fee_: Nat = 10000;
    // private stable var accounts: Trie.Trie<AccountId, Account> = Trie.empty(); 
    private stable var database: Trie.Trie<AccountId, [Nat8]> = Trie.empty(); 
    private stable var database2: Trie.Trie<AccountId, [Nat8]> = Trie.empty(); // have subaccount
    // TODO: New scheme
    // offset: Nat64 = (regionId * 4G + position)
    // (1) AccountId -> hash (index_aid)  put: Trie.Trie<hash, [offset]>
    // (2) Put (AccountId_32 + Account_64) to RegionN (position: index_aid). (119_304_647 reords per region)
    // total: max total 1_000_000_000 reords

    // private stable var index : Index = 0;
    // private stable var accounts: Trie.Trie<AccountId, Index> = Trie.empty(); 
    // private stable var regions : List.List<Region.Region> = List.nil();
    /// let region = Region.new();
    /// let beforeSize = Region.grow(region, 10);
    /// if (beforeSize == 0xFFFF_FFFF_FFFF_FFFF) {
    ///   throw Error.reject("Out of memory");
    /// };
    /// let afterSize = Region.size(region);
    private let sa_zero : [Nat8] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];

    private func keyb(t: Blob) : Trie.Key<Blob> { return { key = t; hash = Blob.hash(t) }; };

    private func encode(account: Account) : [Nat8]{ // max: 64 bytes
        var data: [Nat8] = [];
        let principal = Blob.toArray(Principal.toBlob(account.owner)); 
        data := Tools.arrayAppend(data, [Nat8.fromNat(principal.size())]);
        data := Tools.arrayAppend(data, principal);
        switch(account.subaccount){
            case(?(subaccount)){ 
                if (subaccount == sa_zero){ // 0
                    data := Tools.arrayAppend(data, [0: Nat8]);
                }else{ // 1
                    data := Tools.arrayAppend(data, [1: Nat8]);
                    data := Tools.arrayAppend(data, [Nat8.fromNat(subaccount.size())]);
                    data := Tools.arrayAppend(data, subaccount);
                };
            };
            case(null){ // 0
                data := Tools.arrayAppend(data, [0: Nat8]);
            };
        };
        return data;
    };

    private func decode(data: [Nat8]) : Account{
        var pos: Nat = 0;
        let ownerLength = Nat8.toNat(data[pos]);
        pos += 1;
        let owner = Tools.slice<Nat8>(data, pos, ?(pos+ownerLength-1));
        pos += ownerLength;
        let optionSubaccount: Nat8 = data[pos];
        var subaccount: ?[Nat8] = null; 
        pos += 1;
        switch(optionSubaccount){
            case(1: Nat8){
                let length = Nat8.toNat(data[pos]);
                pos += 1;
                subaccount := ?Tools.slice<Nat8>(data, pos, ?(pos+length-1));
                pos += length;
            };
            case(_){};
        };
        return {owner = Principal.fromBlob(Blob.fromArray(owner)); subaccount = subaccount};
    };
    // Test
    let account1: Account = {owner = Principal.fromText("gpapk-hqaaa-aaaak-aex4q-cai"); subaccount = ?[0:Nat8,0,0,0,0,43,120,227,205,145,132,213,228,170,130,38,236,240,117,107,144,181,228,94,96,181,213,255,239,44,108,118]};
    let temp1 = encode(account1);
    let test1 = decode(temp1);
    assert(account1 == test1);
    let account2: Account = {owner = Principal.fromText("gpapk-hqaaa-aaaak-aex4q-cai"); subaccount = null };
    let temp2 = encode(account2);
    let test2 = decode(temp2);
    assert(account2 == test2);

    public shared func put(_accounts: [Account]): async (){
        let amout = Cycles.available();
        assert(amout >= fee_);
        let accepted = Cycles.accept(fee_);
        for (account in _accounts.vals()){
            let accountId = Tools.principalToAccountBlob(account.owner, account.subaccount);
            if (Option.isNull(account.subaccount)){
                database := Trie.put(database, keyb(accountId), Blob.equal, encode(account)).0;
            }else{
                database2 := Trie.put(database2, keyb(accountId), Blob.equal, encode(account)).0;
            };
        };
    };

    public query func count() : async (Nat, Nat){
        return (Trie.size(database), Trie.size(database2));
    };
    public query func fromAccountId(_accountId: AccountId) : async ?Account{
        switch(Trie.get(database, keyb(_accountId), Blob.equal)){
            case(?data){
                return ?decode(data);
            };
            case(_){
                switch(Trie.get(database2, keyb(_accountId), Blob.equal)){
                    case(?data){
                        return ?decode(data);
                    };
                    case(_){
                        return null;
                    };
                };
            };
        };
    };

    public query func toAccountId(_account: Account) : async AccountId{
        return Tools.principalToAccountBlob(_account.owner, _account.subaccount);
    };

    public func wallet_receive(): async (){
        let amout = Cycles.available();
        let accepted = Cycles.accept(amout);
    };

    // system func postupgrade() {
    //     if (Trie.size(database) == 0){
    //         for ((accountId, account) in Trie.iter(accounts)){
    //             database := Trie.put(database, keyb(accountId), Blob.equal, encode(account)).0;
    //         };
    //     };
    // };

};