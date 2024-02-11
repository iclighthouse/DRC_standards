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
    private var maxMemory: Nat = 3200*1000*1000; // 3.2G
    // Issue: fail to add new data after dataset reaches 300,000 items "IC0522: Canister xxxxxxxx exceeded the instruction limit for single message execution ." 
    // To solve this problem, the data is stored in 3 tries.
    // TODO: New scheme
    // Memory is in units of 32 bytes, and the List is a double-chained structure
    // Encoding is categorized into fixed length (e.g. data_28) and variable length (e.g. length_4 + data)
    // The offset=0 position stores the version and no data.
    // Value: {bytes:?Length; list: List};
    // Key: {bytes:?Length; none};
    // List: {key: Key; value: Value};
    // Variable: {vid: Nat8; valueType: Value; size: Nat64; front_offset: Nat64; back_offset: Nat64}
    // index: hash(\01 + Sid) --> Region-4G.  Duplicates are placed in Trie.Trie<hash, [offset]>
    // Put (vid_1(01) + Sid_28 + content_offset_4 + pre_item_offset_4 + next_item_offset_4) to RegionN.
    // Put (length_4 + vid_1(02) + Array_item_data(length_4 + data) + pre_item_offset_4 + next_item_offset_4)
    // index: hash(\03 + Iid) --> Region-4G.  Duplicates are placed in Trie.Trie<hash, [offset]>
    // Put (vid_1(03) + Iid_28 + Sid_28 + pre_item_offset_4 + next_item_offset_4)
    // index: hash(\04 + AccountId) --> Region-4G. Duplicates are placed in Trie.Trie<hash, [offset]>
    // Put (vid_1(04) + Token_10 + content_offset_4 + pre_item_offset_4 + next_item_offset_4)
    // Put (vid_1(05) + List_item_28 + pre_item_offset_4 + next_item_offset_4)
    private let databaseNumber: Nat = 3;
    private let recordNumberPerDatabase: Nat = 300_000;
    private stable var database: Trie.Trie<Sid, [([Nat8], Time.Time)]> = Trie.empty(); // 0 ~ recordNumberPerDatabase
    private stable var database1: Trie.Trie<Sid, [([Nat8], Time.Time)]> = Trie.empty(); 
    private stable var database2: Trie.Trie<Sid, [([Nat8], Time.Time)]> = Trie.empty(); 
    private stable var count: Nat = 0;
    private stable var lastStorage: (Sid, Time.Time) = (Blob.fromArray([]), 0);
    private stable var appIndexIds: Trie.Trie<Iid, Sid> = Trie.empty();
    private stable var appIndexIds1: Trie.Trie<Iid, Sid> = Trie.empty();
    private stable var appIndexIds2: Trie.Trie<Iid, Sid> = Trie.empty();
    private stable var appAccountIds: Trie.Trie2D<AccountId, Token, List.List<Sid>> = Trie.empty(); 
    private stable var appAccountIds1: Trie.Trie2D<AccountId, Token, List.List<Sid>> = Trie.empty(); 
    private stable var appAccountIds2: Trie.Trie2D<AccountId, Token, List.List<Sid>> = Trie.empty(); 

    private func _onlyOwner(_caller: Principal) : Bool {
        return Principal.isController(_caller);
    };
    private func key(t: Sid) : Trie.Key<Sid> { return { key = t; hash = Blob.hash(t) }; };
    private func keyp(t: Principal) : Trie.Key<Principal> { return { key = t; hash = Principal.hash(t) }; };

    private func _database(_sid: Sid): (data: Trie.Trie<Sid, [([Nat8], Time.Time)]>, id: Nat){
        if (Option.isSome(Trie.get(database, key(_sid), Blob.equal))){
            return (database, 0);
        }else if (Option.isSome(Trie.get(database1, key(_sid), Blob.equal))){
            return (database1, 1);
        }else if (Option.isSome(Trie.get(database2, key(_sid), Blob.equal))){
            return (database2, 2);
        }else if (Trie.size(database) >= recordNumberPerDatabase and Trie.size(database1) >= recordNumberPerDatabase){
            return (database2, 2);
        }else if (Trie.size(database) >= recordNumberPerDatabase){
            return (database1, 1);
        }else{
            return (database, 0);
        };
    };
    private func _saveDatabase(_data: Trie.Trie<Sid, [([Nat8], Time.Time)]>, _id: Nat): (){
        if (_id == 0){
            database := _data;
        }else if (_id == 1){
            database1 := _data;
        }else{
            database2 := _data;
        };
    };
    private func _queryDatabase(_sid: Sid) : ?[([Nat8], Time.Time)]{
        return _queryDatabaseStep(_sid, 0);
    };
    private func _queryDatabaseStep(_sid: Sid, _step: Nat/*0,1,2*/) : ?[([Nat8], Time.Time)]{
        var db: Trie.Trie<Sid, [([Nat8], Time.Time)]> = Trie.empty();
        if (_step == 0){
            db := database2;
        }else if (_step == 1){
            db := database1;
        }else if (_step == 2){
            db := database;
        }else{
            return null;
        };
        switch(Trie.get(db, key(_sid), Blob.equal)){
            case(?(values)){
                return ?values;
            };
            case(_){
                return _queryDatabaseStep(_sid, _step + 1);
            };
        };
    };

    private func _appIndexIds(_iid: Iid): (data: Trie.Trie<Iid, Sid>, id: Nat){
        if (Option.isSome(Trie.get(appIndexIds, key(_iid), Blob.equal))){
            return (appIndexIds, 0);
        }else if (Option.isSome(Trie.get(appIndexIds1, key(_iid), Blob.equal))){
            return (appIndexIds1, 1);
        }else if (Option.isSome(Trie.get(appIndexIds2, key(_iid), Blob.equal))){
            return (appIndexIds2, 2);
        }else if (Trie.size(appIndexIds) >= recordNumberPerDatabase and Trie.size(appIndexIds1) >= recordNumberPerDatabase){
            return (appIndexIds2, 2);
        }else if (Trie.size(appIndexIds) >= recordNumberPerDatabase){
            return (appIndexIds1, 1);
        }else{
            return (appIndexIds, 0);
        };
    };
    private func _saveAppIndexIds(_data: Trie.Trie<Iid, Sid>, _id: Nat): (){
        if (_id == 0){
            appIndexIds := _data;
        }else if (_id == 1){
            appIndexIds1 := _data;
        }else{
            appIndexIds2 := _data;
        };
    };
    private func _queryAppIndexIds(_iid: Iid) : ?Sid{
        return _queryAppIndexIdsStep(_iid, 0);
    };
    private func _queryAppIndexIdsStep(_iid: Iid, _step: Nat/*0,1,2*/) : ?Sid{
        var db: Trie.Trie<Iid, Sid> = Trie.empty();
        if (_step == 0){
            db := appIndexIds2;
        }else if (_step == 1){
            db := appIndexIds1;
        }else if (_step == 2){
            db := appIndexIds;
        }else{
            return null;
        };
        switch(Trie.get(db, key(_iid), Blob.equal)){
            case(?(values)){
                return ?values;
            };
            case(_){
                return _queryAppIndexIdsStep(_iid, _step + 1);
            };
        };
    };

    private func _appAccountIds(_aid: AccountId): (data: Trie.Trie2D<AccountId, Token, List.List<Sid>>, id: Nat){
        if (Option.isSome(Trie.get(appAccountIds, key(_aid), Blob.equal))){
            return (appAccountIds, 0);
        }else if (Option.isSome(Trie.get(appAccountIds1, key(_aid), Blob.equal))){
            return (appAccountIds1, 1);
        }else if (Option.isSome(Trie.get(appAccountIds2, key(_aid), Blob.equal))){
            return (appAccountIds2, 2);
        }else if (Trie.size(appAccountIds) >= recordNumberPerDatabase / 2 and Trie.size(appAccountIds1) >= recordNumberPerDatabase / 2){
            return (appAccountIds2, 2);
        }else if (Trie.size(appAccountIds) >= recordNumberPerDatabase / 2){
            return (appAccountIds1, 1);
        }else{
            return (appAccountIds, 0);
        };
    };
    private func _saveAppAccountIds(_data: Trie.Trie2D<AccountId, Token, List.List<Sid>>, _id: Nat): (){
        if (_id == 0){
            appAccountIds := _data;
        }else if (_id == 1){
            appAccountIds1 := _data;
        }else{
            appAccountIds2 := _data;
        };
    };
    private func _queryAppAccountIds(_aid: AccountId) : ?Trie.Trie<Token, List.List<Sid>>{
        return _queryAppAccountIdsStep(_aid, 0);
    };
    private func _queryAppAccountIdsStep(_aid: AccountId, _step: Nat/*0,1,2*/) : ?Trie.Trie<Token, List.List<Sid>>{
        var db: Trie.Trie2D<AccountId, Token, List.List<Sid>> = Trie.empty();
        if (_step == 0){
            db := appAccountIds2;
        }else if (_step == 1){
            db := appAccountIds1;
        }else if (_step == 2){
            db := appAccountIds;
        }else{
            return null;
        };
        switch(Trie.get(db, key(_aid), Blob.equal)){
            case(?(value)){
                return ?value;
            };
            case(_){
                return _queryAppAccountIdsStep(_aid, _step + 1);
            };
        };
    };

    private func _store(_sid: Sid, _data: [Nat8], _replace: Bool) : (){
        let now = Time.now();
        var values : [([Nat8], Time.Time)] = [(_data, now)];
        let (data, id) = _database(_sid);
        if (not(_replace)){
            switch(Trie.get(data, key(_sid), Blob.equal)){
                case(?(items)){ values := Tools.arrayAppend(items, values); };
                case(_){};
            };
        };
        let res = Trie.put(data, key(_sid), Blob.equal, values);
        _saveDatabase(res.0, id);
        switch (res.1){
            case(?(v)){ lastStorage := (_sid, now); };
            case(_){ count += 1; lastStorage := (_sid, now); };
        };
    };
    private func _get(_sid: Sid) : ?([Nat8], Time.Time){
        switch(_queryDatabase(_sid)){
            case(?(values)){
                if (values.size() > 0){
                    return ?values[values.size() - 1];
                }else{ return null; };
            };
            case(_){ return null; };
        };
    };
    private func _get2(_sid: Sid) : ?(TxnRecord, Time.Time){
        switch(_queryDatabase(_sid)){
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
        switch(_queryDatabase(_sid)){
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
                let (data, id) = _appIndexIds(iid);
                _saveAppIndexIds(Trie.put(data, key(iid), Blob.equal, ids.0).0, id);
            };
            case(_){};
        };
        switch(_txn, ids.2){
            case(?(txn), ?(canisterId)){
                // let tokenSelf = Tools.principalToAccountBlob(canisterId, null);
                // if (txn.caller != txn.transaction.from and txn.caller != txn.transaction.to and txn.caller != Tools.blackhole()){
                //     _putAccountIdLog(txn.caller, canisterId, ids.0);
                // };
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
        let (data, id) = _appAccountIds(_a);
        switch(Trie.get(data, key(_a), Blob.equal)){
            case(?(items)){
                switch(Trie.get(items, keyp(_canisterId), Principal.equal)){
                    case(?(sids)){
                        var _sids = sids;
                        // var count: Nat = 0;
                        // _sids := List.filter(sids, func (t: Sid): Bool{ 
                        //     if (t != _sid and count < 5000){ count += 1; return true } else { return false };
                        // });
                        let db = Trie.put2D(data, key(_a), Blob.equal, keyp(_canisterId), Principal.equal, List.push(_sid, _sids));
                        _saveAppAccountIds(db, id);
                    };
                    case(_){
                        let db = Trie.put2D(data, key(_a), Blob.equal, keyp(_canisterId), Principal.equal, List.push(_sid, null));
                        _saveAppAccountIds(db, id);
                    };
                };
            };
            case(_){
                let db = Trie.put2D(data, key(_a), Blob.equal, keyp(_canisterId), Principal.equal, List.push(_sid, null));
                _saveAppAccountIds(db, id);
            };
        };
    };
    private func _getAccountIdLogs(_a: AccountId, _canisterId: ?Principal, _start: ?Nat, _length: ?Nat) : ([(Principal, Sid)], total: Nat){
        let start = Option.get(_start, 0);
        let length = Option.get(_length, 1000);
        switch(_queryAppAccountIds(_a)){
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
        assert(Prim.rts_memory_size() < maxMemory);
        let sid = _dealWithId(_sid, null);
        _store(sid, _data, false);
    };
    public shared(msg) func storeBytesBatch(batch: [(_sid: Sid, _data: [Nat8])]) : async (){
        assert(_onlyOwner(msg.caller));
        assert(Prim.rts_memory_size() < maxMemory);
        for ((_sid, _data) in batch.vals()){
            let sid = _dealWithId(_sid, null);
            _store(sid, _data, false);
        };
    };
    public shared(msg) func store(_sid: Sid, _txn: TxnRecord) : async (){
        assert(_onlyOwner(msg.caller));
        assert(Prim.rts_memory_size() < maxMemory);
        let sid = _dealWithId(_sid, ?_txn);
        let _data = TokenRecord.encode(_txn);
        _store(sid, _data, false);
    };
    public shared(msg) func storeBatch(batch: [(_sid: Sid, _txn: TxnRecord)]) : async (){
        assert(_onlyOwner(msg.caller));
        assert(Prim.rts_memory_size() < maxMemory);
        for ((_sid, _txn) in batch.vals()){
            let sid = _dealWithId(_sid, ?_txn);
            _store(sid, TokenRecord.encode(_txn), false);
        };
    };
    public shared(msg) func storeBatch2(batch: [(_sid: Sid, _txn: TxnRecord)], replace: Bool) : async (){
        assert(_onlyOwner(msg.caller));
        assert(Prim.rts_memory_size() < maxMemory);
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
        switch(_queryDatabase(_sid)){
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
        switch(_queryAppIndexIds(_iid)){
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
        switch(_queryDatabase(_sid)){
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
    public func dbCount(): async {database: (Nat, Nat, Nat); appIndexIds: (Nat, Nat, Nat); appAccountIds: (Nat, Nat, Nat);}{
        return {
            database = (Trie.size(database), Trie.size(database1), Trie.size(database2)); 
            appIndexIds = (Trie.size(appIndexIds), Trie.size(appIndexIds1), Trie.size(appIndexIds2)); 
            appAccountIds = (Trie.size(appAccountIds), Trie.size(appAccountIds1), Trie.size(appAccountIds2)); 
        };
    };

    // private stable var totalSids: Nat = 180_000;
    // private stable var totalIids: Nat = 180_000;
    // private stable var totalAids: Nat = 0;
    // public shared(msg) func resetBloom(_offset: Nat, _maxRound: Nat): async (){
    //     assert(_onlyOwner(msg.caller));
    //     let proxy: actor{
    //         setBloom: shared (_sids: [Blob]) -> async ();
    //         setBloom2: shared (_iids: [Blob]) -> async ();
    //         setBloom3: shared (_aids: [Blob]) -> async ();
    //     } = actor("y5a36-liaaa-aaaak-aacqa-cai"); // actor(Principal.toText(owner));
    //     var sids: [Blob] = [];
    //     var iids: [Blob] = [];
    //     let n: Nat = 2000;
    //     var i: Nat = 0;
    //     var round: Nat = 0;
    //     for ((iid, sid) in Trie.iter(appIndexIds)){
    //         i += 1;
    //         if (i > _offset){
    //             let m = Nat.sub(i, _offset);
    //             sids := Tools.arrayAppend(sids, [sid]);
    //             iids := Tools.arrayAppend(iids, [iid]);
    //             if (m >= n){
    //                 await proxy.setBloom(sids);
    //                 await proxy.setBloom2(iids);
    //                 totalSids += m;
    //                 totalIids += m;
    //                 i := _offset;
    //                 sids := [];
    //                 iids := [];
    //                 round += 1;
    //                 if (round >= _maxRound){
    //                     return ();
    //                 };
    //             };
    //         };
    //     };
    //     for ((iid, sid) in Trie.iter(appIndexIds1)){
    //         i += 1;
    //         if (i > _offset){
    //             let m = Nat.sub(i, _offset);
    //             sids := Tools.arrayAppend(sids, [sid]);
    //             iids := Tools.arrayAppend(iids, [iid]);
    //             if (m >= n){
    //                 await proxy.setBloom(sids);
    //                 await proxy.setBloom2(iids);
    //                 totalSids += m;
    //                 totalIids += m;
    //                 i := _offset;
    //                 sids := [];
    //                 iids := [];
    //                 round += 1;
    //                 if (round >= _maxRound){
    //                     return ();
    //                 };
    //             };
    //         };
    //     };
    //     for ((iid, sid) in Trie.iter(appIndexIds2)){
    //         i += 1;
    //         if (i > _offset){
    //             let m = Nat.sub(i, _offset);
    //             sids := Tools.arrayAppend(sids, [sid]);
    //             iids := Tools.arrayAppend(iids, [iid]);
    //             if (m >= n){
    //                 await proxy.setBloom(sids);
    //                 await proxy.setBloom2(iids);
    //                 totalSids += m;
    //                 totalIids += m;
    //                 i := _offset;
    //                 sids := [];
    //                 iids := [];
    //                 round += 1;
    //                 if (round >= _maxRound){
    //                     return ();
    //                 };
    //             };
    //         };
    //     };
    //     if (i > _offset){
    //         let m = Nat.sub(i, _offset);
    //         await proxy.setBloom(sids);
    //         await proxy.setBloom2(iids);
    //         totalSids += m;
    //         totalIids += m;
    //         i := _offset;
    //         sids := [];
    //         iids := [];
    //     };
    // }; 
    // public shared(msg) func resetBloom3(_offset: Nat, _maxRound: Nat): async (){
    //     assert(_onlyOwner(msg.caller));
    //     let proxy: actor{
    //         setBloom: shared (_sids: [Blob]) -> async ();
    //         setBloom2: shared (_iids: [Blob]) -> async ();
    //         setBloom3: shared (_aids: [Blob]) -> async ();
    //     } = actor("y5a36-liaaa-aaaak-aacqa-cai"); // actor(Principal.toText(owner));
    //     var aids: [Blob] = [];
    //     let n: Nat = 1000;
    //     var i: Nat = 0;
    //     var round: Nat = 0;
    //     for ((account, item) in Trie.iter(appAccountIds)){
    //         for ((token, list) in Trie.iter(item)){
    //             i += 1;
    //             if (i > _offset){
    //                 let m = Nat.sub(i, _offset);
    //                 let aid = TokenRecord.generateAid(token, account);
    //                 aids := Tools.arrayAppend(aids, [aid]);
    //                 if (m >= n){
    //                     await proxy.setBloom3(aids);
    //                     totalAids += m;
    //                     i := _offset;
    //                     aids := [];
    //                     round += 1;
    //                     if (round >= _maxRound){
    //                         return ();
    //                     };
    //                 };
    //             };
    //         };
    //     };
    //     for ((account, item) in Trie.iter(appAccountIds1)){
    //         for ((token, list) in Trie.iter(item)){
    //             i += 1;
    //             if (i > _offset){
    //                 let m = Nat.sub(i, _offset);
    //                 let aid = TokenRecord.generateAid(token, account);
    //                 aids := Tools.arrayAppend(aids, [aid]);
    //                 if (m >= n){
    //                     await proxy.setBloom3(aids);
    //                     totalAids += m;
    //                     i := _offset;
    //                     aids := [];
    //                     round += 1;
    //                     if (round >= _maxRound){
    //                         return ();
    //                     };
    //                 };
    //             };
    //         };
    //     };
    //     for ((account, item) in Trie.iter(appAccountIds2)){
    //         for ((token, list) in Trie.iter(item)){
    //             i += 1;
    //             if (i > _offset){
    //                 let m = Nat.sub(i, _offset);
    //                 let aid = TokenRecord.generateAid(token, account);
    //                 aids := Tools.arrayAppend(aids, [aid]);
    //                 if (m >= n){
    //                     await proxy.setBloom3(aids);
    //                     totalAids += m;
    //                     i := _offset;
    //                     aids := [];
    //                     round += 1;
    //                     if (round >= _maxRound){
    //                         return ();
    //                     };
    //                 };
    //             };
    //         };
    //     };
    //     if (i > _offset){
    //         let m = Nat.sub(i, _offset);
    //         await proxy.setBloom3(aids);
    //         totalAids += m;
    //         i := _offset;
    //         aids := [];
    //     };
    // }; 
    public query func queryBloom(_page: Nat/*base 0*/): async (sids: [Blob], iids: [Blob]){
        var sids: [Blob] = [];
        var iids: [Blob] = [];
        let n: Nat = 2000;
        var i: Nat = 0;
        let _offset = _page * n;
        for ((iid, sid) in Trie.iter(appIndexIds)){
            i += 1;
            if (i > _offset){
                let m = Nat.sub(i, _offset);
                sids := Tools.arrayAppend(sids, [sid]);
                iids := Tools.arrayAppend(iids, [iid]);
                if (m >= n){
                    return (sids, iids);
                };
            };
        };
        for ((iid, sid) in Trie.iter(appIndexIds1)){
            i += 1;
            if (i > _offset){
                let m = Nat.sub(i, _offset);
                sids := Tools.arrayAppend(sids, [sid]);
                iids := Tools.arrayAppend(iids, [iid]);
                if (m >= n){
                    return (sids, iids);
                };
            };
        };
        for ((iid, sid) in Trie.iter(appIndexIds2)){
            i += 1;
            if (i > _offset){
                let m = Nat.sub(i, _offset);
                sids := Tools.arrayAppend(sids, [sid]);
                iids := Tools.arrayAppend(iids, [iid]);
                if (m >= n){
                    return (sids, iids);
                };
            };
        };
        return (sids, iids);
    }; 
    public query func queryBloomAccounts(_page: Nat/*base 0*/): async (aids: [Blob]){
        var aids: [Blob] = [];
        let n: Nat = 2000;
        var i: Nat = 0;
        let _offset = _page * n;
        for ((account, item) in Trie.iter(appAccountIds)){
            for ((token, list) in Trie.iter(item)){
                i += 1;
                if (i > _offset){
                    let m = Nat.sub(i, _offset);
                    let aid = TokenRecord.generateAid(token, account);
                    aids := Tools.arrayAppend(aids, [aid]);
                    if (m >= n){
                        return aids;
                    };
                };
            };
        };
        for ((account, item) in Trie.iter(appAccountIds1)){
            for ((token, list) in Trie.iter(item)){
                i += 1;
                if (i > _offset){
                    let m = Nat.sub(i, _offset);
                    let aid = TokenRecord.generateAid(token, account);
                    aids := Tools.arrayAppend(aids, [aid]);
                    if (m >= n){
                        return aids;
                    };
                };
            };
        };
        for ((account, item) in Trie.iter(appAccountIds2)){
            for ((token, list) in Trie.iter(item)){
                i += 1;
                if (i > _offset){
                    let m = Nat.sub(i, _offset);
                    let aid = TokenRecord.generateAid(token, account);
                    aids := Tools.arrayAppend(aids, [aid]);
                    if (m >= n){
                        return aids;
                    };
                };
            };
        };
        return aids;
    }; 
    // public query func debug_bloomStats(): async (Nat, Nat, Nat){
    //     return (totalSids, totalIids, totalAids);
    // };

    // receive cycles
    // public func wallet_receive(): async (){
    //     let amout = Cycles.available();
    //     let accepted = Cycles.accept(amout);
    // };
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
    public func wallet_receive(): async (){
        let amout = Cycles.available();
        let accepted = Cycles.accept(amout);
    };
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