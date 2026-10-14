#ifndef NOISESESSION_H
#define NOISESESSION_H

#include <QByteArray>
#include <QString>

// Noise KKpsk2 für Sendspin, nur die Rolle des Responders: In Sendspin ist
// der Server immer Initiator, das Telefon immer Responder (connection.md,
// "Pattern"), unabhängig davon, wer die WebSocket-Verbindung aufmacht.
//
//   Vorab bekannt:  -> s   (server_id)      <- s   (client_id)
//   Nachricht 1:    -> e, es, ss            (Server, Payload: psk_id, psk_category)
//   Nachricht 2:    <- e, ee, se, psk       (Telefon, Payload: "{}")
//
// Gebaut nur aus libcrypto (OpenSSL 3): X25519, SHA-256/HMAC, ChaCha20-Poly1305
// bzw. AES-256-GCM. Eine fertige Noise-Bibliothek gibt es auf Sailfish nicht.
// Byte-genau geprüft gegen die Python-Bibliothek noiseprotocol, die aiosendspin
// verwendet (tests/sendspin/).
class NoiseSession
{
public:
    enum Suite { ChaChaPoly, AesGcm };

    // localStaticPriv: privater X25519-Schlüssel des Telefons (32 Bytes),
    // remoteStaticPub: server_id als 32 Bytes, prologue: client/init gefolgt
    // von server/init, genau so wie gesendet und empfangen.
    NoiseSession(Suite suite, const QByteArray &localStaticPriv,
                 const QByteArray &remoteStaticPub, const QByteArray &prologue);

    static QString suiteName(Suite suite);

    // Nachricht 1 lesen. Liefert die entschlüsselte Payload (JSON); false,
    // wenn die Nachricht kaputt ist oder nicht zu den Schlüsseln passt.
    bool readMessage1(const QByteArray &message, QByteArray *payload);

    // Nachricht 2 schreiben, mit dem zur psk_id passenden PSK. Danach ist der
    // Handshake fertig und encrypt()/decrypt() arbeiten im Transportmodus.
    // ephemeralPriv nur für Tests; leer heisst: frisch aus dem Zufallsgenerator.
    QByteArray writeMessage2(const QByteArray &psk, const QByteArray &payload,
                             const QByteArray &ephemeralPriv = QByteArray());

    bool isTransport() const { return m_transport; }
    QByteArray handshakeHash() const { return m_h; }

    // Transportmodus: Telefon -> Server bzw. Server -> Telefon. decrypt()
    // liefert false bei falschem Tag; laut Spezifikation ist die Verbindung
    // dann zu schliessen.
    QByteArray encrypt(const QByteArray &plaintext);
    bool decrypt(const QByteArray &ciphertext, QByteArray *plaintext);

    // Hilfen, die auch der Rest des Clients braucht.
    static QByteArray generatePrivateKey();
    static QByteArray publicKey(const QByteArray &privateKey);
    static QByteArray sha256(const QByteArray &data);

private:
    struct CipherState {
        QByteArray k;
        quint64 n = 0;
    };

    QByteArray dh(const QByteArray &priv, const QByteArray &pub) const;
    QByteArray aead(bool encrypt, const QByteArray &key, quint64 n,
                    const QByteArray &ad, const QByteArray &in, bool *ok) const;
    void mixHash(const QByteArray &data);
    void mixKey(const QByteArray &ikm);
    void mixKeyAndHash(const QByteArray &ikm);
    QByteArray encryptAndHash(const QByteArray &plaintext);
    bool decryptAndHash(const QByteArray &ciphertext, QByteArray *plaintext);

    Suite m_suite;
    QByteArray m_s;      // eigener statischer privater Schlüssel
    QByteArray m_rs;     // statischer öffentlicher Schlüssel des Servers
    QByteArray m_re;     // flüchtiger öffentlicher Schlüssel des Servers
    QByteArray m_ck;
    QByteArray m_h;
    CipherState m_hs;    // Schlüssel während des Handshakes
    CipherState m_send;  // Telefon -> Server
    CipherState m_recv;  // Server -> Telefon
    bool m_gotMessage1 = false;
    bool m_transport = false;
};

#endif // NOISESESSION_H
