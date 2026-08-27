{
  description = "Logos multi-chain EVM wallet UI (QML, Metamask-like) over wallet_backend_module.";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # The backend the UI drives. Declaring its whole dependency tree here is what
    # lets the standalone app bundle and auto-load every module in order.
    wallet_backend_module.url = "github:logos-co/logos-evm-wallet-backend-module/a8150171b567a4479cca5dc0a19ce2f0423ae132";

    # Each leaf is the backend's OWN locked input, never a second pin of our own:
    # collectAllModuleDeps is `transitive // direct`, so a url here shadows the
    # backend's lock and ships it a module it was not built against.
    eth_rpc_module.follows = "wallet_backend_module/eth_rpc_module";
    keystore_module.follows = "wallet_backend_module/keystore_module";
    token_list_module.follows = "wallet_backend_module/token_list_module";
    uniswap_module.follows = "wallet_backend_module/uniswap_module";

    # NOT followed: railgun still calls keystore's removed `sign_digest`, so it
    # does not compile against the keystore the backend requires. Its private-send
    # path is broken against that keystore either way -- see logos-evm-railgun-module.
    railgun_module.url = "github:logos-co/logos-evm-railgun-module";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
