## DRC207
Monitorable Canister Standard.

### Abstract

The DRC207 standard develops interface specifications to meet the needs of canister monitoring. The standard helps us to monitor changes in the state of the canister, manage the triggering of timed tasks and improve the immutability of canisters.

Standard: https://github.com/iclighthouse/DRC_standards/blob/main/DRC207/DRC207.md

### Implementation

Implement the [DRC207 Standard](https://github.com/iclighthouse/DRC_standards/tree/main/DRC207) in your canister, and set the canister's own canister-id as its controller. For example.

**Step 1**
Canister implement code:  
```
import DRC207 "./lib/DRC207"; // src: https://github.com/iclighthouse/DRC_standards/blob/main/DRC207/examples/ICLighthouse/DRC207.mo
import Cycles "mo:base/ExperimentalCycles";

    // DRC207 ICMonitor
    /// DRC207 support
    public query func drc207() : async DRC207.DRC207Support{
        return {
            monitorable_by_self = true;
            monitorable_by_blackhole = { allowed = true; canister_id = ?Principal.fromText("7hdtw-jqaaa-aaaak-aaccq-cai"); };
            cycles_receivable = true;
            timer = { enable = false; interval_seconds = null; }; 
        };
    };
    /// canister_status
    public func canister_status() : async DRC207.canister_status {
        let ic : DRC207.IC = actor("aaaaa-aa");
        await ic.canister_status({ canister_id = Principal.fromActor(CanisterName) });
    };
    /// receive cycles
    public func wallet_receive(): async (){
        let amout = Cycles.available();
        let accepted = Cycles.accept(amout);
    };
    /// timer tick
    public func timer_tick(): async (){
        //do something
    };
```
**Parameters description**
- monitorable_by_self:  
    If `true` is entered, it's required to add the canister's own canister_id to its controllers.
- monitorable_by_blackhole:  
    `monitorable_by_blackhole.canister_id`(principal) means that a blackhole is specified to read the canister status, For example [`7hdtw-jqaaa-aaaak-aaccq-cai`](https://github.com/iclighthouse/ICMonitor).  
    If monitorable_by_blackhole.canister_id is entered, it's is required to add the blackhole's canister_id to the canister's controllers.
- cycles_receivable:  
    If `true` is entered, It means that the canister has implemented wallet_receive().
- timer:   
    The `timer.interval_seconds` should be greater than or equal to 5 minutes (300 seconds),   
    timer.interval_seconds=`0` means that timer_tick() will be executed once per heartbeat by the Monitor.  
    Notes: Timer_tick() will be executed once the eventType `TimerTick` has been subscribed to in the Monitor. There is no guarantee that timer_tick() will be triggered on time.

**Step 2**
Set canister's own canister-id and/or blackhole (7hdtw-jqaaa-aaaak-aaccq-cai) as its controller.  
```
dfx canister --network ic call aaaaa-aa update_settings '(record {canister_id=principal "<your_canister_id>"; settings= record {controllers=vec {principal "<your_controller_principal>"; principal "<your_canister_id>"; principal "7hdtw-jqaaa-aaaak-aaccq-cai"}}})'
```

**Step 3**
Select a monitor and subscribe to the canister's events. For example https://github.com/iclighthouse/ICMonitor.

### About Blackhole Canister

Use Blackhole canister as a proxy canister to monitor the status of your canister, before using it you need to set a blackhole canister-id as one of the controllers of your canister.
The controller of the blackhole canister has been modified to its own canister id and no one can control the canister. 

The Blackhole canister id is "7hdtw-jqaaa-aaaak-aaccq-cai", or you can deploy one yourself. 

- Canister id:  7hdtw-jqaaa-aaaak-aaccq-cai  
- ModuleHash(dfx: 0.8.4):  603692eda4a0c322caccaff93cf4a21dc44aebad6d71b40ecefebef89e55f3be  
- Controllers:  7hdtw-jqaaa-aaaak-aaccq-cai   
- Github:  https://github.com/iclighthouse/ICMonitor/blob/main/Blackhole.mo