{
  description = "Logos multi-chain EVM wallet UI (QML, Metamask-like) over wallet_backend_module.";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # The backend the UI drives, plus its dependency modules. Declaring the whole
    # tree as inputs lets the standalone app (mkLogosQmlModule's apps.default)
    # bundle and auto-load every module in dependency order — without the leaf
    # modules the backend can't load and the UI's calls time out.
    wallet_backend_module.url = "github:logos-co/logos-evm-wallet-backend-module/61c1cf776bc3ff36371bbbc77e4bed601c80b842";
    eth_rpc_module.url = "github:logos-co/logos-evm-eth-rpc-module";
    keystore_module.url = "github:logos-co/logos-evm-keystore-module";
    token_list_module.url = "github:logos-co/logos-evm-token-list-module";
    uniswap_module.url = "github:logos-co/logos-evm-uniswap-module";
    railgun_module.url = "github:logos-co/logos-evm-railgun-module";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
