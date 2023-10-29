import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import Trie "mo:base/Trie";
import Cycles "mo:base/ExperimentalCycles";
import Tools "mo:icl/Tools";
actor {
    type AccountId = Blob;
    type Account = { owner: Principal; subaccount: ?[Nat8] };
    private let fee_: Nat = 10000;
    private stable var accounts: Trie.Trie<AccountId, Account> = Trie.empty(); 

    private func keyb(t: Blob) : Trie.Key<Blob> { return { key = t; hash = Blob.hash(t) }; };

    public shared func put(_accounts: [Account]): async (){
        let amout = Cycles.available();
        assert(amout >= fee_);
        let accepted = Cycles.accept(fee_);
        for (account in _accounts.vals()){
            let accountId = Tools.principalToAccountBlob(account.owner, account.subaccount);
            accounts := Trie.put(accounts, keyb(accountId), Blob.equal, account).0;
        };
    };

    public query func fromAccountId(_accountId: AccountId) : async ?Account{
        return Trie.get(accounts, keyb(_accountId), Blob.equal);
    };

    public query func toAccountId(_account: Account) : async AccountId{
        return Tools.principalToAccountBlob(_account.owner, _account.subaccount);
    };

    public func wallet_receive(): async (){
        let amout = Cycles.available();
        let accepted = Cycles.accept(amout);
    };

};