/**
 * Module     : DRC205Bucket.mo
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Github     : https://github.com/iclighthouse/DRC_standards/
 */
import Prim "mo:⛔";
import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import Nat "mo:base/Nat";
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
import Text "mo:base/Text";
import Hex "./lib/Hex";
import Hash256 "./lib/Hash256";
import List "mo:base/List";
import Option "mo:base/Option";

shared(installMsg) actor class BucketActor() = this {
    type Bucket = SwapRecord.Bucket;
    type BucketInfo = SwapRecord.BucketInfo;
    type AppId = SwapRecord.AppId;
    type Txid = SwapRecord.Txid;  
    type Sid = SwapRecord.Sid;
    type BalanceChange = SwapRecord.BalanceChange;
    type TxnRecordTemp = SwapRecord.TxnRecordTemp;
    type TxnRecord = SwapRecord.TxnRecord;
    type AccountId = SwapRecord.AccountId;
    type Iid = Blob;

    private stable var owner: Principal = installMsg.caller;
    private var bucketVersion: Nat8 = 1;
    // private stable var data: Trie.Trie<Sid, ([Nat8], Time.Time)> = Trie.empty(); 
    private stable var database: Trie.Trie<Sid, [([Nat8], Time.Time)]> = Trie.empty(); 
    // private stable var txnData: Trie.Trie<Sid, (TxnRecordTemp, Time.Time)> = Trie.empty(); 
    // private stable var txnData2: Trie.Trie<Sid, (TxnRecord, Time.Time)> = Trie.empty(); 
    private stable var database2: Trie.Trie<Sid, [(TxnRecord, Time.Time)]> = Trie.empty(); 
    private stable var count: Nat = 0;
    private stable var lastStorage: (Sid, Time.Time) = (Blob.fromArray([]), 0);
    private stable var appIndexIds: Trie.Trie<Iid, Sid> = Trie.empty(); 
    private stable var appAccountIds: Trie.Trie2D<AccountId, AppId, List.List<Sid>> = Trie.empty(); 

    private func _onlyOwner(_caller: Principal) : Bool {
        return _caller == owner;
    };
    private func key(t: Sid) : Trie.Key<Sid> { return { key = t; hash = Blob.hash(t) }; };
    private func keyp(t: Principal) : Trie.Key<Principal> { return { key = t; hash = Principal.hash(t) }; };
    private func keyn(t: Nat) : Trie.Key<Nat> { return { key = t; hash = Tools.natHash(t) }; };

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
    // private func _store2(_sid: Sid, _data: TxnRecord) : (){
    //     let now = Time.now();
    //     var values : [(TxnRecord, Time.Time)] = [(_data, now)];
    //     switch(Trie.get(database2, key(_sid), Blob.equal)){
    //         case(?(items)){ values := Tools.arrayAppend(items, values); };
    //         case(_){};
    //     };
    //     let res = Trie.put(database2, key(_sid), Blob.equal, values);
    //     database2 := res.0;
    //     switch (res.1){
    //         case(?(v)){ lastStorage := (_sid, now); };
    //         case(_){ count += 1; lastStorage := (_sid, now); };
    //     };
    // };
    private func _get2(_sid: Sid) : ?(TxnRecord, Time.Time){
        let data = _get3(_sid, true);
        if (data.size() > 0){
            return ?data[data.size() - 1];
        }else{
            return null;
        };
    };
    private func _mergerDetails(_data: [(TxnRecord, Time.Time)]): [(TxnRecord, Time.Time)]{
        var data = Trie.empty<Nat, (TxnRecord, Time.Time)>();
        for ((txn, time) in _data.vals()){
            switch(Trie.get(data, keyn(txn.index), Nat.equal)){
                case(?(item, ts)){
                    let temp : TxnRecord = {
                        txid = txn.txid;
                        msgCaller = txn.msgCaller;  
                        caller = txn.caller; 
                        operation = txn.operation;
                        account = txn.account;
                        cyclesWallet = txn.cyclesWallet;
                        token0 = txn.token0;
                        token1 = txn.token1;
                        fee = txn.fee;
                        shares = txn.shares;
                        time = txn.time;
                        index = txn.index;
                        nonce = txn.nonce;
                        order = txn.order;
                        orderMode = txn.orderMode;
                        orderType = txn.orderType;
                        filled = txn.filled;
                        details = Tools.arrayAppend(item.details, txn.details);
                        status = txn.status; 
                        data = txn.data;
                    };
                    data := Trie.put(data, keyn(txn.index), Nat.equal, (temp, time)).0;
                };
                case(_){
                    data := Trie.put(data, keyn(txn.index), Nat.equal, (txn, time)).0;
                };
            };
        };
        var res: [(TxnRecord, Time.Time)] = [];
        for((k, item) in Trie.iter(data)){
            res := Tools.arrayAppend(res, [item]);
        };
        return res;
    };
    private func _get3(_sid: Sid, _merge: Bool) : [(TxnRecord, Time.Time)]{
        switch(Trie.get(database, key(_sid), Blob.equal)){
            case(?(values)){
                let data = Array.mapFilter(values, func (item: ([Nat8], Time.Time)): ?(TxnRecord, Time.Time){
                    let data : ?TxnRecord = from_candid(Blob.fromArray(item.0));
                    switch(data){
                        case(?(v)){ return ?(v, item.1); };
                        case(_){ return null; };
                    };
                });
                return if (_merge) { _mergerDetails(data) }else{ data };
            };
            case(_){
                switch(Trie.get(database2, key(_sid), Blob.equal)){
                    case(?(values)){
                        return if (_merge) { _mergerDetails(values) }else{ values };
                    };
                    case(_){ return []; };
                };
            };
        };
    };
    private func _split(_b: Blob): (_sid: Sid/*28Bytes*/, _iid: ?Blob/*28Bytes*/, _accountId: ?Blob/*32Bytes*/, _canisterId: ?Principal/*10-29Bytes*/){
        let id = Blob.toArray(_b);
        if (id.size() <= 28){
            return (_b, null, null, null);
        }else if (id.size() > 28 and id.size() <= 56){
            return (Blob.fromArray(Tools.slice(id, 0, ?27)), ?Blob.fromArray(Tools.slice(id, 28, null)), null, null);
        }else if (id.size() > 56 and id.size() <= 88){
            return (Blob.fromArray(Tools.slice(id, 0, ?27)), ?Blob.fromArray(Tools.slice(id, 28, ?55)), 
            ?Blob.fromArray(Tools.slice(id, 56, null)), null);
        }else{ //  if (id.size() > 88)
            return (Blob.fromArray(Tools.slice(id, 0, ?27)), ?Blob.fromArray(Tools.slice(id, 28, ?55)), 
            ?Blob.fromArray(Tools.slice(id, 56, ?87)), ?Principal.fromBlob(Blob.fromArray(Tools.slice(id, 88, null))));
        };
    };
    private func _dealWithId(_sid: Blob) : Sid{
        let ids = _split(_sid);
        switch(ids.1){
            case(?(iid)){
                appIndexIds := Trie.put(appIndexIds, key(iid), Blob.equal, ids.0).0;
            };
            case(_){};
        };
        switch(ids.2, ids.3){
            case(?(accountId), ?(canisterId)){
                _putAccountIdLog(accountId, canisterId, ids.0);
            };
            case(_, _){};
        };
        return ids.0;
    };
    private func _putAccountIdLog(_a: AccountId, _canisterId: Principal, _sid: Sid) : (){
        switch(Trie.get(appAccountIds, key(_a), Blob.equal)){
            case(?(items)){
                switch(Trie.get(items, keyp(_canisterId), Principal.equal)){
                    case(?(sids)){
                        appAccountIds := Trie.put2D(appAccountIds, key(_a), Blob.equal, keyp(_canisterId), Principal.equal, List.push(_sid, sids));
                    };
                    case(_){
                        appAccountIds := Trie.put2D(appAccountIds, key(_a), Blob.equal, keyp(_canisterId), Principal.equal, List.push(_sid, null));
                    };
                };
            };
            case(_){
                appAccountIds := Trie.put2D(appAccountIds, key(_a), Blob.equal, keyp(_canisterId), Principal.equal, List.push(_sid, null));
            };
        };
    };
    private func _getAccountIdLogs(_a: AccountId, _canisterId: ?Principal) : [Sid]{
        switch(Trie.get(appAccountIds, key(_a), Blob.equal)){
            case(?(items)){
                switch(_canisterId){
                    case(?(canisterId)){
                        switch(Trie.get(items, keyp(canisterId), Principal.equal)){
                            case(?(sids)){
                                return List.toArray(sids);
                            };
                            case(_){
                                return [];
                            };
                        };
                    };
                    case(_){
                        var res: [Sid] = [];
                        for ((k, v) in Trie.iter(items)){
                            res := Tools.arrayAppend(res, List.toArray(v));
                        };
                        return res;
                    };
                };
            };
            case(_){
                return [];
            };
        };
    };
    // public func debug_logs() : async Text{
    //     return debug_show(appAccountIds);
    // };

    public shared(msg) func storeBytes(_sid: Sid, _data: [Nat8]) : async (){
        assert(_onlyOwner(msg.caller));
        let sid = _dealWithId(_sid);
        _store(sid, _data);
    };
    public shared(msg) func storeBytesBatch(batch: [(_sid: Sid, _data: [Nat8])]) : async (){
        assert(_onlyOwner(msg.caller));
        for ((_sid, _data) in batch.vals()){
            let sid = _dealWithId(_sid);
            _store(sid, _data);
        };
    };
    public shared(msg) func store(_sid: Sid, _txn: TxnRecord) : async (){
        assert(_onlyOwner(msg.caller));
        let sid = _dealWithId(_sid);
        _store(sid, Blob.toArray(to_candid(_txn)));
    };
    public shared(msg) func storeBatch(batch: [(_sid: Sid, _txn: TxnRecord)]) : async (){
        assert(_onlyOwner(msg.caller));
        for ((_sid, _txn) in batch.vals()){
            let sid = _dealWithId(_sid);
            _store(sid, Blob.toArray(to_candid(_txn)));
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
        let data = _get3(_sid, false);
        if (data.size() < 100){
            return data;
        }else{
            return _get3(_sid, true);
        };
    };
    public query func txnByIndex(_app: AppId, _blockIndex: Nat) : async [(TxnRecord, Time.Time)]{
        let _iid = SwapRecord.generateIid(_app, _blockIndex);
        switch(Trie.get(appIndexIds, key(_iid), Blob.equal)){
            case(?(_sid)){
                return _get3(_sid, true);
            };
            case(_){ return []; };
        };
    };
    public query func txnByAccountId(_accountId: AccountId, _app: ?AppId, _page: ?Nat32/*start from 1*/, _size: ?Nat32) : async [[(TxnRecord, Time.Time)]]{
        let size: Nat32 = Option.get(_size, 100:Nat32);
        let page: Nat32 = Option.get(_page, 1:Nat32);
        let start = Nat32.toNat(Nat32.sub(page, 1) * size);
        let end = Nat32.toNat(Nat32.sub(page * size, 1));
        let data = Array.map(_getAccountIdLogs(_accountId, _app), func(sid: Sid): [(TxnRecord, Time.Time)]{
            return _get3(sid, true);
        });
        return Tools.slice(data, start, ?end);
    };
    public query func txnHash(_app: AppId, _txid: Txid, _index: Nat) : async ?Hex.Hex{
        let _sid = SwapRecord.generateSid(_app, _txid);
        switch(Trie.get(database, key(_sid), Blob.equal)){
            case(?(values)){
                return ?Hex.encode(Hash256.hash(null, values[_index].0));
            };
            case(_){
                switch(Trie.get(database2, key(_sid), Blob.equal)){
                    case(?(values)){
                        return ?Hex.encode(Hash256.hash(null, Blob.toArray(to_candid(values[_index].0))));
                    };
                    case(_){ return null; };
                };
            };
        };
    };
    public query func txnHash2(_app: AppId, _txid: Txid, _merge: Bool) : async [Hex.Hex]{
        let _sid = SwapRecord.generateSid(_app, _txid);
        let data = _get3(_sid, _merge);
        return Array.map(data, func (t: (TxnRecord, Time.Time)): Hex.Hex{
            return Hex.encode(Hash256.hash(null, Blob.toArray(to_candid(t.0))));
        });
    };
    public query func txnBytesHash(_app: AppId, _txid: Txid, _index: Nat) : async ?Hex.Hex{
        let _sid = SwapRecord.generateSid(_app, _txid);
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