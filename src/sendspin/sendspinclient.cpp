#include "sendspinclient.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSettings>
#include <QStandardPaths>

namespace {

// Sentinel-PSK und seine psk_id sind veröffentlichte Konstanten
// (connection.md, "Pre-Shared Key").
const char SentinelLabel[] = "sendspin-sentinel-psk-v1";
const char PskIdLabel[] = "sendspin-psk-id-v1";
// Frist je erwarteter Handshake-Nachricht; die Spezifikation schlägt 30 s vor.
const int HandshakeTimeoutMs = 30000;
// Grenze für ausstehende Audio-Chunks (player@v1, buffer_capacity). Solange
// noch nichts abgespielt wird (bis Stufe 5c), nur ein vernünftiger Wert.
const int BufferCapacity = 1024 * 1024;
const char PlayerRole[] = "player@v1";

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
    m_activeRoles.clear();
    m_droppedChunks = 0;
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

void SendspinClient::setPlayerName(const QString &name)
{
    const QString trimmed = name.trimmed();
    if (trimmed == m_playerName)
        return;
    m_playerName = trimmed;
    emit playerNameChanged();
}

QString SendspinClient::effectivePlayerName() const
{
    return m_playerName.isEmpty() ? defaultPlayerName() : m_playerName;
}

QString SendspinClient::defaultPlayerName()
{
    // Gerätename aus /etc/hw-release, z. B. NAME="Jolla Jolla Phone"; das
    // doppelte Herstellerwort fällt weg.
    QSettings hw(QStringLiteral("/etc/hw-release"), QSettings::IniFormat);
    QStringList words = hw.value(QStringLiteral("NAME")).toString().split(QLatin1Char(' '), QString::SkipEmptyParts);
    if (words.size() > 1 && words.at(0) == words.at(1))
        words.removeFirst();
    return words.isEmpty() ? QStringLiteral("Sailfish OS") : words.join(QLatin1Char(' '));
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
    if (!m_activeRoles.isEmpty()) {
        m_activeRoles.clear();
        emit activated();
    }
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
    if (!m_activeRoles.isEmpty()) {
        m_activeRoles.clear();
        emit activated();
    }
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
    // Typ 0: JSON. Alles andere sind Rollen-Daten (Audio-Chunks usw.) oder
    // Fragmente; bis Stufe 5c nur zählen und verwerfen, nicht abspielen.
    if (plain.at(0) != 0) {
        if (m_droppedChunks++ == 0)
            emit log(QStringLiteral("<- Binärtyp %1, wird verworfen (noch kein Ton)").arg(int(quint8(plain.at(0)))));
        return;
    }
    const QJsonObject msg = QJsonDocument::fromJson(plain.mid(1)).object();
    emit log(QStringLiteral("<- %1 (verschlüsselt): %2").arg(msg.value(QStringLiteral("type")).toString(),
                                                            QString::fromUtf8(plain.mid(1))));
    handleMessage(msg);
    emit message(msg);
}

void SendspinClient::handleMessage(const QJsonObject &msg)
{
    const QString type = msg.value(QStringLiteral("type")).toString();
    const QJsonObject payload = msg.value(QStringLiteral("payload")).toObject();
    if (type == QLatin1String("server/hello")) {
        m_timeout.stop();
        m_serverName = payload.value(QStringLiteral("name")).toString();
        emit serverHelloReceived(payload);
        sendHello();
    } else if (type == QLatin1String("server/activate")) {
        // active_roles bleibt bestehen, wenn eine spätere Aktivierung es weglässt.
        if (payload.contains(QStringLiteral("active_roles"))) {
            m_activeRoles.clear();
            for (const QJsonValue &role : payload.value(QStringLiteral("active_roles")).toArray())
                m_activeRoles.append(role.toString());
        }
        emit log(QStringLiteral("aktive Rollen: %1").arg(m_activeRoles.isEmpty()
                 ? QStringLiteral("keine") : m_activeRoles.join(QStringLiteral(", "))));
        emit activated();
        if (!m_activeRoles.isEmpty())
            sendState();
    } else if (type == QLatin1String("stream/start") || type == QLatin1String("stream/end")) {
        if (m_droppedChunks > 0)
            emit log(QStringLiteral("%1 Binärnachrichten verworfen").arg(m_droppedChunks));
        m_droppedChunks = 0;
    }
}

void SendspinClient::sendHello()
{
    QJsonObject device;
    device.insert(QStringLiteral("product_name"), defaultPlayerName());
#ifdef APP_VERSION
    device.insert(QStringLiteral("software_version"), QStringLiteral("Tonarm " APP_VERSION));
#endif

    QJsonObject pcm;
    pcm.insert(QStringLiteral("codec"), QStringLiteral("pcm"));
    pcm.insert(QStringLiteral("channels"), 2);
    pcm.insert(QStringLiteral("sample_rate"), 48000);
    pcm.insert(QStringLiteral("bit_depth"), 16);
    QJsonObject pcm44 = pcm;
    pcm44.insert(QStringLiteral("sample_rate"), 44100);
    QJsonObject player;
    player.insert(QStringLiteral("supported_formats"), QJsonArray { pcm, pcm44 });
    player.insert(QStringLiteral("buffer_capacity"), BufferCapacity);
    // Ältere Fassung (aiosendspin 9.1.1 in MA 2.10.4) verlangt das Feld hier;
    // neuere Server lesen es noch als Altlast.
    player.insert(QStringLiteral("supported_commands"), QJsonArray());

    // Pflichtangabe; das Pairing selbst kommt erst mit Stufe 5b. Als Liste in
    // der älteren Form: MA 2.10.4 kennt nur sie, neuere Server nehmen beide.
    QJsonObject pairingPsk;
    pairingPsk.insert(QStringLiteral("method"), QStringLiteral("pairing_psk"));
    const QJsonArray pairMethods { pairingPsk };
    QJsonObject unpaired;
    unpaired.insert(QStringLiteral("enabled"), true);

    QJsonObject payload;
    payload.insert(QStringLiteral("name"), effectivePlayerName());
    payload.insert(QStringLiteral("device_info"), device);
    payload.insert(QStringLiteral("supported_roles"), QJsonArray { QLatin1String(PlayerRole) });
    payload.insert(QStringLiteral("player@v1_support"), player);
    payload.insert(QStringLiteral("supported_pair_methods"), pairMethods);
    payload.insert(QStringLiteral("unpaired_access"), unpaired);
    QJsonObject hello;
    hello.insert(QStringLiteral("type"), QStringLiteral("client/hello"));
    hello.insert(QStringLiteral("payload"), payload);
    sendJson(hello);
    emit log(QStringLiteral("client/hello als „%1“").arg(effectivePlayerName()));
}

void SendspinClient::sendState()
{
    QJsonObject player;
    player.insert(QStringLiteral("volume"), 100);
    player.insert(QStringLiteral("muted"), false);
    // static_delay_ms ist der ältere Name von output_delay_ms; MA 2.10.4
    // kennt nur ihn, neuere Server übersetzen ihn.
    player.insert(QStringLiteral("static_delay_ms"), 0);
    player.insert(QStringLiteral("required_lead_time_ms"), 500);
    player.insert(QStringLiteral("min_buffer_ms"), 500);
    QJsonObject payload;
    // Bis Stufe 5c gibt es keinen Ton, also auch nicht verfügbar: so schickt
    // Music Assistant keine Musik an einen stummen Player.
    payload.insert(QStringLiteral("available"), false);
    payload.insert(QStringLiteral("player"), player);
    QJsonObject state;
    state.insert(QStringLiteral("type"), QStringLiteral("client/state"));
    state.insert(QStringLiteral("payload"), payload);
    sendJson(state);
    emit log(QStringLiteral("client/state (nicht verfügbar, noch kein Ton)"));
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
    if (!m_activeRoles.isEmpty()) {
        m_activeRoles.clear();
        emit activated();
    }
    setState(Failed);
    m_socket.abort();
}

void SendspinClient::sendJson(const QJsonObject &obj)
{
    m_socket.sendBinaryMessage(m_noise->encrypt(QByteArray(1, '\0') + compact(obj)));
}
