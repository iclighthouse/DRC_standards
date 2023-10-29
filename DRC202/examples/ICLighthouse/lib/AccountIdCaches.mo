module {
  public type Account = { owner : Principal; subaccount : ?[Nat8] };
  public type AccountId = [Nat8];
  public type Self = actor {
    fromAccountId : shared query AccountId -> async ?Account;
    put : shared [Account] -> async ();
    toAccountId : shared query Account -> async AccountId;
  }
}