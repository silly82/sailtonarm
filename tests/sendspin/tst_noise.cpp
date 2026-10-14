// Prüft NoiseSession byte-genau gegen einen Mitschnitt der Python-Bibliothek
// noiseprotocol (make_vectors.py; feste Schlüssel, Sentinel-PSK). Läuft im
// i486-Bauziel, siehe run.sh.

#include "../../src/sendspin/noisesession.h"

#include <QCoreApplication>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <cstdio>

static int failures = 0;

static void check(bool ok, const char *what)
{
    std::printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        ++failures;
}

static void runVector(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        check(false, qPrintable("Datei lesen: " + path));
        return;
    }
    const QJsonObject v = QJsonDocument::fromJson(f.readAll()).object();
    auto hex = [&v](const char *key) { return QByteArray::fromHex(v.value(key).toString().toLatin1()); };
    const NoiseSession::Suite suite = v.value("suite").toString().contains("AESGCM")
            ? NoiseSession::AesGcm : NoiseSession::ChaChaPoly;
    std::printf("-- %s\n", qPrintable(NoiseSession::suiteName(suite)));

    check(NoiseSession::publicKey(hex("cli_s")) == hex("cli_s_pub"), "X25519 öffentlicher Schlüssel");
    check(NoiseSession::sha256("sendspin-sentinel-psk-v1") == hex("psk"), "Sentinel-PSK");

    NoiseSession s(suite, hex("cli_s"), hex("srv_s_pub"), hex("prologue"));
    QByteArray payload;
    check(s.readMessage1(hex("m1"), &payload), "Nachricht 1 lesen");
    check(payload == hex("m1_payload"), "Payload von Nachricht 1");
    check(s.writeMessage2(hex("psk"), "{}", hex("cli_e")) == hex("m2"), "Nachricht 2 byte-gleich");
    check(s.handshakeHash() == hex("handshake_hash"), "Handshake-Hash");

    QByteArray plain;
    check(s.decrypt(hex("t1"), &plain) && plain == hex("t1_plain"), "Transport Server -> Telefon (1)");
    check(s.decrypt(hex("t2"), &plain) && plain == QByteArray("\0second", 7), "Transport Server -> Telefon (2)");
    check(s.encrypt(hex("t3_plain")) == hex("t3"), "Transport Telefon -> Server");

    // Gegenproben: ein verändertes Byte und eine Wiederholung müssen scheitern.
    NoiseSession bad(suite, hex("cli_s"), hex("srv_s_pub"), hex("prologue") + "x");
    check(!bad.readMessage1(hex("m1"), &payload), "anderer Prolog scheitert");
    QByteArray t = hex("t1");
    check(!s.decrypt(t, &plain), "Wiederholung scheitert");
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    for (int i = 1; i < argc; ++i)
        runVector(QString::fromLocal8Bit(argv[i]));
    std::printf("%s: %d Fehler\n", failures ? "FEHLGESCHLAGEN" : "OK", failures);
    return failures ? 1 : 0;
}
