#ifndef SENDSPINCLIENT_H
#define SENDSPINCLIENT_H

#include <QJsonObject>
#include <QObject>
#include <QScopedPointer>
#include <QStringList>
#include <QTimer>
#include <QUrl>
#include <QWebSocket>

#include "audiooutput.h"
#include "noisesession.h"
#include "timefilter.h"

// Sendspin-Verbindung vom Telefon zum Server (Client-initiiert, connection.md).
// Stufe 5a: Init, Noise-Handshake mit dem Sentinel-PSK, server/hello lesen.
// Registrierung: client/hello mit dem gewählten Namen und der Rolle player@v1,
// server/activate auswerten, client/state melden.
// Stufe 5c: Uhrabgleich (client/time, TimeFilter), PCM-Chunks zeitgenau über
// AudioOutput ausgeben, Lautstärke und Stummschaltung vom Server annehmen.
// Verfügbar meldet sich der Player nur mit playbackEnabled und erst, wenn die
// Uhr abgeglichen ist; vorher schickt der Server keinen Ton.
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
    // Darf der Server Ton schicken? Aus heisst: angemeldet, aber nicht verfügbar.
    Q_PROPERTY(bool playbackEnabled READ playbackEnabled WRITE setPlaybackEnabled NOTIFY playbackChanged)
    Q_PROPERTY(int volume READ volume WRITE setVolume NOTIFY playbackChanged)
    Q_PROPERTY(bool muted READ muted WRITE setMuted NOTIFY playbackChanged)
    Q_PROPERTY(bool available READ available NOTIFY playbackChanged)
    Q_PROPERTY(bool streaming READ streaming NOTIFY playbackChanged)
    // Uhrabgleich und Ausgabe in einer Zeile, für die Testseite.
    Q_PROPERTY(QString syncText READ syncText NOTIFY syncTextChanged)

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
    bool playbackEnabled() const { return m_playbackEnabled; }
    void setPlaybackEnabled(bool enabled);
    int volume() const { return m_volume; }
    void setVolume(int volume);
    bool muted() const { return m_muted; }
    void setMuted(bool muted);
    bool available() const { return m_sentAvailable; }
    bool streaming() const { return m_streamActive; }
    QString syncText() const { return m_syncText; }

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
    void playbackChanged();
    void syncTextChanged();
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
    void handleBinary(quint8 type, const QByteArray &data, qint64 arrivalUs);
    void sendTime();
    void handleServerTime(const QJsonObject &payload, qint64 arrivalUs);
    void startStream(const QJsonObject &player);
    void endStream();
    void updateAvailability();
    void applyGain();
    void updateSyncText();
    bool playerActive() const;

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
    // Verworfene Audio-Chunks seit dem letzten stream/start.
    int m_droppedChunks = 0;
    int m_playedChunks = 0;

    // MA 2.10.4 (aiosendspin 9.1.1) spricht eine ältere Fassung: keine
    // psk_category, Audio-Kopf 9 statt 13 Bytes (ohne send_ahead).
    bool m_legacyWire = false;
    TimeFilter m_filter;
    QTimer m_timeSync;
    QTimer m_statsTimer;
    AudioOutput m_audio;
    bool m_playbackEnabled = false;
    bool m_sentAvailable = false;
    bool m_stateSent = false;
    bool m_streamActive = false;
    int m_volume = 100;
    bool m_muted = false;
    QString m_syncText;
    // Fragmente (messaging.md, "Fragmentation").
    bool m_fragmentActive = false;
    quint8 m_fragmentType = 0;
    QByteArray m_fragment;
};

#endif // SENDSPINCLIENT_H
