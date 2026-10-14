#include "noisesession.h"

#include <QList>

#include <openssl/evp.h>
#include <openssl/hmac.h>
#include <openssl/rand.h>

// Alle Schritte und Namen folgen der Noise-Spezifikation (Revision 34),
// Abschnitte 5.1-5.3 (CipherState, SymmetricState, HandshakeState) und 9 (PSK).

namespace {

const int KeyLen = 32;
const int TagLen = 16;

QByteArray hmacSha256(const QByteArray &key, const QByteArray &data)
{
    unsigned char out[32];
    unsigned int len = 0;
    HMAC(EVP_sha256(), key.constData(), key.size(),
         reinterpret_cast<const unsigned char *>(data.constData()), data.size(), out, &len);
    return QByteArray(reinterpret_cast<const char *>(out), int(len));
}

// HKDF in der Noise-Form (Abschnitt 4.3), zwei oder drei Ausgaben.
QList<QByteArray> hkdf(const QByteArray &ck, const QByteArray &ikm, int outputs)
{
    const QByteArray temp = hmacSha256(ck, ikm);
    QList<QByteArray> out;
    QByteArray prev;
    for (int i = 1; i <= outputs; ++i) {
        prev = hmacSha256(temp, prev + char(i));
        out.append(prev);
    }
    return out;
}

} // namespace

NoiseSession::NoiseSession(Suite suite, const QByteArray &localStaticPriv,
                           const QByteArray &remoteStaticPub, const QByteArray &prologue)
    : m_suite(suite), m_s(localStaticPriv), m_rs(remoteStaticPub)
{
    // InitializeSymmetric: der Protokollname ist länger als 32 Bytes, also
    // wird er gehasht.
    const QByteArray name = "Noise_KKpsk2_" + suiteName(suite).toLatin1();
    m_h = name.size() <= 32 ? name + QByteArray(32 - name.size(), '\0') : sha256(name);
    m_ck = m_h;
    mixHash(prologue);
    // Vorab bekannte Schlüssel, der des Initiators (Server) zuerst.
    mixHash(m_rs);
    mixHash(publicKey(m_s));
}

QString NoiseSession::suiteName(Suite suite)
{
    return suite == AesGcm ? QStringLiteral("25519_AESGCM_SHA256")
                           : QStringLiteral("25519_ChaChaPoly_SHA256");
}

bool NoiseSession::readMessage1(const QByteArray &message, QByteArray *payload)
{
    if (m_gotMessage1 || message.size() < KeyLen + TagLen)
        return false;
    m_gotMessage1 = true;
    // e: im PSK-Modus geht der flüchtige Schlüssel auch in MixKey ein.
    m_re = message.left(KeyLen);
    mixHash(m_re);
    mixKey(m_re);
    // es: flüchtig beim Initiator, statisch beim Responder.
    mixKey(dh(m_s, m_re));
    // ss
    mixKey(dh(m_s, m_rs));
    return decryptAndHash(message.mid(KeyLen), payload);
}

QByteArray NoiseSession::writeMessage2(const QByteArray &psk, const QByteArray &payload,
                                       const QByteArray &ephemeralPriv)
{
    if (!m_gotMessage1 || m_transport || psk.size() != KeyLen)
        return QByteArray();
    const QByteArray e = ephemeralPriv.isEmpty() ? generatePrivateKey() : ephemeralPriv;
    const QByteArray ePub = publicKey(e);
    QByteArray out = ePub;
    mixHash(ePub);
    mixKey(ePub);
    mixKey(dh(e, m_re));   // ee
    mixKey(dh(e, m_rs));   // se: statisch beim Initiator, flüchtig beim Responder
    mixKeyAndHash(psk);    // psk
    out += encryptAndHash(payload);

    // Split: der erste Schlüssel gilt in Richtung Initiator -> Responder.
    const QList<QByteArray> keys = hkdf(m_ck, QByteArray(), 2);
    m_recv.k = keys.at(0);
    m_send.k = keys.at(1);
    m_hs = CipherState();
    m_transport = true;
    return out;
}

QByteArray NoiseSession::encrypt(const QByteArray &plaintext)
{
    if (!m_transport)
        return QByteArray();
    bool ok = false;
    const QByteArray out = aead(true, m_send.k, m_send.n++, QByteArray(), plaintext, &ok);
    return ok ? out : QByteArray();
}

bool NoiseSession::decrypt(const QByteArray &ciphertext, QByteArray *plaintext)
{
    if (!m_transport)
        return false;
    bool ok = false;
    *plaintext = aead(false, m_recv.k, m_recv.n, QByteArray(), ciphertext, &ok);
    // Der Zähler zählt nur bei Erfolg weiter; nach einem Fehler wird die
    // Verbindung ohnehin geschlossen.
    if (ok)
        ++m_recv.n;
    return ok;
}

QByteArray NoiseSession::generatePrivateKey()
{
    QByteArray key(KeyLen, '\0');
    if (RAND_bytes(reinterpret_cast<unsigned char *>(key.data()), KeyLen) != 1)
        return QByteArray();
    return key;
}

QByteArray NoiseSession::publicKey(const QByteArray &privateKey)
{
    EVP_PKEY *pkey = EVP_PKEY_new_raw_private_key(
        EVP_PKEY_X25519, Q_NULLPTR,
        reinterpret_cast<const unsigned char *>(privateKey.constData()), privateKey.size());
    if (!pkey)
        return QByteArray();
    QByteArray pub(KeyLen, '\0');
    size_t len = KeyLen;
    const bool ok = EVP_PKEY_get_raw_public_key(
        pkey, reinterpret_cast<unsigned char *>(pub.data()), &len) == 1;
    EVP_PKEY_free(pkey);
    return ok && len == size_t(KeyLen) ? pub : QByteArray();
}

QByteArray NoiseSession::sha256(const QByteArray &data)
{
    unsigned char out[32];
    unsigned int len = 0;
    EVP_Digest(data.constData(), data.size(), out, &len, EVP_sha256(), Q_NULLPTR);
    return QByteArray(reinterpret_cast<const char *>(out), int(len));
}

QByteArray NoiseSession::dh(const QByteArray &priv, const QByteArray &pub) const
{
    EVP_PKEY *own = EVP_PKEY_new_raw_private_key(
        EVP_PKEY_X25519, Q_NULLPTR,
        reinterpret_cast<const unsigned char *>(priv.constData()), priv.size());
    EVP_PKEY *peer = EVP_PKEY_new_raw_public_key(
        EVP_PKEY_X25519, Q_NULLPTR,
        reinterpret_cast<const unsigned char *>(pub.constData()), pub.size());
    QByteArray secret;
    EVP_PKEY_CTX *ctx = own ? EVP_PKEY_CTX_new(own, Q_NULLPTR) : Q_NULLPTR;
    size_t len = KeyLen;
    if (ctx && peer && EVP_PKEY_derive_init(ctx) == 1 && EVP_PKEY_derive_set_peer(ctx, peer) == 1) {
        secret.resize(KeyLen);
        if (EVP_PKEY_derive(ctx, reinterpret_cast<unsigned char *>(secret.data()), &len) != 1
                || len != size_t(KeyLen))
            secret.clear();
    }
    EVP_PKEY_CTX_free(ctx);
    EVP_PKEY_free(peer);
    EVP_PKEY_free(own);
    // Ein leeres Ergebnis lässt den Handshake später am Tag scheitern, statt
    // mit einem Nullschlüssel weiterzumachen.
    return secret;
}

QByteArray NoiseSession::aead(bool encrypt, const QByteArray &key, quint64 n,
                              const QByteArray &ad, const QByteArray &in, bool *ok) const
{
    *ok = false;
    if (key.size() != KeyLen || (!encrypt && in.size() < TagLen))
        return QByteArray();

    // Nonce: 4 Nullbytes, dann der Zähler -- little-endian bei ChaChaPoly,
    // big-endian bei AES-GCM (Noise-Spezifikation, Abschnitt 12).
    unsigned char nonce[12] = {0};
    for (int i = 0; i < 8; ++i) {
        const unsigned char b = (n >> (8 * i)) & 0xff;
        if (m_suite == ChaChaPoly)
            nonce[4 + i] = b;
        else
            nonce[11 - i] = b;
    }

    const EVP_CIPHER *cipher = m_suite == ChaChaPoly ? EVP_chacha20_poly1305() : EVP_aes_256_gcm();
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx)
        return QByteArray();

    const int dataLen = encrypt ? in.size() : in.size() - TagLen;
    QByteArray out(dataLen + (encrypt ? TagLen : 0), '\0');
    unsigned char *o = reinterpret_cast<unsigned char *>(out.data());
    const unsigned char *i = reinterpret_cast<const unsigned char *>(in.constData());
    int len = 0;
    bool good = EVP_CipherInit_ex(ctx, cipher, Q_NULLPTR, Q_NULLPTR, Q_NULLPTR, encrypt ? 1 : 0) == 1
            && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_SET_IVLEN, 12, Q_NULLPTR) == 1
            && EVP_CipherInit_ex(ctx, Q_NULLPTR, Q_NULLPTR,
                                 reinterpret_cast<const unsigned char *>(key.constData()), nonce,
                                 encrypt ? 1 : 0) == 1;
    if (good && !ad.isEmpty())
        good = EVP_CipherUpdate(ctx, Q_NULLPTR, &len,
                                reinterpret_cast<const unsigned char *>(ad.constData()), ad.size()) == 1;
    if (good && dataLen > 0)
        good = EVP_CipherUpdate(ctx, o, &len, i, dataLen) == 1;
    if (good && !encrypt)
        good = EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_SET_TAG, TagLen,
                                   const_cast<unsigned char *>(i + dataLen)) == 1;
    if (good)
        good = EVP_CipherFinal_ex(ctx, o + dataLen, &len) == 1;
    if (good && encrypt)
        good = EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_GET_TAG, TagLen, o + dataLen) == 1;
    EVP_CIPHER_CTX_free(ctx);

    *ok = good;
    return good ? out : QByteArray();
}

void NoiseSession::mixHash(const QByteArray &data)
{
    m_h = sha256(m_h + data);
}

void NoiseSession::mixKey(const QByteArray &ikm)
{
    const QList<QByteArray> out = hkdf(m_ck, ikm, 2);
    m_ck = out.at(0);
    m_hs.k = out.at(1);
    m_hs.n = 0;
}

void NoiseSession::mixKeyAndHash(const QByteArray &ikm)
{
    const QList<QByteArray> out = hkdf(m_ck, ikm, 3);
    m_ck = out.at(0);
    mixHash(out.at(1));
    m_hs.k = out.at(2);
    m_hs.n = 0;
}

QByteArray NoiseSession::encryptAndHash(const QByteArray &plaintext)
{
    bool ok = false;
    const QByteArray c = aead(true, m_hs.k, m_hs.n++, m_h, plaintext, &ok);
    mixHash(c);
    return c;
}

bool NoiseSession::decryptAndHash(const QByteArray &ciphertext, QByteArray *plaintext)
{
    bool ok = false;
    *plaintext = aead(false, m_hs.k, m_hs.n, m_h, ciphertext, &ok);
    if (!ok)
        return false;
    ++m_hs.n;
    mixHash(ciphertext);
    return true;
}
