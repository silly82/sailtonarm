#ifndef SENDSPINCLIENT_H
#define SENDSPINCLIENT_H

#include <QJsonObject>
#include <QObject>
#include <QScopedPointer>
#include <QStringList>
#include <QTimer>
#include <QUrl>
#include <QWebSocket>

#include "noisesession.h"

// Sendspin-Verbindung vom Telefon zum Server (Client-initiiert, connection.md).
// Stufe 5a: Init, Noise-Handshake mit dem Sentinel-PSK, server/hello lesen.
// Registrierung: client/hello mit dem gewählten Namen und der Rolle player@v1,
// server/activate auswerten, client/state melden. Noch ohne Ton (Stufe 5c),
// deshalb meldet sich der Player als nicht verfügbar, und Audio-Chunks werden
// nur gezählt und verworfen.
class SendspinClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(State state READ state NOTIFY stateChanged)
    Q_PROPERTY(QString serverName READ serverName NOTIFY serverHelloReceived)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    // Alles, was log() gemeldet hat, für die Testseite in der App.
    Q_PROPERTY(QString logText READ logText NOTIFY log)
    // Name, unter dem das Telefon in Music Assistant als Player erscheint.
    // Leer heisst: defaultPlayerName.
    Q_PROPERTY(QString playerName READ playerName WRITE setPlayerName NOTIFY playerNameChanged)
    Q_PROPERTY(QString defaultPlayerName READ defaultPlayerName CONSTANT)
    // Vom Server mit server/activate freigegebene Rollen, z. B. "player@v1".
    Q_PROPERTY(QStringList activeRoles READ activeRoles NOTIFY activated)

public:
    enum State { Idle, Connecting, Handshake, Encrypted, Failed };
    Q_ENUM(State)

    explicit SendspinClient(QObject *parent = Q_NULLPTR);

    State state() const { return m_state; }
    QString serverName() const { return m_serverName; }
    QString lastError() const { return m_lastError; }
    QString logText() const { return m_logLines.join(QLatin1Char('\n')); }
    QString playerName() const { return m_playerName; }
    void setPlayerName(const QString &name);
    QString effectivePlayerName() const;
    static QString defaultPlayerName();
    QStringList activeRoles() const { return m_activeRoles; }

    // url: ws://<server>:8927/sendspin; privateKey: statischer X25519-Schlüssel
    // des Telefons (32 Bytes), er ist zugleich seine Kennung beim Server.
    Q_INVOKABLE void open(const QUrl &url, const QByteArray &privateKey);
    // Für die App: Adresse aus der Music-Assistant-Adresse ableiten (gleicher
    // Host, Port 8927) und den eigenen Schlüssel aus dem Datenverzeichnis der
    // App laden bzw. beim ersten Mal anlegen.
    Q_INVOKABLE void openForServer(const QString &maBaseUrl);
    // Sendet client/goodbye (falls schon verschlüsselt) und schliesst.
    Q_INVOKABLE void close(const QString &reason = QStringLiteral("user_request"));

    static QByteArray b64url(const QByteArray &data);
    static QByteArray fromB64url(const QByteArray &text);

signals:
    void stateChanged();
    void lastErrorChanged();
    void serverHelloReceived(const QJsonObject &payload);
    void playerNameChanged();
    void activated();
    void message(const QJsonObject &message);
    void log(const QString &line);

private slots:
    void onConnected();
    void onDisconnected();
    void onText(const QString &text);
    void onBinary(const QByteArray &data);

private:
    void setState(State state);
    void fail(const QString &why);
    void sendJson(const QJsonObject &obj);
    void sendHello();
    void sendState();
    void handleMessage(const QJsonObject &msg);

    QWebSocket m_socket;
    QTimer m_timeout;
    QByteArray m_privateKey;
    QByteArray m_clientInit;
    QScopedPointer<NoiseSession> m_noise;
    State m_state = Idle;
    QString m_serverName;
    QString m_lastError;
    QStringList m_logLines;
    QString m_playerName;
    QStringList m_activeRoles;
    // Verworfene Audio-Chunks seit dem letzten stream/start (bis Stufe 5c).
    int m_droppedChunks = 0;
};

#endif // SENDSPINCLIENT_H
