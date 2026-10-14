#include "sendspinclient.h"

#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QStandardPaths>

namespace {

// Sentinel-PSK und seine psk_id sind veröffentlichte Konstanten
// (connection.md, "Pre-Shared Key").
const char SentinelLabel[] = "sendspin-sentinel-psk-v1";
const char PskIdLabel[] = "sendspin-psk-id-v1";
// Frist je erwarteter Handshake-Nachricht; die Spezifikation schlägt 30 s vor.
const int HandshakeTimeoutMs = 30000;

QByteArray compact(const QJsonObject &obj)
{
    return QJsonDocument(obj).toJson(QJsonDocument::Compact);
}

} // namespace

SendspinClient::SendspinClient(QObject *parent)
    : QObject(parent)
{
    connect(this, &SendspinClient::log, this, [this](const QString &line) { m_logLines.append(line); });
    m_timeout.setSingleShot(true);
    m_timeout.setInterval(HandshakeTimeoutMs);
    connect(&m_timeout, &QTimer::timeout, this, [this]() { fail(QStringLiteral("Zeitüberschreitung im Handshake")); });
    connect(&m_socket, &QWebSocket::connected, this, &SendspinClient::onConnected);
    connect(&m_socket, &QWebSocket::disconnected, this, &SendspinClient::onDisconnected);
    connect(&m_socket, &QWebSocket::textMessageReceived, this, &SendspinClient::onText);
    connect(&m_socket, &QWebSocket::binaryMessageReceived, this, &SendspinClient::onBinary);
}

void SendspinClient::open(const QUrl &url, const QByteArray &privateKey)
{
    if (m_state == Connecting || m_state == Handshake || m_state == Encrypted)
        return;
    m_privateKey = privateKey;
    m_noise.reset();
    m_serverName.clear();
    setState(Connecting);
    emit log(QStringLiteral("verbinde mit %1").arg(url.toString()));
    m_timeout.start();
    m_socket.open(url);
}

void SendspinClient::openForServer(const QString &maBaseUrl)
{
    m_logLines.clear();
    const QUrl ma(maBaseUrl);
    QUrl url;
    url.setScheme(QStringLiteral("ws"));
    url.setHost(ma.host());
    url.setPort(8927);
    url.setPath(QStringLiteral("/sendspin"));

    // Stufe 5a: der Schlüssel liegt als Datei (nur für den Besitzer lesbar)
    // im Datenverzeichnis der App. Mit dem Pairing (5b) kommt ein
    // langfristiger PSK dazu; dann ziehen beide nach Sailfish Secrets um.
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dir);
    QFile file(dir + QStringLiteral("/sendspin.key"));
    QByteArray key;
    if (file.open(QIODevice::ReadOnly))
        key = file.readAll();
    file.close();
    if (key.size() != 32) {
        key = NoiseSession::generatePrivateKey();
        if (!file.open(QIODevice::WriteOnly) || file.write(key) != key.size()) {
            fail(QStringLiteral("Schlüssel nicht speicherbar"));
            return;
        }
        file.setPermissions(QFile::ReadOwner | QFile::WriteOwner);
        emit log(QStringLiteral("neuen Schlüssel angelegt"));
    }
    open(url, key);
}

void SendspinClient::close(const QString &reason)
{
    if (m_state == Encrypted && m_noise) {
        QJsonObject goodbye;
        goodbye.insert(QStringLiteral("type"), QStringLiteral("client/goodbye"));
        QJsonObject payload;
        payload.insert(QStringLiteral("reason"), reason);
        goodbye.insert(QStringLiteral("payload"), payload);
        sendJson(goodbye);
        emit log(QStringLiteral("client/goodbye (%1)").arg(reason));
    }
    m_timeout.stop();
    m_socket.close();
    setState(Idle);
}

QByteArray SendspinClient::b64url(const QByteArray &data)
{
    return data.toBase64(QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals);
}

QByteArray SendspinClient::fromB64url(const QByteArray &text)
{
    return QByteArray::fromBase64(text, QByteArray::Base64UrlEncoding);
}

void SendspinClient::onConnected()
{
    const QByteArray pub = NoiseSession::publicKey(m_privateKey);
    if (pub.size() != 32) {
        fail(QStringLiteral("ungültiger eigener Schlüssel"));
        return;
    }
    QJsonObject payload;
    payload.insert(QStringLiteral("client_id"), QString::fromLatin1(b64url(pub)));
    payload.insert(QStringLiteral("version"), 1);
    payload.insert(QStringLiteral("suite"), NoiseSession::suiteName(NoiseSession::ChaChaPoly));
    QJsonObject init;
    init.insert(QStringLiteral("type"), QStringLiteral("client/init"));
    init.insert(QStringLiteral("payload"), payload);
    // Genau diese Bytes gehen in den Prolog, deshalb merken statt später neu
    // zu kodieren.
    m_clientInit = compact(init);
    m_socket.sendTextMessage(QString::fromUtf8(m_clientInit));
    setState(Handshake);
    emit log(QStringLiteral("client/init gesendet, client_id %1").arg(QString::fromLatin1(b64url(pub))));
}

void SendspinClient::onDisconnected()
{
    m_timeout.stop();
    if (m_state == Connecting || m_state == Handshake)
        fail(m_socket.closeReason().isEmpty()
             ? QStringLiteral("Server hat die Verbindung geschlossen")
             : m_socket.closeReason());
    else if (m_state == Encrypted)
        setState(Idle);
    emit log(QStringLiteral("getrennt (Code %1)").arg(int(m_socket.closeCode())));
}

void SendspinClient::onText(const QString &text)
{
    // Klartext gibt es nur während des Handshakes; danach ist er ein Fehler
    // (connection.md, "Failure Handling": still schliessen).
    if (m_state != Handshake) {
        fail(QStringLiteral("Klartext nach dem Handshake"));
        return;
    }
    const QByteArray raw = text.toUtf8();
    const QJsonObject msg = QJsonDocument::fromJson(raw).object();
    const QString type = msg.value(QStringLiteral("type")).toString();
    const QJsonObject payload = msg.value(QStringLiteral("payload")).toObject();
    emit log(QStringLiteral("<- %1").arg(type));

    if (type == QLatin1String("server/error")) {
        fail(QStringLiteral("server/error: %1").arg(payload.value(QStringLiteral("reason")).toString()));
    } else if (type == QLatin1String("server/init")) {
        if (m_noise || payload.value(QStringLiteral("version")).toInt() != 1) {
            fail(QStringLiteral("unerwartetes server/init"));
            return;
        }
        const QByteArray serverPub = fromB64url(payload.value(QStringLiteral("server_id")).toString().toLatin1());
        if (serverPub.size() != 32) {
            fail(QStringLiteral("ungültige server_id"));
            return;
        }
        m_noise.reset(new NoiseSession(NoiseSession::ChaChaPoly, m_privateKey, serverPub,
                                       m_clientInit + raw));
        m_timeout.start();
    } else if (type == QLatin1String("noise/handshake")) {
        if (!m_noise) {
            fail(QStringLiteral("Handshake vor server/init"));
            return;
        }
        QByteArray inner;
        if (!m_noise->readMessage1(fromB64url(payload.value(QStringLiteral("data")).toString().toLatin1()), &inner)) {
            fail(QStringLiteral("Noise-Nachricht 1 ungültig"));
            return;
        }
        const QJsonObject psk = QJsonDocument::fromJson(inner).object();
        const QString pskId = psk.value(QStringLiteral("psk_id")).toString();
        const QString category = psk.value(QStringLiteral("psk_category")).toString();
        // MA 2.10.4 schickt nur psk_id ohne psk_category (ältere Fassung der
        // Spezifikation, gemessen 2026-10-14); fehlt sie, gilt die psk_id allein.
        if (psk.contains(QStringLiteral("psk_category")) && category != QLatin1String("lt")
                && category != QLatin1String("pr") && category != QLatin1String("sn")) {
            fail(QStringLiteral("ungültige psk_category"));
            return;
        }
        // Noch gibt es kein Pairing (Stufe 5b), also nur den Sentinel. Passt
        // die psk_id nicht, ist das laut Spezifikation der Sentinel-Rückfall,
        // kein Fehler.
        const QByteArray sentinel = NoiseSession::sha256(SentinelLabel);
        const QString sentinelId = QString::fromLatin1(b64url(NoiseSession::sha256(QByteArray(PskIdLabel) + sentinel)));
        emit log(QStringLiteral("PSK verlangt: %1 (%2)").arg(category.isEmpty() ? QStringLiteral("ohne Kategorie") : category,
                 pskId == sentinelId ? QStringLiteral("Sentinel") : QStringLiteral("unbekannt, Sentinel-Rückfall")));
        const QByteArray m2 = m_noise->writeMessage2(sentinel, "{}");
        QJsonObject out;
        out.insert(QStringLiteral("type"), QStringLiteral("noise/handshake"));
        QJsonObject data;
        data.insert(QStringLiteral("data"), QString::fromLatin1(b64url(m2)));
        out.insert(QStringLiteral("payload"), data);
        m_socket.sendTextMessage(QString::fromUtf8(compact(out)));
        setState(Encrypted);
        m_timeout.start();
        emit log(QStringLiteral("Noise-Nachricht 2 gesendet, Transportmodus"));
    }
}

void SendspinClient::onBinary(const QByteArray &data)
{
    if (m_state != Encrypted || !m_noise) {
        fail(QStringLiteral("Binärnachricht vor dem Handshake"));
        return;
    }
    QByteArray plain;
    if (!m_noise->decrypt(data, &plain) || plain.isEmpty()) {
        fail(QStringLiteral("Entschlüsselung fehlgeschlagen"));
        return;
    }
    // Typ 0: JSON. Fragmente (1) und Rollen-Daten kommen ab Stufe 5c.
    if (plain.at(0) != 0) {
        emit log(QStringLiteral("<- Binärtyp %1, %2 Bytes").arg(int(quint8(plain.at(0)))).arg(plain.size()));
        return;
    }
    const QJsonObject msg = QJsonDocument::fromJson(plain.mid(1)).object();
    const QString type = msg.value(QStringLiteral("type")).toString();
    emit log(QStringLiteral("<- %1 (verschlüsselt): %2").arg(type, QString::fromUtf8(plain.mid(1))));
    if (type == QLatin1String("server/hello")) {
        m_timeout.stop();
        m_serverName = msg.value(QStringLiteral("payload")).toObject().value(QStringLiteral("name")).toString();
        emit serverHelloReceived(msg.value(QStringLiteral("payload")).toObject());
    }
    emit message(msg);
}

void SendspinClient::setState(State state)
{
    if (m_state == state)
        return;
    m_state = state;
    emit stateChanged();
}

void SendspinClient::fail(const QString &why)
{
    m_timeout.stop();
    m_lastError = why;
    emit lastErrorChanged();
    emit log(QStringLiteral("Fehler: %1").arg(why));
    setState(Failed);
    m_socket.abort();
}

void SendspinClient::sendJson(const QJsonObject &obj)
{
    m_socket.sendBinaryMessage(m_noise->encrypt(QByteArray(1, '\0') + compact(obj)));
}
