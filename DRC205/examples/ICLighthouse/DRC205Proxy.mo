/**
 * Module     : DRC205Proxy.mo
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Canister   : 6ylab-kiaaa-aaaak-aacga-cai  (Test: ix3cb-4iaaa-aaaak-aagbq-cai)
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
import Binary "mo:icl/Binary";
import SHA224 "mo:sha224/SHA224";
import Tools "mo:icl/Tools";
import Bloom "./lib/Bloom";
import Deque "mo:base/Deque";
import List "mo:base/List";
import Trie "mo:base/Trie";
import TrieMap "mo:base/TrieMap";
import Iter "mo:base/Iter";
import Cycles "mo:base/ExperimentalCycles";
import CyclesMonitor "mo:icl/CyclesMonitor";
import CyclesWallet "mo:icl/CyclesWallet";
import SwapRecord "./lib/SwapRecord";
import DRC205 "mo:icl/DRC205Types";
import DRC205Bucket "DRC205Bucket";
import DRC207 "mo:icl/DRC207";
import IC "mo:icl/IC";

// 0, principal "lr4ff-zqaaa-aaaak-ae2zq-cai" // Test
// 0, principal "lw5dr-uiaaa-aaaak-ae2za-cai"
shared(installMsg) actor class ProxyActor(initStartIndex: Nat, initProxyRoot: Principal) = this {
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

    let app_debug: Bool = false; /*config*/ 
    var bucketCyclesInit: Nat = 10_000_000_000_000; //10T
    if (app_debug){
        bucketCyclesInit := 1_000_000_000_000; //1.0T
    };
    private var version_: Nat8 = 1;
    private var maxStorageTries: Nat = 3;
    private var standard_: Text = "drc205"; 
    private stable var isStopped: Bool = false;
    private stable var proxyRoot: Principal = initProxyRoot;
    private stable var fee_: Nat = 1000000;  //cycles
    private stable var owner: Principal = installMsg.caller;
    private stable var maxMemory: Nat = 3800*1000*1000; // 3.8G /*config*/
    private stable var bucketCount: Nat = 0;
    private stable var appCount: Nat = 0;
    private stable var txnCount: Nat = initStartIndex;
    private stable var errCount: Nat = 0;
    private stable var lastTxns = Deque.empty<(index: Nat, app: AppId, indexInApp: Nat, txid: Txid)>();
    private stable var currentBucket: [(Bucket, BucketInfo)] = [];
    private stable var buckets: [Bucket] = [];
    private stable var buckets2: [(Bucket, startTime: Time.Time, startIndex: Nat)] = [];
    // private stable var lastCheckCyclesTime: Time.Time = 0;
    private var blooms = TrieMap.TrieMap<Bucket, BloomFilter>(Principal.equal, Principal.hash);
    private stable var bloomsEntries : [(Bucket, [[Nat8]])] = []; // for upgrade
    private var blooms2 = TrieMap.TrieMap<Bucket, BloomFilter>(Principal.equal, Principal.hash);
    private stable var blooms2Entries : [(Bucket, [[Nat8]])] = []; // for upgrade
    private var blooms3 = TrieMap.TrieMap<Bucket, BloomFilter>(Principal.equal, Principal.hash);
    private stable var blooms3Entries : [(Bucket, [[Nat8]])] = []; // for upgrade
    private stable var apps: Trie.Trie<AppId, AppInfo> = Trie.empty(); 
    private stable var storeTxns = List.nil<(AppId, DataType, Nat)>();
    private stable var storeErrPool = List.nil<(AppId, DataType, Nat)>();
    private stable var lastFetchBucketTime: Int = 0; 
    private stable var lastStorageTime: Int = 0;
    private stable var lastSessions = Deque.empty<(Principal, Nat)>(); 
    private stable var MaxTPS: Nat = 100; //100
    private stable var MaxTransPerAccount: Nat = 60; // xx trans per 1min
    // private stable var nonces: Trie.Trie<AppId, Nat> = Trie.empty(); 
    // TODO private stable var certifications: Trie.Trie<App, [AppCertification]> = Trie.empty(); 
    // Monitor
    private stable var cyclesMonitor: CyclesMonitor.MonitoredCanisters = Trie.empty(); 
    private stable var lastMonitorTime: Time.Time = 0;

    private func _onlyOwner(_caller: Principal) : Bool {
        return _caller == owner or _caller == proxyRoot;
    };
    private func keyb(t: Blob) : Trie.Key<Blob> { return { key = t; hash = Blob.hash(t) }; };
    private func keyp(t: Principal) : Trie.Key<Principal> { return { key = t; hash = Principal.hash(t) }; };
    private func _now() : Nat{
        return Int.abs(Time.now() / 1000000000);
    };
    private func _natToFloat(_n: Nat) : Float{
        return Float.fromInt64(Int64.fromNat64(Nat64.fromNat(_n)));
    };
    // private func _getNonce(_a: Principal): Nat{
    //     switch(Trie.get(nonces, keyp(_a), Principal.equal)){
    //         case(?(v)){ return v; };
    //         case(_){ return 0; };
    //     };
    // };
    // private func _addNonce(_a: Principal): (){
    //     var n = _getNonce(_a);
    //     nonces := Trie.put(nonces, keyp(_a), Principal.equal, n+1).0;
    // };
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
        let bucketActor = await DRC205Bucket.BucketActor();
        let bucket: Bucket = Principal.fromActor(bucketActor);
        let bucketInfo: BucketInfo = await bucketActor.bucketInfo();
        buckets2 := Tools.arrayAppend([(bucket, Time.now(), txnCount)], buckets2);
        currentBucket := [(bucket, bucketInfo)];
        blooms.put(bucket, Bloom.AutoScalingBloomFilter<Blob>(100000, 0.002, Bloom.blobHash));
        blooms2.put(bucket, Bloom.AutoScalingBloomFilter<Blob>(100000, 0.002, Bloom.blobHash));
        blooms3.put(bucket, Bloom.AutoScalingBloomFilter<Blob>(100000, 0.002, Bloom.blobHash));
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
        cyclesMonitor := await* CyclesMonitor.put(cyclesMonitor, bucket);
        return bucket;
    };
    private func _getBucketInfo(_bucket: Bucket) : async* BucketInfo{
        let bucketActor: DRC205Bucket.BucketActor = actor(Principal.toText(_bucket));
        let bucketInfo: BucketInfo = await bucketActor.bucketInfo();
        if (_bucket == currentBucket[0].0){
            currentBucket := [(_bucket, bucketInfo)];
        };
        return bucketInfo;
    };
    // private func _topup(_bucket: Bucket) : async* (){
    //     let bucketActor: DRC205Bucket.BucketActor = actor(Principal.toText(_bucket));
    //     let bucketInfo: BucketInfo = await bucketActor.bucketInfo();
    //     if (_bucket == currentBucket[0].0){
    //         currentBucket := [(_bucket, bucketInfo)];
    //     };
    //     if (bucketInfo.cycles < bucketCyclesInit/2){
    //         Cycles.add(bucketCyclesInit);
    //         let res = await bucketActor.wallet_receive();
    //     };
    // };
    // private func _monitor() : async (){
    //     for ((bucket, t, i) in buckets2.vals()){
    //         await* _topup(bucket);
    //     };
    // };
    private func _getBucket() : async* Bucket{
        if (currentBucket.size() > 0){
            var bucket: Bucket = currentBucket[0].0;
            if (Time.now() > lastMonitorTime + 2 * 24 * 3600 * 1000000000){
                try{ 
                    ignore await* _getBucketInfo(currentBucket[0].0);
                    if (Trie.size(cyclesMonitor) == 0){
                        for ((cid, t, i) in buckets2.vals()){
                            cyclesMonitor := await* CyclesMonitor.put(cyclesMonitor, cid);
                        };
                    };
                    cyclesMonitor := await* CyclesMonitor.monitor(Principal.fromActor(this), cyclesMonitor, bucketCyclesInit, bucketCyclesInit * 10, 0);
                    lastMonitorTime := Time.now();
                }catch(e){};
            };
            if (currentBucket[0].1.memory >= maxMemory){
                bucket := await* _newBucket();
            };
            return bucket;
        } else {
            return await* _newBucket();
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
    private func _checkBloom(_sid: Sid, _step: Nat) : ?Bucket{
        var step: Nat = 0;
        var hashs: [Hash.Hash] = [];
        for ((bucket, bloom) in blooms.entries()){
            if (hashs.size() == 0){
                hashs := Bloom.blobHash(_sid, bloom.getK());
            };
            if (step < _step and bloom.check2(hashs)){
                step += 1;
            }else if (step == _step and bloom.check2(hashs)){
                return ?bucket;
            };
        };
        return null;
    };
    private func _checkBloom_all(_sid: Blob) : [Bucket]{
        var res: [Bucket] = [];
        var hashs: [Hash.Hash] = [];
        for ((bucket, bloom) in blooms.entries()){
            if (hashs.size() == 0){
                hashs := Bloom.blobHash(_sid, bloom.getK());
            };
            if (bloom.check2(hashs)){
                res := Tools.arrayAppend(res, [bucket]);
            };
        };
        return res;
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
        var hashs: [Hash.Hash] = [];
        for ((bucket, bloom) in blooms2.entries()){
            if (hashs.size() == 0){
                hashs := Bloom.blobHash(_iid, bloom.getK());
            };
            if (step < _step and bloom.check2(hashs)){
                step += 1;
            }else if (step == _step and bloom.check2(hashs)){
                return ?bucket;
            };
        };
        return null;
    };
    private func _checkBloom2_all(_iid: Blob) : [Bucket]{
        var res: [Bucket] = [];
        var hashs: [Hash.Hash] = [];
        for ((bucket, bloom) in blooms2.entries()){
            if (hashs.size() == 0){
                hashs := Bloom.blobHash(_iid, bloom.getK());
            };
            if (bloom.check2(hashs)){
                res := Tools.arrayAppend(res, [bucket]);
            };
        };
        return res;
    };
    private func _addBloom3(_bucket: Bucket, _aid: Blob) : (){
        switch(blooms3.get(_bucket)){
            case(?(bloom)){
                bloom.add(_aid);
                blooms3.put(_bucket, bloom);
            };
            case(_){
                let bloom = Bloom.AutoScalingBloomFilter<Blob>(100000, 0.002, Bloom.blobHash);
                bloom.add(_aid);
                blooms3.put(_bucket, bloom);
            };
        };
    };
    private func _checkBloom3_all(_aid: Blob) : [Bucket]{
        var res: [Bucket] = [];
        var hashs: [Hash.Hash] = [];
        for ((bucket, bloom) in blooms3.entries()){
            if (hashs.size() == 0){
                hashs := Bloom.blobHash(_aid, bloom.getK());
            };
            if (bloom.check2(hashs)){
                res := Tools.arrayAppend(res, [bucket]);
            };
        };
        return res;
    };
    private func _postLog(_txns: List.List<(AppId, DataType, Nat)>) : (){
        var bucket: Bucket = currentBucket[0].0;
        for ((app, dataType, callCount) in Array.reverse(List.toArray(_txns)).vals()){
            switch(dataType){
                case(#Txn(txn)){
                    let sid = SwapRecord.generateSid(app, txn.txid);
                    let iid = SwapRecord.generateIid(app, txn.index);
                    let aid = SwapRecord.generateAid(app, txn.account);
                    _addBloom(bucket, sid);
                    _addBloom2(bucket, iid);
                    _addBloom3(bucket, aid);
                };
                case(#Bytes(txn)){
                    let sid = SwapRecord.generateSid(app, txn.txid);
                    _addBloom(bucket, sid);
                };
            };
            _putApp(app, dataType);
            _pushLastTxns(app, dataType);
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
        let bucketActor: DRC205Bucket.BucketActor = actor(Principal.toText(bucket));
        var _storing = List.nil<(AppId, DataType, Nat)>();
        var _bytesStoring = List.nil<(AppId, DataType, Nat)>();
        var storeBatch: [(_sid: Sid, _txn: TxnRecord)] = [];
        var storeBytesBatch: [(_sid: Sid, _data: [Nat8])] = [];
        for ((app, dataType, callCount) in List.toArray(List.reverse(storeTxns)).vals()){
            switch(dataType){
                case(#Txn(txn)){
                    let sid = SwapRecord.generateSid(app, txn.txid);
                    let iid = SwapRecord.generateIid(app, txn.index);
                    storeBatch := Tools.arrayAppend(storeBatch, [(_blobAppend([sid, iid, Principal.toBlob(app)]), txn)]); // the first item at 0 position
                    _storing := List.push((app, dataType, callCount), _storing);
                };
                case(#Bytes(txn)){
                    let sid = SwapRecord.generateSid(app, txn.txid);
                    storeBytesBatch := Tools.arrayAppend(storeBytesBatch, [(sid, txn.data)]); // the first item at 0 position
                    _bytesStoring := List.push((app, dataType, callCount), _bytesStoring);
                };
            };
        };
        if (storeBatch.size() > 0 or storeBytesBatch.size() > 0){
            storeTxns := List.nil<(AppId, DataType, Nat)>();
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

        // var _storeTxns = List.nil<(AppId, DataType, Nat)>();
        // var item = List.pop(storeTxns);
        // while (Option.isSome(item.0)){
        //     storeTxns := item.1;
        //     switch(item.0){
        //         case(?(app, dataType, callCount)){
        //             if (callCount < maxStorageTries){
        //                 try{
        //                     switch(dataType){
        //                         case(#Txn(txn)){
        //                             let sid = SwapRecord.generateSid(app, txn.txid);
        //                             await bucketActor.store(sid, txn);
        //                             _addBloom(bucket, sid);
        //                         };
        //                         case(#Bytes(txn)){
        //                             let sid = SwapRecord.generateSid(app, txn.txid);
        //                             await bucketActor.storeBytes(sid, txn.data);
        //                             _addBloom(bucket, sid);
        //                         };
        //                     };
        //                     _putApp(app, dataType);
        //                     _pushLastTxns(app, dataType);
        //                     txnCount += 1;
        //                 } catch(e){ //push
        //                     errCount += 1;
        //                     _storeTxns := List.push((app, dataType, callCount+1), _storeTxns);
        //                 };
        //             } else {
        //                 storeErrPool := List.push((app, dataType, 0), storeErrPool);
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

    public query func generateTxid(_app: AppId, _caller: AccountId, _nonce: Nat): async Txid{
        return DRC205.generateTxid(_app, _caller, _nonce);
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
    public query func stats() : async {bucketCount: Nat; appCount: Nat; txnCount: Nat; errCount: Nat; storeErrPool: Nat}{
        return {
            bucketCount = bucketCount; 
            appCount = appCount; 
            txnCount = txnCount;
            errCount = errCount;
            storeErrPool = List.size(storeErrPool);
        };
    };
    // @deprecated: This method will be deprecated
    public query func bucketList() : async [Bucket]{
        return Array.map(buckets2, func(t:(Bucket, Time.Time, Nat)): Bucket{ t.0 });
    };
    public query func bucketListSorted() : async [(Bucket, Time.Time, Nat)]{
        return buckets2;
    };
    public query func appInfo(_app: AppId) : async ?AppInfo{
        return Trie.get(apps, keyp(_app), Principal.equal);
    };
    public query func getLastTxns() : async [(index: Nat, app: AppId, indexInApp: Nat, txid: Txid)]{
        var l = List.append(lastTxns.0, List.reverse(lastTxns.1));
        return List.toArray(l);
    };
    // @deprecated: This method will be deprecated
    public shared(msg) func store(_txn: TxnRecord) : async (){
        assert(not(isStopped));
        _sessionPush(msg.caller);
        if (_tps(60, ?msg.caller).0 > MaxTransPerAccount){
            assert(false);
        };
        let amout = Cycles.available();
        assert(amout >= fee_ or _onlyOwner(msg.caller));
        let accepted = Cycles.accept(fee_);
        let app: AppId = msg.caller;
        storeTxns := List.push((app, #Txn(_txn), 0), storeTxns);
        if (Time.now() > lastStorageTime + 5*1000000000 and _tps(5, null).1 < MaxTPS*7){
            lastStorageTime := Time.now();
            await* _execStorage();
        };
    };
    public shared(msg) func storeBatch(_txns: [TxnRecord]) : async (){ // the first item at 0 position
        assert(not(isStopped));
        _sessionPush(msg.caller);
        if (_tps(60, ?msg.caller).0 > MaxTransPerAccount){
            assert(false);
        };
        let amout = Cycles.available();
        assert(amout >= fee_ * _txns.size() or _onlyOwner(msg.caller));
        let accepted = Cycles.accept(fee_ * _txns.size());
        let app: AppId = msg.caller;
        for (_txn in _txns.vals()){
            storeTxns := List.push((app, #Txn(_txn), 0), storeTxns);
        };
        if (Time.now() > lastStorageTime + 5*1000000000 and _tps(5, null).1 < MaxTPS*7){
            lastStorageTime := Time.now();
            await* _execStorage();
        };
    };
    // @deprecated: This method will be deprecated
    public shared(msg) func storeBytes(_txid: Txid, _data: [Nat8]) : async (){
        assert(not(isStopped));
        assert(_data.size() <= 128 * 1024); // 128 KB
        if (_tps(60, ?msg.caller).0 > MaxTransPerAccount){
            assert(false);
        };
        let amout = Cycles.available();
        assert(amout >= fee_ or _onlyOwner(msg.caller));
        let accepted = Cycles.accept(fee_);
        let _app: AppId = msg.caller;
        storeTxns := List.push((_app, #Bytes({txid = _txid; data = _data;}), 0), storeTxns);
        if (Time.now() > lastStorageTime + 5*1000000000 and _tps(5, null).1 < MaxTPS*7){
            lastStorageTime := Time.now();
            await* _execStorage();
        };
    };
    public shared(msg) func storeBytesBatch(_txns: [(_txid: Txid, _data: [Nat8])]) : async (){ // the first item at 0 position
        assert(not(isStopped));
        if (_tps(60, ?msg.caller).0 > MaxTransPerAccount){
            assert(false);
        };
        let amout = Cycles.available();
        assert(amout >= fee_ * _txns.size() or _onlyOwner(msg.caller));
        let accepted = Cycles.accept(fee_ * _txns.size());
        let app: AppId = msg.caller;
        for ((_txid, _data) in _txns.vals()){
            assert(_data.size() <= 128 * 1024); // 128 KB
            storeTxns := List.push((app, #Bytes({txid = _txid; data = _data;}), 0), storeTxns);
        };
        if (Time.now() > lastStorageTime + 5*1000000000 and _tps(5, null).1 < MaxTPS*7){
            lastStorageTime := Time.now();
            await* _execStorage();
        };
    };
    // @deprecated: This method will be deprecated
    public query func bucket(_app: AppId, _txid: Txid, _step: Nat, _version: ?Nat8) : async (bucket: ?Bucket){
        let _sid = SwapRecord.generateSid(_app, _txid);
        return _checkBloom(_sid, _step);
    };
    // @deprecated: This method will be deprecated
    public query func bucketByIndex(_app: AppId, _blockIndex: Nat, _step: Nat, _version: ?Nat8) : async (bucket: ?Bucket){
        let _iid = SwapRecord.generateIid(_app, _blockIndex);
        return _checkBloom2(_iid, _step);
    };
    private func _locationV1(_app: AppId, _arg: {#txid: Txid; #index: Nat; #account: AccountId}) : [Bucket]{
        var res : [Bucket] = [];
        switch(_arg){
            case(#txid(txid)){
                let _sid = SwapRecord.generateSid(_app, txid);
                res := _checkBloom_all(_sid);
            };
            case(#index(index)){
                let _iid = SwapRecord.generateIid(_app, index);
                res := _checkBloom2_all(_iid);
            };
            case(#account(account)){
                let _aid = SwapRecord.generateAid(_app, account);
                res := _checkBloom3_all(_aid);
            };
        };
        return res;
    };
    public query func location(_app: AppId, _arg: {#txid: Txid; #index: Nat; #account: AccountId}, _version: ?Nat8) : async [Bucket]{
        return _locationV1(_app, _arg);
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
        storeErrPool := List.nil<(AppId, DataType, Nat)>();
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
    public shared(msg) func stop() : async Nat {
        assert(_onlyOwner(msg.caller));
        isStopped := true; /*config*/
        return txnCount;
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

    // Cycles monitor
    public shared(msg) func monitor_put(_canisterId: Principal): async (){
        assert(_onlyOwner(msg.caller));
        cyclesMonitor := await* CyclesMonitor.put(cyclesMonitor, _canisterId);
    };
    public shared(msg) func monitor_remove(_canisterId: Principal): async (){
        assert(_onlyOwner(msg.caller));
        cyclesMonitor := CyclesMonitor.remove(cyclesMonitor, _canisterId);
    };
    public query func monitor_canisters(): async [(Principal, Nat)]{
        return Iter.toArray(Trie.iter(cyclesMonitor));
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
    // public shared(msg) func canister_status() : async DRC207.canister_status {
    //     _sessionPush(msg.caller);
    //     if (_tps(15, null).1 > MaxTPS*5 or _tps(15, ?msg.caller).0 > 2){
    //         assert(false);
    //     };
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

        size := blooms3.size();
        var temp3 : [var (Bucket, [[Nat8]])] = Array.init<(Bucket, [[Nat8]])>(size, (owner, []));
        size := 0;
        for ((k, v) in blooms3.entries()) {
            temp3[size] := (k, v.getBitMap());
            size += 1;
        };
        blooms3Entries := Array.freeze(temp3);
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

        for ((k, v) in blooms3Entries.vals()) {
            let temp = Bloom.AutoScalingBloomFilter<Blob>(100000, 0.002, Bloom.blobHash);
            temp.setData(v);
            blooms3.put(k, temp);
        };

        if (buckets2.size() == 0){
            buckets2 := Array.map<Bucket, (Bucket, Time.Time, Nat)>(buckets, func(t: Bucket): (Bucket, Time.Time, Nat){ (t, 0, 0) });
        };
    };
}
