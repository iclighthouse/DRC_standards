/**
 * Module     : DRC202Bucket.mo
 * Author     : ICLighthouse Team
 * License    : Apache License 2.0
 * Stability  : Experimental
 * Github     : https://github.com/iclighthouse/DRC_standards/
 */
import Prim "mo:⛔";
import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import Time "mo:base/Time";
import Trie "mo:base/Trie";
import Cycles "mo:base/ExperimentalCycles";
import CyclesWallet "./sys/CyclesWallet";
import TokenRecord "./lib/TokenRecord";
import DRC207 "./lib/DRC207";

shared(installMsg) actor class BucketActor() = this {
    type Bucket = TokenRecord.Bucket;
    type BucketInfo = TokenRecord.BucketInfo;
    type Token = TokenRecord.Token;
    type Txid = TokenRecord.Txid;  
    type Sid = TokenRecord.Sid;
    type TxnRecord = TokenRecord.TxnRecord;

    private stable var owner: Principal = installMsg.caller;
    private var bucketVersion: Nat8 = 1;
    private stable var data: Trie.Trie<Sid, ([Nat8], Time.Time)> = Trie.empty(); 
    private stable var count: Nat = 0;
    private stable var lastStorage: (Sid, Time.Time) = (Blob.fromArray([]), 0);

    private func _onlyOwner(_caller: Principal) : Bool {
        return _caller == owner;
    };
    private func key(t: Sid) : Trie.Key<Sid> { return { key = t; hash = Blob.hash(t) }; };

    public shared(msg) func storeBytes(_sid: Sid, _data: [Nat8]) : async (){
        assert(_onlyOwner(msg.caller));
        let now = Time.now();
        let res = Trie.put(data, key(_sid), Blob.equal, (_data, now));
        data := res.0;
        switch (res.1){
            case(?(v)){ lastStorage := (_sid, now); };
            case(_){ count += 1; lastStorage := (_sid, now); };
        };
    };
    public shared(msg) func store(_sid: Sid, _txn: TxnRecord) : async (){
        assert(_onlyOwner(msg.caller));
        let _data = TokenRecord.encode(_txn);
        let now = Time.now();
        let res = Trie.put(data, key(_sid), Blob.equal, (_data, now));
        data := res.0;
        switch (res.1){
            case(?(v)){ lastStorage := (_sid, now); };
            case(_){ count += 1; lastStorage := (_sid, now); };
        };
    };
    public query func txnBytes(_token: Token, _txid: Txid) : async ?([Nat8], Time.Time){
        let _sid = TokenRecord.generateSid(_token, _txid);
        return Trie.get(data, key(_sid), Blob.equal);
    };
    public query func txnBytes2(_sid: Sid) : async ?([Nat8], Time.Time){
        return Trie.get(data, key(_sid), Blob.equal);
    };
    public query func txn(_token: Token, _txid: Txid) : async ?(TxnRecord, Time.Time){
        let _sid = TokenRecord.generateSid(_token, _txid);
        let _data = Trie.get(data, key(_sid), Blob.equal);
        switch (_data){
            case(?(v)){
                return ?(TokenRecord.decode(v.0), v.1);
            };
            case(_){ return null; };
        };
    };

    public query func bucketInfo() : async BucketInfo{
        return {
            cycles = Cycles.balance();
            memory = Prim.rts_memory_size();
            heap = Prim.rts_heap_size();
            stableMemory = Prim.stableMemorySize();
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
    public func drc207() : async DRC207.DRC207Support{
        return {
            monitorable_by_self = true;
            monitorable_by_blackhole = { allowed = true; canister_id = ?Principal.fromText("7hdtw-jqaaa-aaaak-aaccq-cai"); };
            cycles_receivable = true;
            timer = { enable = false; interval_seconds = null; }; 
        };
    };
    /// canister_status
    public func canister_status() : async DRC207.canister_status {
        let ic : DRC207.IC = actor("aaaaa-aa");
        await ic.canister_status({ canister_id = Principal.fromActor(this) });
    };
    /// receive cycles
    // public func wallet_receive(): async (){
    //     let amout = Cycles.available();
    //     let accepted = Cycles.accept(amout);
    // };
    /// timer tick
    // public func timer_tick(): async (){
    //     //
    // };

}