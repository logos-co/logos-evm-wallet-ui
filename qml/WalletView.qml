import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// Multi-chain EVM wallet — Metamask-like UI over wallet_backend_module.
// All backend interaction goes through the injected `logos` bridge:
//   logos.callModule("wallet_backend_module", method, [args])  -> JSON
//   logos.callModuleAsync(module, method, [args], cb, ms)
//   logos.onModuleEvent(module, event) + Connections{onModuleEventReceived}
Item {
    id: root
    width: 460
    height: 720

    readonly property string backend: "wallet_backend_module"
    property var accounts: []
    property string selectedAccount: ""
    property bool unlocked: false
    property var chains: []
    property var balances: ({})          // { address, chains:[{chainId,native,tokens}] }
    property var history: []
    property string status: "Ready"

    // ── backend helpers ───────────────────────────────────────────────────────
    function parseResult(raw) {
        if (raw === undefined || raw === null) return null
        var v = raw
        if (typeof v === "string") { try { v = JSON.parse(v) } catch (e) { return raw } }
        if (typeof v === "string") { try { v = JSON.parse(v) } catch (e) {} }
        return v
    }
    function call(method, args) { return parseResult(logos.callModule(backend, method, args || [])) }
    function callAsync(method, args, cb) {
        logos.callModuleAsync(backend, method, args || [], function (raw) { cb(parseResult(raw)) }, 30000)
    }

    // ── loaders ───────────────────────────────────────────────────────────────
    function loadChains() {
        var r = call("get_chains")
        if (r && r.ok) chains = r.chains
    }
    function loadAccounts() {
        var r = call("list_accounts")
        if (r && r.ok) {
            accounts = r.accounts
            if (accounts.length > 0 && selectedAccount === "") selectedAccount = accounts[0]
        }
    }
    function loadBalances() {
        if (selectedAccount === "") return
        var r = call("get_balances", [selectedAccount])
        if (r && r.ok) balances = r.balances
    }
    function loadHistory() {
        if (selectedAccount === "") return
        var r = call("get_history", [selectedAccount])
        if (r && r.ok) history = r.history
    }
    function refreshBalances() {
        if (selectedAccount === "") return
        status = "Refreshing balances…"
        callAsync("refresh_balances", [selectedAccount], function (ok) {
            status = "Balances updated"; loadBalances()
        })
    }

    function fmtAmount(wei, decimals) {
        // crude base-unit -> human display (no bigint); good enough for the UI
        var d = decimals || 18
        var s = wei.toString()
        while (s.length <= d) s = "0" + s
        var whole = s.slice(0, s.length - d)
        var frac = s.slice(s.length - d).replace(/0+$/, "")
        return frac.length ? whole + "." + frac.slice(0, 6) : whole
    }

    Component.onCompleted: {
        loadChains(); loadAccounts(); loadBalances(); loadHistory()
        logos.onModuleEvent(backend, "balances_updated")
        logos.onModuleEvent(backend, "tx_status_changed")
        logos.onModuleEvent(backend, "proxy_error")
    }

    Connections {
        target: logos
        function onModuleEventReceived(moduleName, eventName, data) {
            if (moduleName !== root.backend) return
            if (eventName === "balances_updated") root.loadBalances()
            else if (eventName === "tx_status_changed") root.loadHistory()
            else if (eventName === "proxy_error") root.status = "⚠ Proxy refused: " + data
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        // ── header: account + lock ──
        RowLayout {
            Layout.fillWidth: true
            ComboBox {
                id: acctBox
                Layout.fillWidth: true
                model: root.accounts
                onActivated: { root.selectedAccount = root.accounts[currentIndex]; root.unlocked = false; root.loadBalances(); root.loadHistory() }
            }
            Button {
                text: root.unlocked ? "Lock" : "Unlock"
                onClicked: {
                    if (root.unlocked) { root.call("lock", [root.selectedAccount]); root.unlocked = false }
                    else unlockDialog.open()
                }
            }
            Button { text: "New"; onClicked: createDialog.open() }
        }
        Label {
            Layout.fillWidth: true
            elide: Text.ElideMiddle
            text: root.selectedAccount === "" ? "No accounts — create one" : root.selectedAccount
            color: root.unlocked ? "#2e7d32" : "#777"
            font.family: "monospace"
        }

        // ── tabs ──
        TabBar {
            id: tabs
            Layout.fillWidth: true
            TabButton { text: "Balances" }
            TabButton { text: "Send" }
            TabButton { text: "Tokens" }
            TabButton { text: "History" }
            TabButton { text: "Settings" }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabs.currentIndex

            // ── Balances ──
            ColumnLayout {
                spacing: 6
                Button { text: "Refresh balances"; onClicked: root.refreshBalances() }
                ListView {
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 6
                    model: root.balances && root.balances.chains ? root.balances.chains : []
                    delegate: Frame {
                        width: ListView.view ? ListView.view.width : 0
                        ColumnLayout {
                            anchors.fill: parent
                            property var chainInfo: {
                                for (var i = 0; i < root.chains.length; i++)
                                    if (root.chains[i].chainId === modelData.chainId) return root.chains[i]
                                return { name: "Chain " + modelData.chainId, nativeSymbol: "" }
                            }
                            Label { text: chainInfo.name; font.bold: true }
                            Label { text: root.fmtAmount(modelData.native, 18) + " " + chainInfo.nativeSymbol }
                            Repeater {
                                model: modelData.tokens || []
                                Label {
                                    font.pixelSize: 12; color: "#555"
                                    text: modelData.balance + "  " + modelData.address
                                }
                            }
                        }
                    }
                }
            }

            // ── Send ──
            ColumnLayout {
                spacing: 6
                ComboBox {
                    id: sendChain; Layout.fillWidth: true
                    textRole: "name"; model: root.chains
                }
                CheckBox { id: isErc20; text: "ERC20 token" }
                TextField { id: tokenAddr; Layout.fillWidth: true; visible: isErc20.checked; placeholderText: "Token contract address" }
                TextField { id: toAddr; Layout.fillWidth: true; placeholderText: "Recipient address (0x…)" }
                TextField { id: amount; Layout.fillWidth: true; placeholderText: "Amount (base units / wei)" }
                Label { id: feePreview; text: ""; color: "#777"; font.pixelSize: 12 }
                RowLayout {
                    Button {
                        text: "Estimate"
                        onClicked: {
                            var p = root.buildSend()
                            var r = root.call("estimate_fee", [JSON.stringify(p)])
                            feePreview.text = (r && r.ok) ? ("≈ fee " + root.fmtAmount(r.feeWei, 18) + " (gas " + r.gasLimit + ")") : ("estimate failed")
                        }
                    }
                    Button {
                        text: "Send"
                        enabled: root.unlocked
                        onClicked: {
                            var p = root.buildSend()
                            var method = isErc20.checked ? "send_erc20" : "send_native"
                            root.status = "Sending…"
                            root.callAsync(method, [JSON.stringify(p)], function (r) {
                                root.status = (r && r.ok) ? ("Sent: " + r.hash) : ("Send failed: " + (r ? r.error : "?"))
                                root.loadHistory()
                            })
                        }
                    }
                }
                Item { Layout.fillHeight: true }
            }

            // ── Tokens ──
            ColumnLayout {
                spacing: 6
                ComboBox { id: tokChain; Layout.fillWidth: true; textRole: "name"; model: root.chains }
                Button {
                    text: "Load tokens"
                    onClicked: {
                        var cid = root.chains[tokChain.currentIndex].chainId
                        var r = root.call("get_tokens", [cid])
                        tokenList.model = (r && r.ok) ? r.tokens : []
                    }
                }
                ListView {
                    id: tokenList
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 4
                    delegate: Label { text: (modelData.symbol || "?") + " — " + (modelData.name || "") + "  " + modelData.address; font.pixelSize: 12 }
                }
                Button { text: "Add custom token…"; onClicked: addTokenDialog.open() }
            }

            // ── History ──
            ColumnLayout {
                Button { text: "Refresh"; onClicked: root.loadHistory() }
                ListView {
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 6
                    model: root.history
                    delegate: Frame {
                        width: ListView.view ? ListView.view.width : 0
                        ColumnLayout {
                            anchors.fill: parent
                            Label { text: modelData.kind.toUpperCase() + " · chain " + modelData.chainId + " · " + modelData.status
                                    color: modelData.status === "confirmed" ? "#2e7d32" : (modelData.status === "failed" ? "#c62828" : "#f9a825") }
                            Label { text: "→ " + modelData.to; font.pixelSize: 12; elide: Text.ElideMiddle }
                            Label { text: modelData.hash; font.pixelSize: 11; color: "#999"; font.family: "monospace"; elide: Text.ElideMiddle }
                        }
                    }
                }
            }

            // ── Settings (proxy / privacy) ──
            ColumnLayout {
                spacing: 6
                Label { text: "Privacy / proxy"; font.bold: true }
                TextField { id: proxyUrl; Layout.fillWidth: true; placeholderText: "socks5h://127.0.0.1:9050" }
                CheckBox { id: proxyRequired; text: "Require proxy (fail-closed — refuse if unavailable)" }
                Button {
                    text: "Apply proxy"
                    onClicked: {
                        var p = { proxy: proxyUrl.text.length ? proxyUrl.text : null, proxyRequired: proxyRequired.checked }
                        root.call("set_proxy_config", [JSON.stringify(p)])
                        root.status = "Proxy applied"
                    }
                }
                Item { Layout.fillHeight: true }
            }
        }

        Label { Layout.fillWidth: true; text: root.status; color: "#555"; elide: Text.ElideRight }
    }

    function buildSend() {
        var cid = root.chains[sendChain.currentIndex].chainId
        var p = { from: root.selectedAccount, to: toAddr.text, chainId: cid, amount: amount.text }
        if (isErc20.checked) p.tokenAddress = tokenAddr.text
        return p
    }

    // ── dialogs ──
    Dialog {
        id: unlockDialog; title: "Unlock account"; modal: true; anchors.centerIn: parent
        standardButtons: Dialog.Ok | Dialog.Cancel
        ColumnLayout { TextField { id: unlockPw; placeholderText: "Passphrase"; echoMode: TextInput.Password } }
        onAccepted: {
            var ok = root.call("unlock", [root.selectedAccount, unlockPw.text])
            root.unlocked = (ok === true); root.status = root.unlocked ? "Unlocked" : "Wrong passphrase"; unlockPw.text = ""
        }
    }

    Dialog {
        id: createDialog; title: "Create account"; modal: true; anchors.centerIn: parent
        standardButtons: Dialog.Ok | Dialog.Cancel
        ColumnLayout {
            TextField { id: newLabel; placeholderText: "Label" }
            TextField { id: newPw; placeholderText: "Passphrase"; echoMode: TextInput.Password }
        }
        onAccepted: {
            var r = root.call("create_account", [newPw.text, newLabel.text])
            if (r && r.ok) { root.status = "Created " + r.address; root.loadAccounts(); root.selectedAccount = r.address }
            else root.status = "Create failed"
            newPw.text = ""
        }
    }

    Dialog {
        id: addTokenDialog; title: "Add custom token"; modal: true; anchors.centerIn: parent
        standardButtons: Dialog.Ok | Dialog.Cancel
        ColumnLayout {
            TextField { id: ctChain; placeholderText: "chainId (e.g. 1)" }
            TextField { id: ctAddr; placeholderText: "Token address (0x…)" }
            TextField { id: ctSym; placeholderText: "Symbol" }
            TextField { id: ctDec; placeholderText: "Decimals (e.g. 18)" }
        }
        onAccepted: {
            var t = { chainId: parseInt(ctChain.text), address: ctAddr.text, name: ctSym.text, symbol: ctSym.text, decimals: parseInt(ctDec.text) }
            var ok = root.call("add_custom_token", [JSON.stringify(t)])
            root.status = (ok === true) ? "Token added" : "Add failed"
        }
    }
}
