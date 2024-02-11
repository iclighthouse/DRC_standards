/**
 * Module     : Bloom.mo v 1.0
 * Author     : DFINITY-Education, Modified by ICLight.house Team
 * Stability  : Experimental
 * Description: BloomFilter.
 * Refers     : https://github.com/DFINITY-Education/data-structures/tree/main/src/BloomFilter
 */
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Float "mo:base/Float";
import Hash "mo:base/Hash";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat8 "mo:base/Nat8";
import Principal "mo:base/Principal";
import SHA224 "mo:sha224/SHA224";
import Buffer "mo:base/Buffer";

module {

    type Hash = Hash.Hash;

    /// Hash function example in case the element's type is Blob: 
    private func nat8to32 (n : Nat8) : Nat32{ 
        Nat32.fromIntWrap(Nat8.toNat(n)); 
    };
    public func arrayAppend<T>(a: [T], b: [T]) : [T]{
        let buffer = Buffer.Buffer<T>(1);
        for (t in a.vals()){
            buffer.add(t);
        };
        for (t in b.vals()){
            buffer.add(t);
        };
        return Buffer.toArray(buffer);
    };
    public func blobHash(b: Blob, k: Nat32) : [Hash]{
        if (k == 0){ return [] };
        var s: [Nat8] = Blob.toArray(b);
        var res: [Hash] = [];
        for (i in Iter.range(1, Nat32.toNat(k))){
            s := SHA224.sha224(s);
            let h = nat8to32(s[3])  | nat8to32(s[2]) << 8  | nat8to32(s[1]) << 16 | nat8to32(s[0]) << 24;
            res := arrayAppend(res, [h]);
        };
        return res;
    };
    public func principalHash(p: Principal, k: Nat32) : [Hash]{
        return blobHash(Principal.toBlob(p), k);
    };

    /// Manages BloomFilters, deploys new BloomFilters, and checks for element membership across filters.
    /// Args:
    ///   |n|   The maximum number of elements a BlooomFilter may store.
    ///   |p|   The maximum false positive rate a BloomFilter may maintain.
    ///   |f|   The hash function used to hash element.
    public class AutoScalingBloomFilter<S>(n: Nat, p: Float, f: (S, Nat32) -> [Hash]) {

        var filters: [BloomFilter<S>] = [];
        var numItems = 0;
        var m: Float =  Float.ceil(Float.fromInt(n) * Float.abs(Float.log(p)) / (Float.log(2) ** 2));
        m := Float.ceil(m / 8) * 8;
        let m_: Nat32 = Nat32.fromNat(Int.abs(Float.toInt(m)));
        let k: Float = Float.ceil(0.7 * m / Float.fromInt(n));
        let k_: Nat32 = Nat32.fromNat(Int.abs(Float.toInt(k)));

        public func getN() : Nat {
            return n;
        };
        public func getP() : Float {
            return p;
        };

        public func getM() : Nat32 {
            return m_;
        };
        public func getK() : Nat32 {
            return k_;
        };

        /// Adds an element to the BloomFilter's bitmap and deploys new BloomFilter if previous is at n.
        /// Args:
        ///   |item|   The item to be added.
        public func add(item: S) {
            var newFilter: Bool = false;
            var filter: BloomFilter<S> = do {
                if (filters.size() > 0) {
                    let last_filter = filters[filters.size() - 1];
                    if (last_filter.getNumItems() < n) {
                        last_filter
                    } else {
                        newFilter := true;
                        BloomFilter(m_, k_, f)
                    }
                } else {
                    newFilter := true;
                    BloomFilter(m_, k_, f)
                }
            };
            filter.add(item);
            numItems += 1;
            if (newFilter) {
                filters := arrayAppend<BloomFilter<S>>(filters, [filter]);
            };
        };

        /// Checks if an item is contained in any BloomFilters
        /// Args:
        ///   |item|   The item to be searched for.
        /// Returns:
        ///   A boolean indicating set membership.
        public func check(item: S) : Bool {
            let hashs = f(item, k_);
            for (filter in Iter.fromArray(filters)) {
                if (filter.check(hashs)) { return true; };
            };
            false
        };
        public func check2(hashs: [Hash]) : Bool {
            for (filter in Iter.fromArray(filters)) {
                if (filter.check(hashs)) { return true; };
            };
            false
        };

        public func getNumItems() : Nat {
            return numItems;
        };

        public func getData() : [([Nat8], Nat)] {
            var size = filters.size();
            if (size == 0 ) { return [] };
            let bitMaps = Array.init<([Nat8], Nat)>(size, ([], 0));
            for (i in Iter.range(0, size-1)){
                bitMaps[i] := (filters[i].getBitMap(), filters[i].getNumItems());
            };
            return Array.freeze(bitMaps);
        };

        public func setData(data: [([Nat8], Nat)], num: Nat) {
            var size = data.size();
            if (size ==0 ) { return () };
            numItems := num;
            for (i in Iter.range(0, size-1)){
                let filter = BloomFilter<S>(m_, k_, f);
                filter.setData(data[i].0, data[i].1);
                filters := arrayAppend<BloomFilter<S>>(filters, [filter]);
            };
        };

    };

    /// The specific BloomFilter implementation used in AutoScalingBloomFilter.
    /// Args:
    ///   |m|     The size of the bitmap (as determined in AutoScalingBloomFilter).
    ///   |k|     Number of hash functions.
    ///   |f|     The hash function of element.
    public class BloomFilter<S>(m: Nat32, k: Nat32, f: (S, Nat32) -> [Hash]) {

        var numItems = 0;
        //let bitMap: [var Bool] = Array.init<Bool>(Nat32.toNat(m), false);
        var mapSize: Nat = Nat32.toNat(m / 8);
        if (m % 8 > 0){ mapSize += 1; }; 
        let bitMap_: [var Nat8] = Array.init<Nat8>(mapSize, 0);
        let bit8: [Nat8] = [0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01];

        public func add(item: S) {
            for (h in Iter.fromArray(f(item, k))) {
                let pos = Nat32.toNat((h-1) % m);
                let mapPos = pos / 8;
                let bitPos = pos % 8;
                bitMap_[mapPos] |= bit8[bitPos];
            };
            numItems += 1;
        };

        public func check(hashs: [Hash]) : Bool { // item: S
            for (h in Iter.fromArray(hashs)) { // f(item, k)
                let pos = Nat32.toNat((h-1) % m);
                let mapPos = pos / 8;
                let bitPos = pos % 8;
                if (bitMap_[mapPos] ^ bit8[bitPos] == bit8[bitPos]) return false;
            };
            return true;
        };

        public func getNumItems() : Nat {
            return numItems;
        };

        public func getBitMap() : [Nat8] {
            return Array.freeze(bitMap_);
        };

        public func setData(data: [Nat8], num: Nat) {
            assert(data.size() == mapSize);
            numItems := num;
            for (i in Iter.range(0, data.size() - 1)) {
                bitMap_[i] := data[i];
            };
        };

    };

};
