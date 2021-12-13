/**
 * Module     : types.mo
 * Author     : ICLighthouse Team
 * License    : Apache License 2.0
 * Stability  : Experimental
 */

import Time "mo:base/Time";
import Result "mo:base/Result";

module {
    public type Metadata = {
        name: Text;
        content: Text;
    };
    public type Gas = {
        #cycles: Nat;  //1
        #token: Nat;   //2
        #noFee;       //0
    };
    // Address: principal string or account-id hex
    public type Address = Text;
    public type AccountId = Blob; 
    // Txid: Require unique txid in a token. It is recommended to use DRC202 standard to generate txid.
    public type Txid = Blob;  
    public type TxnResult = Result.Result<Txid, {  //<#ok, #err> 
        code: {
            #InsufficientBalance;
            #InsufficientAllowance;
            #InsufficientGas;
            #LockedTransferExpired;
            #UndefinedError;
        };
        message: Text;
    }>;
    public type ExecuteType = {
        #fallback;  //operator with access: _decider(anytime), _from(when expired).
        #sendAll;  //operator with access: _decider(when not expired).
        #send: Nat;  //operator with access: _decider(when not expired). 
    };
    public type Operation = {
        #transfer: { //0
            action: {
                #send;  //0
                #mint;  //1
                #burn;  //2
            };
        };
        #lockTransfer: { //1
            locked: Nat;  // Locked the amount in account `from`
            expiration: Time.Time;  //Expiration timestamp(seconds) = lockTransferTimestamp + _timeout
            decider: AccountId; //Who has access to execute the executeTransfer() before it expires
        };
        #executeTransfer: { //2
            lockedTxid: Txid;
            fallback: Nat; // `from` receives back the amount
        };
        #approve: { //3
            allowance: Nat;
        };
    };
    public type Transaction = {
        from: AccountId;
        to: AccountId;
        value: Nat;   // `to` receives the amount (If lockTransfer operation, value SHOULD be 0)
        operation: Operation;
        data: ?Blob;
    };
    public type TxnRecord = {
        txid: Txid;
        caller: Principal; //maybe: sender/spender/decider
        timestamp: Time.Time; //Time
        index: Nat;
        nonce: Nat;
        gas: Gas;
        transaction: Transaction;
    };
    public type Callback = shared (record: TxnRecord) -> async ();
    public type MsgType = {
        #onTransfer;
        #onLock;
        #onExecute;
        #onApprove;
    };
    public type Subscription = {
        callback: Callback;
        msgTypes: [MsgType];
    };
    public type Allowance = {
        spender: AccountId;
        remaining: Nat;
    };
    public type TxnQueryRequest = {
        #txnCountGlobal;
        #txnCount: { owner: Address; };
        #getTxn: { txid: Txid; };
        #lastTxidsGlobal;
        #lastTxids: { owner: Address; };
        #lockedTxns: { owner: Address; };
        #getEvents: { owner: ?Address; };
    };
    public type TxnQueryResponse = {
        #txnCountGlobal: Nat;
        #txnCount: Nat;
        #getTxn: ?TxnRecord;
        #lastTxidsGlobal: [Txid];
        #lastTxids: [Txid];
        #lockedTxns: { lockedBalance: Nat; txns: [TxnRecord]; };
        #getEvents: [TxnRecord];
    };
    public type InitArgs = {
        totalSupply: Nat;
        decimals: Nat8;
        gas: Gas;
        name: ?Text;
        symbol:? Text;
        metadata: ?[Metadata];
        founder: ?Address;
    };
    
}