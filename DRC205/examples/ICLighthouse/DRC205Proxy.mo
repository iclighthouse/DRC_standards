/**
 * Module     : DRC205Proxy.mo
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Canister   : 6ylab-kiaaa-aaaak-aacga-cai
 * Github     : https://github.com/iclighthouse/DRC_standards/
 */
import Prim "mo:⛔";
import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Nat32 "mo:base/Nat32";
import Blob "mo:base/Blob";
import Option "mo:base/Option";
import Time "mo:base/Time";
import Hash "mo:base/Hash";
import Binary "./lib/Binary";
import SHA224 "./lib/SHA224";
import Tools "./lib/Tools";
import Bloom "./lib/Bloom";
import Deque "mo:base/Deque";
import List "mo:base/List";
import Trie "mo:base/Trie";
import TrieMap "mo:base/TrieMap";
import Cycles "mo:base/ExperimentalCycles";
import CyclesWallet "./sys/CyclesWallet";
import SwapRecord "./lib/SwapRecord";
import DRC205Bucket "DRC205Bucket";
import DRC207 "./lib/DRC207";

shared(installMsg) actor class ProxyActor() = this {
    type Bucket = SwapRecord.Bucket;
    type BucketInfo = SwapRecord.BucketInfo;
    type AppId = SwapRecord.AppId;
    type AppInfo = SwapRecord.AppInfo;
    type AppCertification = SwapRecord.AppCertification;
    type Txid = SwapRecord.Txid;  
    type Sid = SwapRecord.Sid;
    type AccountId = SwapRecord.AccountId;
    type TxnRecord = SwapRecord.TxnRecord;
    type BloomFilter = Bloom.AutoScalingBloomFilter<Blob>;
    type DataType = {
        #Txn: TxnRecord;
        #Bytes: {txid: Txid; data: [Nat8]};
    };

    private var version_: Nat8 = 1;
    private var bucketCyclesInit: Nat = 200000000000;
    private var maxStorageTries: Nat = 3;
    private stable var owner: Principal = installMsg.caller;
    private stable var fee_: Nat = 100000000;  //cycles
    private stable var maxMemory: Nat = 3900 * 1024 * 1024; //3.8GB
    private stable var bucketCount: Nat = 0;
    private stable var appCount: Nat = 0;
    private stable var txnCount: Nat = 0;
    private stable var errCount: Nat = 0;
    private stable var lastTxns = Deque.empty<(index: Nat, app: AppId, indexInApp: Nat, txid: Txid)>();
    private stable var currentBucket: [(Bucket, BucketInfo)] = [];
    private stable var buckets: [Bucket] = [];
    private var blooms = TrieMap.TrieMap<Bucket, BloomFilter>(Principal.equal, Principal.hash);
    private stable var bloomsEntries : [(Bucket, [[Nat8]])] = []; // for upgrade
    private stable var apps: Trie.Trie<AppId, AppInfo> = Trie.empty(); 
    private stable var storeTxns = List.nil<(AppId, DataType, Nat)>();
    private stable var storeErrPool = List.nil<(AppId, DataType, Nat)>();
    // TODO private stable var certifications: Trie.Trie<App, [AppCertification]> = Trie.empty(); 

    private func _onlyOwner(_caller: Principal) : Bool {
        return _caller == owner;
    };
    private func keyb(t: Blob) : Trie.Key<Blob> { return { key = t; hash = Blob.hash(t) }; };
    private func keyp(t: Principal) : Trie.Key<Principal> { return { key = t; hash = Principal.hash(t) }; };
    private func _newBucket() : async Bucket {
        Cycles.add(bucketCyclesInit);
        let bucketActor = await DRC205Bucket.BucketActor();
        let bucket: Bucket = Principal.fromActor(bucketActor);
        let bucketInfo: BucketInfo = await bucketActor.bucketInfo();
        buckets := Array.append(buckets, [bucket]);
        currentBucket := [(bucket, bucketInfo)];
        blooms.put(bucket, Bloom.AutoScalingBloomFilter<Blob>(100000, 0.002, Bloom.blobHash));
        bucketCount += 1;
        return bucket;
    };
    private func _getBucket() : async Bucket{
        if (currentBucket.size() > 0){
            var bucket: Bucket = currentBucket[0].0;
            let bucketActor: DRC205Bucket.BucketActor = actor(Principal.toText(bucket));
            let bucketInfo: BucketInfo = await bucketActor.bucketInfo();
            currentBucket := [(bucket, bucketInfo)];
            if (bucketInfo.cycles < bucketCyclesInit/2){
                Cycles.add(bucketCyclesInit);
                let res = /*await*/ bucketActor.wallet_receive();
            };
            if (bucketInfo.memory >= maxMemory){
                bucket := await _newBucket();
            };
            return bucket;
        } else {
            return await _newBucket();
        };
    };
    private func _pushLastTxns(_app: AppId, _data: DataType) : (){
        switch(_data){
            case(#Txn(txn)){
                lastTxns := Deque.pushFront(lastTxns, (txnCount, _app, txn.index, txn.txid));
            };
            case(#Bytes(txn)){
                lastTxns := Deque.pushFront(lastTxns, (txnCount, _app, 0, txn.txid));
            };
        };
        var size = List.size(lastTxns.0) + List.size(lastTxns.1);
        while (size > 200){
            size -= 1;
            switch (Deque.popBack(lastTxns)){
                case(?(q, v)){
                    lastTxns := q;
                };
                case(_){};
            };
        };
    };
    private func _putApp(_app: AppId, _data: DataType) : (){
        var _count: Nat = 0;
        switch(Trie.get(apps, keyp(_app), Principal.equal)){
            case(?(info)){
                _count := info.count+1;
            };
            case(_){
                _count := 1;
                appCount += 1;
            };
        };
        switch(_data){
            case(#Txn(_txn)){
                apps := Trie.put(apps, keyp(_app), Principal.equal, {
                    lastIndex = _txn.index;
                    lastTxid = _txn.txid;
                    count = _count;
                }).0;
            };
            case(#Bytes(txn)){
                apps := Trie.put(apps, keyp(_app), Principal.equal, {
                    lastIndex = 0;
                    lastTxid = txn.txid;
                    count = _count;
                }).0;
            };
        };
    };
    private func _addBloom(_bucket: Bucket, _sid: Sid) : (){
        switch(blooms.get(_bucket)){
            case(?(bloom)){
                bloom.add(_sid);
                blooms.put(_bucket, bloom);
            };
            case(_){
                let bloom = Bloom.AutoScalingBloomFilter<Blob>(100000, 0.002, Bloom.blobHash);
                bloom.add(_sid);
                blooms.put(_bucket, bloom);
            };
        };
    };
    private func _checkBloom(_sid: Sid, _step: Nat) : (?Bucket, Bool){
        var step: Nat = 0;
        for ((bucket, bloom) in blooms.entries()){
            if (step < _step and bloom.check(_sid)){
                step += 1;
            }else if (step == _step and bloom.check(_sid)){
                return (?bucket, false);
            };
        };
        return (null, true);
    };
    private func _execStorage() : async (){
        let bucket: Bucket = await _getBucket();
        let bucketActor: DRC205Bucket.BucketActor = actor(Principal.toText(bucket));
        var _storeTxns = List.nil<(AppId, DataType, Nat)>();
        var item = List.pop(storeTxns);
        while (Option.isSome(item.0)){
            switch(item.0){
                case(?(app, dataType, callCount)){
                    if (callCount < maxStorageTries){
                        try{
                            switch(dataType){
                                case(#Txn(txn)){
                                    let sid = SwapRecord.generateSid(app, txn.txid);
                                    await bucketActor.store(sid, txn);
                                    _addBloom(bucket, sid);
                                };
                                case(#Bytes(txn)){
                                    let sid = SwapRecord.generateSid(app, txn.txid);
                                    await bucketActor.storeBytes(sid, txn.data);
                                    _addBloom(bucket, sid);
                                };
                            };
                            _putApp(app, dataType);
                            _pushLastTxns(app, dataType);
                            txnCount += 1;
                        } catch(e){ //push
                            errCount += 1;
                            _storeTxns := List.push((app, dataType, callCount+1), _storeTxns);
                        };
                    } else {
                        storeErrPool := List.push((app, dataType, 0), storeErrPool);
                    };
                };
                case(_){};
            };
            item := List.pop(item.1);
        };
        storeTxns := _storeTxns;
    };
    private func _reExecStorage() : async (){
        var item = List.pop(storeErrPool);
        while (Option.isSome(item.0)){
            switch(item.0){
                case(?(v)){
                    storeTxns := List.push(v, storeTxns);
                };
                case(_){};
            };
            item := List.pop(item.1);
        };
        await _execStorage();
    };

    public query func generateTxid(_app: Principal, _caller: Principal, _nonce: Nat): async Txid{
        let canister: [Nat8] = Blob.toArray(Principal.toBlob(_app));
        let caller: [Nat8] = Blob.toArray(Principal.toBlob(_caller));
        let nonce: [Nat8] = Binary.BigEndian.fromNat32(Nat32.fromNat(_nonce));
        let txInfo = Array.append(Array.append(canister, caller), nonce);
        let h224: [Nat8] = SHA224.sha224(txInfo);
        return Blob.fromArray(Array.append(nonce, h224));
    };


    public query func version() : async Nat8{
        return version_;
    };
    public query func fee() : async (cycles: Nat){
        return fee_;
    };
    public query func maxBucketMemory() : async (memory: Nat){
        return maxMemory;
    };
    public query func stats() : async {bucketCount: Nat; appCount: Nat; txnCount: Nat; errCount: Nat; storeErrPool: Nat}{
        return {
            bucketCount = bucketCount; 
            appCount = appCount; 
            txnCount = txnCount;
            errCount = errCount;
            storeErrPool = List.size(storeErrPool);
        };
    };
    public /*query*/ func bucketInfo(_bucket: ?Bucket) : async (Bucket, BucketInfo){
        switch(_bucket){
            case(?(bucket)){
                let bucketActor: DRC205Bucket.BucketActor = actor(Principal.toText(bucket));
                return (bucket, await bucketActor.bucketInfo());
            };
            case(_){
                return currentBucket[0];
            };
        };
    };
    public query func appInfo(_app: AppId) : async ?AppInfo{
        return Trie.get(apps, keyp(_app), Principal.equal);
    };
    public query func getLastTxns() : async [(index: Nat, app: AppId, indexInApp: Nat, txid: Txid)]{
        var l = List.append(lastTxns.0, List.reverse(lastTxns.1));
        return List.toArray(l);
    };
    public shared(msg) func store(_txn: TxnRecord) : async (){
        let amout = Cycles.available();
        assert(amout >= fee_ or _onlyOwner(msg.caller));
        let accepted = Cycles.accept(fee_);
        let app: AppId = msg.caller;
        storeTxns := List.push((app, #Txn(_txn), 0), storeTxns);
        await _execStorage();
    };
    public shared(msg) func storeBytes(_txid: Txid, _data: [Nat8]) : async (){
        let amout = Cycles.available();
        assert(amout >= fee_ or _onlyOwner(msg.caller));
        let accepted = Cycles.accept(fee_);
        let _app: AppId = msg.caller;
        storeTxns := List.push((_app, #Bytes({txid = _txid; data = _data;}), 0), storeTxns);
        await _execStorage();
    };
    public query func bucket(_app: Principal, _txid: Txid, _step: Nat, _version: ?Nat8) : async (bucket: ?Principal, isEnd: Bool){
        let _sid = SwapRecord.generateSid(_app, _txid);
        return _checkBloom(_sid, _step);
    };
    
    /* 
    * Owner's Management
    */
    public query func getOwner() : async Principal{  
        return owner;
    };
    public shared(msg) func changeOwner(_newOwner: Principal) : async Bool{  
        assert(_onlyOwner(msg.caller));
        owner := _newOwner;
        return true;
    };
    public shared(msg) func setFee(_fee: Nat) : async Bool{  
        assert(_onlyOwner(msg.caller));
        fee_ := _fee;
        return true;
    };
    public shared(msg) func setMaxMemory(_memory: Nat) : async Bool{  
        assert(_onlyOwner(msg.caller));
        maxMemory := _memory;
        return true;
    };
    public shared(msg) func reStore() : async (){  
        assert(_onlyOwner(msg.caller));
        await _reExecStorage();
    };
    public shared(msg) func clearStoreErrPool() : async (){  
        assert(_onlyOwner(msg.caller));
        storeErrPool := List.nil<(AppId, DataType, Nat)>();
    };
    // receive cycles
    public func wallet_receive(): async (){
        let amout = Cycles.available();
        let accepted = Cycles.accept(amout);
    };
    //cycles withdraw
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
    /// canister memory
    public query func getMemory() : async (Nat,Nat,Nat,Nat32){
        return (Prim.rts_memory_size(), Prim.rts_heap_size(), Prim.rts_total_allocation(),Prim.stableMemorySize());
    };
    /// canister cycles
    public query func getCycles() : async Nat{
        return return Cycles.balance();
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

    /*
    * upgrade functions
    */
    system func preupgrade() {
        var size : Nat = blooms.size();
        var temp : [var (Bucket, [[Nat8]])] = Array.init<(Bucket, [[Nat8]])>(size, (owner, []));
        size := 0;
        for ((k, v) in blooms.entries()) {
            temp[size] := (k, v.getBitMap());
            size += 1;
        };
        bloomsEntries := Array.freeze(temp);
    };

    system func postupgrade() {
        for ((k, v) in bloomsEntries.vals()) {
            let temp = Bloom.AutoScalingBloomFilter<Blob>(100000, 0.002, Bloom.blobHash);
            temp.setData(v);
            blooms.put(k, temp);
        };
    };
}
