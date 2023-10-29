/**
 * Module     : DRC205Root.mo
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Canister   : lw5dr-uiaaa-aaaak-ae2za-cai  (Test: lr4ff-zqaaa-aaaak-ae2zq-cai)
 * Github     : https://github.com/iclighthouse/DRC_standards/
 */

import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Option "mo:base/Option";
import Array "mo:base/Array";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Trie "mo:base/Trie";
import Tools "mo:icl/Tools";
import Timer "mo:base/Timer";
import Iter "mo:base/Iter";
import Cycles "mo:base/ExperimentalCycles";
import CyclesMonitor "mo:icl/CyclesMonitor";
import CyclesWallet "mo:icl/CyclesWallet";
import IC "mo:icl/IC";
import Hex "mo:icl/Hex";
import T "mo:icl/DRC205Types";
import DRC205Proxy "DRC205Proxy";

shared(installMsg) actor class ProxyRoot() = this {
    let app_debug: Bool = false; /*config*/ 
    var INIT_CYCLES: Nat = 50_000_000_000_000; //50T
    if (app_debug){
        INIT_CYCLES := 1_000_000_000_000; //1.0T
    };
    private stable var maxMemory: Nat = 3800*1000*1000; // 3.8G /*config*/
    // Supports multiple DRC205Proxies, each of which can hold about 1 billion records.
    private stable var proxyDefault: Principal = Principal.fromText("6ylab-kiaaa-aaaak-aacga-cai"); 
    if (app_debug){
        proxyDefault := Principal.fromText("ix3cb-4iaaa-aaaak-aagbq-cai");
    };
    private stable var proxies: [(canisterId: Principal, startTime: Time.Time, startIndex: Nat)] = [(proxyDefault, 0, 0)]; // Latest in position 0
    private stable var proxyCurrent: (canisterId: Principal, startTime: Time.Time, startIndex: Nat) = (proxyDefault, 0, 0); 
    // Monitor
    private stable var cyclesMonitor: CyclesMonitor.MonitoredCanisters = Trie.empty(); 
    private stable var lastMonitorTime: Time.Time = 0;

    private func _onlyOwner(_caller: Principal) : Bool {
        return Principal.isController(_caller);
    };
    private func _onlyProxy(_caller: Principal) : Bool {
        return Option.isSome(Array.find(proxies, func(t: (Principal, Time.Time, Nat)): Bool{ t.0 == _caller }));
    };

    // Multi-Proxy
    private func _addProxy(_canisterId: Principal, _startTime: Time.Time, _startIndex: Nat, _isCurrentProxy: Bool): (){
        proxies := Array.filter(proxies, func (t: (Principal, Time.Time, Nat)):Bool{ t.0 != _canisterId });
        proxies := Tools.arrayAppend([(_canisterId, _startTime, _startIndex)], proxies);
        if (_isCurrentProxy){
            proxyCurrent := (_canisterId, _startTime, _startIndex); /*config*/
        };
    };
    private func _removeProxy(_removeCanisterId: Principal, _currentProxy: ?Principal) : (){
        proxies := Array.filter(proxies, func (t: (Principal, Time.Time, Nat)):Bool{ t.0 != _removeCanisterId });
        switch(Array.find(proxies, func (t: (Principal, Time.Time, Nat)):Bool{ ?t.0 == _currentProxy })){
            case(?(item)){
                proxyCurrent := item;
            };
            case(_){};
        };
    };
    public shared(msg) func addProxy(_canisterId: Principal, _startTime: Time.Time, _startIndex: Nat, _isCurrentProxy: Bool): async (){
        assert(_onlyOwner(msg.caller) or _onlyProxy(msg.caller));
        _addProxy(_canisterId, _startTime, _startIndex, _isCurrentProxy);
        cyclesMonitor := await* CyclesMonitor.put(cyclesMonitor, _canisterId);
    };
    public shared(msg) func removeProxy(_removeCanisterId: Principal, _currentProxy: ?Principal): async (){
        assert(_onlyOwner(msg.caller));
        _removeProxy(_removeCanisterId, _currentProxy);
        cyclesMonitor := CyclesMonitor.remove(cyclesMonitor, _removeCanisterId);
    };
    public query func proxyList() : async {root: Principal; list: [(Principal, Time.Time, Nat)]; current: ?(Principal, Time.Time, Nat)}{
        return {
            root = Principal.fromActor(this);
            list = proxies;
            current = ?proxyCurrent;
        };
    };
    private func _stopAndCreateNewProxy() : async* (Principal, Time.Time, Nat) {
        let proxyCurrentActor: actor{ stop : shared () -> async Nat } = actor(Principal.toText(proxyCurrent.0));
        let txnCount = await proxyCurrentActor.stop(); /*config*/
            //let txnCount : Nat = 100000;
        Cycles.add(INIT_CYCLES); 
        let proxyActor = await DRC205Proxy.ProxyActor(txnCount, Principal.fromActor(this));
        let proxy = Principal.fromActor(proxyActor);
        let ic: IC.Self = actor("aaaaa-aa");
        let settings = await ic.update_settings({
            canister_id = proxy; 
            settings={ 
                compute_allocation = null;
                controllers = ?[proxy, Principal.fromText("7hdtw-jqaaa-aaaak-aaccq-cai"), Principal.fromActor(this)]; 
                freezing_threshold = null;
                memory_allocation = null;
            };
        });
        _addProxy(proxy, Time.now(), txnCount, true);
        cyclesMonitor := await* CyclesMonitor.put(cyclesMonitor, proxy);
        return (proxy, Time.now(), txnCount);
    };
    public shared(msg) func stopAndCreateNewProxy() : async (Principal, Time.Time, Nat) {
        assert(_onlyOwner(msg.caller));
        return await* _stopAndCreateNewProxy();
    };

    // composite queries

    /// returns txn hash. The parameter `_merge` indicates whether multiple fills of an order need to be merged into a single transaction.  
    public shared composite query func getTxnHash(_app: T.AppId, _txid: T.Txid, _merge: Bool) : async [Hex.Hex]{
        for ((proxy, t, i) in proxies.vals()){
            let proxyActor: T.Self = actor(Principal.toText(proxy));
            let buckets = await proxyActor.location(_app, #txid(_txid), null);
            for (canisterId in buckets.vals()){
                let bucket : T.Bucket = actor(Principal.toText(canisterId));
                let res = await bucket.txnHash(_app, _txid, _merge);
                if (Array.size(res) > 0) return res;
            };
        };
        return [];
    };
    /// returns txn record. 
    public shared composite query func getArchivedTxnBytes(_app: T.AppId, _txid: T.Txid) : async [([Nat8], Time.Time)]{
        for ((proxy, t, i) in proxies.vals()){
            let proxyActor: T.Self = actor(Principal.toText(proxy));
            let buckets = await proxyActor.location(_app, #txid(_txid), null);
            for (bucketId in buckets.vals()){
                let bucket: T.Bucket = actor(Principal.toText(bucketId));
                let res = await bucket.txnBytesHistory(_app, _txid);
                if (Array.size(res) > 0) return res;
            };
        };
        return [];
    };
    public shared composite query func getArchivedTxn(_app: T.AppId, _txid: T.Txid) : async [(T.TxnRecord, Time.Time)]{
        for ((proxy, t, i) in proxies.vals()){
            let proxyActor: T.Self = actor(Principal.toText(proxy));
            let buckets = await proxyActor.location(_app, #txid(_txid), null);
            for (bucketId in buckets.vals()){
                let bucket: T.Bucket = actor(Principal.toText(bucketId));
                let res = await bucket.txnHistory(_app, _txid);
                if (Array.size(res) > 0) return res;
            };
        };
        return [];
    };
    public shared composite query func getArchivedTxnByIndex(_app: T.AppId, _pairBlockIndex: Nat) : async [(T.TxnRecord, Time.Time)]{
        for ((proxy, t, i) in proxies.vals()){
            let proxyActor: T.Self = actor(Principal.toText(proxy));
            let buckets = await proxyActor.location(_app, #index(_pairBlockIndex), null);
            for (canisterId in buckets.vals()){
                let bucket : T.Bucket = actor(Principal.toText(canisterId));
                let res = await bucket.txnByIndex(_app, _pairBlockIndex);
                if (Array.size(res) > 0) return res;
            };
        };
        return [];
    };
    /// Returns archived records. 
    public shared composite query func getArchivedDexTxns(_app: T.AppId, _start_desc: Nat, _length: Nat) : async [T.TxnRecord]{
        var res : [T.TxnRecord] = [];
        var blockIndex: Nat = _start_desc;
        var count : Nat = 0;
        label FindTxnStep1 while (blockIndex > 0 and count < _length){
            label FindTxnStep2 for ((proxy, t, i) in proxies.vals()){
                if (blockIndex < i){
                    continue FindTxnStep2;
                };
                let proxyActor: T.Self = actor(Principal.toText(proxy));
                let buckets = await proxyActor.location(_app, #index(blockIndex), null);
                for (bucketId in buckets.vals()){
                    let bucket: T.Bucket = actor(Principal.toText(bucketId));
                    let txns = await bucket.txnByIndex(_app, blockIndex);
                    if (txns.size() > 0){
                        res := Tools.arrayAppend(res, [txns[txns.size() - 1].0]);
                        blockIndex -= 1;
                        continue FindTxnStep1;
                    };
                };
            };
            count += 1;
        };
        return res;
    };
    /// Returns archived records based on AccountId. This is a composite query method that returns data for only the specified number of buckets.
    public shared composite query func getArchivedAccountTxns(_buckets_offset: ?Nat, _buckets_length: Nat, _accountId: T.AccountId, _app: ?T.AppId, _page: ?Nat32/*base 1*/, _size: ?Nat32) : async 
    {data: [(Principal, [(T.TxnRecord, Time.Time)])]; totalPage: Nat; total: Nat}{
        var offset = Option.get(_buckets_offset, 0);
        let page: Nat32 = Option.get(_page, 1:Nat32);
        var buckets: [Principal] = [];
        var r: [Principal] = [];
        label ProxyLoop for ((proxy, t, i) in proxies.vals()){
            let proxyActor: T.Self = actor(Principal.toText(proxy));
            switch(_app){
                case(?(app)){
                    r := await proxyActor.location(app, #account(_accountId), null);
                    let length = r.size();
                    if (offset >= length){
                        r := [];
                        offset -= length;
                    }else if (offset > 0 and offset < length){
                        r := Tools.slice(r, offset, null);
                        offset := 0;
                    };
                };
                case(_){
                    let temp = await proxyActor.bucketListSorted();
                    r := Array.map(temp, func(t:(T.BucketId, Time.Time, Nat)): T.BucketId{ t.0 });
                    let length = r.size();
                    if (offset >= length){
                        r := [];
                        offset -= length;
                    }else if (offset > 0 and offset < length){
                        r := Tools.slice(r, offset, null);
                        offset := 0;
                    };
                };
            };
            if (offset == 0){
                buckets := Tools.arrayAppend(buckets, r);
                if (buckets.size() >= _buckets_length){
                    buckets := Tools.slice(buckets, 0, ?Nat.sub(Nat.max(_buckets_length, 1), 1));
                    break ProxyLoop;
                };
            };
        };
        var totalPage: Nat = 0;
        var total: Nat = 0;
        var pageOnes: [(bucket: Principal, {data: [(Principal, [(T.TxnRecord, Time.Time)])]; totalPage: Nat; total: Nat})] = [];
        for (bucketId in buckets.vals()){
            let bucket: T.Bucket = actor(Principal.toText(bucketId));
            let r = await bucket.txnByAccountId(_accountId, _app, ?1, _size);
            pageOnes := Tools.arrayAppend(pageOnes, [(bucketId, r)]);
            totalPage += r.totalPage;
            total += r.total;
        };
        if (total > 0){
            var thisBucketIndex: Nat = 0;
            var thisBucket: Principal = pageOnes[thisBucketIndex].0;
            var thisPage: Nat32 = page;
            var preTempTotalPage: Nat = 0;
            var tempTotalPage: Nat = 0;
            for (index in pageOnes.keys()){
                preTempTotalPage := tempTotalPage;
                tempTotalPage += pageOnes[index].1.totalPage;
                if (Nat32.toNat(page) > preTempTotalPage and Nat32.toNat(page) <= tempTotalPage){
                    thisBucketIndex := index;
                    thisBucket := pageOnes[thisBucketIndex].0;
                    thisPage := Nat32.sub(page, Nat32.fromNat(preTempTotalPage));
                };
            };
            if (thisPage == 1){
                return pageOnes[thisBucketIndex].1;
            }else{
                let bucket: T.Bucket = actor(Principal.toText(thisBucket));
                return await bucket.txnByAccountId(_accountId, _app, ?thisPage, _size);
            };
        }else{
            return {data = []; totalPage = 0; total = 0};
        };
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
    

    private func timerLoop() : async (){
        if (Time.now() > lastMonitorTime + 2 * 24 * 3600 * 1000000000){
            try{ 
                if ((await* CyclesMonitor.get_canister_status(proxyCurrent.0)).memory_size > maxMemory){
                    ignore await* _stopAndCreateNewProxy();
                };
                if (Trie.size(cyclesMonitor) == 0){
                    for ((cid, t, i) in proxies.vals()){
                        cyclesMonitor := await* CyclesMonitor.put(cyclesMonitor, cid);
                    };
                };
                cyclesMonitor := await* CyclesMonitor.monitor(Principal.fromActor(this), cyclesMonitor, INIT_CYCLES, INIT_CYCLES * 10, 0);
                lastMonitorTime := Time.now();
             }catch(e){};
        };
    };
    private var timerId: Nat = 0;
    public shared(msg) func timerStart(_intervalSeconds1: Nat): async (){
        assert(_onlyOwner(msg.caller));
        Timer.cancelTimer(timerId);
        timerId := Timer.recurringTimer(#seconds(_intervalSeconds1), timerLoop);
    };
    public shared(msg) func timerStop(): async (){
        assert(_onlyOwner(msg.caller));
        Timer.cancelTimer(timerId);
    };

    system func preupgrade() {
        Timer.cancelTimer(timerId);
    };
    system func postupgrade() {
        timerId := Timer.recurringTimer(#seconds(3600*12), timerLoop);
    };

};