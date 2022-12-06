/**
 * Module     : Hash32.mo
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Description: Generate hash value for data.
 * Refers     : https://github.com/iclighthouse/
 */
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Option "mo:base/Option";
import SHA224 "SHA224";
import CRC32 "CRC32";

module {
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
    public func hash(_pre: ?[Nat8], _input: [Nat8]) : [Nat8]{
        let pre = Option.get(_pre, []);
        let data: [Nat8] = arrayAppend(pre, _input);
        let h : [Nat8] = SHA224.sha224(data);
        let crc : [Nat8] = CRC32.crc32(h);
        return arrayAppend(crc, h);
    };
    public func hashb(_pre: ?Blob, _input: Blob) : Blob{
        let pre = Option.get(_pre, Blob.fromArray([]));
        return Blob.fromArray(hash(?Blob.toArray(pre), Blob.toArray(_input)));
    };
};