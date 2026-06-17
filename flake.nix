{
  description = "Logos multi-chain EVM wallet UI (QML, Metamask-like) over wallet_backend_module.";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # The backend the UI drives. Declaring it as an input lets the standalone
    # app (mkLogosQmlModule's apps.default) bundle and auto-load it (and, via the
    # backend's own flake, its eth-rpc/keystore/token-list dependencies).
    wallet_backend_module.url = "github:logos-co/logos-evm-wallet-backend-module";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
