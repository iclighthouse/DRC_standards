/**
 * Module     : TokenRecord.mo
 * Author     : ICLight.house Team
 * License    : Apache License 2.0
 * Stability  : Experimental
 */
import Array "mo:base/Array";
import Binary "Binary";
import Blob "mo:base/Blob";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import Int64 "mo:base/Int64";
import Option "mo:base/Option";
import Prim "mo:⛔";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Types "DRC202Types";
import SHA224 "SHA224";
import Tools "Tools";

module {
    public type Gas = Types.Gas;
    public type Address = Types.Address;
    public type AccountId = Types.AccountId; 
    public type Txid = Types.Txid;  
    public type Operation = Types.Operation;
    public type Transaction = Types.Transaction;
    public type TxnRecord = Types.TxnRecord;
    public type Bucket = Principal;
    public type BucketInfo = {
        cycles: Nat;
        memory: Nat;
        heap: Nat;
        stableMemory: Nat32; // M
        count: Nat;
    };
    public type Token = Principal;
    public type TokenInfo = {
        lastIndex: Nat;
        lastTxid: Txid;
        count: Nat;
    };
    public type TokenCertification = {
        level: Nat; // 1~3
        moduleHash: [Nat8];
        certifiedBy: Principal;
    };
    public type Sid = Blob;

    /* TxnRecord Encode Data Structure
    * version(1bytes)+txid(32bytes)+caller(length(1byte)+Upto53bytes content)+timestamp(8bytes)+
    * index(8bytes)+nonce(4bytes)+gas(1option+value[(8bytes+1decimals) | ])+from(32bytes)+to(32bytes)+
    * value(8bytes+1decimals)+operation(1option+value[action_1option | locked(8bytes+1decimals)+expiration(8bytes)+decider(32bytes) | lockedTxid(32bytes)+fallback(8bytes+1decimals) | allowance(8bytes+1decimals)]) +
    * data(?bytes)      
    */

    public let Nat64Max: Nat = 0xFFFFFFFFFFFFFFFF;  //2**64 - 1;
    public func slice<T>(a: [T], from: Nat, to: ?Nat): [T]{
        let len = a.size();
        if (len == 0) { return []; };
        var to_: Nat = Option.get(to, Nat.sub(len, 1));
        if (len <= to_){ to_ := len - 1; };
        var na: [T] = [];
        var i: Nat = from;
        while ( i <= to_ ){
            na := Tools.arrayAppend(na, Array.make(a[i]));
            i += 1;
        };
        return na;
    };
    //version: 1bytes
    private let _data: [Nat8] = [1];
    //amount: 9bytes(8bytes+1decimals)
    private func _amountEncode(_value: Nat) : [Nat8]{
        var value = _value;
        var decimals: Nat8 = 0;
        while (value > Nat64Max){
            value /= 10;
            decimals += 1;
        };
        return Tools.arrayAppend(Binary.BigEndian.fromNat64(Nat64.fromNat(value)), [decimals]);
    };
    private func _amountDecode(_bytes: [Nat8]) : Nat{
        if (_bytes.size() == 0) { return 0; };
        let value = Nat64.toNat(Binary.BigEndian.toNat64(slice(_bytes, 0, ?7)));
        let decimals = Nat8.toNat(_bytes[8]);
        return value * (10 ** decimals);
    };

    public func generateSid(token: Token, txid: Txid) : Blob{
        let h224 = SHA224.sha224(Tools.arrayAppend(Blob.toArray(Principal.toBlob(token)), Blob.toArray(txid)));
        return Blob.fromArray(h224);
    };
    public func encode(txn: TxnRecord) : [Nat8]{
        //version: 1bytes
        var data: [Nat8] = _data;
        //txid: 32bytes
        data := Tools.arrayAppend(data, Blob.toArray(txn.txid));
        //msgCaller: option 1byte + 1byte length + Up to 32bytes Content
        switch(txn.msgCaller){
            case(?(_msgCaller)){ // 1
                data := Tools.arrayAppend(data, [1: Nat8]);
                //var msgCallerText = Text.replace(Principal.toText(_msgCaller), #char('-'), "");
                //data := Tools.arrayAppend(data, [Nat8.fromNat(msgCallerText.size())]);
                //data := Tools.arrayAppend(data, Blob.toArray(Text.encodeUtf8(msgCallerText)));
                let principal = Blob.toArray(Principal.toBlob(_msgCaller)); 
                data := Tools.arrayAppend(data, [Nat8.fromNat(principal.size())]);
                data := Tools.arrayAppend(data, principal);
            };
            case(null){ // 0
                data := Tools.arrayAppend(data, [0: Nat8]);
            };
        };
        //caller: 32bytes
        data := Tools.arrayAppend(data, Blob.toArray(txn.caller));
        //timestamp: 8bytes
        data := Tools.arrayAppend(data, Binary.BigEndian.fromNat64(Nat64.fromIntWrap(txn.timestamp)));
        //index: 8bytes
        data := Tools.arrayAppend(data, Binary.BigEndian.fromNat64(Nat64.fromNat(txn.index)));
        //nonce: 4bytes
        data := Tools.arrayAppend(data, Binary.BigEndian.fromNat32(Nat32.fromNat(txn.nonce)));
        //gas: option 1byte  + value[amount 9bytes | 0byte]
        switch(txn.gas){
            case(#noFee){
                data := Tools.arrayAppend(data, [0: Nat8]);
            };
            case(#cycles(v)){
                data := Tools.arrayAppend(data, [1: Nat8]);
                data := Tools.arrayAppend(data, _amountEncode(v));
            };
            case(#token(v)){
                data := Tools.arrayAppend(data, [2: Nat8]);
                data := Tools.arrayAppend(data, _amountEncode(v));
            };
        };
        //from: 32bytes
        data := Tools.arrayAppend(data, Blob.toArray(txn.transaction.from));
        //to: 32bytes
        data := Tools.arrayAppend(data, Blob.toArray(txn.transaction.to));
        //value: amount 9bytes
        data := Tools.arrayAppend(data, _amountEncode(txn.transaction.value));
        //operation: option 1byte
        switch(txn.transaction.operation){
            case(#transfer(v)){
                data := Tools.arrayAppend(data, [0: Nat8]);
                switch(v.action){ //action: option 1byte
                    case(#send){ data := Tools.arrayAppend(data, [0: Nat8]); };
                    case(#mint){ data := Tools.arrayAppend(data, [1: Nat8]); };
                    case(#burn){ data := Tools.arrayAppend(data, [2: Nat8]); };
                };
            };
            case(#lockTransfer(v)){
                data := Tools.arrayAppend(data, [1: Nat8]);
                //locked: amount 9bytes
                data := Tools.arrayAppend(data, _amountEncode(v.locked));
                //expiration: 8bytes
                data := Tools.arrayAppend(data, Binary.BigEndian.fromNat64(Nat64.fromIntWrap(v.expiration)));
                //decider: 32bytes
                data := Tools.arrayAppend(data, Blob.toArray(v.decider));
            };
            case(#executeTransfer(v)){
                data := Tools.arrayAppend(data, [2: Nat8]);
                //lockedTxid: 32bytes
                data := Tools.arrayAppend(data, Blob.toArray(v.lockedTxid));
                //fallback: amount 9bytes
                data := Tools.arrayAppend(data, _amountEncode(v.fallback));
            };
            case(#approve(v)){
                data := Tools.arrayAppend(data, [3: Nat8]);
                //allowance: amount 9bytes
                data := Tools.arrayAppend(data, _amountEncode(v.allowance));
            };
        };
        //data: 0~64K bytes
        switch(txn.transaction.data){
            case(?(v)){ 
                if (v.size() > 64*1024){
                    data := Tools.arrayAppend(data, slice<Nat8>(Blob.toArray(v), 0, ?(64*1024-1))); 
                }else{
                    data := Tools.arrayAppend(data, Blob.toArray(v)); 
                };
            };
            case(_){};
        };
        return data;
    };

    public func decode(data: [Nat8]) : TxnRecord{
        var pos: Nat = 0;
        //version: 1bytes
        let version: Nat8 = data[0];
        //txid: 32bytes
        let txid: Txid = Blob.fromArray(slice<Nat8>(data, 1, ?32));
        //msgCaller: option 1byte + 1byte length + Up to 32bytes Content
        pos := 33;
        let optionMsgCaller: Nat8 = data[pos];
        var msgCaller: ?Principal = null; 
        pos += 1;
        switch(optionMsgCaller){
            case(1: Nat8){
                let length = Nat8.toNat(data[pos]);
                pos += 1;
                let msgCaller_ = slice<Nat8>(data, pos, ?(pos+length-1));
                msgCaller := ?Tools.principalBlobToPrincipal(Blob.fromArray(msgCaller_));
                pos += length;
            };
            case(_){};
        };
        //caller: 32bytes
        let caller = Blob.fromArray(slice<Nat8>(data, pos, ?(pos+31)));
        pos += 32;
        //timestamp: 8bytes
        let timestamp: Int = Nat64.toNat(Binary.BigEndian.toNat64(slice<Nat8>(data, pos, ?(pos+7))));
        pos += 8;
        //index: 8bytes
        let index: Nat = Nat64.toNat(Binary.BigEndian.toNat64(slice<Nat8>(data, pos, ?(pos+7))));
        pos += 8;
        //nonce: 4bytes
        let nonce: Nat = Nat32.toNat(Binary.BigEndian.toNat32(slice<Nat8>(data, pos, ?(pos+3))));
        pos += 4;
        //gas: option 1byte  + value[amount 9bytes | 0byte]
        let gas_: Nat8 = data[pos];
        var gas: Gas = #noFee; //#noFee
        pos += 1;
        switch(gas_){
            case(1: Nat8){ //#cycles
                gas := #cycles(_amountDecode(slice<Nat8>(data, pos, ?(pos+8))));
                pos += 9;
            };
            case(2: Nat8){ //#token
                gas := #token(_amountDecode(slice<Nat8>(data, pos, ?(pos+8))));
                pos += 9;
            };
            case(_){};
        };
        //from: 32bytes
        let from = Blob.fromArray(slice<Nat8>(data, pos, ?(pos+31)));
        pos += 32;
        //to: 32bytes
        let to = Blob.fromArray(slice<Nat8>(data, pos, ?(pos+31)));
        pos += 32;
        //value: amount 9bytes
        let value = _amountDecode(slice<Nat8>(data, pos, ?(pos+8)));
        pos += 9;
        //operation: option 1byte
        let operation_: Nat8 = data[pos];
        var operation: Operation = #transfer({action = #send;});
        pos += 1;
        switch(operation_){
            case(0: Nat8){ //#transfer
                let action_: Nat8 = data[pos]; //action: option 1byte
                pos += 1;
                switch(action_){ 
                    case(0: Nat8){ operation := #transfer({action = #send;}); };
                    case(1: Nat8){ operation := #transfer({action = #mint;}); };
                    case(2: Nat8){ operation := #transfer({action = #burn;}); };
                    case(_){};
                };
            };
            case(1: Nat8){  //#lockTransfer
                //locked: amount 9bytes
                let locked: Nat = _amountDecode(slice<Nat8>(data, pos, ?(pos+8)));
                pos += 9;
                //expiration: 8bytes
                let expiration: Int = Nat64.toNat(Binary.BigEndian.toNat64(slice<Nat8>(data, pos, ?(pos+7))));
                pos += 8;
                //decider: 32bytes
                let decider = Blob.fromArray(slice<Nat8>(data, pos, ?(pos+31)));
                pos += 32;
                operation := #lockTransfer({locked = locked; expiration = expiration; decider = decider; });
            };
            case(2: Nat8){  //#executeTransfer
                //lockedTxid: 32bytes
                let lockedTxid = Blob.fromArray(slice<Nat8>(data, pos, ?(pos+31)));
                pos += 32;
                //fallback: amount 9bytes
                let fallback: Nat = _amountDecode(slice<Nat8>(data, pos, ?(pos+8)));
                pos += 9;
                operation := #executeTransfer({lockedTxid = lockedTxid; fallback = fallback; });
            };
            case(3: Nat8){  //#approve
                //allowance: amount 9bytes
                let allowance: Nat = _amountDecode(slice<Nat8>(data, pos, ?(pos+8)));
                pos += 9;
                operation := #approve({allowance = allowance; });
            };
            case(_){};
        };
        //data: 0~64K bytes
        var data_: ?Blob = null;
        if (pos < data.size()){
            data_ := ?Blob.fromArray(slice(data, pos, null));
        };
        let txn: TxnRecord = {
            txid = txid;
            msgCaller = msgCaller;
            caller = caller;
            timestamp = timestamp;
            index = index;
            nonce = nonce;
            gas = gas;
            transaction = {
                from = from;
                to = to;
                value = value; 
                operation = operation;
                data = data_;
            };
        };
        return txn;
    };
    

};