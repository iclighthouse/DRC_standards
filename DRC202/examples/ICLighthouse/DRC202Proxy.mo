/**
 * Module     : DRC202Proxy.mo
 * Author     : ICLighthouse Team
 * License    : Apache License 2.0
 * Stability  : Experimental
 * CanisterId : y5a36-liaaa-aaaak-aacqa-cai
 * Github     : https://github.com/iclighthouse/DRC_standards/
 */
 
import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Nat32 "mo:base/Nat32";
import Blob "mo:base/Blob";
import Option "mo:base/Option";
import Time "mo:base/Time";
import Int "mo:base/Int";
import Int64 "mo:base/Int64";
import Nat64 "mo:base/Nat64";
import Float "mo:base/Float";
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
import DRC207 "./lib/DRC207";
import IC "sys/IC";

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
    private var bucketCyclesInit: Nat = 2000000000000;
    private var maxStorageTries: Nat = 3;
    private var standard_: Text = "drc202"; 
    private stable var fee_: Nat = 1000000;  //cycles
    private stable var owner: Principal = installMsg.caller;
    private stable var maxMemory: Nat = 3900 * 1024 * 1024; //3.8GB
    private stable var bucketCount: Nat = 0;
    private stable var tokenCount: Nat = 0;
    private stable var txnCount: Nat = 0;
    private stable var errCount: Nat = 0;
    private stable var lastTxns = Deque.empty<(index: Nat, token: Token, indexInToken: Nat, txid: Txid)>();
    private stable var currentBucket: [(Bucket, BucketInfo)] = [];
    private stable var buckets: [Bucket] = [];
    private stable var lastCheckCyclesTime: Time.Time = 0;
    private var blooms = TrieMap.TrieMap<Bucket, BloomFilter>(Principal.equal, Principal.hash);
    private stable var bloomsEntries : [(Bucket, [[Nat8]])] = []; // for upgrade
    private var blooms2 = TrieMap.TrieMap<Bucket, BloomFilter>(Principal.equal, Principal.hash);
    private stable var blooms2Entries : [(Bucket, [[Nat8]])] = []; // for upgrade
    private stable var tokens: Trie.Trie<Token, TokenInfo> = Trie.empty(); 
    private stable var storeTxns = List.nil<(Token, DataType, Nat)>();
    private stable var storeErrPool = List.nil<(Token, DataType, Nat)>();
    private stable var tokenStd: Trie.Trie<Token, Text> = Trie.empty(); 
    private stable var lastFetchBucketTime: Int = 0; 
    private stable var lastStorageTime: Int = 0;
    private stable var lastSessions = Deque.empty<(Principal, Nat)>(); 
    private stable var MaxTPS: Nat = 100; //100
    private stable var MaxTransPerAccount: Nat = 500; // xx trans per 1min
    // TODO private stable var certifications: Trie.Trie<Token, [TokenCertification]> = Trie.empty(); 

    private func _onlyOwner(_caller: Principal) : Bool {
        return _caller == owner;
    };
    private func keyb(t: Blob) : Trie.Key<Blob> { return { key = t; hash = Blob.hash(t) }; };
    private func keyp(t: Principal) : Trie.Key<Principal> { return { key = t; hash = Principal.hash(t) }; };
    private func _now() : Nat{
        return Int.abs(Time.now() / 1000000000);
    };
    private func _natToFloat(_n: Nat) : Float{
        return Float.fromInt64(Int64.fromNat64(Nat64.fromNat(_n)));
    };
    private func _sessionPush(_a: Principal): (){
        lastSessions := Deque.pushFront(lastSessions, (_a, _now()));
        var enLoop: Bool = true;
        while(enLoop){
            switch(Deque.popBack(lastSessions)){
                case(?(deque, (_account, _ts))){
                    if (_now() > _ts + 120){ //2min
                        lastSessions := deque;
                    }else{
                        enLoop := false;
                    };
                };
                case(_){ enLoop := false; };
            };
        };
    };
    private func _tps(_duration: Nat, _a: ?Principal) : (total: Nat, tpsX10: Nat){
        var count: Nat = 0;
        var ts = _now();
        var temp_deque = lastSessions;
        while(ts > 0 and _now() < ts + _duration){
            switch(Deque.popFront(temp_deque)){
                case(?((_account, _ts), deque)){
                    temp_deque := deque;
                    ts := _ts;
                    switch(_a){
                        case(?(account)){
                            if(_now() < _ts + _duration and account == _account){ count += 1; };
                        };
                        case(_){
                            if(_now() < _ts + _duration){ count += 1; };
                        };
                    };
                };
                case(_){ ts := 0; return (0,0); };
            };
        };
        return (count, count * 10 / _duration);
    };
    private func _newBucket() : async* Bucket {
        Cycles.add(bucketCyclesInit);
        let bucketActor = await DRC202Bucket.BucketActor();
        let bucket: Bucket = Principal.fromActor(bucketActor);
        let bucketInfo: BucketInfo = await bucketActor.bucketInfo();
        buckets := Tools.arrayAppend(buckets, [bucket]);
        currentBucket := [(bucket, bucketInfo)];
        blooms.put(bucket, Bloom.AutoScalingBloomFilter<Blob>(100000, 0.002, Bloom.blobHash));
        blooms2.put(bucket, Bloom.AutoScalingBloomFilter<Blob>(100000, 0.002, Bloom.blobHash));
        bucketCount += 1;
        let ic: IC.Self = actor("aaaaa-aa");
        let settings = await ic.update_settings({
            canister_id = bucket; 
            settings={ 
                compute_allocation = null;
                controllers = ?[bucket, Principal.fromText("7hdtw-jqaaa-aaaak-aaccq-cai"), Principal.fromActor(this)]; 
                freezing_threshold = null;
                memory_allocation = null;
            };
        });
        return bucket;
    };
    private func _topup(_bucket: Bucket) : async* (){
        let bucketActor: DRC202Bucket.BucketActor = actor(Principal.toText(_bucket));
        let bucketInfo: BucketInfo = await bucketActor.bucketInfo();
        if (_bucket == currentBucket[0].0){
            currentBucket := [(_bucket, bucketInfo)];
        };
        if (bucketInfo.cycles < bucketCyclesInit/2){
            Cycles.add(bucketCyclesInit);
            let res = await bucketActor.wallet_receive();
        };
    };
    private func _monitor() : async (){
        for (bucket in buckets.vals()){
            await* _topup(bucket);
        };
    };
    private func _getBucket() : async* Bucket{
        if (currentBucket.size() > 0){
            var bucket: Bucket = currentBucket[0].0;
            if (Time.now() > lastCheckCyclesTime + 4*3600*1000000000){ 
                let f = _monitor();
                lastCheckCyclesTime := Time.now();
            };
            if (currentBucket[0].1.memory >= maxMemory){
                bucket := await* _newBucket();
            };
            return bucket;
        } else {
            return await* _newBucket();
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
    private func _checkBloom(_sid: Sid, _step: Nat) : ?Bucket{
        var step: Nat = 0;
        for ((bucket, bloom) in blooms.entries()){
            if (step < _step and bloom.check(_sid)){
                step += 1;
            }else if (step == _step and bloom.check(_sid)){
                return ?bucket;
            };
        };
        return null;
    };
    private func _addBloom2(_bucket: Bucket, _iid: Blob) : (){
        switch(blooms2.get(_bucket)){
            case(?(bloom)){
                bloom.add(_iid);
                blooms2.put(_bucket, bloom);
            };
            case(_){
                let bloom = Bloom.AutoScalingBloomFilter<Blob>(100000, 0.002, Bloom.blobHash);
                bloom.add(_iid);
                blooms2.put(_bucket, bloom);
            };
        };
    };
    private func _checkBloom2(_iid: Blob, _step: Nat) : ?Bucket{
        var step: Nat = 0;
        for ((bucket, bloom) in blooms2.entries()){
            if (step < _step and bloom.check(_iid)){
                step += 1;
            }else if (step == _step and bloom.check(_iid)){
                return ?bucket;
            };
        };
        return null;
    };
    private func _postLog(_txns: List.List<(Token, DataType, Nat)>) : (){
        var bucket: Bucket = currentBucket[0].0;
        for ((token, dataType, callCount) in Array.reverse(List.toArray(_txns)).vals()){
            switch(dataType){
                case(#Txn(txn)){
                    let sid = TokenRecord.generateSid(token, txn.txid);
                    let iid = TokenRecord.generateIid(token, txn.index);
                    _addBloom(bucket, sid);
                    _addBloom2(bucket, iid);
                };
                case(#Bytes(txn)){
                    let sid = TokenRecord.generateSid(token, txn.txid);
                    _addBloom(bucket, sid);
                };
            };
            _putToken(token, dataType);
            _pushLastTxns(token, dataType);
            txnCount += 1;
        };
    };
    private func _blobAppend(_bytesArr: [Blob]): Blob{
        var data : [Nat8] = [];
        for (item in _bytesArr.vals()){
            data := Tools.arrayAppend(data, Blob.toArray(item));
        };
        return Blob.fromArray(data);
    };
    private func _execStorage() : async* (){
        var bucket: Bucket = currentBucket[0].0;
        if (Time.now() > lastFetchBucketTime + 10*60*1000000000){
            bucket := await* _getBucket();
            lastFetchBucketTime := Time.now();
        };
        let bucketActor: DRC202Bucket.BucketActor = actor(Principal.toText(bucket));
        var _storing = List.nil<(Token, DataType, Nat)>();
        var _bytesStoring = List.nil<(Token, DataType, Nat)>();
        var storeBatch: [(_sid: Sid, _txn: TxnRecord)] = [];
        var storeBytesBatch: [(_sid: Sid, _data: [Nat8])] = [];
        for ((token, dataType, callCount) in List.toArray(List.reverse(storeTxns)).vals()){
            switch(dataType){
                case(#Txn(txn)){
                    let sid = TokenRecord.generateSid(token, txn.txid);
                    let iid = TokenRecord.generateIid(token, txn.index);
                    storeBatch := Tools.arrayAppend(storeBatch, [(_blobAppend([sid, iid, txn.caller, Principal.toBlob(token)]), txn)]); // the first item at 0 position
                    _storing := List.push((token, dataType, callCount), _storing);
                };
                case(#Bytes(txn)){
                    let sid = TokenRecord.generateSid(token, txn.txid);
                    storeBytesBatch := Tools.arrayAppend(storeBytesBatch, [(sid, txn.data)]); // the first item at 0 position
                    _bytesStoring := List.push((token, dataType, callCount), _bytesStoring);
                };
            };
        };
        if (storeBatch.size() > 0 or storeBytesBatch.size() > 0){
            storeTxns := List.nil<(Token, DataType, Nat)>();
            if (storeBatch.size() > 0){
                try{
                    await bucketActor.storeBatch(storeBatch);
                    _postLog(_storing);
                }catch(e){
                    storeTxns := List.append(storeTxns, _storing);
                };
            };
            if (storeBytesBatch.size() > 0){
                try{
                    await bucketActor.storeBytesBatch(storeBytesBatch);
                    _postLog(_bytesStoring);
                }catch(e){
                    storeTxns := List.append(storeTxns, _bytesStoring);
                };
            };
        };
        
        // var _storeTxns = List.nil<(Token, DataType, Nat)>();
        // var item = List.pop(storeTxns);
        // while (Option.isSome(item.0)){
        //     storeTxns := item.1;
        //     switch(item.0){
        //         case(?(token, dataType, callCount)){
        //             if (callCount < maxStorageTries){
        //                 try{
        //                     switch(dataType){
        //                         case(#Txn(txn)){
        //                             let sid = TokenRecord.generateSid(token, txn.txid);
        //                             await bucketActor.store(sid, txn);
        //                             _addBloom(bucket, sid);
        //                         };
        //                         case(#Bytes(txn)){
        //                             let sid = TokenRecord.generateSid(token, txn.txid);
        //                             await bucketActor.storeBytes(sid, txn.data);
        //                             _addBloom(bucket, sid);
        //                         };
        //                     };
        //                     _putToken(token, dataType);
        //                     _pushLastTxns(token, dataType);
        //                     txnCount += 1;
        //                 } catch(e){ //push
        //                     errCount += 1;
        //                     _storeTxns := List.push((token, dataType, callCount+1), _storeTxns);
        //                 };
        //             } else {
        //                 storeErrPool := List.push((token, dataType, 0), storeErrPool);
        //             };
        //         };
        //         case(_){};
        //     };
        //     item := List.pop(storeTxns);
        // };
        // storeTxns := _storeTxns;
    };
    private func _reExecStorage() : async* (){
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
        await* _execStorage();
    };

    public query func generateTxid(_token: Token, _caller: AccountId, _nonce: Nat): async Txid{
        let canister: [Nat8] = Blob.toArray(Principal.toBlob(_token));
        let caller: [Nat8] = Blob.toArray(_caller);
        let nonce: [Nat8] = Binary.BigEndian.fromNat32(Nat32.fromNat(_nonce));
        let txInfo = Tools.arrayAppend(Tools.arrayAppend(canister, caller), nonce);
        let h224: [Nat8] = SHA224.sha224(txInfo);
        return Blob.fromArray(Tools.arrayAppend(nonce, h224));
    };

    public query func standard() : async Text{
        return standard_;
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
    public query func bucketList() : async [Bucket]{
        return buckets;
    };
    public query func tokenInfo(_token: Token) : async (?Text, ?TokenInfo){
        return (Trie.get(tokenStd, keyp(_token), Principal.equal),
            Trie.get(tokens, keyp(_token), Principal.equal));
    };
    public query func getLastTxns() : async [(index: Nat, token: Token, indexInToken: Nat, txid: Txid)]{
        var l = List.append(lastTxns.0, List.reverse(lastTxns.1));
        return List.toArray(l);
    };
    public shared(msg) func setStd(_std: Text) : async (){
        let token: Token = msg.caller;
        tokenStd := Trie.put(tokenStd, keyp(token), Principal.equal, _std).0;
    };
    public shared(msg) func store(_txn: TxnRecord) : async (){
        // Note: This method will be deprecated
        _sessionPush(msg.caller);
        if (_tps(60, ?msg.caller).0 > MaxTransPerAccount){
            assert(false);
        };
        let amout = Cycles.available();
        assert(amout >= fee_ or _onlyOwner(msg.caller));
        let accepted = Cycles.accept(fee_);
        let token: Token = msg.caller;
        storeTxns := List.push((token, #Txn(_txn), 0), storeTxns);
        if (Time.now() > lastStorageTime + 5*1000000000 and _tps(5, null).1 < MaxTPS*7){
            lastStorageTime := Time.now();
            await* _execStorage();
        };
    };
    public shared(msg) func storeBatch(_txns: [TxnRecord]) : async (){ // the first item at 0 position
        _sessionPush(msg.caller);
        if (_tps(60, ?msg.caller).0 > MaxTransPerAccount){
            assert(false);
        };
        let amout = Cycles.available();
        assert(amout >= fee_ * _txns.size() or _onlyOwner(msg.caller));
        let accepted = Cycles.accept(fee_ * _txns.size());
        let token: Token = msg.caller;
        for (_txn in _txns.vals()){
            storeTxns := List.push((token, #Txn(_txn), 0), storeTxns);
        };
        if (Time.now() > lastStorageTime + 5*1000000000 and _tps(5, null).1 < MaxTPS*7){
            lastStorageTime := Time.now();
            await* _execStorage();
        };
    };
    public shared(msg) func storeBytes(_txid: Txid, _data: [Nat8]) : async (){
        // Note: This method will be deprecated
        assert(_data.size() <= 128 * 1024); // 128 KB
        if (_tps(60, ?msg.caller).0 > MaxTransPerAccount){
            assert(false);
        };
        let amout = Cycles.available();
        assert(amout >= fee_ or _onlyOwner(msg.caller));
        let accepted = Cycles.accept(fee_);
        let token: Token = msg.caller;
        storeTxns := List.push((token, #Bytes({txid = _txid; data = _data;}), 0), storeTxns);
        if (Time.now() > lastStorageTime + 5*1000000000 and _tps(5, null).1 < MaxTPS*7){
            lastStorageTime := Time.now();
            await* _execStorage();
        };
    };
    public shared(msg) func storeBytesBatch(_txns: [(_txid: Txid, _data: [Nat8])]) : async (){ // the first item at 0 position
        if (_tps(60, ?msg.caller).0 > MaxTransPerAccount){
            assert(false);
        };
        let amout = Cycles.available();
        assert(amout >= fee_ * _txns.size() or _onlyOwner(msg.caller));
        let accepted = Cycles.accept(fee_ * _txns.size());
        let token: Token = msg.caller;
        for ((_txid, _data) in _txns.vals()){
            assert(_data.size() <= 128 * 1024); // 128 KB
            storeTxns := List.push((token, #Bytes({txid = _txid; data = _data;}), 0), storeTxns);
        };
        if (Time.now() > lastStorageTime + 5*1000000000 and _tps(5, null).1 < MaxTPS*7){
            lastStorageTime := Time.now();
            await* _execStorage();
        };
    };
    public query func bucket(_token: Token, _txid: Txid, _step: Nat, _version: ?Nat8) : async (bucket: ?Bucket){
        let _sid = TokenRecord.generateSid(_token, _txid);
        return _checkBloom(_sid, _step);
    };
    public query func bucketByIndex(_token: Token, _blockIndex: Nat, _step: Nat, _version: ?Nat8) : async (bucket: ?Principal){
        let _iid = TokenRecord.generateIid(_token, _blockIndex);
        return _checkBloom2(_iid, _step);
    };
    public query func minInterval() : async Int{ //ns
        return 60*1000000000 / MaxTransPerAccount;
    };
    public query func tpsStats() : async (Float, Nat){
        return (_natToFloat(_tps(60, null).1) / 10.0, List.size(lastSessions.0)+List.size(lastSessions.1));
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
    public shared(msg) func setMaxTPS(_tps: Nat, _maxpm: Nat) : async Bool{ 
        assert(_onlyOwner(msg.caller));
        MaxTPS := _tps;
        MaxTransPerAccount := _maxpm;
        return true;
    };
    public shared(msg) func reStore() : async (){  
        assert(_onlyOwner(msg.caller));
        await* _reExecStorage();
    };
    public shared(msg) func clearStoreErrPool() : async (){  
        assert(_onlyOwner(msg.caller));
        storeErrPool := List.nil<(Token, DataType, Nat)>();
    };
    public shared(msg) func setController(_bucket: Principal, _add: Bool) : async () {
        assert(_onlyOwner(msg.caller));
        var controllers : [Principal] = [_bucket, Principal.fromText("7hdtw-jqaaa-aaaak-aaccq-cai"), Principal.fromActor(this), msg.caller];
        if (not(_add)){
            controllers := [_bucket, Principal.fromText("7hdtw-jqaaa-aaaak-aaccq-cai"), Principal.fromActor(this)];
        };
        let ic: IC.Self = actor("aaaaa-aa");
        let settings = await ic.update_settings({
            canister_id = _bucket; 
            settings={ 
                compute_allocation = null;
                controllers = ?controllers; 
                freezing_threshold = null;
                memory_allocation = null;
            };
        });
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
    /// canister cycles
    public query func getCycles() : async Nat{
        return return Cycles.balance();
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

        size := blooms2.size();
        var temp2 : [var (Bucket, [[Nat8]])] = Array.init<(Bucket, [[Nat8]])>(size, (owner, []));
        size := 0;
        for ((k, v) in blooms2.entries()) {
            temp2[size] := (k, v.getBitMap());
            size += 1;
        };
        blooms2Entries := Array.freeze(temp2);
    };

    system func postupgrade() {
        for ((k, v) in bloomsEntries.vals()) {
            let temp = Bloom.AutoScalingBloomFilter<Blob>(100000, 0.002, Bloom.blobHash);
            temp.setData(v);
            blooms.put(k, temp);
        };

        for ((k, v) in blooms2Entries.vals()) {
            let temp = Bloom.AutoScalingBloomFilter<Blob>(100000, 0.002, Bloom.blobHash);
            temp.setData(v);
            blooms2.put(k, temp);
        };
    };
}
