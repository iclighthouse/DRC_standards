module {
  public type AccountId = Blob;
  public type Address = Text;
  public type Allowance = { remaining : Nat; spender : AccountId };
  public type Callback = shared TxnRecord -> async ();
  public type ExecuteType = { #sendAll; #send : Nat; #fallback };
  public type Gas = { #token : Nat; #cycles : Nat; #noFee };
  public type Metadata = { content : Text; name : Text };
  public type MsgType = { #onApprove; #onExecute; #onTransfer; #onLock };
  public type Operation = {
    #approve : { allowance : Nat };
    #lockTransfer : { locked : Nat; expiration : Time; decider : AccountId };
    #transfer : { action : { #burn; #mint; #send } };
    #executeTransfer : { fallback : Nat; lockedTxid : Txid };
  };
  public type Subscription = { callback : Callback; msgTypes : [MsgType] };
  public type Time = Int;
  public type Transaction = {
    to : AccountId;
    value : Nat;
    data : ?Blob;
    from : AccountId;
    operation : Operation;
  };
  public type Txid = Blob;
  public type TxnQueryRequest = {
    #txnCount : { owner : Address };
    #lockedTxns : { owner : Address };
    #lastTxids : { owner : Address };
    #lastTxidsGlobal;
    #getTxn : { txid : Txid };
    #txnCountGlobal;
    #getEvents: { owner: ?Address; };
  };
  public type TxnQueryResponse = {
    #txnCount : Nat;
    #lockedTxns : { txns : [TxnRecord]; lockedBalance : Nat };
    #lastTxids : [Txid];
    #lastTxidsGlobal : [Txid];
    #getTxn : ?TxnRecord;
    #txnCountGlobal : Nat;
    #getEvents: [TxnRecord];
  };
  public type TxnRecord = {
    gas : Gas;
    transaction : Transaction;
    txid : Txid;
    nonce : Nat;
    timestamp : Time;
    caller : Principal;
    index : Nat;
  };
  public type TxnResult = {
    #ok : Txid;
    #err : {
      code : {
        #InsufficientGas;
        #InsufficientAllowance;
        #UndefinedError;
        #InsufficientBalance;
        #LockedTransferExpired;
      };
      message : Text;
    };
  };
  public type Self = actor {
    allowance : shared query (Address, Address) -> async Nat;
    approvals : shared query Address -> async [Allowance];
    approve : shared (Address, Nat, ?[Nat8]) -> async TxnResult;
    balanceOf : shared query Address -> async Nat;
    cyclesBalanceOf : shared query Address -> async Nat;
    cyclesReceive : shared ?Address -> async Nat;
    decimals : shared query () -> async Nat8;
    executeTransfer : shared (Txid, ExecuteType, ?[Nat8]) -> async TxnResult;
    gas : shared query () -> async Gas;
    lockTransfer : shared (
        Address,
        Nat,
        Nat32,
        ?Address, 
        ?[Nat8],
        ?Blob,
      ) -> async TxnResult;
    lockTransferFrom : shared (
        Address,
        Address,
        Nat,
        Nat32,
        ?Address, 
        ?[Nat8],
        ?Blob,
      ) -> async TxnResult;
    metadata : shared query () -> async [Metadata];
    name : shared query () -> async Text;
    standard : shared query () -> async Text;
    subscribe : shared (Callback, [MsgType], ?[Nat8]) -> async Bool;
    subscribed : shared query Address -> async ?Subscription;
    symbol : shared query () -> async Text;
    totalSupply : shared query () -> async Nat;
    transfer : shared (Address, Nat, ?[Nat8], ?Blob) -> async TxnResult;
    transferFrom : shared (
        Address,
        Address,
        Nat, 
        ?[Nat8],
        ?Blob,
      ) -> async TxnResult;
    txnQuery : shared query TxnQueryRequest -> async TxnQueryResponse;
  }
}