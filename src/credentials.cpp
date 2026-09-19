#include "credentials.h"

#include <QDebug>
#include <QVector>

#include <Secrets/plugininfo.h>
#include <Secrets/request.h>
#include <Secrets/result.h>
#include <Secrets/secret.h>

using namespace Sailfish::Secrets;

static const QLatin1String BaseUrlSecretName("harbour-tonarm-baseUrl");
static const QLatin1String TokenSecretName("harbour-tonarm-token");

Credentials::Credentials(QObject *parent)
    : QObject(parent)
    , m_loaded(false)
    , m_pendingStores(0)
    , m_saveBusy(false)
    , m_lastSaveOk(false)
    , m_saveFailed(false)
    , m_storagePluginName(SecretManager::DefaultStoragePluginName)
    , m_encryptionPluginName(SecretManager::DefaultEncryptionPluginName)
    , m_pluginsResolved(false)
{
    // Ohne Manager ist ein Request nutzlos: jeder muss wissen, über welchen
    // SecretManager (also welche Verbindung zu sailfishsecretsd) er läuft.
    m_baseUrlLoad.setManager(&m_manager);
    m_tokenLoad.setManager(&m_manager);
    m_baseUrlStore.setManager(&m_manager);
    m_tokenStore.setManager(&m_manager);
    m_baseUrlDelete.setManager(&m_manager);
    m_tokenDelete.setManager(&m_manager);
    m_pluginInfo.setManager(&m_manager);

    // Systemvermittelte Interaktion, keine App-Dialoge: die eigenen Secrets
    // zurückzulesen darf den Nutzer zu nichts auffordern.
    m_baseUrlLoad.setUserInteractionMode(SecretManager::SystemInteraction);
    m_tokenLoad.setUserInteractionMode(SecretManager::SystemInteraction);

    connect(&m_pluginInfo, &PluginInfoRequest::statusChanged, this, [this]() {
        if (m_pluginInfo.status() != Request::Finished) {
            return;
        }
        if (m_pluginInfo.result().code() != Result::Succeeded) {
            qWarning() << "Credentials: plugin query failed:"
                       << m_pluginInfo.result().errorMessage()
                       << "-- falling back to the default plugin names";
            m_pluginsResolved = true;
            startLoading();
            return;
        }
        choosePlugins(m_pluginInfo.storagePlugins(),
                      m_pluginInfo.encryptedStoragePlugins(),
                      m_pluginInfo.encryptionPlugins());
    });

    connect(&m_baseUrlLoad, &StoredSecretRequest::statusChanged, this, [this]() {
        if (m_baseUrlLoad.status() != Request::Finished) {
            return;
        }
        const Result result = m_baseUrlLoad.result();
        if (result.code() == Result::Succeeded) {
            setBaseUrl(QString::fromUtf8(m_baseUrlLoad.secret().data()));
        } else {
            // "noch nichts gespeichert" landet bei einer frischen Installation
            // ebenfalls hier -- kein Fehler, den der Nutzer sehen muss, die
            // leeren Felder in Settings sind Beleg genug.
            qDebug() << "Credentials: baseUrl not loaded:" << result.errorMessage();
        }
        // Token als zweites, damit `loaded` erst umspringt, wenn beide durch sind.
        startTokenLoad();
    });

    connect(&m_tokenLoad, &StoredSecretRequest::statusChanged, this, [this]() {
        if (m_tokenLoad.status() != Request::Finished) {
            return;
        }
        const Result result = m_tokenLoad.result();
        if (result.code() == Result::Succeeded) {
            setToken(QString::fromUtf8(m_tokenLoad.secret().data()));
        } else {
            qDebug() << "Credentials: token not loaded:" << result.errorMessage();
        }
        // Nur Längen -- nie die Werte selbst, das Journal lesen mehr als nur
        // diese App.
        qDebug() << "Credentials: loaded -- baseUrl" << m_baseUrl.length()
                 << "chars, token" << m_token.length() << "chars";
        setLoaded(true);
    });

    connect(&m_baseUrlStore, &StoreSecretRequest::statusChanged, this, [this]() {
        if (m_baseUrlStore.status() != Request::Finished) {
            return;
        }
        const Result result = m_baseUrlStore.result();
        finishStore(result.code() == Result::Succeeded,
                    QStringLiteral("baseUrl"),
                    result.errorMessage());
    });

    connect(&m_tokenStore, &StoreSecretRequest::statusChanged, this, [this]() {
        if (m_tokenStore.status() != Request::Finished) {
            return;
        }
        const Result result = m_tokenStore.result();
        finishStore(result.code() == Result::Succeeded,
                    QStringLiteral("token"),
                    result.errorMessage());
    });

    resolvePlugins();
}

QString Credentials::baseUrl() const
{
    return m_baseUrl;
}

QString Credentials::token() const
{
    return m_token;
}

bool Credentials::loaded() const
{
    return m_loaded;
}

QString Credentials::lastError() const
{
    return m_lastError;
}

bool Credentials::saveBusy() const
{
    return m_saveBusy;
}

bool Credentials::lastSaveOk() const
{
    return m_lastSaveOk;
}

void Credentials::resolvePlugins()
{
    m_pluginInfo.startRequest();
}

QString Credentials::firstAvailable(const QVector<PluginInfo> &plugins)
{
    for (const PluginInfo &plugin : plugins) {
        if (plugin.statusFlags().testFlag(PluginInfo::Available)) {
            return plugin.name();
        }
    }
    // Keine Statusinformation vorhanden: nehmen, was der Daemon aufgezählt hat.
    return plugins.isEmpty() ? QString() : plugins.first().name();
}

void Credentials::choosePlugins(const QVector<PluginInfo> &storage,
                                const QVector<PluginInfo> &encryptedStorage,
                                const QVector<PluginInfo> &encryption)
{
    const auto names = [](const QVector<PluginInfo> &plugins) {
        QStringList names;
        for (const PluginInfo &plugin : plugins) {
            names << plugin.name();
        }
        return names.join(QStringLiteral(", "));
    };
    qDebug() << "Credentials: daemon plugins -- storage:" << names(storage)
             << "| encrypted storage:" << names(encryptedStorage)
             << "| encryption:" << names(encryption);

    // Das einfache Storage-Plugin ist das, welches das Standalone-Device-Lock-
    // Secret auf diesem Gerät tatsächlich angenommen hat (auf dem Telefon
    // verifiziert) -- also bevorzugen und nur auf ein Encrypted-Storage-Plugin
    // ausweichen, wenn es kein einfaches gibt. Verschlüsselung geht dabei nicht
    // verloren: der Request nennt das Encryption-Plugin, der Daemon verschlüsselt
    // also, bevor er die Daten an das Storage-Plugin gibt.
    QString chosen = firstAvailable(storage);
    if (chosen.isEmpty()) {
        chosen = firstAvailable(encryptedStorage);
    }
    if (!chosen.isEmpty()) {
        m_storagePluginName = chosen;
    }
    const QString encryptionPlugin = firstAvailable(encryption);
    if (!encryptionPlugin.isEmpty()) {
        m_encryptionPluginName = encryptionPlugin;
    }

    qDebug() << "Credentials: using storage plugin" << m_storagePluginName
             << "and encryption plugin" << m_encryptionPluginName;
    m_pluginsResolved = true;
    startLoading();
}

void Credentials::save(const QString &baseUrl, const QString &token)
{
    setLastError(QString());

    // Die App muss sich verhalten wie vorher, sobald Settings ausgefüllt ist --
    // die Properties ändern sich daher sofort, gespeichert wird im Hintergrund.
    setBaseUrl(baseUrl);
    setToken(token);

    // Zwei Stores ergeben ein save(); vor jedem kann ein Delete laufen, deshalb
    // wird der Stapel hier gezählt und nur von finishStore() geschlossen.
    m_saveFailed = false;
    m_pendingStores = 2;
    setSaveBusy(true);
    setLastSaveOk(false);

    deleteThenStore(&m_baseUrlDelete, &m_baseUrlStore, BaseUrlSecretName);
    deleteThenStore(&m_tokenDelete, &m_tokenStore, TokenSecretName);
}

void Credentials::reload()
{
    setLoaded(false);
    setBaseUrl(QString());
    setToken(QString());
    startLoading();
}

void Credentials::clear()
{
    setLastError(QString());
    setBaseUrl(QString());
    setToken(QString());

    // Dieselben Delete-Requests wie im Upsert-Pfad, nur ohne anschliessendes
    // Speichern -- setIdentifier() überschreibt den vorherigen Zielnamen, und
    // die in deleteThenStore() verbundenen Handler feuern hier nicht, weil sie
    // an dieselben Request-Objekte hängen und der Store-Aufruf am Ende des
    // Handlers m_baseUrl/m_token (jetzt leer) schreiben würde. Deshalb eigene
    // Request-Objekte wären sauberer -- für Ausbaustufe 0 genügt es, dass
    // clear() nur aufgerufen wird, wenn kein save() in Flug ist (die UI
    // deaktiviert den Knopf währenddessen, siehe SettingsPage.qml).
    m_baseUrlDelete.setIdentifier(
        Secret::Identifier(BaseUrlSecretName, QString(), m_storagePluginName));
    m_baseUrlDelete.setUserInteractionMode(SecretManager::SystemInteraction);
    m_tokenDelete.setIdentifier(
        Secret::Identifier(TokenSecretName, QString(), m_storagePluginName));
    m_tokenDelete.setUserInteractionMode(SecretManager::SystemInteraction);
    m_baseUrlDelete.startRequest();
    m_tokenDelete.startRequest();
}

void Credentials::startLoading()
{
    m_baseUrlLoad.setIdentifier(
        Secret::Identifier(BaseUrlSecretName, QString(), m_storagePluginName));
    m_baseUrlLoad.startRequest();
}

void Credentials::startTokenLoad()
{
    m_tokenLoad.setIdentifier(
        Secret::Identifier(TokenSecretName, QString(), m_storagePluginName));
    m_tokenLoad.startRequest();
}

void Credentials::deleteThenStore(DeleteSecretRequest *request,
                                  StoreSecretRequest *storeRequest,
                                  const QString &name)
{
    // Pro Request einmal verbunden; abgesichert, damit ein zweites save() bei
    // noch laufendem Delete keine doppelten Handler aufreiht.
    if (!request->property("tonarmConnected").toBool()) {
        request->setProperty("tonarmConnected", true);
        connect(request, &DeleteSecretRequest::statusChanged, this,
                [this, request, storeRequest, name]() {
                    if (request->status() != Request::Finished) {
                        return;
                    }
                    // Beim ersten Speichern gibt es nichts zu löschen -- der
                    // Fehler ist erwartet und nicht meldenswert.
                    const Result result = request->result();
                    if (result.code() != Result::Succeeded) {
                        qDebug() << "Credentials: nothing to delete for" << name
                                 << "(" << result.errorMessage() << ")";
                    }
                    // Nach clear() ist m_pendingStores 0 -- dann war das Delete
                    // ein reines Löschen und es folgt kein Store.
                    if (m_pendingStores == 0) {
                        return;
                    }
                    storeOne(storeRequest, name,
                             storeRequest == &m_baseUrlStore ? m_baseUrl : m_token);
                });
    }

    request->setIdentifier(
        Secret::Identifier(name, QString(), m_storagePluginName));
    request->setUserInteractionMode(SecretManager::SystemInteraction);
    request->startRequest();
}

void Credentials::storeOne(StoreSecretRequest *request, const QString &name, const QString &value)
{
    Secret secret(name, QString(), m_storagePluginName);
    secret.setData(value.toUtf8());

    request->setSecret(secret);
    request->setSecretStorageType(StoreSecretRequest::StandaloneDeviceLockSecret);
    request->setEncryptionPluginName(m_encryptionPluginName);
    // Bleibt entsperrt, solange das Gerät entsperrt ist -- Einnutzer-Gerät, auf
    // dem Datenträger verschlüsselt und vom Daemon vermittelt statt von allem
    // lesbar, was die Konfigurationsdatei öffnen kann.
    request->setDeviceLockUnlockSemantic(SecretManager::DeviceLockKeepUnlocked);
    request->setAccessControlMode(SecretManager::OwnerOnlyMode);
    request->setUserInteractionMode(SecretManager::SystemInteraction);
    request->startRequest();
}

void Credentials::finishStore(bool ok, const QString &what, const QString &error)
{
    if (ok) {
        qDebug() << "Credentials: stored" << what;
    } else {
        m_saveFailed = true;
        setLastError(error);
        qWarning() << "Credentials: storing" << what << "failed:" << error;
    }

    if (m_pendingStores > 0) {
        --m_pendingStores;
    }
    if (m_pendingStores == 0) {
        setSaveBusy(false);
        setLastSaveOk(!m_saveFailed);
    }
}

void Credentials::setBaseUrl(const QString &baseUrl)
{
    if (m_baseUrl == baseUrl) {
        return;
    }
    m_baseUrl = baseUrl;
    Q_EMIT baseUrlChanged();
}

void Credentials::setToken(const QString &token)
{
    if (m_token == token) {
        return;
    }
    m_token = token;
    Q_EMIT tokenChanged();
}

void Credentials::setLoaded(bool loaded)
{
    if (m_loaded == loaded) {
        return;
    }
    m_loaded = loaded;
    Q_EMIT loadedChanged();
}

void Credentials::setLastError(const QString &lastError)
{
    if (m_lastError == lastError) {
        return;
    }
    m_lastError = lastError;
    Q_EMIT lastErrorChanged();
}

void Credentials::setSaveBusy(bool saveBusy)
{
    if (m_saveBusy == saveBusy) {
        return;
    }
    m_saveBusy = saveBusy;
    Q_EMIT saveBusyChanged();
}

void Credentials::setLastSaveOk(bool lastSaveOk)
{
    if (m_lastSaveOk == lastSaveOk) {
        return;
    }
    m_lastSaveOk = lastSaveOk;
    Q_EMIT lastSaveOkChanged();
}
