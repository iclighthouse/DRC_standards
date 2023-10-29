/**
 * Module     : DRC202Root.mo
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Canister   : bffvb-aiaaa-aaaak-ae3ba-cai  (Test: bcetv-nqaaa-aaaak-ae3bq-cai)
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
import T "mo:icl/DRC202Types";
import DRC202Proxy "DRC202Proxy";

shared(installMsg) actor class ProxyRoot() = this {
    let app_debug: Bool = false; /*config*/ 
    var INIT_CYCLES: Nat = 50_000_000_000_000; //50T
    if (app_debug){
        INIT_CYCLES := 1_000_000_000_000; //1.0T
    };
    private stable var maxMemory: Nat = 3800*1000*1000; // 3.8G /*config*/
    // Supports multiple DRC202Proxies, each of which can hold about 1 billion records.
    private stable var proxyDefault: Principal = Principal.fromText("y5a36-liaaa-aaaak-aacqa-cai"); 
    if (app_debug){
        proxyDefault := Principal.fromText("iq2ev-rqaaa-aaaak-aagba-cai");
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
        let proxyCurrentActor: actor{ 
            stop : shared () -> async (Nat, [(Principal, Nat)]);
            initIcrc1Tokens :  shared () -> async ();
        } = actor(Principal.toText(proxyCurrent.0));
        let (txnCount, snsTokens) = await proxyCurrentActor.stop(); /*config*/
            //let txnCount : Nat = 100000;
        Cycles.add(INIT_CYCLES); 
        let proxyActor = await DRC202Proxy.ProxyActor(txnCount, Principal.fromActor(this), snsTokens);
        await proxyActor.initIcrc1Tokens();
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

    /// returns txn hash. 
    public shared composite query func getTxnHash(_token: T.Token, _txid: T.Txid) : async [Hex.Hex]{
        for ((proxy, t, i) in proxies.vals()){
            let proxyActor: T.Self = actor(Principal.toText(proxy));
            let buckets = await proxyActor.location(_token, #txid(_txid), null);
            for (canisterId in buckets.vals()){
                let bucket : T.Bucket = actor(Principal.toText(canisterId));
                let res = await bucket.txnHash(_token, _txid);
                if (Array.size(res) > 0) return res;
            };
        };
        return [];
    };
    /// returns txn record. 
    public shared composite query func getArchivedTxnBytes(_token: T.Token, _txid: T.Txid) : async [([Nat8], Time.Time)]{
        for ((proxy, t, i) in proxies.vals()){
            let proxyActor: T.Self = actor(Principal.toText(proxy));
            let buckets = await proxyActor.location(_token, #txid(_txid), null);
            for (bucketId in buckets.vals()){
                let bucket: T.Bucket = actor(Principal.toText(bucketId));
                let res = await bucket.txnBytesHistory(_token, _txid);
                if (Array.size(res) > 0) return res;
            };
        };
        return [];
    };
    public shared composite query func getArchivedTxn(_token: T.Token, _txid: T.Txid) : async [(T.TxnRecord, Time.Time)]{
        for ((proxy, t, i) in proxies.vals()){
            let proxyActor: T.Self = actor(Principal.toText(proxy));
            let buckets = await proxyActor.location(_token, #txid(_txid), null);
            for (bucketId in buckets.vals()){
                let bucket: T.Bucket = actor(Principal.toText(bucketId));
                let res = await bucket.txnHistory(_token, _txid);
                if (Array.size(res) > 0) return res;
            };
        };
        return [];
    };
    public shared composite query func getArchivedTxnByIndex(_token: T.Token, _tokenBlockIndex: Nat) : async [(T.TxnRecord, Time.Time)]{
        for ((proxy, t, i) in proxies.vals()){
            let proxyActor: T.Self = actor(Principal.toText(proxy));
            let buckets = await proxyActor.location(_token, #index(_tokenBlockIndex), null);
            for (canisterId in buckets.vals()){
                let bucket : T.Bucket = actor(Principal.toText(canisterId));
                let res = await bucket.txnByIndex(_token, _tokenBlockIndex);
                if (Array.size(res) > 0) return res;
            };
        };
        return [];
    };
    /// Returns archived records. 
    public shared composite query func getArchivedTokenTxns(_token: T.Token, _start_desc: Nat, _length: Nat) : async [T.TxnRecord]{
        var res : [T.TxnRecord] = [];
        var blockIndex: Nat = _start_desc;
        var count : Nat = 0;
        label FindTxnStep1 while (blockIndex > 0 and count < _length){
            label FindTxnStep2 for ((proxy, t, i) in proxies.vals()){
                if (blockIndex < i){
                    continue FindTxnStep2;
                };
                let proxyActor: T.Self = actor(Principal.toText(proxy));
                let buckets = await proxyActor.location(_token, #index(blockIndex), null);
                for (bucketId in buckets.vals()){
                    let bucket: T.Bucket = actor(Principal.toText(bucketId));
                    let txns = await bucket.txnByIndex(_token, blockIndex);
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
    public shared composite query func getArchivedAccountTxns(_buckets_offset: ?Nat, _buckets_length: Nat, _account: T.AccountId, _token: ?T.Token, _page: ?Nat32/*base 1*/, _size: ?Nat32) : async 
    {data: [(Principal, [(T.TxnRecord, Time.Time)])]; totalPage: Nat; total: Nat}{
        var offset = Option.get(_buckets_offset, 0);
        let page: Nat32 = Option.get(_page, 1:Nat32);
        var buckets: [Principal] = [];
        var r: [Principal] = [];
        label ProxyLoop for ((proxy, t, i) in proxies.vals()){
            let proxyActor: T.Self = actor(Principal.toText(proxy));
            switch(_token){
                case(?(token)){
                    r := await proxyActor.location(token, #account(_account), null);
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
                    r := Array.map(temp, func(t:(Principal, Time.Time, Nat)): Principal{ t.0 });
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
            let r = await bucket.txnByAccountId(_account, _token, ?1, _size);
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
                return await bucket.txnByAccountId(_account, _token, ?thisPage, _size);
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