#include "covercache.h"

#include <QDebug>
#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QNetworkAccessManager>
#include <QNetworkDiskCache>
#include <QStandardPaths>

QString CoverCacheFactory::directory()
{
    // Unter dem Cache-Verzeichnis der App, das Sailjail freigibt
    // (~/.cache/<Organisation>/<App>). Eigenes Unterverzeichnis, damit
    // "leeren" nichts anderes trifft.
    return QStandardPaths::writableLocation(QStandardPaths::CacheLocation)
            + QStringLiteral("/covers");
}

QNetworkAccessManager *CoverCacheFactory::create(QObject *parent)
{
    QNetworkAccessManager *manager = new QNetworkAccessManager(parent);
    QNetworkDiskCache *cache = new QNetworkDiskCache(manager);
    cache->setCacheDirectory(directory());
    cache->setMaximumCacheSize(MaximumBytes);
    manager->setCache(cache);
    return manager;
}

CoverCache::CoverCache(QObject *parent)
    : QObject(parent)
    , m_sizeBytes(0)
{
    qDebug() << "CoverCache: directory" << CoverCacheFactory::directory();
    refresh();
}

qint64 CoverCache::sizeBytes() const
{
    return m_sizeBytes;
}

void CoverCache::refresh()
{
    qint64 total = 0;
    QDirIterator it(CoverCacheFactory::directory(), QDir::Files, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        it.next();
        total += it.fileInfo().size();
    }
    if (total != m_sizeBytes) {
        m_sizeBytes = total;
        Q_EMIT sizeChanged();
    }
}

void CoverCache::clear()
{
    // Die Cache-Objekte der laufenden Netzwerk-Manager merken davon nichts;
    // QNetworkDiskCache kommt mit verschwundenen Dateien aber zurecht (ein
    // fehlender Eintrag ist ein Cache-Fehlschuss, dann eben übers Netz).
    QDir dir(CoverCacheFactory::directory());
    if (!dir.removeRecursively()) {
        qWarning() << "CoverCache: could not remove" << dir.path();
    }
    refresh();
}
