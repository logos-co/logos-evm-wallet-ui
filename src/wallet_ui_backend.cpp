#include "wallet_ui_backend.h"

// Generated umbrella: modules() → typed callers + typed event accessors for the
// modules in metadata.json#dependencies (here: wallet_backend_module).
#include "logos_sdk.h"

void WalletUiBackend::onContextReady()
{
    // Initial state from the backend.
    setChainsJson(modules().wallet_backend_module.get_chains());
    refreshAccounts();

    // Push backend events into PROPs so the QML view updates live.
    modules().wallet_backend_module.onBalances_updated([this](QString address) {
        setBalancesJson(modules().wallet_backend_module.get_balances(address));
    });
    modules().wallet_backend_module.onTx_status_changed([this](QString) {
        if (!selectedAccount().isEmpty()) {
            setHistoryJson(modules().wallet_backend_module.get_history(selectedAccount()));
        }
    });

    setStatusText(QStringLiteral("Ready"));
}

// ── Config / privacy ─────────────────────────────────────────────────────────

bool WalletUiBackend::setProxyConfig(QString proxyJson)
{
    bool ok = modules().wallet_backend_module.set_proxy_config(proxyJson);
    setProxyStatus(ok ? QStringLiteral("Proxy applied") : QStringLiteral("Proxy failed"));
    setStatusText(ok ? QStringLiteral("Proxy applied") : QStringLiteral("Proxy failed"));
    return ok;
}

bool WalletUiBackend::setChains(QString chainsJson)
{
    bool ok = modules().wallet_backend_module.set_chains(chainsJson);
    if (ok) {
        setChainsJson(modules().wallet_backend_module.get_chains());
    }
    setStatusText(ok ? QStringLiteral("Chains updated") : QStringLiteral("Set chains failed"));
    return ok;
}

QString WalletUiBackend::testEndpoint(int chainId)
{
    return modules().wallet_backend_module.test_endpoint(chainId);
}

// ── Accounts ─────────────────────────────────────────────────────────────────

QString WalletUiBackend::createAccount(QString passphrase, QString label)
{
    QString r = modules().wallet_backend_module.create_account(passphrase, label);
    refreshAccounts();
    setStatusText(QStringLiteral("Account created"));
    return r;
}

QString WalletUiBackend::importMnemonic(QString phraseJson, QString label)
{
    QString r = modules().wallet_backend_module.import_mnemonic(phraseJson, label);
    refreshAccounts();
    setStatusText(QStringLiteral("Account imported"));
    return r;
}

void WalletUiBackend::refreshAccounts()
{
    setAccountsJson(modules().wallet_backend_module.list_accounts());
}

bool WalletUiBackend::unlock(QString address, QString passphrase)
{
    bool ok = modules().wallet_backend_module.unlock(address, passphrase);
    setAccountUnlocked(ok);
    setStatusText(ok ? QStringLiteral("Unlocked") : QStringLiteral("Wrong passphrase"));
    return ok;
}

bool WalletUiBackend::lock(QString address)
{
    bool ok = modules().wallet_backend_module.lock(address);
    setAccountUnlocked(false);
    setStatusText(QStringLiteral("Locked"));
    return ok;
}

// ── Balances + tokens ────────────────────────────────────────────────────────

void WalletUiBackend::refreshBalances(QString address)
{
    setStatusText(QStringLiteral("Refreshing balances…"));
    // Kicks off the multi-chain fetch (emits balances_updated when done) and
    // returns the last cached aggregate immediately.
    modules().wallet_backend_module.refresh_balances(address);
    setBalancesJson(modules().wallet_backend_module.get_balances(address));
}

void WalletUiBackend::loadTokens(int chainId)
{
    setTokensJson(modules().wallet_backend_module.get_tokens(chainId));
}

bool WalletUiBackend::addCustomToken(QString tokenJson)
{
    bool ok = modules().wallet_backend_module.add_custom_token(tokenJson);
    setStatusText(ok ? QStringLiteral("Token added") : QStringLiteral("Add token failed"));
    return ok;
}

// ── Send ─────────────────────────────────────────────────────────────────────

QString WalletUiBackend::estimateFee(QString sendJson)
{
    return modules().wallet_backend_module.estimate_fee(sendJson);
}

QString WalletUiBackend::sendNative(QString sendJson)
{
    setStatusText(QStringLiteral("Sending…"));
    QString r = modules().wallet_backend_module.send_native(sendJson);
    setStatusText(QStringLiteral("Native transfer submitted"));
    return r;
}

QString WalletUiBackend::sendErc20(QString sendJson)
{
    setStatusText(QStringLiteral("Sending…"));
    QString r = modules().wallet_backend_module.send_erc20(sendJson);
    setStatusText(QStringLiteral("ERC20 transfer submitted"));
    return r;
}

// ── History ──────────────────────────────────────────────────────────────────

void WalletUiBackend::refreshHistory(QString address)
{
    setHistoryJson(modules().wallet_backend_module.get_history(address));
}
