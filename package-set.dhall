-- let upstream = https://github.com/dfinity/vessel-package-set/releases/download/mo-0.10.0-20230911/package-set.dhall sha256:7bce6afe8b96a8808f66b5b6f7015257d44fc1f3e95add7ced3ccb7ce36e5603
-- mo-0.9.7-20230718
let upstream = 
[ { dependencies = [] : List Text
  , name = "base"
  , repo = "https://github.com/dfinity/motoko-base.git"
  , version = "1bee37dbe5dbab1017b18ba0490b78f148196c8b"
  }
, { dependencies = [ "base" ]
  , name = "crud"
  , repo = "https://github.com/matthewhammer/motoko-crud.git"
  , version = "0367a9a40eb708772df0662232a842c273a263e9"
  }
, { dependencies = [ "base" ]
  , name = "matchers"
  , repo = "https://github.com/kritzcreek/motoko-matchers.git"
  , version = "3dac8a071b69e4e651b25a7d9683fe831eb7cffd"
  }
, { dependencies = [ "base" ]
  , name = "parsec"
  , repo = "https://github.com/crusso/mo-parsec.git"
  , version = "6d84fe23245dac4c8c6c83f83349d972dd98289c"
  }
, { dependencies = [ "base" ]
  , name = "scc"
  , repo = "https://github.com/nomeata/motoko-scc.git"
  , version = "a6ddd4e688f75443674ad8ed24495fbeb103fc7b"
  }
, { dependencies = [ "base" ]
  , name = "sha256"
  , repo = "https://github.com/enzoh/motoko-sha.git"
  , version = "9e2468f51ef060ae04fde8d573183191bda30189"
  }
, { dependencies = [ "base" ]
  , name = "icip"
  , repo = "https://github.com/feliciss/icip.git"
  , version = "3188b01d7ec5ef354c773c66197869cdce18c4b7"
  }
, { dependencies = [ "base" ]
  , name = "pretty"
  , repo = "https://github.com/kritzcreek/motoko-pretty.git"
  , version = "73b81a2df1058396f0395d2d4a38ddcca4531142"
  }
, { dependencies = [ "base" ]
  , name = "sha224"
  , repo = "https://github.com/flyq/motoko-sha224.git"
  , version = "82e0aa1a77a8c0a2f98332b59ffc242d820e62cb"
  }
, { dependencies = [ "base" ]
  , name = "splay"
  , repo = "https://github.com/chenyan2002/motoko-splay.git"
  , version = "f8e50749f9c4d7ccae99694c35310ac68945a225"
  }
, { dependencies = [ "base" ]
  , name = "sequence"
  , repo = "https://github.com/matthewhammer/motoko-sequence.git"
  , version = "e57b88cf4aa4852c7f66b9150692e256911c1425"
  }
, { dependencies = [ "base" ]
  , name = "base32"
  , repo = "https://github.com/flyq/motoko-base32.git"
  , version = "067ac54e288f4cd7302be1f400bcddcce70f7d77"
  }
, { dependencies = [ "base" ]
  , name = "adapton"
  , repo = "https://github.com/matthewhammer/motoko-adapton.git"
  , version = "d1b130fd930d8b498b66d2a2c6a45beea3f67c3a"
  }
, { dependencies = [ "base" ]
  , name = "iterext"
  , repo = "https://github.com/timohanke/motoko-iterext"
  , version = "6c05ff069e00eabdd2fc700d7457878d72dafaa9"
  }
, { dependencies = [ "base", "iterext" ]
  , name = "sha2"
  , repo = "https://github.com/timohanke/motoko-sha2"
  , version = "837682e5a503f200f6829081e41dd6c98b8d6bf9"
  }
, { dependencies = [ "base" ]
  , name = "easy-random"
  , repo = "https://github.com/neokree/easy-random.git"
  , version = "87acbe9565cb7fb4397c97d871bc8624a6bfb882"
  }
, { dependencies = [ "base" ]
  , name = "xtended-numbers"
  , repo = "https://github.com/edjcase/motoko_numbers"
  , version = "773953141f976ccdfc2e6a2c451b841a53bb39a0"
  }
, { dependencies = [ "xtended-numbers" ]
  , name = "cbor"
  , repo = "https://github.com/gekctek/motoko_cbor"
  , version = "5adf22b177d187d076b222e94b3fdf071b7c0b65"
  }
, { dependencies = [ "base", "sha256", "cbor", "sha224" ]
  , name = "ic-certification"
  , repo = "https://github.com/nomeata/ic-certification"
  , version = "5556c18ab4e9f751affbebbd60508791a102b57f"
  }
]
let Package =
    { name : Text, version : Text, repo : Text, dependencies : List Text }

let
  -- This is where you can add your own packages to the package-set
  additions =
    [
    { dependencies = [ "base", "sha224" ]
      , name = "icl"
      , repo = "https://github.com/iclighthouse/icl-vessel"
      , version = "037e073f14d9a91ba6c3a0f72ef69e6201629dd2"
      }
    ] : List Package

let
  {- This is where you can override existing packages in the package-set

     For example, if you wanted to use version `v2.0.0` of the foo library:
     let overrides = [
         { name = "foo"
         , version = "v2.0.0"
         , repo = "https://github.com/bar/foo"
         , dependencies = [] : List Text
         }
     ]
  -}
  overrides =
    [] : List Package

in  upstream # additions # overrides