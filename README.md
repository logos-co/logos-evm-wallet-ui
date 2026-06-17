# logos-evm-wallet-ui

A Metamask-like **QML UI** (`ui_qml`) for the Logos multi-chain EVM wallet, over
[`wallet_backend_module`](https://github.com/logos-co/logos-evm-wallet-backend-module).

It is **QML-only** — no C++/QtRO backend. The view drives the wallet backend
entirely through the injected `logos` bridge
(`logos.callModule`/`callModuleAsync`/`onModuleEvent`) against the backend's
JSON-string API, which keeps the UI simple and language-agnostic.

Tabs: **Balances** (per-chain + tokens, refresh), **Send** (native + ERC20 with
fee preview), **Tokens** (per-chain lists + add custom token), **History** (local
wallet-originated txs), **Settings** (proxy URL + fail-closed toggle). Live
updates come from the backend's `balances_updated` / `tx_status_changed` /
`proxy_error` events.

## Build

```bash
nix build .#install   # -> result/plugins/wallet_ui/  (QML + manifest)
```

The plugin declares `wallet_backend_module` as a dependency; a host
(`logos-standalone-app` / `logos-basecamp`) loads the UI plugin and auto-loads the
backend (and its dependency modules) alongside it.
