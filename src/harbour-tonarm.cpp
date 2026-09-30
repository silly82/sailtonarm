#ifdef QT_QML_DEBUG
#include <QtQuick>
#endif

#include "covercache.h"
#include "credentials.h"

#include <sailfishapp.h>
#include <QGuiApplication>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickView>

int main(int argc, char *argv[])
{
    QScopedPointer<QGuiApplication> app(SailfishApp::application(argc, argv));
    app->setApplicationVersion(QStringLiteral(APP_VERSION));
    QScopedPointer<QQuickView> view(SailfishApp::createView());

    // Cover auf der Platte zwischenspeichern (siehe src/covercache.h). Muss
    // vor dem ersten setSource() stehen, sonst hat die Engine ihren
    // Netzwerk-Manager schon ohne Cache angelegt.
    CoverCacheFactory coverCacheFactory;
    view->engine()->setNetworkAccessManagerFactory(&coverCacheFactory);
    CoverCache coverCache;
    view->rootContext()->setContextProperty(QStringLiteral("CoverCache"), &coverCache);

    // Serveradresse + Token leben in C++, weil Sailfish.Secrets aus QML nicht
    // ansteuerbar ist (siehe src/credentials.h). Als Kontext-Property
    // bereitgestellt: in QML einfach `Credentials.baseUrl` / `Credentials.token`.
    Credentials credentials;
    view->rootContext()->setContextProperty(QStringLiteral("Credentials"), &credentials);

    view->setSource(SailfishApp::pathTo(QStringLiteral("qml/harbour-tonarm.qml")));
    view->show();

    return app->exec();
}
