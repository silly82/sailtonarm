#ifndef CREDENTIALS_H
#define CREDENTIALS_H

#include <QObject>
#include <QString>

#include <Secrets/deletesecretrequest.h>
#include <Secrets/plugininforequest.h>
#include <Secrets/secretmanager.h>
#include <Secrets/storedsecretrequest.h>
#include <Secrets/storesecretrequest.h>

// Serveradresse + Long-Lived Access Token des Music-Assistant-Servers,
// verschlüsselt über Sailfish Secrets abgelegt und QML als Kontext-Property
// "Credentials" zur Verfügung gestellt (siehe main()).
//
// Das liegt bewusst in C++ statt in QML: das Sailfish.Secrets-QML-Plugin kann
// keine der beiden hier nötigen Requests ausdrücken. StoredSecretRequest.identifier
// ist vom Typ Sailfish::Secrets::Secret::Identifier -- eine reine C++-Klasse, die
// das Plugin nie registriert (kein Q_OBJECT/Q_GADGET), QML scheitert mit
// "Cannot assign QJSValue to Sailfish::Secrets::Secret::Identifier"; und
// StoreSecretRequest.secretStorageType ist ein Enum ohne Q_ENUM, Zuweisung aus QML
// scheitert mit "Cannot assign int to an unregistered type". Beides auf echter
// Hardware verifiziert (harbour-hacontrol v0.50-3, im Journal nachlesbar). Die
// C++-API nimmt exakt dieselben Werte anstandslos.
//
// Übernommen aus harbour-hacontrol; geändert sind nur die Secret-Namen und die
// Bedeutung von baseUrl (dort HA-Instanz, hier MA-Server).
class Credentials : public QObject
{
    Q_OBJECT
    // Stammadresse des MA-Servers, z.B. "http://musicassistant.local:8095".
    Q_PROPERTY(QString baseUrl READ baseUrl NOTIFY baseUrlChanged)
    Q_PROPERTY(QString token READ token NOTIFY tokenChanged)
    // true, sobald der erste Ladeversuch durch ist (Erfolg oder "noch nichts
    // gespeichert") -- damit Settings leere Felder zeigt statt kurz
    // "nicht konfiguriert" aufblitzen zu lassen, solange der asynchrone
    // Secrets-Request noch läuft.
    Q_PROPERTY(bool loaded READ loaded NOTIFY loadedChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    // true, solange ein save() noch zum Daemon geschrieben wird, und ob das
    // zuletzt abgeschlossene save() tatsächlich erfolgreich war.
    Q_PROPERTY(bool saveBusy READ saveBusy NOTIFY saveBusyChanged)
    Q_PROPERTY(bool lastSaveOk READ lastSaveOk NOTIFY lastSaveOkChanged)

public:
    explicit Credentials(QObject *parent = Q_NULLPTR);

    QString baseUrl() const;
    QString token() const;
    bool loaded() const;
    QString lastError() const;
    bool saveBusy() const;
    bool lastSaveOk() const;

    // Setzt die Werte sofort im Speicher (die App verbindet sich also umgehend
    // neu) und schreibt sie asynchron in den Secrets-Daemon -- blockiert den
    // UI-Thread nie.
    Q_INVOKABLE void save(const QString &baseUrl, const QString &token);
    Q_INVOKABLE void reload();
    // Löscht beide Secrets und leert die Properties (Settings: "Zugangsdaten
    // löschen"). Absichtlich ohne Rückfrage hier -- die stellt die UI.
    Q_INVOKABLE void clear();

Q_SIGNALS:
    void baseUrlChanged();
    void tokenChanged();
    void loadedChanged();
    void lastErrorChanged();
    void saveBusyChanged();
    void lastSaveOkChanged();

private:
    // Welche Plugins ansprechbar sind, ist vorher nicht bekannt: der Daemon lehnt
    // Requests ab, die ein im Image nicht registriertes Plugin nennen (auf dem
    // Jolla Phone: "No such storage plugin exists:
    // org.sailfishos.secrets.plugin.encryptedstorage.sqlcipher", obwohl die .so
    // installiert ist), und ein leerer Verschlüsselungs-Plugin-Name wird mit
    // "No such encryption plugin exists: " quittiert. Also einmal den Daemon
    // fragen, bevor der erste Request rausgeht.
    void resolvePlugins();
    void choosePlugins(const QVector<Sailfish::Secrets::PluginInfo> &storage,
                       const QVector<Sailfish::Secrets::PluginInfo> &encryptedStorage,
                       const QVector<Sailfish::Secrets::PluginInfo> &encryption);
    static QString firstAvailable(const QVector<Sailfish::Secrets::PluginInfo> &plugins);

    void startLoading();
    void startTokenLoad();
    void storeOne(Sailfish::Secrets::StoreSecretRequest *request, const QString &name, const QString &value);
    // Erst löschen macht das Schreiben zu einem Upsert; ein blosses Überschreiben
    // quittiert der Daemon mit SecretAlreadyExistsError, und das Löschen eines
    // nicht vorhandenen Secrets liefert nur ein (ignoriertes) Fehlerergebnis.
    void deleteThenStore(Sailfish::Secrets::DeleteSecretRequest *request,
                         Sailfish::Secrets::StoreSecretRequest *storeRequest,
                         const QString &name);
    void setBaseUrl(const QString &baseUrl);
    void setToken(const QString &token);
    void setLoaded(bool loaded);
    void setLastError(const QString &lastError);
    void setSaveBusy(bool saveBusy);
    void setLastSaveOk(bool lastSaveOk);
    // Von beiden Store-Requests aufgerufen: ein "save" besteht aus zweien, der
    // Stapel ist also erst fertig (und lastSaveOk endgültig), wenn beide da sind.
    void finishStore(bool ok, const QString &what, const QString &error);

    Sailfish::Secrets::SecretManager m_manager;
    Sailfish::Secrets::PluginInfoRequest m_pluginInfo;

    Sailfish::Secrets::StoredSecretRequest m_baseUrlLoad;
    Sailfish::Secrets::StoredSecretRequest m_tokenLoad;
    Sailfish::Secrets::StoreSecretRequest m_baseUrlStore;
    Sailfish::Secrets::StoreSecretRequest m_tokenStore;
    Sailfish::Secrets::DeleteSecretRequest m_baseUrlDelete;
    Sailfish::Secrets::DeleteSecretRequest m_tokenDelete;

    QString m_baseUrl;
    QString m_token;
    QString m_lastError;
    bool m_loaded;
    int m_pendingStores;
    bool m_saveBusy;
    bool m_lastSaveOk;
    bool m_saveFailed;

    // Standalone-Device-Lock-Secrets: bleiben entsperrt, solange das Gerät
    // entsperrt ist (Einnutzer-Gerät), auf dem Datenträger vom Daemon
    // verschlüsselt.
    QString m_storagePluginName;
    QString m_encryptionPluginName;
    bool m_pluginsResolved;
};

#endif // CREDENTIALS_H
