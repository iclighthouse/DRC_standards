import DRC207 "DRC207";
import Principal "mo:base/Principal";
import Cycles "mo:base/ExperimentalCycles";

actor Monitor {
    let Threshold: Nat = 1_000_000_000_000;

    public func monitor(_canisterId: Principal) : async (){
        let ic: DRC207.IC = actor("aaaaa-aa");
        let blackhole: DRC207.Blackhole = actor("7hdtw-jqaaa-aaaak-aaccq-cai");
        let drc207: DRC207.Self = actor(Principal.toText(_canisterId));
        var canisterStatus: ?DRC207.canister_status = null;
        try{
            canisterStatus := ?(await blackhole.canister_status({canister_id = _canisterId }));
        }catch(e){
            canisterStatus := ?(await drc207.canister_status());
        };
        switch(canisterStatus){
            case(?(status)){
                if (status.cycles < Threshold){
                    Cycles.add(Threshold * 2);
                    await ic.deposit_cycles({canister_id = _canisterId });
                };
            };
            case(_){};
        };
    };
};