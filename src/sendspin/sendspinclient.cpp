#include "sendspinclient.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSettings>
#include <QStandardPaths>

#include <cmath>

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
const int SampleRate = 48000;
const int Channels = 2;

qint64 readBe(const QByteArray &data, int offset, int bytes)
{
    qint64 value = 0;
    for (int i = 0; i < bytes; ++i)
        value = (value << 8) | quint8(data.at(offset + i));
    return value;
}

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
    m_timeSync.setSingleShot(true);
    connect(&m_timeSync, &QTimer::timeout, this, &SendspinClient::sendTime);
    m_statsTimer.setInterval(1000);
    connect(&m_statsTimer, &QTimer::timeout, this, &SendspinClient::updateSyncText);
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
    m_playedChunks = 0;
    m_legacyWire = false;
    m_filter.reset();
    m_sentAvailable = false;
    m_stateSent = false;
    m_fragmentActive = false;
    m_fragment.clear();
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
    m_timeSync.stop();
    m_statsTimer.stop();
    endStream();
    m_socket.close();
    if (m_sentAvailable) {
        m_sentAvailable = false;
        emit playbackChanged();
    }
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
    m_timeSync.stop();
    m_statsTimer.stop();
    endStream();
    if (m_sentAvailable) {
        m_sentAvailable = false;
        emit playbackChanged();
    }
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
        m_legacyWire = !psk.contains(QStringLiteral("psk_category"));
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
    // Empfangszeit so früh wie möglich (messaging.md, "Receive timestamps").
    const qint64 arrival = AudioOutput::nowUs();
    QByteArray plain;
    if (!m_noise->decrypt(data, &plain) || plain.isEmpty()) {
        fail(QStringLiteral("Entschlüsselung fehlgeschlagen"));
        return;
    }
    const quint8 type = quint8(plain.at(0));
    if (type == 1) {
        // Fragment: [1][flags][orig_type][data] bzw. [1][flags][data].
        if (plain.size() < 2 || (quint8(plain.at(1)) & 0xfc)) {
            fail(QStringLiteral("ungültiges Fragment"));
            return;
        }
        const quint8 flags = quint8(plain.at(1));
        if (flags & 0x02) {
            if (m_fragmentActive || plain.size() < 3 || quint8(plain.at(2)) == 1) {
                fail(QStringLiteral("ungültiges Fragment"));
                return;
            }
            m_fragmentActive = true;
            m_fragmentType = quint8(plain.at(2));
            m_fragment = plain.mid(3);
        } else {
            if (!m_fragmentActive) {
                fail(QStringLiteral("Fragment ohne Anfang"));
                return;
            }
            m_fragment.append(plain.mid(2));
        }
        if (flags & 0x01) {
            m_fragmentActive = false;
            const QByteArray whole = m_fragment;
            m_fragment.clear();
            handleBinary(m_fragmentType, whole, arrival);
        }
        return;
    }
    if (m_fragmentActive) {
        fail(QStringLiteral("Nachricht mitten in Fragmenten"));
        return;
    }
    handleBinary(type, plain.mid(1), arrival);
}

void SendspinClient::handleBinary(quint8 type, const QByteArray &data, qint64 arrivalUs)
{
    if (type == 0) {
        const QJsonObject msg = QJsonDocument::fromJson(data).object();
        const QString msgType = msg.value(QStringLiteral("type")).toString();
        if (msgType == QLatin1String("server/time")) {
            handleServerTime(msg.value(QStringLiteral("payload")).toObject(), arrivalUs);
            return; // zu häufig fürs Protokoll
        }
        emit log(QStringLiteral("<- %1 (verschlüsselt): %2").arg(msgType, QString::fromUtf8(data)));
        handleMessage(msg);
        emit message(msg);
        return;
    }
    if (type != 4) {
        if (m_droppedChunks++ == 0)
            emit log(QStringLiteral("<- Binärtyp %1, wird verworfen").arg(int(type)));
        return;
    }
    // Audio-Chunk: Zeitstempel (int64, big-endian) des ersten Samples in
    // Serverzeit, in der aktuellen Fassung danach send_ahead (uint32).
    const int header = m_legacyWire ? 8 : 12;
    if (data.size() < header) {
        fail(QStringLiteral("Audio-Chunk zu kurz"));
        return;
    }
    if (!m_streamActive || !m_audio.isRunning() || !m_filter.isSynchronized()) {
        if (m_droppedChunks++ == 0)
            emit log(QStringLiteral("Audio wird verworfen (keine Ausgabe)"));
        return;
    }
    const qint64 serverTs = readBe(data, 0, 8);
    m_audio.push(m_filter.computeClientTime(serverTs), data.mid(header));
    ++m_playedChunks;
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
        if (playerActive()) {
            // Erst Zustand melden (nicht verfügbar), dann die Uhr abgleichen;
            // verfügbar wird der Player, sobald sie steht.
            sendState();
            sendTime();
            m_statsTimer.start();
        } else {
            m_timeSync.stop();
            endStream();
        }
    } else if (type == QLatin1String("stream/start")) {
        if (payload.contains(QStringLiteral("player")))
            startStream(payload.value(QStringLiteral("player")).toObject());
    } else if (type == QLatin1String("stream/clear")) {
        const QJsonArray roles = payload.value(QStringLiteral("roles")).toArray();
        if (roles.isEmpty() || roles.contains(QStringLiteral("player")))
            m_audio.clear();
    } else if (type == QLatin1String("stream/end")) {
        const QJsonArray roles = payload.value(QStringLiteral("roles")).toArray();
        if (roles.isEmpty() || roles.contains(QStringLiteral("player")))
            endStream();
    } else if (type == QLatin1String("server/command")) {
        const QJsonObject player = payload.value(QStringLiteral("player")).toObject();
        const QString command = player.value(QStringLiteral("command")).toString();
        if (command == QLatin1String("volume"))
            setVolume(player.value(QStringLiteral("volume")).toInt(m_volume));
        else if (command == QLatin1String("mute"))
            setMuted(player.value(QStringLiteral("mute")).toBool(m_muted));
    }
}

bool SendspinClient::playerActive() const
{
    return m_activeRoles.contains(QLatin1String(PlayerRole));
}

void SendspinClient::setPlaybackEnabled(bool enabled)
{
    if (enabled == m_playbackEnabled)
        return;
    m_playbackEnabled = enabled;
    emit playbackChanged();
    if (!enabled)
        endStream();
    updateAvailability();
}

void SendspinClient::setVolume(int volume)
{
    volume = qBound(0, volume, 100);
    if (volume == m_volume)
        return;
    m_volume = volume;
    applyGain();
    emit playbackChanged();
    if (m_stateSent)
        sendState();
}

void SendspinClient::setMuted(bool muted)
{
    if (muted == m_muted)
        return;
    m_muted = muted;
    applyGain();
    emit playbackChanged();
    if (m_stateSent)
        sendState();
}

void SendspinClient::applyGain()
{
    // Lautstärke ist wahrgenommene Lautheit; Amplitude = (v/100)^1.5
    // (roles/player/v1.md).
    m_audio.setGain(m_muted ? 0.0 : std::pow(m_volume / 100.0, 1.5));
}

void SendspinClient::sendTime()
{
    if (m_state != Encrypted || !m_noise)
        return;
    QJsonObject payload;
    payload.insert(QStringLiteral("client_transmitted"), double(AudioOutput::nowUs()));
    QJsonObject msg;
    msg.insert(QStringLiteral("type"), QStringLiteral("client/time"));
    msg.insert(QStringLiteral("payload"), payload);
    sendJson(msg);
}

void SendspinClient::handleServerTime(const QJsonObject &payload, qint64 arrivalUs)
{
    const qint64 t1 = qint64(payload.value(QStringLiteral("client_transmitted")).toDouble());
    const qint64 t2 = qint64(payload.value(QStringLiteral("server_received")).toDouble());
    const qint64 t3 = qint64(payload.value(QStringLiteral("server_transmitted")).toDouble());
    const qint64 t4 = arrivalUs;
    m_filter.update(((t2 - t1) + (t3 - t4)) / 2, ((t4 - t1) - (t3 - t2)) / 2, t4);

    // Abstand wie in aiosendspin: dicht, bis der Filter steht, dann je nach
    // Fehler bis zu 3 s.
    int interval = 200;
    if (m_filter.isSynchronized()) {
        const qint64 error = m_filter.error();
        interval = error < 1000 ? 3000 : error < 2000 ? 1000 : error < 5000 ? 500 : 200;
    }
    m_timeSync.start(interval);
    updateAvailability();
}

void SendspinClient::updateAvailability()
{
    if (!playerActive() || m_state != Encrypted)
        return;
    // Verfügbar erst mit abgeglichener Uhr (messaging.md, client/state).
    const bool available = m_playbackEnabled && m_filter.isSynchronized() && m_filter.count() >= 5;
    if (m_stateSent && available == m_sentAvailable)
        return;
    m_sentAvailable = available;
    emit playbackChanged();
    sendState();
}

void SendspinClient::startStream(const QJsonObject &player)
{
    const QString codec = player.value(QStringLiteral("codec")).toString();
    const int rate = player.value(QStringLiteral("sample_rate")).toInt();
    const int channels = player.value(QStringLiteral("channels")).toInt();
    const int bits = player.value(QStringLiteral("bit_depth")).toInt();
    if (codec != QLatin1String("pcm") || bits != 16 || channels < 1 || channels > 2 || rate <= 0) {
        emit log(QStringLiteral("Format nicht unterstützt: %1 %2 Hz %3 Kanäle %4 Bit")
                 .arg(codec).arg(rate).arg(channels).arg(bits));
        return;
    }
    if (!m_playbackEnabled)
        return;
    m_droppedChunks = 0;
    m_playedChunks = 0;
    if (m_audio.isRunning() && m_audio.sampleRate() == rate && m_audio.channels() == channels) {
        // Nur die Konfiguration aktualisiert, die Zeitachse läuft weiter.
        m_streamActive = true;
        return;
    }
    QString error;
    applyGain();
    if (!m_audio.start(rate, channels, &error)) {
        emit log(QStringLiteral("Audioausgabe nicht möglich: %1").arg(error));
        return;
    }
    m_streamActive = true;
    m_statsTimer.start();
    emit playbackChanged();
    emit log(QStringLiteral("Wiedergabe: PCM %1 Hz, %2 Kanäle").arg(rate).arg(channels));
}

void SendspinClient::endStream()
{
    const bool wasActive = m_streamActive || m_audio.isRunning();
    m_audio.stop();
    m_streamActive = false;
    if (wasActive) {
        emit log(QStringLiteral("Wiedergabe beendet (%1 Chunks gespielt, %2 verworfen)")
                 .arg(m_playedChunks).arg(m_droppedChunks));
        emit playbackChanged();
    }
    m_playedChunks = 0;
    m_droppedChunks = 0;
}

void SendspinClient::updateSyncText()
{
    QString text = QStringLiteral("Uhr: %1 Messungen, Fehler %2 µs")
            .arg(m_filter.count()).arg(m_filter.isSynchronized() ? m_filter.error() : -1);
    if (m_audio.isRunning()) {
        const AudioOutput::Stats st = m_audio.stats();
        text += QStringLiteral("\nAusgabe: Abweichung %1 µs, Latenz %2 ms, Puffer %3 Chunks\n"
                               "korrigiert −%4/+%5 Frames, %6× neu ausgerichtet, %7 Aussetzer, %8 zu spät")
                .arg(st.errorUs).arg(st.latencyUs / 1000).arg(st.queued)
                .arg(st.dropped).arg(st.duplicated).arg(st.resyncs).arg(st.underruns).arg(st.late);
    }
    if (text != m_syncText) {
        m_syncText = text;
        emit syncTextChanged();
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
    pcm.insert(QStringLiteral("channels"), Channels);
    pcm.insert(QStringLiteral("sample_rate"), SampleRate);
    pcm.insert(QStringLiteral("bit_depth"), 16);
    // Nur eine Rate: die Ausgabe kann nicht lückenlos wechseln, also rechnet
    // der Server um (roles/player/v1.md).
    QJsonObject player;
    player.insert(QStringLiteral("supported_formats"), QJsonArray { pcm });
    player.insert(QStringLiteral("buffer_capacity"), BufferCapacity);
    // Ältere Fassung (aiosendspin 9.1.1 in MA 2.10.4) verlangt das Feld hier;
    // neuere Server lesen es noch als Altlast.
    player.insert(QStringLiteral("supported_commands"), QJsonArray { QStringLiteral("volume"), QStringLiteral("mute") });

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
    player.insert(QStringLiteral("volume"), m_volume);
    player.insert(QStringLiteral("muted"), m_muted);
    // static_delay_ms ist der ältere Name von output_delay_ms; MA 2.10.4
    // kennt nur ihn, neuere Server übersetzen ihn.
    player.insert(QStringLiteral("static_delay_ms"), 0);
    player.insert(QStringLiteral("required_lead_time_ms"), 500);
    player.insert(QStringLiteral("min_buffer_ms"), 500);
    // Aktuelle Fassung: Befehle hier. MA 2.10.4 erlaubt hier nur
    // set_static_delay und lehnt alles andere ab; dort stehen sie in client/hello.
    if (!m_legacyWire)
        player.insert(QStringLiteral("supported_commands"), QJsonArray { QStringLiteral("volume"), QStringLiteral("mute") });
    QJsonObject payload;
    // Ohne playbackEnabled oder ohne abgeglichene Uhr nicht verfügbar: dann
    // schickt Music Assistant keinen Ton.
    payload.insert(QStringLiteral("available"), m_sentAvailable);
    payload.insert(QStringLiteral("player"), player);
    QJsonObject state;
    state.insert(QStringLiteral("type"), QStringLiteral("client/state"));
    state.insert(QStringLiteral("payload"), payload);
    sendJson(state);
    m_stateSent = true;
    emit log(QStringLiteral("client/state (%1, Lautstärke %2%3)")
             .arg(m_sentAvailable ? QStringLiteral("verfügbar") : QStringLiteral("nicht verfügbar"))
             .arg(m_volume).arg(m_muted ? QStringLiteral(", stumm") : QString()));
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
    m_timeSync.stop();
    m_statsTimer.stop();
    endStream();
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
