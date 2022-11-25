/**
 * Module     : DRC205Bucket.mo
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Github     : https://github.com/iclighthouse/DRC_standards/
 */
import Prim "mo:⛔";
import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Time "mo:base/Time";
import Array "mo:base/Array";
import Trie "mo:base/Trie";
import Cycles "mo:base/ExperimentalCycles";
import CyclesWallet "./sys/CyclesWallet";
import SwapRecord "./lib/SwapRecord";
import DRC207 "./lib/DRC207";
import Tools "./lib/Tools";

shared(installMsg) actor class BucketActor() = this {
    type Bucket = SwapRecord.Bucket;
    type BucketInfo = SwapRecord.BucketInfo;
    type AppId = SwapRecord.AppId;
    type Txid = SwapRecord.Txid;  
    type Sid = SwapRecord.Sid;
    type BalanceChange = SwapRecord.BalanceChange;
    type TxnRecordTemp = SwapRecord.TxnRecordTemp;
    type TxnRecord = SwapRecord.TxnRecord;

    private stable var owner: Principal = installMsg.caller;
    private var bucketVersion: Nat8 = 1;
    // private stable var data: Trie.Trie<Sid, ([Nat8], Time.Time)> = Trie.empty(); 
    private stable var database: Trie.Trie<Sid, [([Nat8], Time.Time)]> = Trie.empty(); 
    // private stable var txnData: Trie.Trie<Sid, (TxnRecordTemp, Time.Time)> = Trie.empty(); 
    // private stable var txnData2: Trie.Trie<Sid, (TxnRecord, Time.Time)> = Trie.empty(); 
    private stable var database2: Trie.Trie<Sid, [(TxnRecord, Time.Time)]> = Trie.empty(); 
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
    private func _store2(_sid: Sid, _data: TxnRecord) : (){
        let now = Time.now();
        var values : [(TxnRecord, Time.Time)] = [(_data, now)];
        switch(Trie.get(database2, key(_sid), Blob.equal)){
            case(?(items)){ values := Tools.arrayAppend(items, values); };
            case(_){};
        };
        let res = Trie.put(database2, key(_sid), Blob.equal, values);
        database2 := res.0;
        switch (res.1){
            case(?(v)){ lastStorage := (_sid, now); };
            case(_){ count += 1; lastStorage := (_sid, now); };
        };
    };
    private func _get2(_sid: Sid) : ?(TxnRecord, Time.Time){
        switch(Trie.get(database2, key(_sid), Blob.equal)){
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
        _store2(_sid, _txn);
    };
    public shared(msg) func storeBatch(batch: [(_sid: Sid, _txn: TxnRecord)]) : async (){
        assert(_onlyOwner(msg.caller));
        for ((_sid, _txn) in batch.vals()){
            _store2(_sid, _txn);
        };
    };
    public query func txnBytes(_app: AppId, _txid: Txid) : async ?([Nat8], Time.Time){
        let _sid = SwapRecord.generateSid(_app, _txid);
        return _get(_sid);
    };
    public query func txnBytesHistory(_app: AppId, _txid: Txid) : async [([Nat8], Time.Time)]{
        let _sid = SwapRecord.generateSid(_app, _txid);
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
    public query func txn(_app: AppId, _txid: Txid) : async ?(TxnRecord, Time.Time){
        let _sid = SwapRecord.generateSid(_app, _txid);
        return _get2(_sid);
    };
    public query func txnHistory(_app: AppId, _txid: Txid) : async [(TxnRecord, Time.Time)]{
        let _sid = SwapRecord.generateSid(_app, _txid);
        switch(Trie.get(database2, key(_sid), Blob.equal)){
            case(?(values)){
                return values;
            };
            case(_){ return []; };
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
    //     txnData2 := Trie.mapFilter(txnData, func (k:Sid, v:(TxnRecordTemp, Time.Time)): ?(TxnRecord, Time.Time){
    //         return ?({
    //             txid = v.0.txid;
    //             msgCaller = v.0.msgCaller;
    //             caller = v.0.caller;
    //             operation = v.0.operation;
    //             account = v.0.account;
    //             cyclesWallet = v.0.cyclesWallet;
    //             token0 = v.0.token0;
    //             token1 = v.0.token1;
    //             fee = v.0.fee;
    //             shares = v.0.shares;
    //             time = v.0.time;
    //             index = v.0.index;
    //             nonce = v.0.nonce;
    //             order = {token0Value = ?v.0.token0Value; token1Value = ?v.0.token1Value;};
    //             orderMode = v.0.orderType;
    //             orderType = null;
    //             filled = {token0Value = v.0.token0Value; token1Value = v.0.token1Value;};
    //             details = Array.map(v.0.details, func (item:{counterparty: Txid; token0Value: BalanceChange; token1Value: BalanceChange;}): 
    //             {counterparty: Txid; token0Value: BalanceChange; token1Value: BalanceChange; time: Time.Time;}{
    //                 {counterparty = item.counterparty; token0Value = item.token0Value; token1Value = item.token1Value; time = v.0.time; }
    //             });
    //             status = #Completed;
    //             data = v.0.data;
    //         }, v.1);
    //     });
    // };

    // system func postupgrade() {
    //     for ((k, v) in Trie.iter(data)) {
    //         database := Trie.put(database, key(k), Blob.equal, [v]).0;
    //     };
    //     for ((k, v) in Trie.iter(txnData2)) {
    //         database2 := Trie.put(database2, key(k), Blob.equal, [v]).0;
    //     };
    // };

}