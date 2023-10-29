/**
 * Module     : DRC202Bucket.mo
 * Author     : ICLighthouse Team
 * License    : Apache License 2.0
 * Stability  : Experimental
 * Github     : https://github.com/iclighthouse/DRC_standards/
 */
import Prim "mo:⛔";
import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Time "mo:base/Time";
import Trie "mo:base/Trie";
import Cycles "mo:base/ExperimentalCycles";
import CyclesWallet "mo:icl/CyclesWallet";
import TokenRecord "./lib/TokenRecord";
import DRC207 "mo:icl/DRC207";
import Tools "mo:icl/Tools";
import Hex "mo:icl/Hex";
import Hash256 "lib/Hash256";
import List "mo:base/List";
import Option "mo:base/Option";

shared(installMsg) actor class BucketActor() = this {
    // Debug.trap("HERE");
    type Bucket = TokenRecord.Bucket;
    type BucketInfo = TokenRecord.BucketInfo;
    type Token = TokenRecord.Token;
    type Txid = TokenRecord.Txid;  
    type Sid = TokenRecord.Sid;
    type TxnRecord = TokenRecord.TxnRecord;
    type AccountId = TokenRecord.AccountId;
    type Iid = Blob;

    private stable var owner: Principal = installMsg.caller;
    private var bucketVersion: Nat8 = 1;
    // private stable var data: Trie.Trie<Sid, ([Nat8], Time.Time)> = Trie.empty(); 
    private stable var database: Trie.Trie<Sid, [([Nat8], Time.Time)]> = Trie.empty(); 
    private stable var count: Nat = 0;
    private stable var lastStorage: (Sid, Time.Time) = (Blob.fromArray([]), 0);
    private stable var appIndexIds: Trie.Trie<Iid, Sid> = Trie.empty();
    private stable var appAccountIds: Trie.Trie2D<AccountId, Token, List.List<Sid>> = Trie.empty(); 

    private func _onlyOwner(_caller: Principal) : Bool {
        return Principal.isController(_caller);
    };
    private func key(t: Sid) : Trie.Key<Sid> { return { key = t; hash = Blob.hash(t) }; };
    private func keyp(t: Principal) : Trie.Key<Principal> { return { key = t; hash = Principal.hash(t) }; };

    private func _store(_sid: Sid, _data: [Nat8], _replace: Bool) : (){
        let now = Time.now();
        var values : [([Nat8], Time.Time)] = [(_data, now)];
        if (not(_replace)){
            switch(Trie.get(database, key(_sid), Blob.equal)){
                case(?(items)){ values := Tools.arrayAppend(items, values); };
                case(_){};
            };
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
    private func _get2(_sid: Sid) : ?(TxnRecord, Time.Time){
        switch(Trie.get(database, key(_sid), Blob.equal)){
            case(?(values)){
                if (values.size() > 0){
                    let _data = values[values.size() - 1];
                    return ?(TokenRecord.decode(_data.0), _data.1);
                }else{ return null; };
            };
            case(_){ return null; };
        };
    };
    private func _get3(_sid: Sid) : [(TxnRecord, Time.Time)]{
        switch(Trie.get(database, key(_sid), Blob.equal)){
            case(?(values)){
                return Array.map<([Nat8],Time.Time), (TxnRecord, Time.Time)>(values, func (a:([Nat8],Time.Time)): (TxnRecord, Time.Time){
                    return (TokenRecord.decode(a.0), a.1)
                });
            };
            case(_){ return []; };
        };
    };
    private func _split(_b: Blob): (_sid: Sid/*28Bytes*/, _iid: ?Blob/*28Bytes*/, _canisterId: ?Principal/*10-29Bytes*/){
        let id = Blob.toArray(_b);
        if (id.size() <= 28){
            return (_b, null, null);
        }else if (id.size() > 28 and id.size() <= 56){
            return (Blob.fromArray(Tools.slice(id, 0, ?27)), ?Blob.fromArray(Tools.slice(id, 28, null)), null);
        }else{ //  if (id.size() > 56)
            return (Blob.fromArray(Tools.slice(id, 0, ?27)), ?Blob.fromArray(Tools.slice(id, 28, ?55)), 
            ?Principal.fromBlob(Blob.fromArray(Tools.slice(id, 56, null))));
        };
    };
    private func _dealWithId(_sid: Blob, _txn: ?TxnRecord) : Sid{
        let ids = _split(_sid);
        switch(ids.1){
            case(?(iid)){
                appIndexIds := Trie.put(appIndexIds, key(iid), Blob.equal, ids.0).0;
            };
            case(_){};
        };
        switch(_txn, ids.2){
            case(?(txn), ?(canisterId)){
                // let tokenSelf = Tools.principalToAccountBlob(canisterId, null);
                if (txn.caller != txn.transaction.from and txn.caller != txn.transaction.to and txn.caller != Tools.blackhole()){
                    _putAccountIdLog(txn.caller, canisterId, ids.0);
                };
                if (txn.transaction.from != txn.transaction.to and txn.transaction.from != Tools.blackhole()){
                    _putAccountIdLog(txn.transaction.from, canisterId, ids.0);
                };
                if (txn.transaction.to != Tools.blackhole()){
                    _putAccountIdLog(txn.transaction.to, canisterId, ids.0);
                };
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
                        var _sids = sids;
                        // var count: Nat = 0;
                        // _sids := List.filter(sids, func (t: Sid): Bool{ 
                        //     if (t != _sid and count < 5000){ count += 1; return true } else { return false };
                        // });
                        appAccountIds := Trie.put2D(appAccountIds, key(_a), Blob.equal, keyp(_canisterId), Principal.equal, List.push(_sid, _sids));
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
    private func _getAccountIdLogs(_a: AccountId, _canisterId: ?Principal, _start: ?Nat, _length: ?Nat) : ([(Principal, Sid)], total: Nat){
        let start = Option.get(_start, 0);
        let length = Option.get(_length, 1000);
        switch(Trie.get(appAccountIds, key(_a), Blob.equal)){
            case(?(items)){
                switch(_canisterId){
                    case(?(canisterId)){
                        switch(Trie.get(items, keyp(canisterId), Principal.equal)){
                            case(?(sids)){
                                var temp = sids;
                                var res: [Sid] = [];
                                var count: Nat = 0;
                                var i : Nat = 0;
                                while(Option.isSome(temp) and count < length){
                                    let (optItem, list) = List.pop(temp);
                                    switch(optItem){
                                        case(?item){
                                            if (i >= start){
                                                res := Tools.arrayAppend(res, [item]);
                                                count += 1;
                                            };
                                        };
                                        case(_){};
                                    };
                                    i += 1;
                                    temp := list;
                                };
                                return (Array.map<Sid, (Principal, Sid)>(res, func (x: Sid): (Principal, Sid){ (canisterId, x) }), List.size(sids));
                            };
                            case(_){
                                return ([], 0);
                            };
                        };
                    };
                    case(_){
                        var res: [(Principal, Sid)] = [];
                        for ((k, v) in Trie.iter(items)){
                            res := Tools.arrayAppend(res, Array.map<Sid, (Principal, Sid)>(List.toArray(v), func (x: Sid): (Principal, Sid){ (k, x) }));
                        };
                        return (Tools.slice(res, start, ?Nat.sub(Nat.max(start+length, 1), 1)), res.size());
                    };
                };
            };
            case(_){
                return ([], 0);
            };
        };
    };

    public shared(msg) func storeBytes(_sid: Sid, _data: [Nat8]) : async (){
        assert(_onlyOwner(msg.caller));
        let sid = _dealWithId(_sid, null);
        _store(sid, _data, false);
    };
    public shared(msg) func storeBytesBatch(batch: [(_sid: Sid, _data: [Nat8])]) : async (){
        assert(_onlyOwner(msg.caller));
        for ((_sid, _data) in batch.vals()){
            let sid = _dealWithId(_sid, null);
            _store(sid, _data, false);
        };
    };
    public shared(msg) func store(_sid: Sid, _txn: TxnRecord) : async (){
        assert(_onlyOwner(msg.caller));
        let sid = _dealWithId(_sid, ?_txn);
        let _data = TokenRecord.encode(_txn);
        _store(sid, _data, false);
    };
    public shared(msg) func storeBatch(batch: [(_sid: Sid, _txn: TxnRecord)]) : async (){
        assert(_onlyOwner(msg.caller));
        for ((_sid, _txn) in batch.vals()){
            let sid = _dealWithId(_sid, ?_txn);
            _store(sid, TokenRecord.encode(_txn), false);
        };
    };
    public shared(msg) func storeBatch2(batch: [(_sid: Sid, _txn: TxnRecord)], replace: Bool) : async (){
        assert(_onlyOwner(msg.caller));
        for ((_sid, _txn) in batch.vals()){
            let sid = _dealWithId(_sid, ?_txn);
            _store(sid, TokenRecord.encode(_txn), replace);
        };
    };
    public query func txnBytes(_token: Token, _txid: Txid) : async ?([Nat8], Time.Time){
        let _sid = TokenRecord.generateSid(_token, _txid);
        return _get(_sid);
    };
    public query func txnBytesHistory(_token: Token, _txid: Txid) : async [([Nat8], Time.Time)]{
        let _sid = TokenRecord.generateSid(_token, _txid);
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
    public query func txn(_token: Token, _txid: Txid) : async ?(TxnRecord, Time.Time){
        let _sid = TokenRecord.generateSid(_token, _txid);
        return _get2(_sid);
    };
    public query func txnHistory(_token: Token, _txid: Txid) : async [(TxnRecord, Time.Time)]{
        let _sid = TokenRecord.generateSid(_token, _txid);
        return _get3(_sid);
    };
    public query func txnByIndex(_token: Token, _blockIndex: Nat) : async [(TxnRecord, Time.Time)]{
        let _iid = TokenRecord.generateIid(_token, _blockIndex);
        switch(Trie.get(appIndexIds, key(_iid), Blob.equal)){
            case(?(_sid)){
                return _get3(_sid);
            };
            case(_){ return []; };
        };
    };
    public query func txnByAccountId(_accountId: AccountId, _token: ?Token, _page: ?Nat32/*base 1*/, _size: ?Nat32) : async 
    {data: [(Token, [(TxnRecord, Time.Time)])]; totalPage: Nat; total: Nat} {
        let size: Nat32 = Option.get(_size, 100:Nat32);
        let page: Nat32 = Option.get(_page, 1:Nat32);
        let start = Nat32.toNat(Nat32.sub(page, 1) * size);
        let end = Nat32.toNat(Nat32.sub(page * size, 1));
        let (items, length) = _getAccountIdLogs(_accountId, _token, ?start, ?Nat32.toNat(size));
        return {
            data = Array.map<(Principal,Sid), (Token, [(TxnRecord, Time.Time)])>(items, 
            func(t: (Principal,Sid)): (Token, [(TxnRecord, Time.Time)]){
                return (t.0, _get3(t.1));
            });
            totalPage = (length + Nat32.toNat(size) - 1) / Nat32.toNat(size);
            total = length;
        };
    };
    public query func txnHash(_token: Token, _txid: Txid) : async [Hex.Hex]{
        let _sid = TokenRecord.generateSid(_token, _txid);
        switch(Trie.get(database, key(_sid), Blob.equal)){
            case(?(values)){
                return Array.map<([Nat8], Time.Time), Hex.Hex>(values, func(t: ([Nat8], Time.Time)): Hex.Hex{
                    Hex.encode(Hash256.hash(null, t.0))
                });
            };
            case(_){ return []; };
        };
    };
    // public query func txnBytesHash(_token: Token, _txid: Txid, _index: Nat) : async ?Hex.Hex{
    //     let _sid = TokenRecord.generateSid(_token, _txid);
    //     switch(Trie.get(database, key(_sid), Blob.equal)){
    //         case(?(values)){
    //             return ?Hex.encode(Hash256.hash(null, values[_index].0));
    //         };
    //         case(_){ return null; };
    //     };
    // };

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
    //     // for ((k, v) in Trie.iter(data)) {
    //     //     database := Trie.put(database, key(k), Blob.equal, [v]).0;
    //     // };
    // };
}