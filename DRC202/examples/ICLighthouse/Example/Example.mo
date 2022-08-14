import Array "mo:base/Array";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import DRC202 "lib/DRC202";
import T "lib/DRC202Types";

shared actor class Example() = this {
    // DRC202: Records Storage for Token Canister
    /// Notes:
    ///   AccountId: Blob, Token Holder. Principal and Account should be converted to 32Bytes Blob.
    ///   Txid: Blob, Transaction id, generated by drc202.generateTxid(). You can use a custom Txid, which needs to be converted to 32Bytes Blob.
    ///   Set EN_DEBUG=false in the production environment.
    private var drc202 = DRC202.DRC202({EN_DEBUG = true; MAX_CACHE_TIME = 3 * 30 * 24 * 3600 * 1000000000; MAX_CACHE_NUMBER_PER = 100; MAX_STORAGE_TRIES = 2; }, "drc20");
    
    /********************
    * your token codes
    *********************/
    public shared(msg) func test(_n: Nat) : async DRC202.Txid{
        let caller = drc202.getAccountId(msg.caller, null);
        let from = drc202.getAccountId(msg.caller, null);
        let to = drc202.getAccountId(Principal.fromText("aaaaa-aa"), null);
        let txid = drc202.generateTxid(Principal.fromActor(this), caller, _n);
        var txn: DRC202.TxnRecord = {
            txid = txid; // Transaction id
            transaction = {
                from = from; // from
                to = to; //to
                value = 100000000; // amount
                operation = #transfer({ action = #send }); // DRC202.Operation;
                data = null; // attached data(Blob)
            };
            gas = #token(10000); // gas
            msgCaller = null;  // Caller principal
            caller = caller; // Caller account (Blob)
            index = _n; // Global Index
            nonce = _n; // Nonce of user
            timestamp = Time.now(); // Timestamp (nanoseconds).
        };
        drc202.put(txn); // Put txn to the current canister cache.
        drc202.pushLastTxn([from, to], txid); // Put txid to LastTxn cache.
        let store = /*await*/ drc202.store(); // Store in the DRC202 scalable bucket.
        return txid;
    };
    /********************
    * your token codes
    *********************/
    

    /// returns setting
    public query func drc202_getConfig() : async DRC202.Setting{
        return drc202.getConfig();
    };
    public query func drc202_canisterId() : async Principal{
        return drc202.drc202CanisterId();
    };
    /// config
    // public shared(msg) func drc202_config(config: DRC202.Config) : async Bool{ 
    //     assert(msg.caller == owner);
    //     return drc202.config(config);
    // };
    /// returns events
    public query func drc202_events(_account: ?DRC202.Address) : async [DRC202.TxnRecord]{
        switch(_account){
            case(?(account)){ return drc202.getEvents(?drc202.getAccountId(Principal.fromText(account), null)); };
            case(_){return drc202.getEvents(null);}
        };
    };
    /// returns txn record. It's an query method that will try to find txn record in token canister cache.
    public query func drc202_txn(_txid: DRC202.Txid) : async (txn: ?DRC202.TxnRecord){
        return drc202.get(_txid);
    };
    /// returns txn record. It's an update method that will try to find txn record in the DRC202 canister if the record does not exist in this canister.
    public shared func drc202_txn2(_txid: DRC202.Txid) : async (txn: ?DRC202.TxnRecord){
        return await drc202.get2(Principal.fromActor(this), _txid);
    };
    // upgrade
    private stable var __drc202Data: [DRC202.DataTemp] = [];
    system func preupgrade() {
        __drc202Data := T.arrayAppend(__drc202Data, [drc202.getData()]);
    };
    system func postupgrade() {
        if (__drc202Data.size() > 0){
            drc202.setData(__drc202Data[0]);
            __drc202Data := [];
        };
    };

};