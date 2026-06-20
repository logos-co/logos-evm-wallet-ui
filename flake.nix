{
  description = "Logos multi-chain EVM wallet UI (QML, Metamask-like) over wallet_backend_module.";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # The backend the UI drives, plus its dependency modules. Declaring the whole
    # tree as inputs lets the standalone app (mkLogosQmlModule's apps.default)
    # bundle and auto-load every module in dependency order — without the leaf
    # modules the backend can't load and the UI's calls time out.
    wallet_backend_module.url = "github:logos-co/logos-evm-wallet-backend-module/856b9adfed175c2f52b1a8ae6fb4bd45da4c96d5";
    eth_rpc_module.url = "github:logos-co/logos-evm-eth-rpc-module";
    keystore_module.url = "github:logos-co/logos-evm-keystore-module";
    token_list_module.url = "github:logos-co/logos-evm-token-list-module";
    uniswap_module.url = "github:logos-co/logos-evm-uniswap-module";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
