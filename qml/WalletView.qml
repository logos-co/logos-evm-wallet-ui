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

    // Parsed views of the backend's JSON PROPs.
    readonly property var chains: parseField(backend ? backend.chainsJson : "", "chains", [])
    readonly property var accounts: parseField(backend ? backend.accountsJson : "", "accounts", [])
    readonly property var balances: parseField(backend ? backend.balancesJson : "", "balances", ({}))
    readonly property var tokens: parseField(backend ? backend.tokensJson : "", "tokens", [])
    readonly property var history: parseField(backend ? backend.historyJson : "", "history", [])
    readonly property var market: parseField(backend ? backend.marketJson : "", "chains", [])

    function parseField(json, field, fallback) {
        if (!json) return fallback
        try { var o = JSON.parse(json); return (o && o[field] !== undefined) ? o[field] : fallback }
        catch (e) { return fallback }
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
            TabButton { text: "Settings" }
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
                    ComboBox { id: sendChain; Layout.fillWidth: true; textRole: "name"; model: root.chains }
                    CheckBox { id: isErc20; text: "ERC20 token" }
                    TextField { id: tokenAddr; Layout.fillWidth: true; visible: isErc20.checked; placeholderText: "Token contract address" }
                    TextField { id: toAddr; Layout.fillWidth: true; placeholderText: "Recipient address (0x…)" }
                    TextField { id: amount; Layout.fillWidth: true; placeholderText: "Amount (base units / wei)" }
                    RowLayout {
                        Button {
                            text: "Estimate"; enabled: root.ready
                            onClicked: logos.watch(backend.estimateFee(JSON.stringify(buildSend())),
                                                   function (r) { feePreview.text = "fee: " + r },
                                                   function (e) { feePreview.text = "estimate failed" })
                        }
                        Button {
                            text: "Send"; enabled: root.ready && backend && backend.accountUnlocked
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
                    Label { text: "Recent activity"; font.bold: true }
                    Label {
                        visible: !root.history || root.history.length === 0
                        text: "No transactions yet"; color: "#888"; font.pixelSize: 12
                    }
                    Repeater {
                        model: root.history
                        Label {
                            font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideMiddle
                            text: modelData.kind + " · " + modelData.status + " · " + modelData.hash
                            color: modelData.status === "confirmed" ? "#2e7d32" : (modelData.status === "failed" ? "#c62828" : "#f9a825")
                        }
                    }
                }
            }

            // ── 5 · Settings (privacy / proxy) ──
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
        }

        // ── Status (shared, always visible below the tabs) ──
        Label {
            Layout.fillWidth: true
            text: backend ? backend.statusText : ""; color: "#555"
        }
    }

    function buildSend() {
        var cid = root.chains.length ? root.chains[sendChain.currentIndex].chainId : 1
        var p = { from: acctBox.currentText, to: toAddr.text, chainId: cid, amount: amount.text }
        if (isErc20.checked) p.tokenAddress = tokenAddr.text
        return p
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
