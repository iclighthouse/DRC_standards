module {
  public type canister_id = Principal;

  public type definite_canister_settings = {
    freezing_threshold : Nat;
    controllers : [Principal];
    memory_allocation : Nat;
    compute_allocation : Nat;
  };

  public type canister_status = {
     status : { #stopped; #stopping; #running };
     memory_size : Nat;
     cycles : Nat;
     settings : definite_canister_settings;
     module_hash : ?[Nat8];
  };

  public type IC = actor {
   canister_status : { canister_id : canister_id } -> async canister_status;
  };

  public type Self = actor {
    canister_status : () -> async canister_status;
    timer_tick : () -> async ();
    wallet_receive : () -> async ();
  };

}
