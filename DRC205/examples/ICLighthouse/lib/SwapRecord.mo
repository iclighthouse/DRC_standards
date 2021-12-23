/**
 * Module     : SwapRecord.mo
 * Author     : ICLight.house Team
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
import Types "DRC205";
import SHA224 "SHA224";

module {
    public type Address = Types.Address;
    public type AccountId = Types.AccountId; 
    public type Txid = Types.Txid;  
    public type CyclesWallet = Types.CyclesWallet;
    public type Shares = Types.Shares; 
    public type Nonce = Types.Nonce; 
    public type Data = Types.Data; 
    public type TokenType = Types.TokenType; 
    public type OperationType = Types.OperationType; 
    public type BalanceChange = Types.BalanceChange; 
    public type ShareChange = Types.ShareChange; 
    public type TxnRecord = Types.TxnRecord;
    public type Bucket = Principal;
    public type BucketInfo = {
        cycles: Nat;
        memory: Nat;
        heap: Nat;
        stableMemory: Nat32;
        count: Nat;
    };
    public type AppId = Principal;
    public type AppInfo = {
        lastIndex: Nat;
        lastTxid: Txid;
        count: Nat;
    };
    public type AppCertification = {
        level: Nat; // 1~3
        moduleHash: [Nat8];
        certifiedBy: Principal;
    };
    public type Sid = Blob;

    /* TxnRecord Encode Data Structure
    * .............    
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
            na := Array.append(na, Array.make(a[i]));
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
        return Array.append(Binary.BigEndian.fromNat64(Nat64.fromNat(value)), [decimals]);
    };
    private func _amountDecode(_bytes: [Nat8]) : Nat{
        if (_bytes.size() == 0) { return 0; };
        let value = Nat64.toNat(Binary.BigEndian.toNat64(slice(_bytes, 0, ?7)));
        let decimals = Nat8.toNat(_bytes[8]);
        return value * (10 ** decimals);
    };
    private func _principalFormat(_p: Text) : Text{
        var i: Nat = 0;
        var t: Text = "";
        for (c in _p.chars()){
            if (i > 0 and i % 5 == 0) { t #= "-"; };
            t #= Text.fromChar(c);
            i += 1;
        };
        return t;
    };

    public func generateSid(app: AppId, txid: Txid) : Blob{
        let h224 = SHA224.sha224(Array.append(Blob.toArray(Principal.toBlob(app)), Blob.toArray(txid)));
        return Blob.fromArray(h224);
    };

    // public func encode(txn: TxnRecord) : [Nat8]{
    //     []
    // };

    // public func decode(data: [Nat8]) : TxnRecord{
    //     //
    // };
    

};