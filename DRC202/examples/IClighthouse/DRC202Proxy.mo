/**
 * Module     : DRC202Proxy.mo
 * Author     : ICLighthouse Team
 * License    : Apache License 2.0
 * Stability  : Experimental
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
import TokenRecord "./lib/TokenRecord";
import DRC202Bucket "DRC202Bucket";
import Monitee "./lib/Monitee";

shared(installMsg) actor class ProxyActor() = this {
    type Bucket = TokenRecord.Bucket;
    type BucketInfo = TokenRecord.BucketInfo;
    type Token = TokenRecord.Token;
    type TokenInfo = TokenRecord.TokenInfo;
    type TokenCertification = TokenRecord.TokenCertification;
    type Txid = TokenRecord.Txid;  
    type Sid = TokenRecord.Sid;
    type AccountId = TokenRecord.AccountId;
    type TxnRecord = TokenRecord.TxnRecord;
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
    private stable var tokenCount: Nat = 0;
    private stable var txnCount: Nat = 0;
    private stable var errCount: Nat = 0;
    private stable var lastTxns = Deque.empty<(index: Nat, token: Token, indexInToken: Nat, txid: Txid)>();
    private stable var currentBucket: [(Bucket, BucketInfo)] = [];
    private stable var buckets: [Bucket] = [];
    private var blooms = TrieMap.TrieMap<Bucket, BloomFilter>(Principal.equal, Principal.hash);
    private stable var bloomsEntries : [(Bucket, [[Nat8]])] = []; // for upgrade
    private stable var tokens: Trie.Trie<Token, TokenInfo> = Trie.empty(); 
    private stable var storeTxns = List.nil<(Token, DataType, Nat)>();
    private stable var storeErrPool = List.nil<(Token, DataType, Nat)>();
    // TODO private stable var certifications: Trie.Trie<Token, [TokenCertification]> = Trie.empty(); 

    private func _onlyOwner(_caller: Principal) : Bool {
        return _caller == owner;
    };
    private func keyb(t: Blob) : Trie.Key<Blob> { return { key = t; hash = Blob.hash(t) }; };
    private func keyp(t: Principal) : Trie.Key<Principal> { return { key = t; hash = Principal.hash(t) }; };
    private func _newBucket() : async Bucket {
        Cycles.add(bucketCyclesInit);
        let bucketActor = await DRC202Bucket.BucketActor();
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
            let bucketActor: DRC202Bucket.BucketActor = actor(Principal.toText(bucket));
            let bucketInfo: BucketInfo = await bucketActor.bucketInfo();
            currentBucket := [(bucket, bucketInfo)];
            if (bucketInfo.cycles < bucketCyclesInit/2){
                Cycles.add(bucketCyclesInit);
                await bucketActor.wallet_receive();
            };
            if (bucketInfo.memory >= maxMemory){
                bucket := await _newBucket();
            };
            return bucket;
        } else {
            return await _newBucket();
        };
    };
    private func _pushLastTxns(_token: Token, _data: DataType) : (){
        switch(_data){
            case(#Txn(txn)){
                lastTxns := Deque.pushFront(lastTxns, (txnCount, _token, txn.index, txn.txid));
            };
            case(#Bytes(txn)){
                lastTxns := Deque.pushFront(lastTxns, (txnCount, _token, 0, txn.txid));
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
    private func _putToken(_token: Token, _data: DataType) : (){
        var _count: Nat = 0;
        switch(Trie.get(tokens, keyp(_token), Principal.equal)){
            case(?(info)){
                _count := info.count+1;
            };
            case(_){
                _count := 1;
                tokenCount += 1;
            };
        };
        switch(_data){
            case(#Txn(_txn)){
                tokens := Trie.put(tokens, keyp(_token), Principal.equal, {
                    lastIndex = _txn.index;
                    lastTxid = _txn.txid;
                    count = _count;
                }).0;
            };
            case(#Bytes(txn)){
                tokens := Trie.put(tokens, keyp(_token), Principal.equal, {
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
        let bucketActor: DRC202Bucket.BucketActor = actor(Principal.toText(bucket));
        var _storeTxns = List.nil<(Token, DataType, Nat)>();
        var item = List.pop(storeTxns);
        while (Option.isSome(item.0)){
            switch(item.0){
                case(?(token, dataType, callCount)){
                    if (callCount < maxStorageTries){
                        try{
                            switch(dataType){
                                case(#Txn(txn)){
                                    let sid = TokenRecord.generateSid(token, txn.txid);
                                    await bucketActor.store(sid, txn);
                                    _addBloom(bucket, sid);
                                };
                                case(#Bytes(txn)){
                                    let sid = TokenRecord.generateSid(token, txn.txid);
                                    await bucketActor.storeBytes(sid, txn.data);
                                    _addBloom(bucket, sid);
                                };
                            };
                            _putToken(token, dataType);
                            _pushLastTxns(token, dataType);
                            txnCount += 1;
                        } catch(e){ //push
                            errCount += 1;
                            _storeTxns := List.push((token, dataType, callCount+1), _storeTxns);
                        };
                    } else {
                        storeErrPool := List.push((token, dataType, 0), storeErrPool);
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

    public query func generateTxid(_token: Principal, _caller: Principal, _nonce: Nat): async Txid{
        let canister: [Nat8] = Blob.toArray(Principal.toBlob(_token));
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
    public query func stats() : async {bucketCount: Nat; tokenCount: Nat; txnCount: Nat; errCount: Nat; storeErrPool: Nat}{
        return {
            bucketCount = bucketCount; 
            tokenCount = tokenCount; 
            txnCount = txnCount;
            errCount = errCount;
            storeErrPool = List.size(storeErrPool);
        };
    };
    public /*query*/ func bucketInfo(_bucket: ?Bucket) : async (Bucket, BucketInfo){
        switch(_bucket){
            case(?(bucket)){
                let bucketActor: DRC202Bucket.BucketActor = actor(Principal.toText(bucket));
                return (bucket, await bucketActor.bucketInfo());
            };
            case(_){
                return currentBucket[0];
            };
        };
    };
    public query func tokenInfo(_token: Token) : async ?TokenInfo{
        return Trie.get(tokens, keyp(_token), Principal.equal);
    };
    public query func getLastTxns() : async [(index: Nat, token: Token, indexInToken: Nat, txid: Txid)]{
        var l = List.append(lastTxns.0, List.reverse(lastTxns.1));
        return List.toArray(l);
    };
    public shared(msg) func store(_txn: TxnRecord) : async (){
        let amout = Cycles.available();
        assert(amout >= fee_ or _onlyOwner(msg.caller));
        let accepted = Cycles.accept(fee_);
        let token: Token = msg.caller;
        storeTxns := List.push((token, #Txn(_txn), 0), storeTxns);
        await _execStorage();
    };
    public shared(msg) func storeBytes(_txid: Txid, _data: [Nat8]) : async (){
        let amout = Cycles.available();
        assert(amout >= fee_ or _onlyOwner(msg.caller));
        let accepted = Cycles.accept(fee_);
        let _token: Token = msg.caller;
        storeTxns := List.push((_token, #Bytes({txid = _txid; data = _data;}), 0), storeTxns);
        await _execStorage();
    };
    public query func bucket(_token: Principal, _txid: Txid, _step: Nat, _version: ?Nat8) : async (bucket: ?Principal, isEnd: Bool){
        let _sid = TokenRecord.generateSid(_token, _txid);
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
        storeErrPool := List.nil<(Token, DataType, Nat)>();
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
    /// query canister status: Add itself as a controller, canister_id = Principal.fromActor(<your actor name>)
    public func canister_status() : async Monitee.canister_status {
        let ic : Monitee.IC = actor("aaaaa-aa");
        await ic.canister_status({ canister_id = Principal.fromActor(this) });
    };
    /// canister memory
    public query func getMemory() : async (Nat,Nat,Nat,Nat32){
        return (Prim.rts_memory_size(), Prim.rts_heap_size(), Prim.rts_total_allocation(),Prim.stableMemorySize());
    };
    /// canister cycles
    public query func getCycles() : async Nat{
        return return Cycles.balance();
    };

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
