import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// Metamask-like multi-chain EVM wallet view. Drives the C++ backend
// (wallet_ui.rep) over QtRO: PROPs (backend.*Json) auto-sync from the backend,
// SLOTs are called directly (PROP-updating) or via logos.watch (for a reply).
// The backend in turn calls wallet_backend_module over the typed modules() client.
//
// The sections live on a TabBar + StackLayout. Only the active page's controls
// are in the visible scene, so headless qt-mcp drives navigation through the
// root's `selectTab(i)` helper (call_method on objectName "walletRoot") before
// asserting a tab's controls — the account selector + status line stay shared
// above/below the tabs so they're always visible.
Item {
    id: root
    objectName: "walletRoot"
    width: 460
    height: 760

    readonly property var backend: logos.module("wallet_ui")
    property bool ready: false
    // When a custom network is saved/selected on the Advanced tab, sends target it
    // directly (so a freshly-added local node is usable without touching the Send
    // dropdown). Cleared when the user picks a chain from the Send dropdown.
    property int overrideChainId: 0

    // Parsed views of the backend's JSON PROPs.
    readonly property var chains: parseField(backend ? backend.chainsJson : "", "chains", [])
    readonly property var accounts: parseField(backend ? backend.accountsJson : "", "accounts", [])
    readonly property var balances: parseField(backend ? backend.balancesJson : "", "balances", ({}))
    readonly property var tokens: parseField(backend ? backend.tokensJson : "", "tokens", [])
    readonly property var history: parseField(backend ? backend.historyJson : "", "history", [])
    readonly property var market: parseField(backend ? backend.marketJson : "", "chains", [])
    readonly property var shielded: parseField(backend ? backend.shieldedBalanceJson : "", "balances", [])

    function parseField(json, field, fallback) {
        if (!json) return fallback
        try { var o = JSON.parse(json); return (o && o[field] !== undefined) ? o[field] : fallback }
        catch (e) { return fallback }
    }

    // Active chain id for the Private tab (defaults to Sepolia 11155111).
    function privChainId() {
        return root.chains.length ? root.chains[privChain.currentIndex].chainId : 11155111
    }

    // Doctest hook: switch the active tab deterministically. qt-mcp drives this via
    // `call_method` (find_by objectName "walletRoot", method "selectTab", args [i]),
    // the same pattern the tutorial QML UI uses for coreModulesView.openInterface.
    // Switching the tab makes that page's controls visible/findable to qt-mcp.
    function selectTab(i) { tabs.currentIndex = Number(i) }

    Connections {
        target: logos
        function onViewModuleReadyChanged(moduleName, isReady) {
            if (moduleName === "wallet_ui") root.ready = isReady && root.backend !== null
        }
    }
    Component.onCompleted: root.ready = root.backend !== null && logos.isViewModuleReady("wallet_ui")

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        // ── Header ──
        Label { text: "Logos Wallet"; font.pixelSize: 22; font.bold: true }
        Label {
            text: root.ready ? "Connected to backend" : "Connecting to backend…"
            color: root.ready ? "#2e7d32" : "#f0883e"; font.pixelSize: 12
        }

        // ── Accounts (shared across tabs) ──
        Label { text: "Accounts"; font.bold: true; Layout.topMargin: 4 }
        RowLayout {
            Layout.fillWidth: true
            ComboBox {
                id: acctBox; Layout.fillWidth: true; model: root.accounts
                onActivated: backend.selectedAccount = root.accounts[currentIndex]
                // Auto-select the first account once accounts load, so backend
                // events (balances/history) target it without a manual pick.
                onCountChanged: if (count > 0 && backend
                        && (!backend.selectedAccount || backend.selectedAccount.length === 0)) {
                    currentIndex = 0
                    backend.selectedAccount = root.accounts[0]
                }
            }
            Button {
                text: backend && backend.accountUnlocked ? "Lock" : "Unlock"
                enabled: root.ready && acctBox.currentText.length > 0
                onClicked: backend && backend.accountUnlocked
                           ? backend.lock(acctBox.currentText)
                           : unlockDialog.open()
            }
            Button { text: "New"; enabled: root.ready; onClicked: createDialog.open() }
        }

        // ── Tabs ──
        TabBar {
            id: tabs
            objectName: "walletTabs"
            Layout.fillWidth: true
            TabButton { text: "Balances" }
            TabButton { text: "Market" }
            TabButton { text: "Send" }
            TabButton { text: "Tokens" }
            TabButton { text: "History" }
            TabButton { text: "Private" }
            TabButton { text: "Settings" }
            TabButton { text: "Advanced" }
        }

        StackLayout {
            id: pages
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabs.currentIndex

            // ── 0 · Balances ──
            ScrollView {
                clip: true
                ColumnLayout {
                    width: pages.width - 16
                    spacing: 8
                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "Balances"; font.bold: true; Layout.fillWidth: true }
                        Button {
                            text: "Refresh balances"; enabled: root.ready && acctBox.currentText.length > 0
                            onClicked: backend.refreshBalances(acctBox.currentText)
                        }
                    }
                    Repeater {
                        model: root.balances && root.balances.chains ? root.balances.chains : []
                        Frame {
                            Layout.fillWidth: true
                            ColumnLayout {
                                anchors.fill: parent
                                Label { text: "chain " + modelData.chainId; font.bold: true }
                                Label { text: "native: " + modelData.native }
                                Repeater {
                                    model: modelData.tokens || []
                                    Label { font.pixelSize: 12; color: "#555"; text: modelData.balance + "  " + modelData.address }
                                }
                            }
                        }
                    }
                }
            }

            // ── 1 · Market (Uniswap prices for held tokens, balance > 0) ──
            ScrollView {
                clip: true
                ColumnLayout {
                    width: pages.width - 16
                    spacing: 8
                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "Market"; font.bold: true; Layout.fillWidth: true }
                        Button {
                            text: "Refresh market"; enabled: root.ready && acctBox.currentText.length > 0
                            onClicked: backend.refreshMarket(acctBox.currentText)
                        }
                    }
                    Repeater {
                        model: root.market
                        ColumnLayout {
                            Layout.fillWidth: true
                            Label { text: "chain " + modelData.chainId; font.pixelSize: 11; color: "#888" }
                            Repeater {
                                model: modelData.items || []
                                RowLayout {
                                    Layout.fillWidth: true
                                    Label { text: modelData.symbol; font.bold: true; Layout.preferredWidth: 64 }
                                    Label {
                                        Layout.fillWidth: true; font.pixelSize: 12; color: "#555"
                                        text: modelData.usd != null ? ("$" + Number(modelData.usd).toFixed(2)) : "—"
                                    }
                                    Label {
                                        font.pixelSize: 12; color: "#2e7d32"
                                        text: modelData.valueUsd != null ? ("$" + Number(modelData.valueUsd).toFixed(2)) : ""
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── 2 · Send ──
            ScrollView {
                clip: true
                ColumnLayout {
                    width: pages.width - 16
                    spacing: 8
                    Label { text: "Send"; font.bold: true }
                    ComboBox {
                        id: sendChain; Layout.fillWidth: true; textRole: "name"; model: root.chains
                        // Picking a chain here clears the Advanced-tab override.
                        onActivated: root.overrideChainId = 0
                    }
                    Label {
                        visible: root.overrideChainId > 0; color: "#2e7d32"; font.pixelSize: 11
                        text: "Active network: chain " + root.overrideChainId + " (set on Advanced)"
                    }
                    CheckBox { id: isErc20; text: "ERC20 token" }
                    TextField { id: tokenAddr; Layout.fillWidth: true; visible: isErc20.checked; placeholderText: "Token contract address" }
                    TextField { id: toAddr; objectName: "sendToField"; Layout.fillWidth: true; placeholderText: "Recipient address (0x…)" }
                    TextField { id: amount; objectName: "sendAmountField"; Layout.fillWidth: true; placeholderText: "Amount (base units / wei)" }
                    RowLayout {
                        Button {
                            text: "Estimate"; enabled: root.ready
                            onClicked: logos.watch(backend.estimateFee(JSON.stringify(buildSend())),
                                                   function (r) { feePreview.text = "fee: " + r },
                                                   function (e) { feePreview.text = "estimate failed" })
                        }
                        Button {
                            text: "Send transaction"; enabled: root.ready && backend && backend.accountUnlocked
                            onClicked: {
                                var m = isErc20.checked ? backend.sendErc20(JSON.stringify(buildSend()))
                                                        : backend.sendNative(JSON.stringify(buildSend()))
                                logos.watch(m, function (r) {}, function (e) {})
                            }
                        }
                    }
                    Label { id: feePreview; color: "#777"; font.pixelSize: 12 }
                }
            }

            // ── 3 · Tokens ──
            ScrollView {
                clip: true
                ColumnLayout {
                    width: pages.width - 16
                    spacing: 8
                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "Tokens"; font.bold: true; Layout.fillWidth: true }
                        Button {
                            text: "Load tokens"; enabled: root.ready
                            onClicked: backend.loadTokens(root.chains.length ? root.chains[sendChain.currentIndex].chainId : 1)
                        }
                    }
                    Repeater {
                        model: root.tokens
                        Label { font.pixelSize: 12; text: (modelData.symbol || "?") + "  " + (modelData.name || "") + "  " + modelData.address }
                    }
                    Button { text: "Add custom token"; enabled: root.ready; onClicked: addTokenDialog.open() }
                }
            }

            // ── 4 · History ──
            ScrollView {
                clip: true
                ColumnLayout {
                    width: pages.width - 16
                    spacing: 8
                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "Recent activity"; font.bold: true; Layout.fillWidth: true }
                        Button {
                            text: "Refresh history"; enabled: root.ready && acctBox.currentText.length > 0
                            onClicked: backend.refreshHistory(acctBox.currentText)
                        }
                    }
                    Label {
                        visible: !root.history || root.history.length === 0
                        text: "No transactions yet"; color: "#888"; font.pixelSize: 12
                    }
                    Repeater {
                        model: root.history
                        RowLayout {
                            Layout.fillWidth: true
                            // Separate labels so each field is its own text node
                            // (kind/status are assertable verbatim in UI tests).
                            Label { text: modelData.kind; font.bold: true; font.pixelSize: 12; Layout.preferredWidth: 64 }
                            Label {
                                text: modelData.status; font.pixelSize: 12
                                color: modelData.status === "confirmed" ? "#2e7d32" : (modelData.status === "failed" ? "#c62828" : "#f9a825")
                            }
                            Label { text: modelData.hash; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideMiddle; color: "#555" }
                        }
                    }
                }
            }

            // ── 5 · Private (RAILGUN — UNAUDITED upstream, Sepolia-first) ──
            ScrollView {
                clip: true
                ColumnLayout {
                    width: pages.width - 16
                    spacing: 8

                    // Prominent unaudited / testnet warning.
                    Frame {
                        Layout.fillWidth: true
                        background: Rectangle { color: "#fff3e0"; border.color: "#ef6c00"; radius: 4 }
                        ColumnLayout {
                            anchors.fill: parent
                            Label { text: "⚠ Private transactions (RAILGUN)"; font.bold: true; color: "#e65100" }
                            Label {
                                Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: 11; color: "#bf360c"
                                text: "Experimental. The underlying engine is UNAUDITED — use on Sepolia (testnet) only; " +
                                      "do not move mainnet funds here. Proving a private send can take a while."
                            }
                        }
                    }

                    ComboBox { id: privChain; Layout.fillWidth: true; textRole: "name"; model: root.chains }

                    // Enable the private account + show the 0zk address.
                    RowLayout {
                        Layout.fillWidth: true
                        Button {
                            text: backend && backend.zkAddress.length ? "Re-enable" : "Enable private account"
                            enabled: root.ready && backend && backend.accountUnlocked && acctBox.currentText.length > 0
                            onClicked: logos.watch(backend.initPrivate(acctBox.currentText, root.privChainId()),
                                                   function (r) {}, function (e) {})
                        }
                        Button {
                            text: "Sync"; enabled: root.ready && backend && backend.zkAddress.length > 0
                            onClicked: backend.syncPrivate()
                        }
                    }
                    Label {
                        Layout.fillWidth: true; font.pixelSize: 11; color: "#555"; elide: Text.ElideMiddle
                        text: backend && backend.zkAddress.length
                              ? ("0zk: " + backend.zkAddress)
                              : "Not enabled — unlock an account, then enable."
                    }

                    // Shielded balances.
                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "Shielded balance"; font.bold: true; Layout.fillWidth: true }
                        Button {
                            text: "Refresh"; enabled: backend && backend.zkAddress.length > 0
                            onClicked: backend.refreshShieldedBalance()
                        }
                    }
                    Repeater {
                        model: root.shielded
                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideMiddle
                                text: (modelData.asset && modelData.asset.erc20) ? modelData.asset.erc20 : "asset"
                            }
                            Label { font.pixelSize: 12; color: "#2e7d32"; text: "" + modelData.amount }
                        }
                    }
                    Label {
                        visible: !root.shielded || root.shielded.length === 0
                        text: "No shielded balance"; color: "#888"; font.pixelSize: 12
                    }

                    // Shield (public → private).
                    Label { text: "Shield (deposit public → private)"; font.bold: true }
                    TextField { id: shieldAsset; Layout.fillWidth: true; placeholderText: "ERC-20 token address (0x…)" }
                    TextField { id: shieldAmount; Layout.fillWidth: true; placeholderText: "Amount (base units)" }
                    Button {
                        text: "Shield"
                        enabled: root.ready && backend && backend.accountUnlocked && backend.zkAddress.length > 0
                        onClicked: logos.watch(backend.shield(JSON.stringify({
                            from: acctBox.currentText, chainId: root.privChainId(),
                            asset: shieldAsset.text, amount: shieldAmount.text
                        })), function (r) {}, function (e) {})
                    }

                    // Private send — 0zk… → private transfer, 0x… → unshield (via the 4337 relayer).
                    Label { text: "Private send (the relayer hides the sender)"; font.bold: true }
                    TextField { id: privTo; Layout.fillWidth: true; placeholderText: "Recipient — 0zk… (private) or 0x… (withdraw)" }
                    TextField { id: privAsset; Layout.fillWidth: true; placeholderText: "ERC-20 token address (0x…)" }
                    TextField { id: privAmount; Layout.fillWidth: true; placeholderText: "Amount (base units)" }
                    TextField { id: privMemo; Layout.fillWidth: true; placeholderText: "Memo (optional — private transfers only)" }
                    TextField { id: privBundler; Layout.fillWidth: true; placeholderText: "Bundler URL (ERC-4337, Sepolia)" }
                    Button {
                        text: "Send privately"
                        enabled: root.ready && backend && backend.accountUnlocked
                                 && backend.zkAddress.length > 0 && privBundler.text.length > 0
                        onClicked: logos.watch(backend.privateSend(JSON.stringify({
                            from: acctBox.currentText, chainId: root.privChainId(), to: privTo.text,
                            asset: privAsset.text, amount: privAmount.text,
                            memo: privMemo.text, bundlerUrl: privBundler.text
                        })), function (r) {}, function (e) {})
                    }
                }
            }

            // ── 6 · Settings (privacy / proxy) ──
            ScrollView {
                clip: true
                ColumnLayout {
                    width: pages.width - 16
                    spacing: 8
                    Label { text: "Privacy / proxy"; font.bold: true }
                    TextField { id: proxyUrl; Layout.fillWidth: true; placeholderText: "socks5h://127.0.0.1:9050" }
                    CheckBox { id: proxyRequired; text: "Require proxy (fail-closed)" }
                    Button {
                        text: "Apply proxy"; enabled: backend !== null
                        onClicked: backend.setProxyConfig(JSON.stringify({
                            proxy: proxyUrl.text.length ? proxyUrl.text : null,
                            proxyRequired: proxyRequired.checked
                        }))
                    }
                }
            }

            // ── 7 · Advanced (custom networks + account import; dev / testing) ──
            ScrollView {
                clip: true
                ColumnLayout {
                    width: pages.width - 16
                    spacing: 8

                    // Custom network — add or replace an RPC endpoint (e.g. a local
                    // dev node). Saving repoints the wallet at this chain (set_chains
                    // → eth-rpc) and makes it the active network for sends.
                    Label { text: "Custom network"; font.bold: true }
                    Label {
                        Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: 11; color: "#777"
                        text: "Add or update an RPC endpoint — e.g. a local node at http://127.0.0.1:8545. " +
                              "Saving repoints the wallet and makes it the active send network."
                    }
                    TextField { id: advChainId; objectName: "advChainIdField"; Layout.fillWidth: true; placeholderText: "Chain ID (e.g. 31337)" }
                    TextField { id: advChainName; objectName: "advChainNameField"; Layout.fillWidth: true; placeholderText: "Network name (e.g. Local Anvil)" }
                    TextField { id: advRpcUrl; objectName: "advRpcUrlField"; Layout.fillWidth: true; placeholderText: "RPC URL (http://127.0.0.1:8545)" }
                    TextField { id: advSymbol; objectName: "advSymbolField"; Layout.fillWidth: true; placeholderText: "Native symbol (e.g. ETH)" }
                    TextField { id: advMulticall; objectName: "advMulticallField"; Layout.fillWidth: true; placeholderText: "Multicall3 address (optional, 0x…)" }
                    RowLayout {
                        Button {
                            text: "Test endpoint"; enabled: root.ready && advChainId.text.length > 0 && advRpcUrl.text.length > 0
                            // Push the entered endpoint into eth-rpc first (idempotent), then verify
                            // it — so Test works on a not-yet-saved network (verify what you typed).
                            // backend calls are serialized, so the push lands before the verify.
                            onClicked: {
                                backend.setChains(JSON.stringify(root.upsertChain()))
                                logos.watch(backend.testEndpoint(parseInt(advChainId.text)),
                                    function (r) {
                                        var ok = false; try { ok = JSON.parse(r).ok === true } catch (e) {}
                                        advResult.text = ok ? "Endpoint reachable" : ("Endpoint error: " + r)
                                    },
                                    function (e) { advResult.text = "Endpoint error" })
                            }
                        }
                        Button {
                            text: "Save chain"; enabled: root.ready && advChainId.text.length > 0 && advRpcUrl.text.length > 0
                            onClicked: {
                                backend.setChains(JSON.stringify(root.upsertChain()))
                                root.overrideChainId = parseInt(advChainId.text)
                            }
                        }
                    }
                    Label { id: advResult; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: "#777"; font.pixelSize: 12 }

                    Label { text: "Configured networks"; font.bold: true; Layout.topMargin: 8 }
                    Repeater {
                        model: root.chains
                        Label {
                            Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: 12; color: "#555"
                            text: modelData.chainId + " · " + modelData.name + " · " + modelData.rpcUrl
                        }
                    }

                    // Import an account from a seed phrase, then unlock it — inline
                    // (no modal) so the whole wallet flow is scriptable headless.
                    // Signing stays in the keystore module; the seed only transits
                    // to the backend's import call.
                    Label { text: "Import account (seed phrase)"; font.bold: true; Layout.topMargin: 8 }
                    TextField { id: advSeed; objectName: "advSeedField"; Layout.fillWidth: true; placeholderText: "Seed phrase (BIP-39 words)" }
                    TextField { id: advAcctLabel; objectName: "advAcctLabelField"; Layout.fillWidth: true; placeholderText: "Account label (e.g. main)" }
                    TextField { id: advAcctPw; objectName: "advAcctPwField"; Layout.fillWidth: true; placeholderText: "Account passphrase"; echoMode: TextInput.Password }
                    RowLayout {
                        Button {
                            text: "Import"; enabled: root.ready && advSeed.text.length > 0
                            onClicked: logos.watch(backend.importMnemonic(JSON.stringify({
                                    phrase: advSeed.text, accountIndex: 0, password: advAcctPw.text
                                }), advAcctLabel.text),
                                function (r) { advAcctResult.text = "Imported: " + r },
                                function (e) { advAcctResult.text = "Import failed: " + e })
                        }
                        Button {
                            text: "Unlock imported"; enabled: root.ready && acctBox.currentText.length > 0
                            onClicked: backend.unlock(acctBox.currentText, advAcctPw.text)
                        }
                    }
                    Label { id: advAcctResult; Layout.fillWidth: true; elide: Text.ElideMiddle; color: "#777"; font.pixelSize: 12 }
                }
            }
        }

        // ── Status (shared, always visible below the tabs) ──
        Label {
            Layout.fillWidth: true
            text: backend ? backend.statusText : ""; color: "#555"
        }
    }

    // Chain a send targets: the Advanced-tab override if set, else the Send tab's
    // dropdown selection.
    function activeSendChainId() {
        if (root.overrideChainId > 0) return root.overrideChainId
        return root.chains.length ? root.chains[sendChain.currentIndex].chainId : 1
    }

    function buildSend() {
        var p = { from: acctBox.currentText, to: toAddr.text, chainId: activeSendChainId(), amount: amount.text }
        if (isErc20.checked) p.tokenAddress = tokenAddr.text
        return p
    }

    // Build a ChainInfo (camelCase, matching wallet_backend's get/set_chains) from
    // the Advanced-tab form.
    function buildAdvChain() {
        var c = {
            chainId: parseInt(advChainId.text),
            name: advChainName.text.length ? advChainName.text : ("chain " + advChainId.text),
            rpcUrl: advRpcUrl.text,
            nativeSymbol: advSymbol.text.length ? advSymbol.text : "ETH"
        }
        if (advMulticall.text.length) c.multicall3 = advMulticall.text
        return c
    }

    // Upsert the Advanced-tab chain into the current chain list (replace by
    // chainId, else append). setChains replaces the whole list, so we preserve the
    // existing chains and add/update just this one.
    function upsertChain() {
        var cid = parseInt(advChainId.text)
        var out = []
        var found = false
        for (var i = 0; i < root.chains.length; i++) {
            if (root.chains[i].chainId === cid) { out.push(buildAdvChain()); found = true }
            else { out.push(root.chains[i]) }
        }
        if (!found) out.push(buildAdvChain())
        return out
    }

    Dialog {
        id: unlockDialog; title: "Unlock account"; modal: true; anchors.centerIn: parent
        standardButtons: Dialog.Ok | Dialog.Cancel
        ColumnLayout { TextField { id: unlockPw; placeholderText: "Passphrase"; echoMode: TextInput.Password } }
        onAccepted: { backend.unlock(acctBox.currentText, unlockPw.text); unlockPw.text = "" }
    }
    Dialog {
        id: createDialog; title: "New account"; modal: true; anchors.centerIn: parent
        standardButtons: Dialog.Ok | Dialog.Cancel
        ColumnLayout {
            TextField { id: newLabel; placeholderText: "Label" }
            TextField { id: newPw; placeholderText: "Passphrase"; echoMode: TextInput.Password }
        }
        onAccepted: { logos.watch(backend.createAccount(newPw.text, newLabel.text), function (r) {}, function (e) {}); newPw.text = "" }
    }
    Dialog {
        id: addTokenDialog; title: "Add custom token"; modal: true; anchors.centerIn: parent
        standardButtons: Dialog.Ok | Dialog.Cancel
        ColumnLayout {
            TextField { id: ctChain; placeholderText: "chainId" }
            TextField { id: ctAddr; placeholderText: "Token address (0x…)" }
            TextField { id: ctSym; placeholderText: "Symbol" }
            TextField { id: ctDec; placeholderText: "Decimals" }
        }
        onAccepted: backend.addCustomToken(JSON.stringify({
            chainId: parseInt(ctChain.text), address: ctAddr.text,
            name: ctSym.text, symbol: ctSym.text, decimals: parseInt(ctDec.text)
        }))
    }
}
