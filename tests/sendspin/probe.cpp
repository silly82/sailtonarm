// Sendspin-Probe: Handshake mit einem echten Sendspin-Server, server/hello
// lesen, als Player anmelden (client/hello, nicht verfügbar), einige Sekunden
// verbunden bleiben und mit client/goodbye verabschieden. Spielt nichts ab.
//
//   probe ws://<server>:8927/sendspin <schlüsseldatei> [name] [sekunden]
//
// Die Schlüsseldatei hält den privaten X25519-Schlüssel (32 Bytes) und wird
// beim ersten Lauf angelegt -- ausserhalb des Repos ablegen.

#include "../../src/sendspin/sendspinclient.h"

#include <QCoreApplication>
#include <QFile>
#include <QTimer>
#include <cstdio>

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    if (argc < 3 || argc > 5) {
        std::fprintf(stderr, "Aufruf: %s ws://<server>:8927/sendspin <schlüsseldatei> [name] [sekunden]\n", argv[0]);
        return 2;
    }
    QFile keyFile(QString::fromLocal8Bit(argv[2]));
    QByteArray key;
    if (keyFile.open(QIODevice::ReadOnly))
        key = keyFile.readAll();
    if (key.size() != 32) {
        key = NoiseSession::generatePrivateKey();
        keyFile.close();
        if (!keyFile.open(QIODevice::WriteOnly) || keyFile.write(key) != 32) {
            std::fprintf(stderr, "Schlüsseldatei nicht schreibbar\n");
            return 2;
        }
        keyFile.setPermissions(QFile::ReadOwner | QFile::WriteOwner);
    }

    SendspinClient client;
    if (argc > 3)
        client.setPlayerName(QString::fromLocal8Bit(argv[3]));
    const int stayMs = argc > 4 ? QByteArray(argv[4]).toInt() * 1000 : 1500;
    int result = 1;
    QObject::connect(&client, &SendspinClient::log, [](const QString &line) {
        std::printf("%s\n", qPrintable(line));
        std::fflush(stdout);
    });
    QObject::connect(&client, &SendspinClient::serverHelloReceived, [&](const QJsonObject &) {
        std::printf("ERFOLG: server/hello von \"%s\"\n", qPrintable(client.serverName()));
        result = 0;
        // Verbunden bleiben (server/activate, Player in MA sichtbar), dann gehen.
        QTimer::singleShot(stayMs, [&]() {
            client.close();
            QTimer::singleShot(500, &app, &QCoreApplication::quit);
        });
    });
    QObject::connect(&client, &SendspinClient::stateChanged, [&]() {
        if (client.state() == SendspinClient::Failed)
            QTimer::singleShot(0, &app, &QCoreApplication::quit);
    });
    QTimer::singleShot(40000 + stayMs, &app, &QCoreApplication::quit);
    client.open(QUrl(QString::fromLocal8Bit(argv[1])), key);
    app.exec();
    return result;
}
