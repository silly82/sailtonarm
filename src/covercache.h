#ifndef COVERCACHE_H
#define COVERCACHE_H

#include <QObject>
#include <QQmlNetworkAccessManagerFactory>
#include <QString>

// Cover auf der Platte statt nur im Speicher.
//
// QMLs Image-Element hält geladene Bilder nur im Speicher; nach jedem
// Neustart kam jedes Cover wieder über das Netz, unterwegs also über
// Mobilfunk. Der Bildproxy von Music Assistant antwortet aber mit
// `Cache-Control: max-age=31536000` (ein Jahr, gegen MA 2.10.4 geprüft), und
// die Adressen sind stabil (`proxy_id` ist eine Prüfsumme des Bildes). Ein
// QNetworkDiskCache in der Netzwerkschicht der QML-Engine genügt also: QNAM
// beantwortet frische Einträge dann selbst, ohne den Server zu fragen.
//
// Die Fabrik ist nötig, weil die Engine für Bildladen in eigenen Threads
// jeweils einen eigenen QNetworkAccessManager erzeugt -- jeder bekommt hier
// seinen Cache auf dasselbe Verzeichnis (so auch das Qt-Beispiel
// "networkaccessmanagerfactory"). WebSocket und XMLHttpRequest ohne
// Cache-Header sind davon nicht betroffen: nur zwischengespeichert wird, was
// der Server als speicherbar kennzeichnet.
class CoverCacheFactory : public QQmlNetworkAccessManagerFactory
{
public:
    QNetworkAccessManager *create(QObject *parent) override;

    static QString directory();
    // Obergrenze auf der Platte. Ein Cover in 512 px wiegt 30-120 KB; das
    // reicht für einige tausend.
    static const qint64 MaximumBytes = 100 * 1024 * 1024;
};

// Für die Einstellungen: wie viel liegt im Zwischenspeicher, und ihn leeren.
// Als Kontext-Property "CoverCache" (siehe main()).
class CoverCache : public QObject
{
    Q_OBJECT
    Q_PROPERTY(qint64 sizeBytes READ sizeBytes NOTIFY sizeChanged)

public:
    explicit CoverCache(QObject *parent = Q_NULLPTR);

    qint64 sizeBytes() const;

    // Neu zählen (die Seite ruft das beim Öffnen auf; der Cache wächst im
    // Hintergrund, ohne Bescheid zu sagen).
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void clear();

Q_SIGNALS:
    void sizeChanged();

private:
    qint64 m_sizeBytes;
};

#endif // COVERCACHE_H
