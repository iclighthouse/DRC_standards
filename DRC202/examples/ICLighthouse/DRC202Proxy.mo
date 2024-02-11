/**
 * Module     : DRC202Proxy.mo
 * Author     : ICLighthouse Team
 * License    : Apache License 2.0
 * Stability  : Experimental
 * CanisterId : y5a36-liaaa-aaaak-aacqa-cai (Test: iq2ev-rqaaa-aaaak-aagba-cai)
 * Github     : https://github.com/iclighthouse/DRC_standards/
 */
 
import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Nat "mo:base/Nat";
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
import TokenRecord "./lib/TokenRecord";
import DRC202Bucket "DRC202Bucket";
import DRC207 "mo:icl/DRC207";
import IC "mo:icl/IC";
import DRC202 "mo:icl/DRC202Types";
import ICRC1 "mo:icl/ICRC1";
import ICRC3 "./lib/ICRC3";
import AccountIdCaches "./lib/AccountIdCaches";
import Timer "mo:base/Timer";
import Error "mo:base/Error";
import Text "mo:base/Text";

// 0, principal "bcetv-nqaaa-aaaak-ae3bq-cai", vec{}, true //Test
// 0, principal "bffvb-aiaaa-aaaak-ae3ba-cai", vec{}, true
shared(installMsg) actor class ProxyActor(initStartIndex: Nat, initProxyRoot: Principal, initSNSTokens: [(Principal, Nat)], isDefaultProxy: Bool) = this {
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
    type ICRC3BlockIndex = Nat;
    type ICRC1Fee = Nat;
    type ArchivedCanister = Principal;
    
    let app_debug: Bool = false; /*config*/ 
    let is_default_proxy: Bool = isDefaultProxy;
    var bucketCyclesInit: Nat = 5_000_000_000_000; //5T
    if (app_debug){
        bucketCyclesInit := 1_000_000_000_000; //1.0T
    };
    private var version_: Nat8 = 1;
    private var maxStorageTries: Nat = 3;
    private var standard_: Text = "drc202"; 
    private var defaultBucket: Bucket = Principal.fromText("juxlh-iqaaa-aaaak-aagha-cai");
    if (app_debug){
        defaultBucket := Principal.fromText("ukekj-paaaa-aaaak-aaipa-cai");
    };
    private stable var isStopped: Bool = false;
    private stable var proxyRoot: Principal = initProxyRoot;
    private var fee_: Nat = 1000000;  //cycles
    private stable var owner: Principal = installMsg.caller;
    private var maxMemory: Nat = 1490*1000*1000; // 1.49G
    private stable var bucketCount: Nat = 0;
    private stable var tokenCount: Nat = 0;
    private stable var txnCount: Nat = initStartIndex;
    private stable var errCount: Nat = 0;
    private stable var lastTxns = Deque.empty<(index: Nat, token: Token, indexInToken: Nat, txid: Txid)>();
    private stable var currentBucket: [(Bucket, BucketInfo)] = [];
    private stable var buckets: [Bucket] = [];
    private stable var buckets2: [(Bucket, startTime: Time.Time, startIndex: Nat)] = []; // CreatedTime Desc
    private stable var lastCheckCyclesTime: Time.Time = 0;
    private var blooms = TrieMap.TrieMap<Bucket, BloomFilter>(Principal.equal, Principal.hash); 
    private stable var bloomsEntries : [(Bucket, [[Nat8]])] = []; // for upgrade
    private stable var bloomsEntriesV2 : [(Bucket, (n: Nat, p: Float, num: Nat, filters: [([Nat8], Nat)]))] = []; // for upgrade
    private var blooms2 = TrieMap.TrieMap<Bucket, BloomFilter>(Principal.equal, Principal.hash);
    private stable var blooms2Entries : [(Bucket, [[Nat8]])] = []; // for upgrade
    private stable var blooms2EntriesV2 : [(Bucket, (n: Nat, p: Float, num: Nat, filters: [([Nat8], Nat)]))] = []; // for upgrade
    private var blooms3 = TrieMap.TrieMap<Bucket, BloomFilter>(Principal.equal, Principal.hash);
    private stable var blooms3Entries : [(Bucket, [[Nat8]])] = []; // for upgrade
    private stable var blooms3EntriesV2 : [(Bucket, (n: Nat, p: Float, num: Nat, filters: [([Nat8], Nat)]))] = []; // for upgrade
    private stable var tokens: Trie.Trie<Token, TokenInfo> = Trie.empty(); 
    private stable var storeTxns = List.nil<(Token, DataType, Nat)>();
    private stable var icrc1_storeTxns = List.nil<(Token, DataType, Nat)>();
    private stable var storeErrPool = List.nil<(Token, DataType, Nat)>();
    private stable var tokenStd: Trie.Trie<Token, Text> = Trie.empty(); 
    private stable var lastFetchBucketTime: Int = 0; 
    private stable var lastStorageTime: Int = 0;
    private stable var lastSessions = Deque.empty<(Principal, Nat)>(); 
    private stable var MaxTPS: Nat = 100; //100
    private stable var MaxTransPerAccount: Nat = 60; // xx trans per 1min
    // private stable var ICRC1Tokens: Trie.Trie<Token, (ArchivedCanister, ICRC1Fee, ICRC3BlockIndex)> = Trie.empty(); 
    private stable var ICRC3Tokens: Trie.Trie<Token, (ICRC1Fee, ICRC3BlockIndex)> = Trie.empty(); 
    // Monitor
    private stable var cyclesMonitor: CyclesMonitor.MonitoredCanisters = Trie.empty(); 
    private stable var lastMonitorTime: Time.Time = 0;
    private let sa_zero : [Nat8] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
    private var NumberOfBatchAtOnce: Nat = 100;
    private var lastToken : Text = "";
    private var lastError : Text = "";

    private func _onlyOwner(_caller: Principal) : Bool {
        return Principal.isController(_caller) or _caller == proxyRoot;
    };
    // private func _onlyBucket(_caller: Principal) : Bool {
    //     return Option.isSome(Array.find(buckets2, func (t: (Bucket, startTime: Time.Time, startIndex: Nat)): Bool{
    //         t.0 == _caller
    //     }));
    // };
    private func keyb(t: Blob) : Trie.Key<Blob> { return { key = t; hash = Blob.hash(t) }; };
    private func keyp(t: Principal) : Trie.Key<Principal> { return { key = t; hash = Principal.hash(t) }; };
    private func _now() : Nat{
        return Int.abs(Time.now() / 1000000000);
    };
    private func _natToFloat(_n: Nat) : Float{
        return Float.fromInt64(Int64.fromNat64(Nat64.fromNat(_n)));
    };
    private func _createBloom(_n: ?Nat, _p: ?Float): BloomFilter{
        let n: Nat = Option.get(_n, 100_000);
        let p: Float = Option.get(_p, 0.004);
        return Bloom.AutoScalingBloomFilter<Blob>(n, p, Bloom.blobHash);
    };

    private func _toSaBlob(_sa: ?[Nat8]) : ?Blob{
        switch(_sa){
            case(?(sa)){ 
                if (sa.size() == 0 or sa == sa_zero){
                    return null;
                }else{
                    return ?Blob.fromArray(sa); 
                };
            };
            case(_){ return null; };
        }
    };
    private func _toSaNat8(_sa: ?Blob) : ?[Nat8]{
        switch(_sa){
            case(?(sa)){ 
                if (sa.size() == 0 or sa == Blob.fromArray(sa_zero)){
                    return null;
                }else{
                    return ?Blob.toArray(sa); 
                };
            };
            case(_){ return null; };
        }
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
        buckets2 := Tools.arrayAppend([(bucket, Time.now(), txnCount)], buckets2);
        currentBucket := [(bucket, bucketInfo)];
        blooms.put(bucket, _createBloom(null, null));
        blooms2.put(bucket, _createBloom(null, null));
        blooms3.put(bucket, _createBloom(null, null));
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
        let bucketActor: DRC202Bucket.BucketActor = actor(Principal.toText(_bucket));
        let bucketInfo: BucketInfo = await bucketActor.bucketInfo();
        if (_bucket == currentBucket[0].0){
            currentBucket := [(_bucket, bucketInfo)];
        };
        return bucketInfo;
    };
    // private func _topup(_bucket: Bucket) : async* (){
    //     let bucketActor: DRC202Bucket.BucketActor = actor(Principal.toText(_bucket));
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
    private var lastGetBucketInfoTime: Time.Time = 0;
    private func _getBucket() : async* Bucket{
        if (currentBucket.size() > 0){
            var bucket: Bucket = currentBucket[0].0;
            if (Time.now() > lastGetBucketInfoTime + 2 * 3600 * 1000000000 or currentBucket[0].1.memory > maxMemory * 9 / 10){
                lastGetBucketInfoTime := Time.now();
                try{ 
                    ignore await* _getBucketInfo(currentBucket[0].0);
                }catch(e){};
            };
            if (currentBucket[0].1.memory >= maxMemory or (currentBucket[0].1.memory >= maxMemory / 2 and Text.contains(lastError, #text("exceeded the instruction limit for single message execution")))){
                bucket := await* _newBucket();
                lastError := "Error: exceeded the instruction limit";
                NumberOfBatchAtOnce := 100;
            }else if (NumberOfBatchAtOnce > 10 and currentBucket[0].1.memory >= maxMemory * 4 / 5){
                NumberOfBatchAtOnce := 10;
            }else if (NumberOfBatchAtOnce > 25 and currentBucket[0].1.memory >= maxMemory * 3 / 5){
                NumberOfBatchAtOnce := 25;
            }else if (NumberOfBatchAtOnce > 50 and currentBucket[0].1.memory >= maxMemory / 2){
                NumberOfBatchAtOnce := 50;
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
        // if (_bucket != defaultBucket){
            switch(blooms.get(_bucket)){
                case(?(bloom)){
                    bloom.add(_sid);
                    blooms.put(_bucket, bloom);
                };
                case(_){
                    let bloom = _createBloom(null, null);
                    bloom.add(_sid);
                    blooms.put(_bucket, bloom);
                };
            };
        // };
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
        if (is_default_proxy and step == _step and _step == 0){ // fix default bucket
            return ?defaultBucket;
        }else{
            return null;
        };
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
            if (res.size() >= 5){
                return res;
            };
        };
        if (is_default_proxy and res.size() == 0){ // fix default bucket
            res := [defaultBucket];
        };
        return res;
    };
    private func _addBloom2(_bucket: Bucket, _iid: Blob) : (){
        // if (_bucket != defaultBucket){
            switch(blooms2.get(_bucket)){
                case(?(bloom)){
                    bloom.add(_iid);
                    blooms2.put(_bucket, bloom);
                };
                case(_){
                    let bloom = _createBloom(null, null);
                    bloom.add(_iid);
                    blooms2.put(_bucket, bloom);
                };
            };
        // };
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
        if (is_default_proxy and step == _step and _step == 0){ // fix default bucket
            return ?defaultBucket;
        }else{
            return null;
        };
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
            if (res.size() >= 5){
                return res;
            };
        };
        if (is_default_proxy and res.size() == 0){ // fix default bucket
            res := [defaultBucket];
        };
        return res;
    };
    private func _addBloom3(_bucket: Bucket, _aid: Blob) : (){
        // if (_bucket != defaultBucket){
            switch(blooms3.get(_bucket)){
                case(?(bloom)){
                    bloom.add(_aid);
                    blooms3.put(_bucket, bloom);
                };
                case(_){
                    let bloom = _createBloom(null, null);
                    bloom.add(_aid);
                    blooms3.put(_bucket, bloom);
                };
            };
        // };
    };
    private func _filterBloom3(_aid: Blob, _bucket: Principal) : ?Bucket{
        var step: Nat = 0;
        var hashs: [Hash.Hash] = [];
        for ((bucket, bloom) in blooms3.entries()){
            if (hashs.size() == 0){
                hashs := Bloom.blobHash(_aid, bloom.getK());
            };
            if (_bucket == bucket and bloom.check2(hashs)){
                return ?_bucket;
            };
        };
        return null;
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
            // if (res.size() >= 5){
            //     return res;
            // };
        };
        if (is_default_proxy){ // fix default bucket
            res := Tools.arrayAppend(res, [defaultBucket]);
        };
        return res;
    };
    private func _postLog(_txns: List.List<(Token, DataType, Nat)>) : (){
        var bucket: Bucket = currentBucket[0].0;
        for ((token, dataType, callCount) in Array.reverse(List.toArray(_txns)).vals()){
            switch(dataType){
                case(#Txn(txn)){
                    let sid = TokenRecord.generateSid(token, txn.txid);
                    let iid = TokenRecord.generateIid(token, txn.index);
                    // let aid1 = TokenRecord.generateAid(token, txn.caller);
                    let aid2 = TokenRecord.generateAid(token, txn.transaction.from);
                    let aid3 = TokenRecord.generateAid(token, txn.transaction.to);
                    _addBloom(bucket, sid);
                    _addBloom2(bucket, iid);
                    if (txn.transaction.from != Tools.blackhole() and _filterBloom3(aid2, bucket) == null){
                        _addBloom3(bucket, aid2);
                    };
                    if (txn.transaction.to != Tools.blackhole() and txn.transaction.to != txn.transaction.from and _filterBloom3(aid3, bucket) == null){
                        _addBloom3(bucket, aid3);
                    };
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
    private func _execStorage(_type: {#original; #sync}, _number: ?Nat) : async* (){
        var bucket: Bucket = currentBucket[0].0;
        if (Time.now() > lastFetchBucketTime + 5*60*1000000000){
            bucket := await* _getBucket();
            lastFetchBucketTime := Time.now();
        };
        let number = Option.get(_number, NumberOfBatchAtOnce);
        
        var _storeTxns = storeTxns;
        if (_type == #sync){
            _storeTxns := icrc1_storeTxns;
        };
        let bucketActor: DRC202Bucket.BucketActor = actor(Principal.toText(bucket));
        var _storing = List.nil<(Token, DataType, Nat)>();
        var _pending = List.nil<(Token, DataType, Nat)>();
        var _bytesStoring = List.nil<(Token, DataType, Nat)>();
        var storeBatch: [(_sid: Sid, _txn: TxnRecord)] = [];
        var storeBytesBatch: [(_sid: Sid, _data: [Nat8])] = [];
        var i: Nat = 0;
        for ((token, dataType, callCount) in List.toArray(List.reverse(_storeTxns)).vals()){
            if (i < number){
                switch(dataType){
                    case(#Txn(txn)){
                        let sid = TokenRecord.generateSid(token, txn.txid);
                        let iid = TokenRecord.generateIid(token, txn.index);
                        storeBatch := Tools.arrayAppend(storeBatch, [(_blobAppend([sid, iid, Principal.toBlob(token)]), txn)]); // the first item at 0 position
                        _storing := List.push((token, dataType, callCount), _storing);
                    };
                    case(#Bytes(txn)){
                        let sid = TokenRecord.generateSid(token, txn.txid);
                        storeBytesBatch := Tools.arrayAppend(storeBytesBatch, [(sid, txn.data)]); // the first item at 0 position
                        _bytesStoring := List.push((token, dataType, callCount), _bytesStoring);
                    };
                };
            }else{
                _pending := List.push((token, dataType, callCount), _pending);
            };
            i += 1;
        };
        if (_type == #sync){
            icrc1_storeTxns := _pending;
        }else{
            storeTxns := _pending;
        };

        if (storeBatch.size() > 0 or storeBytesBatch.size() > 0){
            if (storeBatch.size() > 0){
                try{
                    if (_type == #sync){
                        await bucketActor.storeBatch2(storeBatch, true);
                    }else{
                        await bucketActor.storeBatch(storeBatch);
                    };
                    _postLog(_storing);
                }catch(e){
                    lastGetBucketInfoTime := 0;
                    lastFetchBucketTime := 0;
                    NumberOfBatchAtOnce := Nat.max(NumberOfBatchAtOnce / 2, 1);
                    lastError := Error.message(e);
                    if (_type == #sync){
                        lastToken := "icrc1";
                        icrc1_storeTxns := List.append(icrc1_storeTxns, _storing);
                    }else{
                        lastToken := "drc20";
                        storeTxns := List.append(storeTxns, _storing);
                    };
                };
            };
            if (storeBytesBatch.size() > 0){
                try{
                    await bucketActor.storeBytesBatch(storeBytesBatch);
                    _postLog(_bytesStoring);
                }catch(e){
                    lastGetBucketInfoTime := 0;
                    lastFetchBucketTime := 0;
                    storeTxns := List.append(storeTxns, _storing);
                };
            };
        };
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
        await* _execStorage(#original, null);
    };

    public query func generateTxid(_token: Token, _caller: AccountId, _nonce: Nat): async Txid{
        return DRC202.generateTxid(_token, _caller, _nonce);
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
    public query func getBloomMK() : async ?{m: Nat32; k: Nat32}{
        switch(blooms.get(currentBucket[0].0)){
            case(?bloom){ return ?{m = bloom.getM(); k = bloom.getK() } };
            case(_){ return null; };
        };
    };
    // @deprecated: This method will be deprecated
    public query func bucketList() : async [Bucket]{
        return Array.map(buckets2, func(t:(Bucket, Time.Time, Nat)): Bucket{ t.0 });
    };
    public query func bucketListSorted() : async [(Bucket, Time.Time, Nat)]{
        return buckets2;
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
        let token: Token = msg.caller;
        storeTxns := List.push((token, #Txn(_txn), 0), storeTxns);
        if (Time.now() > lastStorageTime + 5*1000000000 and _tps(5, null).1 < MaxTPS*7){
            lastStorageTime := Time.now();
            await* _execStorage(#original, null);
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
        let token: Token = msg.caller;
        for (_txn in _txns.vals()){
            storeTxns := List.push((token, #Txn(_txn), 0), storeTxns);
        };
        if (Time.now() > lastStorageTime + 5*1000000000 and _tps(5, null).1 < MaxTPS*7){
            lastStorageTime := Time.now();
            await* _execStorage(#original, null);
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
        let token: Token = msg.caller;
        storeTxns := List.push((token, #Bytes({txid = _txid; data = _data;}), 0), storeTxns);
        if (Time.now() > lastStorageTime + 5*1000000000 and _tps(5, null).1 < MaxTPS*7){
            lastStorageTime := Time.now();
            await* _execStorage(#original, null);
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
        let token: Token = msg.caller;
        for ((_txid, _data) in _txns.vals()){
            assert(_data.size() <= 128 * 1024); // 128 KB
            storeTxns := List.push((token, #Bytes({txid = _txid; data = _data;}), 0), storeTxns);
        };
        if (Time.now() > lastStorageTime + 5*1000000000 and _tps(5, null).1 < MaxTPS*7){
            lastStorageTime := Time.now();
            await* _execStorage(#original, null);
        };
    };
    // @deprecated: This method will be deprecated
    public query func bucket(_token: Token, _txid: Txid, _step: Nat, _version: ?Nat8) : async (bucket: ?Bucket){
        let _sid = TokenRecord.generateSid(_token, _txid);
        return _checkBloom(_sid, _step);
    };
    // @deprecated: This method will be deprecated
    public query func bucketByIndex(_token: Token, _blockIndex: Nat, _step: Nat, _version: ?Nat8) : async (bucket: ?Principal){
        let _iid = TokenRecord.generateIid(_token, _blockIndex);
        return _checkBloom2(_iid, _step);
    };
    private func _locationV1(_token: Token, _arg: {#txid: Txid; #index: Nat; #account: AccountId}) : [Bucket]{
        var res : [Bucket] = [];
        switch(_arg){
            case(#txid(txid)){
                let _sid = TokenRecord.generateSid(_token, txid);
                res := _checkBloom_all(_sid);
            };
            case(#index(index)){
                let _iid = TokenRecord.generateIid(_token, index);
                res := _checkBloom2_all(_iid);
            };
            case(#account(account)){
                let _aid = TokenRecord.generateAid(_token, account);
                res := _checkBloom3_all(_aid);
            };
        };
        return res;
    };
    public query func location(_token: Token, _arg: {#txid: Txid; #index: Nat; #account: AccountId}, _version: ?Nat8) : async [Bucket]{
        let res = _locationV1(_token, _arg);
        if (res.size() > 1){ // CreateTime DESC
            let tmp = Array.filter(buckets2, func (t: (Bucket, Time.Time, Nat)): Bool{
                Option.isSome(Array.find(res, func (x: Bucket): Bool { t.0 == x }))
            });
            return Array.map(tmp, func(t:(Bucket, Time.Time, Nat)): Bucket{ t.0 });
        }else{
            return res;
        };
    };
    public query func minInterval() : async Int{ //ns
        return 60*1000000000 / MaxTransPerAccount;
    };
    public query func tpsStats() : async (Float, Nat){
        return (_natToFloat(_tps(60, null).1) / 10.0, List.size(lastSessions.0)+List.size(lastSessions.1));
    };


    /*
    * ICRC1 token records
    */
    private func _getCaller(_token: Token, _txn: ICRC3.Transaction) : ICRC3.Account{
        if(_txn.kind == "burn"){
            return switch(_txn.burn){
                case(?burn){ burn.from };
                case(_){ {owner = _token; subaccount = null} };
            };
        }else if(_txn.kind == "transfer"){
            return switch(_txn.transfer){
                case(?transfer){ transfer.from };
                case(_){ {owner = _token; subaccount = null} };
            };
        }else{
            return {owner = _token; subaccount = null};
        };
    };
    private func _getFromAccount(_token: Token, _txn: ICRC3.Transaction) : ICRC3.Account{
        if(_txn.kind == "burn"){
            return switch(_txn.burn){
                case(?burn){ burn.from };
                case(_){ {owner = _token; subaccount = null} };
            };
        }else if(_txn.kind == "transfer"){
            return switch(_txn.transfer){
                case(?transfer){ transfer.from };
                case(_){ {owner = _token; subaccount = null} };
            };
        }else{
            return {owner = _token; subaccount = null};
        };
    };
    private func _getToAccount(_token: Token, _txn: ICRC3.Transaction) : ICRC3.Account{
        if(_txn.kind == "mint"){
            return switch(_txn.mint){
                case(?mint){ mint.to };
                case(_){ {owner = _token; subaccount = null} };
            };
        }else if(_txn.kind == "burn"){
            return {owner = _token; subaccount = null};
        }else if(_txn.kind == "transfer"){
            return switch(_txn.transfer){
                case(?transfer){ transfer.to };
                case(_){ {owner = _token; subaccount = null} };
            };
        }else{
            return {owner = _token; subaccount = null};
        };
    };
    private func _getFrom(_token: Token, _txn: ICRC3.Transaction) : Blob{
        if(_txn.kind == "burn"){
            return switch(_txn.burn){
                case(?burn){ Tools.principalToAccountBlob(burn.from.owner, _toSaNat8(burn.from.subaccount)) };
                case(_){ Tools.blackhole() };
            };
        }else if(_txn.kind == "transfer"){
            return switch(_txn.transfer){
                case(?transfer){ Tools.principalToAccountBlob(transfer.from.owner, _toSaNat8(transfer.from.subaccount)) };
                case(_){ Tools.blackhole() };
            };
        }else{
            return Tools.blackhole();
        };
    };
    private func _getTo(_token: Token, _txn: ICRC3.Transaction) : Blob{
        if(_txn.kind == "mint"){
            return switch(_txn.mint){
                case(?mint){ Tools.principalToAccountBlob(mint.to.owner, _toSaNat8(mint.to.subaccount)) };
                case(_){ Tools.blackhole() };
            };
        }else if(_txn.kind == "burn"){
            return Tools.blackhole();
        }else if(_txn.kind == "transfer"){
            return switch(_txn.transfer){
                case(?transfer){ Tools.principalToAccountBlob(transfer.to.owner, _toSaNat8(transfer.to.subaccount)) };
                case(_){ Tools.principalToAccountBlob(_token, null) };
            };
        }else{
            return Tools.blackhole();
        };
    };
    private func _getValue(_token: Token, _txn: ICRC3.Transaction) : Nat{
        if(_txn.kind == "mint"){
            return switch(_txn.mint){
                case(?mint){ mint.amount };
                case(_){ 0 };
            };
        }else if(_txn.kind == "burn"){
            return switch(_txn.burn){
                case(?burn){ burn.amount };
                case(_){ 0 };
            };
        }else if(_txn.kind == "transfer"){
            return switch(_txn.transfer){
                case(?transfer){ transfer.amount };
                case(_){ 0 };
            };
        }else{
            return 0;
        };
    };
    private func _getData(_token: Token, _txn: ICRC3.Transaction) : ?Blob{
        if(_txn.kind == "mint"){
            return switch(_txn.mint){
                case(?mint){ mint.memo };
                case(_){ null };
            };
        }else if(_txn.kind == "burn"){
            return switch(_txn.burn){
                case(?burn){ burn.memo };
                case(_){ null };
            };
        }else if(_txn.kind == "transfer"){
            return switch(_txn.transfer){
                case(?transfer){ transfer.memo };
                case(_){ null };
            };
        }else{
            return null;
        };
    };
    private func _getOperation(_token: Token, _txn: ICRC3.Transaction) : DRC202.Operation{
        if(_txn.kind == "mint"){
            return #transfer({ action = #mint });
        }else if(_txn.kind == "burn"){
            return #transfer({ action = #burn });
        }else if(_txn.kind == "transfer"){
            return #transfer({ action = #send });
        }else if(_txn.kind == "approve"){
            var amount: Nat = 0;
            switch(_txn.approve){
                case(?approve){ amount := approve.amount };
                case(_){};
            };
            return #approve({ allowance = amount });
        }else{
            return #transfer({ action = #send });
        };
    };
    private func _format(_token: Token, _fee: Nat, _index: ICRC3BlockIndex, _txn: ICRC3.Transaction) : TxnRecord{
        let caller = _getCaller(_token, _txn);
        let callerAccountId = _getFrom(_token, _txn); // Tools.principalToAccountBlob(caller.owner, caller.subaccount);
        let txid = DRC202.generateTxid(_token, callerAccountId, _index);
        return {
            txid = txid; // Transaction id
            transaction = {
                from = _getFrom(_token, _txn); // from
                to = _getTo(_token, _txn); //to
                value = _getValue(_token, _txn); // amount
                operation = _getOperation(_token, _txn); // DRC202.Operation;
                data = _getData(_token, _txn); // attached data(Blob)
            };
            gas = #token(_fee); // gas
            msgCaller = if (callerAccountId == Tools.blackhole()){ null }else{ ?caller.owner };  // Caller principal
            caller = callerAccountId; // Caller account (Blob)
            index = _index; // Global Index
            nonce = _index; // Nonce of user
            timestamp = Nat64.toNat(_txn.timestamp); // Timestamp (nanoseconds).
        };
    };
    private func _updateIcrc3Token(_token: Token, _blockIndex: ICRC3BlockIndex) : (){
        switch(Trie.get(ICRC3Tokens, keyp(_token), Principal.equal)){
            case(?(fee, index)){
                ICRC3Tokens := Trie.put(ICRC3Tokens, keyp(_token), Principal.equal, (fee, Nat.max(index, _blockIndex))).0;
            };
            case(_){};
        };
    };
    private func _putAccounts(_accounts: [ICRC3.Account]): async (){
        let canister : AccountIdCaches.Self = actor("gpapk-hqaaa-aaaak-aex4q-cai");
        Cycles.add(10000);
        await canister.put(Array.map(_accounts, func (t: ICRC3.Account): { owner : Principal; subaccount : ?[Nat8] }{
            { owner = t.owner; subaccount = _toSaNat8(t.subaccount) }
        }));
    };
    private func _fetch_icrc3Txns(_token: Principal, _start: Nat, _length: Nat, _fee: Nat) : async* {txns: [(Token, DataType, Nat)]; accounts: [ICRC3.Account]}{
        let icrc3: ICRC3.Self = actor(Principal.toText(_token));
        let res = await icrc3.get_transactions({ start = _start; length = _length });
        var length = Array.size(res.transactions);
        var txns : [(Token, DataType, Nat)] = [];
        var accounts: [ICRC3.Account] = [];
        for (archived in res.archived_transactions.vals()){
            let archivedRes = await archived.callback({ start = archived.start; length = archived.length });
            length += Array.size(archivedRes.transactions);
            var i : Nat = archived.start;
            for (txn in archivedRes.transactions.vals()){
                txns := Tools.arrayAppend([(_token, #Txn(_format(_token, _fee, i, txn)), 0)], txns);
                let from = _getFromAccount(_token, txn);
                let to = _getToAccount(_token, txn);
                if (Option.isNull(Array.find(accounts, func (t: ICRC3.Account): Bool{ from == t }))){
                    accounts := Tools.arrayAppend(accounts, [from]);
                };
                if (Option.isNull(Array.find(accounts, func (t: ICRC3.Account): Bool{ to == t }))){
                    accounts := Tools.arrayAppend(accounts, [to]);
                };
                i += 1;
            };
        };
        var i : Nat = Nat.max(_start, res.first_index);
        for (txn in res.transactions.vals()){
            txns := Tools.arrayAppend([(_token, #Txn(_format(_token, _fee, i, txn)), 0)], txns);
            let from = _getFromAccount(_token, txn);
            let to = _getToAccount(_token, txn);
            if (Option.isNull(Array.find(accounts, func (t: ICRC3.Account): Bool{ from == t }))){
                accounts := Tools.arrayAppend(accounts, [from]);
            };
            if (Option.isNull(Array.find(accounts, func (t: ICRC3.Account): Bool{ to == t }))){
                accounts := Tools.arrayAppend(accounts, [to]);
            };
            i += 1;
        };
        return {txns = txns; accounts = accounts };
    };
    private func _icrc3Sync() : async* (){
        let sizePerPage : Nat = 1000; // Multiples of 50
        for ((_token, (_fee, _index)) in Trie.iter(ICRC3Tokens)){
            if (List.size(icrc1_storeTxns) < 5000 and NumberOfBatchAtOnce >= 8){
                try{
                    let data = await* _fetch_icrc3Txns(_token, _index, sizePerPage, _fee);
                    icrc1_storeTxns := List.append(icrc1_storeTxns, List.fromArray(data.txns));
                    _updateIcrc3Token(_token, _index + data.txns.size());
                    if (data.accounts.size() > 0){
                        let f = _putAccounts(data.accounts);
                    };
                    for (x in Iter.range(0, data.txns.size() / NumberOfBatchAtOnce + 1)){
                        await* _execStorage(#sync, null);
                    };
                }catch(e){
                    var start = _index;
                    var size: Nat = 0;
                    for (i in Iter.range(1, sizePerPage / 50)){
                        try{
                            let data = await* _fetch_icrc3Txns(_token, start, 50, _fee);
                            icrc1_storeTxns := List.append(icrc1_storeTxns, List.fromArray(data.txns));
                            size += data.txns.size();
                            _updateIcrc3Token(_token, start + data.txns.size());
                            if (data.accounts.size() > 0){
                                let f = _putAccounts(data.accounts);
                            };
                            start += data.txns.size();
                        }catch(e){
                            for (i in Iter.range(1, 50)){
                                try{
                                    let data = await* _fetch_icrc3Txns(_token, start, 1, _fee);
                                    icrc1_storeTxns := List.append(icrc1_storeTxns, List.fromArray(data.txns));
                                    size += data.txns.size();
                                    _updateIcrc3Token(_token, start + data.txns.size());
                                    if (data.accounts.size() > 0){
                                        let f = _putAccounts(data.accounts);
                                    };
                                    start += data.txns.size();
                                }catch(e){
                                    start += 1;
                                };
                            };
                        };
                    };
                    for (x in Iter.range(0, size / NumberOfBatchAtOnce + 1)){
                        await* _execStorage(#sync, null);
                    };
                };
            }else{
                await* _execStorage(#sync, null);
            };
        };
    };
    public shared(msg) func debug_fetchIcrc1Txns(_token: Principal, _start: Nat, _length: Nat, _fee: Nat): async Nat{
        assert(_onlyOwner(msg.caller));
        let data = await* _fetch_icrc3Txns(_token: Principal, _start, _length, _fee);
        icrc1_storeTxns := List.append(icrc1_storeTxns, List.fromArray(data.txns));
        if (data.accounts.size() > 0){
            let f = _putAccounts(data.accounts);
        };
        for (x in Iter.range(0, _length / NumberOfBatchAtOnce + 1)){
            await* _execStorage(#sync, null);
        };
        return data.txns.size();
    };
    public shared(msg) func debug_resetIcrc1TokensIndex() : async (){
        assert(_onlyOwner(msg.caller));
        icrc1_storeTxns := List.nil();
        for ((tokenCanisterId, (fee, index)) in Trie.iter(ICRC3Tokens)){
            ICRC3Tokens := Trie.put(ICRC3Tokens, keyp(tokenCanisterId), Principal.equal, (fee, 0)).0;
        };
    };
    public shared(msg) func initIcrc1Tokens() : async (){
        assert(_onlyOwner(msg.caller));
        for ((tokenCanisterId, index) in initSNSTokens.vals()){
            let icrc1: ICRC1.Self = actor(Principal.toText(tokenCanisterId));
            let fee = await icrc1.icrc1_fee();
            switch(Trie.get(ICRC3Tokens, keyp(tokenCanisterId), Principal.equal)){
                case(?(fee_, index_)){
                    ICRC3Tokens := Trie.put(ICRC3Tokens, keyp(tokenCanisterId), Principal.equal, (fee, index_)).0;
                };
                case(_){
                    ICRC3Tokens := Trie.put(ICRC3Tokens, keyp(tokenCanisterId), Principal.equal, (fee, index)).0;
                    tokenStd := Trie.put(tokenStd, keyp(tokenCanisterId), Principal.equal, "icrc1").0;
                };
            };
        };
    };
    public shared(msg) func addIcrc1Token(_token: Token) : async (){
        assert(_onlyOwner(msg.caller));
        let icrc1: ICRC1.Self = actor(Principal.toText(_token));
        let fee = await icrc1.icrc1_fee();
        switch(Trie.get(ICRC3Tokens, keyp(_token), Principal.equal)){
            case(?(fee_, index_)){
                ICRC3Tokens := Trie.put(ICRC3Tokens, keyp(_token), Principal.equal, (fee, index_)).0;
            };
            case(_){
                ICRC3Tokens := Trie.put(ICRC3Tokens, keyp(_token), Principal.equal, (fee, 0)).0;
                tokenStd := Trie.put(tokenStd, keyp(_token), Principal.equal, "icrc1").0;
            };
        };
    };
    public query func icrc1Tokens(): async [(Token, ICRC3BlockIndex)]{
        return Trie.toArray<Token, (ICRC1Fee, ICRC3BlockIndex), (Token, ICRC3BlockIndex)>(ICRC3Tokens, 
        func (k: Token, v: (ICRC1Fee, ICRC3BlockIndex)): (Token, ICRC3BlockIndex){
            (k, v.1)
        });
    };
    public shared(msg) func icrc3sync() : async (){
        assert(_onlyOwner(msg.caller));
        await* _icrc3Sync();
    };
    public query func getPoolSize() : async (Nat, Nat, Nat){
        return (List.size(storeTxns), List.size(icrc1_storeTxns), NumberOfBatchAtOnce);
    };
    public shared(msg) func debug_execStorage(_number: ?Nat): async (){
        assert(_onlyOwner(msg.caller));
        await* _execStorage(#sync, _number);
    };
    public shared(msg) func debug_lastError(): async Text{
        assert(_onlyOwner(msg.caller));
        return lastToken # ":" # lastError;
    };
    public shared(msg) func debug_storeTxns(): async [(Token, DataType, Nat)]{
        assert(_onlyOwner(msg.caller));
        return List.toArray(storeTxns);
    };
    
    /* 
    * Owner's Management
    */
    // public query func getOwner() : async Principal{  
    //     return owner;
    // };
    // public shared(msg) func changeOwner(_newOwner: Principal) : async Bool{  
    //     assert(_onlyOwner(msg.caller));
    //     owner := _newOwner;
    //     return true;
    // };
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
    public shared(msg) func stop() : async (Nat, [(Token, ICRC3BlockIndex)]) {
        assert(_onlyOwner(msg.caller));
        isStopped := true; /*config*/
        return (txnCount,
            Trie.toArray<Token, (ICRC1Fee, ICRC3BlockIndex), (Token, ICRC3BlockIndex)>(ICRC3Tokens, 
            func (k: Token, v: (ICRC1Fee, ICRC3BlockIndex)): (Token, ICRC3BlockIndex){
                (k, v.1)
            })
        );
    };

    // Reset Blooms
    public shared(msg) func setBloom(_bucket: Principal): async (){
        assert(_onlyOwner(msg.caller));
        let bucket: actor{
            queryBloom: shared query (_page: Nat/*base 0*/) -> async (sids: [Blob], iids: [Blob]);
            queryBloomAccounts: shared query (_page: Nat/*base 0*/) -> async (aids: [Blob]);
        } = actor(Principal.toText(_bucket)); 
        var p: Nat = 0;
        var completed: Bool = false;
        while(not(completed)){
            let (sids, iids) = await bucket.queryBloom(p);
            p += 1;
            if (sids.size() == 0){
                completed := true;
            };
            for (sid in sids.vals()){
                _addBloom(_bucket, sid);
            };
            for (iid in iids.vals()){
                _addBloom2(_bucket, iid);
            };
        };
    };
    public shared(msg) func setBloomAccounts(_bucket: Principal): async (){
        assert(_onlyOwner(msg.caller));
        let bucket: actor{
            queryBloom: shared query (_page: Nat/*base 0*/) -> async (sids: [Blob], iids: [Blob]);
            queryBloomAccounts: shared query (_page: Nat/*base 0*/) -> async (aids: [Blob]);
        } = actor(Principal.toText(_bucket)); 
        var p: Nat = 0;
        var completed: Bool = false;
        while(not(completed)){
            let (aids) = await bucket.queryBloomAccounts(p);
            p += 1;
            if (aids.size() == 0){
                completed := true;
            };
            for (aid in aids.vals()){
                _addBloom3(_bucket, aid);
            };
        };
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
    public shared(msg) func debug_monitor(): async (){
        assert(_onlyOwner(msg.caller));
        let monitor = await* CyclesMonitor.monitor(Principal.fromActor(this), cyclesMonitor, bucketCyclesInit, bucketCyclesInit * 10, 0);
        if (Trie.size(cyclesMonitor) == Trie.size(monitor)){
            cyclesMonitor := monitor;
        };
    };

    public query func debug_bloomsStatus(_index: Nat): async ([(Bucket, (n: Nat, p: Float, num: Nat, filters: [(length: Nat, nonZero: Nat, Nat)]))]){
        var bloomsData = blooms;
        if (_index == 2){
            bloomsData := blooms2;
        }else if (_index == 3){
            bloomsData := blooms3;
        };
        var size : Nat = bloomsData.size();
        var temp : [var (Bucket, (n: Nat, p: Float, num: Nat, filters: [(length: Nat, nonZero: Nat, Nat)]))] = 
        Array.init<(Bucket, (Nat, Float, Nat, [(Nat, Nat, Nat)]))>(size, (owner, (0, 0, 0, [])));
        var i : Nat = 0;
        label Test1 for ((k, v) in bloomsData.entries()) {
            let blms = v.getData();
            var stats: [(length: Nat, nonZero: Nat, Nat)] = [];
            label Test2 for ((data, num) in blms.vals()){
                var x: Nat = 0;
                var y: Nat = 0;
                for (bit in data.vals()){
                    x += 1;
                    if (bit != (0: Nat8)){ y += 1 };
                };
                stats := Tools.arrayAppend(stats, [(x, y, num)]);
                // break Test2;
            };
            temp[i] := (k, (v.getN(), v.getP(), v.getNumItems(), stats));
            i += 1;
        };
        return Array.freeze(temp);
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

    private var isIcrc3Syncing : Bool = false;
    private var lastIcrc3SyncTime : Nat = 0;
    private var isTimerRunning: Bool = false;
    private func timerLoop() : async (){
        if (isTimerRunning){
            return ();
        };
        isTimerRunning := true;
        if (not(isStopped) and NumberOfBatchAtOnce > 1 and (not(isIcrc3Syncing) or _now() > lastIcrc3SyncTime + 900)){
            isIcrc3Syncing := true;
            lastIcrc3SyncTime := _now();
            try{
                await* _execStorage(#sync, null);
                await* _execStorage(#original, null);
                await* _icrc3Sync();
            }catch(e){};
            isIcrc3Syncing := false;
        };
        if (Time.now() > lastMonitorTime + 6 * 3600 * 1000000000){
            try{ 
                let monitor = await* CyclesMonitor.monitor(Principal.fromActor(this), cyclesMonitor, bucketCyclesInit, bucketCyclesInit * 10, 0);
                if (Trie.size(cyclesMonitor) == Trie.size(monitor)){
                    cyclesMonitor := monitor;
                };
                lastMonitorTime := Time.now();
             }catch(e){};
        };
        isTimerRunning := false;
    };
    private var timerId: Nat = 0;
    public shared(msg) func timerStart(_intervalSeconds: Nat): async (){
        assert(_onlyOwner(msg.caller));
        Timer.cancelTimer(timerId);
        timerId := Timer.recurringTimer(#seconds(_intervalSeconds), timerLoop);
    };
    public shared(msg) func timerStop(): async (){
        assert(_onlyOwner(msg.caller));
        Timer.cancelTimer(timerId);
    };

    /*
    * upgrade functions
    */
    public shared(msg) func debug_clearBlooms(_bucket: Bucket): async (){
        assert(_onlyOwner(msg.caller));
        blooms.put(_bucket, _createBloom(null, null));
        blooms2.put(_bucket, _createBloom(null, null));
        blooms3.put(_bucket, _createBloom(null, null));
    };
    system func preupgrade() {
        var size : Nat = blooms.size();
        var temp : [var (Bucket, (n: Nat, p: Float, num: Nat, filters: [([Nat8], Nat)]))] = 
        Array.init<(Bucket, (Nat, Float, Nat, [([Nat8], Nat)]))>(size, (owner, (0, 0, 0, [])));
        var i : Nat = 0;
        for ((k, v) in blooms.entries()) {
            temp[i] := (k, (v.getN(), v.getP(), v.getNumItems(), v.getData()));
            i += 1;
        };
        bloomsEntries := [];
        bloomsEntriesV2 := Array.freeze(temp);

        size := blooms2.size();
        var temp2 : [var (Bucket, (n: Nat, p: Float, num: Nat, filters: [([Nat8], Nat)]))] = 
        Array.init<(Bucket, (Nat, Float, Nat, [([Nat8], Nat)]))>(size, (owner, (0, 0, 0, [])));
        i := 0;
        for ((k, v) in blooms2.entries()) {
            temp2[i] := (k, (v.getN(), v.getP(), v.getNumItems(), v.getData()));
            i += 1;
        };
        blooms2Entries := [];
        blooms2EntriesV2 := Array.freeze(temp2);

        size := blooms3.size();
        var temp3 : [var (Bucket, (n: Nat, p: Float, num: Nat, filters: [([Nat8], Nat)]))] = 
        Array.init<(Bucket, (Nat, Float, Nat, [([Nat8], Nat)]))>(size, (owner, (0, 0, 0, [])));
        i := 0;
        for ((k, v) in blooms3.entries()) {
            temp3[i] := (k, (v.getN(), v.getP(), v.getNumItems(), v.getData()));
            i += 1;
        };
        blooms3Entries := [];
        blooms3EntriesV2 := Array.freeze(temp3);

        Timer.cancelTimer(timerId);
    };

    system func postupgrade() {
        if (bloomsEntries.size() > 0){
            for ((k, v) in bloomsEntries.vals()) {
                let temp = _createBloom(?100000, ?0.004);
                temp.setData(Array.map<[Nat8], ([Nat8], Nat)>(v, func (t: [Nat8]): ([Nat8], Nat){ (t, 0) }), 0);
                blooms.put(k, temp);
            };
            for ((k, v) in blooms2Entries.vals()) {
                let temp = _createBloom(?100000, ?0.004);
                temp.setData(Array.map<[Nat8], ([Nat8], Nat)>(v, func (t: [Nat8]): ([Nat8], Nat){ (t, 0) }), 0);
                blooms2.put(k, temp);
            };
            for ((k, v) in blooms3Entries.vals()) {
                let temp = _createBloom(?100000, ?0.004);
                temp.setData(Array.map<[Nat8], ([Nat8], Nat)>(v, func (t: [Nat8]): ([Nat8], Nat){ (t, 0) }), 0);
                blooms3.put(k, temp);
            };
        }else{ // V2
            for ((k, (n, p, num, v)) in bloomsEntriesV2.vals()) {
                let temp = _createBloom(?n, ?p);
                temp.setData(v, num);
                blooms.put(k, temp);
            };
            bloomsEntriesV2 := [];
            for ((k, (n, p, num, v)) in blooms2EntriesV2.vals()) {
                let temp = _createBloom(?n, ?p);
                temp.setData(v, num);
                blooms2.put(k, temp);
            };
            blooms2EntriesV2 := [];
            for ((k, (n, p, num, v)) in blooms3EntriesV2.vals()) {
                let temp = _createBloom(?n, ?p);
                temp.setData(v, num);
                blooms3.put(k, temp);
            };
            blooms3EntriesV2 := [];
        };

        if (buckets2.size() == 0){
            buckets2 := Array.map<Bucket, (Bucket, Time.Time, Nat)>(buckets, func(t: Bucket): (Bucket, Time.Time, Nat){ (t, 0, 0) });
        };

        timerId := Timer.recurringTimer(#seconds(60), timerLoop);
        
    };
}
