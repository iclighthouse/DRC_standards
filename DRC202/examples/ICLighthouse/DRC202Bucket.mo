/**
 * Module     : DRC202Bucket.mo
 * Author     : ICLighthouse Team
 * License    : Apache License 2.0
 * Stability  : Experimental
 * Github     : https://github.com/iclighthouse/DRC_standards/
 */
import Prim "mo:⛔";
import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Time "mo:base/Time";
import Trie "mo:base/Trie";
import Cycles "mo:base/ExperimentalCycles";
import CyclesWallet "./sys/CyclesWallet";
import TokenRecord "./lib/TokenRecord";
import DRC207 "./lib/DRC207";
import Tools "./lib/Tools";
import Hex "./lib/Hex";
import Hash256 "./lib/Hash256";

shared(installMsg) actor class BucketActor() = this {
    type Bucket = TokenRecord.Bucket;
    type BucketInfo = TokenRecord.BucketInfo;
    type Token = TokenRecord.Token;
    type Txid = TokenRecord.Txid;  
    type Sid = TokenRecord.Sid;
    type TxnRecord = TokenRecord.TxnRecord;

    private stable var owner: Principal = installMsg.caller;
    private var bucketVersion: Nat8 = 1;
    // private stable var data: Trie.Trie<Sid, ([Nat8], Time.Time)> = Trie.empty(); 
    private stable var database: Trie.Trie<Sid, [([Nat8], Time.Time)]> = Trie.empty(); 
    private stable var count: Nat = 0;
    private stable var lastStorage: (Sid, Time.Time) = (Blob.fromArray([]), 0);

    private func _onlyOwner(_caller: Principal) : Bool {
        return _caller == owner;
    };
    private func key(t: Sid) : Trie.Key<Sid> { return { key = t; hash = Blob.hash(t) }; };

    private func _store(_sid: Sid, _data: [Nat8]) : (){
        let now = Time.now();
        var values : [([Nat8], Time.Time)] = [(_data, now)];
        switch(Trie.get(database, key(_sid), Blob.equal)){
            case(?(items)){ values := Tools.arrayAppend(items, values); };
            case(_){};
        };
        let res = Trie.put(database, key(_sid), Blob.equal, values);
        database := res.0;
        switch (res.1){
            case(?(v)){ lastStorage := (_sid, now); };
            case(_){ count += 1; lastStorage := (_sid, now); };
        };
    };
    private func _get(_sid: Sid) : ?([Nat8], Time.Time){
        switch(Trie.get(database, key(_sid), Blob.equal)){
            case(?(values)){
                if (values.size() > 0){
                    return ?values[values.size() - 1];
                }else{ return null; };
            };
            case(_){ return null; };
        };
    };

    public shared(msg) func storeBytes(_sid: Sid, _data: [Nat8]) : async (){
        assert(_onlyOwner(msg.caller));
        _store(_sid, _data);
    };
    public shared(msg) func storeBytesBatch(batch: [(_sid: Sid, _data: [Nat8])]) : async (){
        assert(_onlyOwner(msg.caller));
        for ((_sid, _data) in batch.vals()){
            _store(_sid, _data);
        };
    };
    public shared(msg) func store(_sid: Sid, _txn: TxnRecord) : async (){
        assert(_onlyOwner(msg.caller));
        let _data = TokenRecord.encode(_txn);
        _store(_sid, _data);
    };
    public shared(msg) func storeBatch(batch: [(_sid: Sid, _txn: TxnRecord)]) : async (){
        assert(_onlyOwner(msg.caller));
        for ((_sid, _txn) in batch.vals()){
            _store(_sid, TokenRecord.encode(_txn));
        };
    };
    public query func txnBytes(_token: Token, _txid: Txid) : async ?([Nat8], Time.Time){
        let _sid = TokenRecord.generateSid(_token, _txid);
        return _get(_sid);
    };
    public query func txnBytesHistory(_token: Token, _txid: Txid) : async [([Nat8], Time.Time)]{
        let _sid = TokenRecord.generateSid(_token, _txid);
        switch(Trie.get(database, key(_sid), Blob.equal)){
            case(?(values)){
                return values;
            };
            case(_){ return []; };
        };
    };
    public query func txnBytes2(_sid: Sid) : async ?([Nat8], Time.Time){
        return _get(_sid);
    };
    public query func txn(_token: Token, _txid: Txid) : async ?(TxnRecord, Time.Time){
        let _sid = TokenRecord.generateSid(_token, _txid);
        switch(Trie.get(database, key(_sid), Blob.equal)){
            case(?(values)){
                if (values.size() > 0){
                    let _data = values[values.size() - 1];
                    return ?(TokenRecord.decode(_data.0), _data.1);
                }else{ return null; };
            };
            case(_){ return null; };
        };
    };
    public query func txnHistory(_token: Token, _txid: Txid) : async [(TxnRecord, Time.Time)]{
        let _sid = TokenRecord.generateSid(_token, _txid);
        switch(Trie.get(database, key(_sid), Blob.equal)){
            case(?(values)){
                return Array.map<([Nat8],Time.Time), (TxnRecord, Time.Time)>(values, func (a:([Nat8],Time.Time)): (TxnRecord, Time.Time){
                    return (TokenRecord.decode(a.0), a.1)
                });
            };
            case(_){ return []; };
        };
    };
    public query func txnHash(_token: Token, _txid: Txid, _index: Nat) : async ?Hex.Hex{
        let _sid = TokenRecord.generateSid(_token, _txid);
        switch(Trie.get(database, key(_sid), Blob.equal)){
            case(?(values)){
                return ?Hex.encode(Hash256.hash(null, Blob.toArray(to_candid(TokenRecord.decode(values[_index].0)))));
            };
            case(_){ return null; };
        };
    };
    public query func txnBytesHash(_token: Token, _txid: Txid, _index: Nat) : async ?Hex.Hex{
        let _sid = TokenRecord.generateSid(_token, _txid);
        switch(Trie.get(database, key(_sid), Blob.equal)){
            case(?(values)){
                return ?Hex.encode(Hash256.hash(null, values[_index].0));
            };
            case(_){ return null; };
        };
    };

    public query func bucketInfo() : async BucketInfo{
        return {
            cycles = Cycles.balance();
            memory = Prim.rts_memory_size();
            heap = Prim.rts_heap_size();
            stableMemory = Nat32.fromNat(Nat64.toNat(Prim.stableMemorySize() / 1024 /1024)); //M
            count = count;
        };
    };
    public query func last() : async (Sid, Time.Time){
        return lastStorage;
    };

    // receive cycles
    public func wallet_receive(): async (){
        let amout = Cycles.available();
        let accepted = Cycles.accept(amout);
    };
    //cycles withdraw: _onlyOwner
    public shared(msg) func cyclesWithdraw(_wallet: Principal, _amount: Nat): async (){
        assert(_onlyOwner(msg.caller));
        let cyclesWallet: CyclesWallet.Self = actor(Principal.toText(_wallet));
        let balance = Cycles.balance();
        var value: Nat = _amount;
        if (balance <= _amount) {
            value := balance;
        };
        Cycles.add(value);
        await cyclesWallet.wallet_receive();
        //Cycles.refunded();
    };
    
    // DRC207 ICMonitor
    /// DRC207 support
    public query func drc207() : async DRC207.DRC207Support{
        return {
            monitorable_by_self = false;
            monitorable_by_blackhole = { allowed = true; canister_id = ?Principal.fromText("7hdtw-jqaaa-aaaak-aaccq-cai"); };
            cycles_receivable = true;
            timer = { enable = false; interval_seconds = null; };  
        };
    };
    /// canister_status
    // public func canister_status() : async DRC207.canister_status {
    //     let ic : DRC207.IC = actor("aaaaa-aa");
    //     await ic.canister_status({ canister_id = Principal.fromActor(this) });
    // };
    /// receive cycles
    // public func wallet_receive(): async (){
    //     let amout = Cycles.available();
    //     let accepted = Cycles.accept(amout);
    // };
    /// timer tick
    // public func timer_tick(): async (){
    //     //
    // };

    // system func postupgrade() {
    //     for ((k, v) in Trie.iter(data)) {
    //         database := Trie.put(database, key(k), Blob.equal, [v]).0;
    //     };
    // };
}