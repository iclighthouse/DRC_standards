/**
 * Module     : DRC205.mo
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Description: DRC205 Swap Records Storage.
 * Refers     : https://github.com/iclighthouse/
 * Canister   : 6ylab-kiaaa-aaaak-aacga-cai
 */

import Array "mo:base/Array";
import Principal "mo:base/Principal";
import Hash "mo:base/Hash";
import Blob "mo:base/Blob";
import Option "mo:base/Option";
import Time "mo:base/Time";
import List "mo:base/List";
import Deque "mo:base/Deque";
import Trie "mo:base/Trie";
import Cycles "mo:base/ExperimentalCycles";
import SHA224 "./SHA224";
import CRC32 "./CRC32";
import T "DRC205Types";

module {
    public type Address = T.Address;
    public type Txid = T.Txid;
    public type AccountId = T.AccountId;
    public type CyclesWallet = T.CyclesWallet;
    public type Nonce = T.Nonce;
    public type Data = T.Data;
    public type Shares = T.Shares;
    public type Status = T.Status;
    public type TokenType = T.TokenType;
    public type TokenStd = T.TokenStd;
    public type OperationType = T.OperationType;
    public type BalanceChange = T.BalanceChange;
    public type ShareChange = T.ShareChange;
    public type TxnRecord = T.TxnRecord;
    public type Bucket = T.Bucket;
    public type Setting = T.Setting;
    public type Config = T.Config;
    public type DexInfo = {
        canisterId: Principal;
        mmType: { #AMM; #OrderBook; };
        dexName: Text;
        pairName: Text;
        token0: (TokenType, TokenStd);
        token1: (TokenType, TokenStd);
        feeRate: Float;
    };
    public type DataTemp = {
        setting: Setting;
        txnRecords: Trie.Trie<Txid, TxnRecord>;
        globalTxns: Deque.Deque<(Txid, Time.Time)>;
        globalLastTxns: Deque.Deque<Txid>;
        accountLastTxns: Trie.Trie<AccountId, Deque.Deque<Txid>>; 
        storeRecords: List.List<(Txid, Nat)>;
    };
    public type DataTempV2 = {
        setting: Setting;
        txnRecords: Trie.Trie<Txid, TxnRecord>;
        globalTxns: Deque.Deque<(Txid, Time.Time)>;
        globalLastTxns: Deque.Deque<Txid>;
        accountLastTxns: Trie.Trie<AccountId, Deque.Deque<Txid>>; 
        storagePool: List.List<(Txid, TxnRecord, Nat)>;
    };
    // public type DataTemp2 = {
    //     setting: Setting;
    //     txns: Trie.Trie<Txid, [TxnRecord]>;
    //     globalTxids: Deque.Deque<(Txid, Nat, Time.Time)>;
    //     globalLastTxids: Deque.Deque<(Txid, Nat)>;
    //     accountLastTxids: Trie.Trie<AccountId, Deque.Deque<(Txid, Nat)>>; 
    //     storagePool: List.List<(Txid, Nat, Nat)>;
    // };

    public class DRC205(_setting: Setting){
        var setting: Setting = _setting;
        var txnRecords: Trie.Trie<Txid, TxnRecord> = Trie.empty(); 
        //var txns: Trie.Trie<Txid, [TxnRecord]> = Trie.empty(); 
        var globalTxns = Deque.empty<(Txid, Time.Time)>(); 
        //var globalTxids = Deque.empty<(Txid, Nat, Time.Time)>(); 
        var globalLastTxns = Deque.empty<Txid>(); 
        //var globalLastTxids = Deque.empty<(Txid, Nat)>(); 
        var accountLastTxns: Trie.Trie<AccountId, Deque.Deque<Txid>> = Trie.empty(); 
        //var accountLastTxids: Trie.Trie<AccountId, Deque.Deque<(Txid, Nat)>> = Trie.empty(); 
        var storeRecords = List.nil<(Txid, Nat)>(); 
        var storagePool = List.nil<(Txid, TxnRecord, Nat)>(); 
        var DRC205Fee : Nat = 0;
        var lastGetDRC205FeeTime : Time.Time = 0;

        private func keyp(t: Principal) : Trie.Key<Principal> { return { key = t; hash = Principal.hash(t) }; };
        private func keyb(t: Blob) : Trie.Key<Blob> { return { key = t; hash = Blob.hash(t) }; };

        private func pushGlobalTxns(_txid: Txid): (){
            // push new txid.
            //globalTxns := (List.filter(globalTxns.0, func (t:(Blob,Int)): Bool{ t.0 != _txid }), List.filter(globalTxns.1, func (t:(Blob,Int)): Bool{ t.0 != _txid }));
            globalTxns := Deque.pushFront(globalTxns, (_txid, Time.now()));
            globalLastTxns := (List.filter(globalLastTxns.0, func (t:Blob): Bool{ t != _txid }), List.filter(globalLastTxns.1, func (t:Blob): Bool{ t != _txid }));
            globalLastTxns := Deque.pushFront(globalLastTxns, _txid);
            var size = List.size(globalLastTxns.0) + List.size(globalLastTxns.1);
            while (size > setting.MAX_CACHE_NUMBER_PER * 5){
                size -= 1;
                switch (Deque.popBack(globalLastTxns)){
                    case(?(q, v)){
                        globalLastTxns := q;
                    };
                    case(_){};
                };
            };
            // pop expired txids, and delete records.
            switch(Deque.peekBack(globalTxns)){
                case (?(txid, ts)){
                    var timestamp: Time.Time = ts;
                    var i : Nat = 0;
                    while (Time.now() - timestamp > setting.MAX_CACHE_TIME and i < 2000){
                        switch (Deque.popBack(globalTxns)){
                            case(?(q, v)){
                                globalTxns := q;
                                deleteTxnRecord(v.0); // delete the record.
                            };
                            case(_){};
                        };
                        switch(Deque.peekBack(globalTxns)){
                            case(?(txid_,ts_)){
                                timestamp := ts_;
                            };
                            case(_){
                                timestamp := Time.now();
                            };
                        };
                        i += 1;
                    };
                };
                case(_){};
            };
        };
        private func pushLastTxn(_a: AccountId, _txid: Txid): (){
            switch(Trie.get(accountLastTxns, keyb(_a), Blob.equal)){
                case(?(q)){
                    var txids: Deque.Deque<Txid> = q;
                    txids := (List.filter(txids.0, func (t:Blob): Bool{ t != _txid }), List.filter(txids.1, func (t:Blob): Bool{ t != _txid }));
                    txids := Deque.pushFront(txids, _txid);
                    accountLastTxns := Trie.put(accountLastTxns, keyb(_a), Blob.equal, txids).0;
                    cleanLastTxns(_a);
                };
                case(_){
                    var new = Deque.empty<Txid>();
                    new := Deque.pushFront(new, _txid);
                    accountLastTxns := Trie.put(accountLastTxns, keyb(_a), Blob.equal, new).0;
                };
            };
        };
        private func deleteTxnRecord(_txid: Txid): (){
            switch(getTxnRecord(_txid)){ 
                case(?(txn)){
                    let _a = txn.account;
                    cleanLastTxns(_a);
                    if (Time.now() > txn.time + setting.MAX_CACHE_TIME){ // check timestamp
                        txnRecords := Trie.remove(txnRecords, keyb(_txid), Blob.equal).0;
                    };
                };
                case(_){};
            };
        };
        private func cleanLastTxns(_a: AccountId): (){
            switch(Trie.get(accountLastTxns, keyb(_a), Blob.equal)){
                case(?(txns)){  
                    var txids: Deque.Deque<Txid> = txns;
                    var size = List.size(txids.0) + List.size(txids.1);
                    while (size > setting.MAX_CACHE_NUMBER_PER){
                        size -= 1;
                        switch (Deque.popBack(txids)){
                            case(?(q, v)){
                                txids := q;
                            };
                            case(_){};
                        };
                    };
                    switch(Deque.peekBack(txids)){
                        case (?(txid)){
                            let txn_ = getTxnRecord(txid);
                            switch(txn_){
                                case(?(txn)){
                                    var timestamp = txn.time;
                                    while (Time.now() - timestamp > setting.MAX_CACHE_TIME and size > 0){
                                        switch (Deque.popBack(txids)){
                                            case(?(q, v)){
                                                txids := q;
                                                size -= 1;
                                            };
                                            case(_){};
                                        };
                                        switch(Deque.peekBack(txids)){
                                            case(?(txid)){
                                                let txn_ = getTxnRecord(txid);
                                                switch(txn_){
                                                    case(?(txn)){ timestamp := txn.time; };
                                                    case(_){ };
                                                };
                                            };
                                            case(_){ timestamp := Time.now(); };
                                        };
                                    };
                                };
                                case(_){
                                    switch (Deque.popBack(txids)){
                                        case(?(q, v)){
                                            txids := q;
                                            size -= 1;
                                        };
                                        case(_){};
                                    };
                                };
                            };
                        };
                        case(_){};
                    };
                    if (size == 0){
                        accountLastTxns := Trie.remove(accountLastTxns, keyb(_a), Blob.equal).0;
                    }else{
                        accountLastTxns := Trie.put(accountLastTxns, keyb(_a), Blob.equal, txids).0;
                    };
                };
                case(_){};
            };
        };
        public func getAccountId(p : Principal, sa: ?[Nat8]) : Blob {
            let data = Blob.toArray(Principal.toBlob(p));
            let ads : [Nat8] = [10, 97, 99, 99, 111, 117, 110, 116, 45, 105, 100]; //b"\x0Aaccount-id"
            var _sa : [Nat8] = [0:Nat8,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
            _sa := Option.get(sa, _sa);
            var hash : [Nat8] = SHA224.sha224(T.arrayAppend(T.arrayAppend(ads, data), _sa));
            var crc : [Nat8] = CRC32.crc32(hash);
            return Blob.fromArray(T.arrayAppend(crc, hash));                     
        };

        // public methods
        public func drc205CanisterId() : Principal{
            if (setting.EN_DEBUG) {
                return Principal.fromText("ix3cb-4iaaa-aaaak-aagbq-cai");
            } else {
                return Principal.fromText("6ylab-kiaaa-aaaak-aacga-cai");
            };
        };
        public func drc205() : T.Self{
            return actor(Principal.toText(drc205CanisterId()));
        };
        public func config(_config: Config) : Bool {
            setting := {
                EN_DEBUG: Bool = Option.get(_config.EN_DEBUG, setting.EN_DEBUG);
                MAX_CACHE_TIME: Nat = Option.get(_config.MAX_CACHE_TIME, setting.MAX_CACHE_TIME);
                MAX_CACHE_NUMBER_PER: Nat = Option.get(_config.MAX_CACHE_NUMBER_PER, setting.MAX_CACHE_NUMBER_PER);
                MAX_STORAGE_TRIES: Nat = Option.get(_config.MAX_STORAGE_TRIES, setting.MAX_STORAGE_TRIES);
            };
            return true;
        };
        public func getConfig() : Setting{
            return setting;
        };
        public func generateTxid(_app: Principal, _caller: AccountId, _nonce: Nat) : Txid{
            return T.generateTxid(_app, _caller, _nonce);
        };

        private func getTxnRecord(_txid: Txid): ?TxnRecord{
            return Trie.get(txnRecords, keyb(_txid), Blob.equal);
        };
        public func get(_txid: Txid): ?TxnRecord{
            return getTxnRecord(_txid);
        };

        private func insertTxnRecord(_txn: TxnRecord, _isAppend: Bool): (){
            var txid = _txn.txid;
            assert(Blob.toArray(txid).size() >= 4);
            //assert(Blob.toArray(_txn.caller).size() == 32);
            //assert(Blob.toArray(_txn.account).size() == 32);
            storagePool := List.push((txid, _txn, 0), storagePool);
            if (_isAppend){
                switch(getTxnRecord(txid)){
                    case(?(txn)){
                        let temp: TxnRecord = {
                            txid = _txn.txid;
                            msgCaller = _txn.msgCaller;
                            caller = _txn.caller;
                            operation = _txn.operation;
                            account = _txn.account;
                            cyclesWallet = _txn.cyclesWallet;
                            token0 = _txn.token0;
                            token1 = _txn.token1;
                            fee = _txn.fee;
                            shares = _txn.shares;
                            time = txn.time;
                            index = _txn.index;
                            nonce = _txn.nonce;
                            order = _txn.order;
                            orderMode = _txn.orderMode;
                            orderType = _txn.orderType;
                            filled = _txn.filled;
                            details = T.arrayAppend(txn.details, _txn.details);
                            status = _txn.status;
                            data = _txn.data;
                        };
                        txnRecords := Trie.put(txnRecords, keyb(txid), Blob.equal, temp).0;
                    };
                    case(_){
                        txnRecords := Trie.put(txnRecords, keyb(txid), Blob.equal, _txn).0;
                    };
                };
            } else {
                txnRecords := Trie.put(txnRecords, keyb(txid), Blob.equal, _txn).0;
            };
            pushGlobalTxns(txid);
            pushLastTxn(_txn.account, txid);
        };
        public func put(_txn: TxnRecord, _isAppend: Bool): (){
            return insertTxnRecord(_txn, _isAppend);
        };
        public func getLastTxns(_account: ?AccountId): [Txid]{
            switch(_account){
                case(?(a)){
                    switch(Trie.get(accountLastTxns, keyb(a), Blob.equal)){
                        case(?(swaps)){
                            var l = List.append(swaps.0, List.reverse(swaps.1));
                            return List.toArray(l);
                        };
                        case(_){
                            return [];
                        };
                    };
                };
                case(_){
                    var l = List.append(globalLastTxns.0, List.reverse(globalLastTxns.1));
                    return List.toArray(l);
                };
            };
        };
        public func getEvents(_account: ?AccountId) : [TxnRecord]{
            switch(_account) {
                case(null){
                    var i: Nat = 0;
                    return Array.chain(getLastTxns(null), func (value:Txid): [TxnRecord]{
                        if (i < getConfig().MAX_CACHE_NUMBER_PER){
                            i += 1;
                            switch(getTxnRecord(value)){
                                case(?(r)){ return [r]; };
                                case(_){ return []; };
                            };
                        }else{ return []; };
                    });
                };
                case(?(account)){
                    return Array.chain(getLastTxns(?account), func (value:Txid): [TxnRecord]{
                        switch(getTxnRecord(value)){
                            case(?(r)){ return [r]; };
                            case(_){ return []; };
                        };
                    });
                };
            }
        };
        // public func get2(_app: Principal, _txid: Txid) : async (txn: ?TxnRecord){
        //     var step: Nat = 0;
        //     func _getTxn(_app: Principal, _txid: Txid) : async* ?TxnRecord{
        //         switch(await drc205().bucket(_app, _txid, step, null)){
        //             case(?(bucketId)){
        //                 let bucket: T.Bucket = actor(Principal.toText(bucketId));
        //                 switch(await bucket.txn(_app, _txid)){
        //                     case(?(txn, time)){ return ?txn; };
        //                     case(_){
        //                         step += 1;
        //                         return await* _getTxn(_app, _txid);
        //                     };
        //                 };
        //             };
        //             case(_){ return null; };
        //         };
        //     };
        //     return await* _getTxn(_app, _txid);
        // };
        public func get2(_app: Principal, _txid: Txid) : async (txn: ?TxnRecord){
            let buckets = await drc205().location(_app, #txid(_txid), null);
            for (bucketId in buckets.vals()){
                let bucket: T.Bucket = actor(Principal.toText(bucketId));
                switch(await bucket.txn(_app, _txid)){
                    case(?(txn, time)){ return ?txn; };
                    case(_){};
                };
            };
            return null;
        };

        public func getPool() : [(Txid, TxnRecord, Nat)]{
            return List.toArray(storagePool);
        };
        // records storage (DRC205 Standard)
        public func store() : async (){
            var _storing = List.nil<(Txid, TxnRecord, Nat)>();
            var _remaining = List.nil<(Txid, TxnRecord, Nat)>();
            if (Time.now() > lastGetDRC205FeeTime + 14400000000000){ //4h
                lastGetDRC205FeeTime := Time.now();
                DRC205Fee := await drc205().fee();
            };
            var storageFee = DRC205Fee;
            var storeBatch: [TxnRecord] = [];
            var i: Nat = 0;
            for ((txid, txn, callCount) in List.toArray(List.reverse(storagePool)).vals()){
                if (i < 200){
                    storeBatch := T.arrayAppend(storeBatch, [txn]); // the first item at 0 position
                    _storing := List.push((txid, txn, callCount), _storing);
                }else{
                    _remaining := List.push((txid, txn, callCount), _remaining);
                };
                i += 1;
            };
            if (storeBatch.size() > 0){
                Cycles.add(storageFee * storeBatch.size());
                storagePool := List.nil<(Txid, TxnRecord, Nat)>();
                try{
                    await drc205().storeBatch(storeBatch);
                    storagePool := List.append(storagePool, _remaining);
                }catch(e){
                    storagePool := List.append(storagePool, List.append(_remaining, _storing));
                    lastGetDRC205FeeTime := 0;
                };
            };
            // var item = List.pop(storagePool);
            // var count : Nat = 0;
            // while (Option.isSome(item.0) and count < 20){
            //     count += 1;
            //     storagePool := item.1;
            //     switch(item.0){
            //         case(?(txid, callCount)){
            //             if (callCount < setting.MAX_STORAGE_TRIES){
            //                 switch(getTxnRecord(txid)){
            //                     case(?(txn)){
            //                         try{
            //                             Cycles.add(storageFee);
            //                             await drc205().store(txn);
            //                         } catch(e){ //push
            //                             _storagePool := List.push((txid, callCount+1), _storagePool);
            //                         };
            //                     };
            //                     case(_){};
            //                 };
            //             };
            //         };
            //         case(_){};
            //     };
            //     item := List.pop(storagePool);
            // };
            // storagePool := List.append(storagePool, _storagePool);
        };

        // for updating
        public func getData() : DataTempV2 {
            return {
                setting = setting;
                txnRecords = txnRecords;
                globalTxns = globalTxns;
                globalLastTxns = globalLastTxns;
                accountLastTxns = accountLastTxns; 
                storagePool = storagePool;
            };
        };
        public func setData(_data: DataTempV2) : (){
            setting := _data.setting;
            txnRecords := _data.txnRecords;
            globalTxns := _data.globalTxns;
            globalLastTxns := _data.globalLastTxns;
            accountLastTxns := _data.accountLastTxns; 
            storagePool := _data.storagePool; 
        };
    };
 };
