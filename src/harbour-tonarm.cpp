#ifdef QT_QML_DEBUG
#include <QtQuick>
#endif

#include "covercache.h"
#include "credentials.h"
#ifdef TONARM_SENDSPIN
#include "sendspin/sendspinclient.h"
#endif

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

    // Sendspin gibt es nur in der OpenRepos-Variante (KONZEPT.md Abschnitt
    // 38). SendspinAvailable steht in beiden, damit QML fragen kann, ohne an
    // einer fehlenden Kontext-Property zu scheitern.
#ifdef TONARM_SENDSPIN
    SendspinClient sendspin;
    view->rootContext()->setContextProperty(QStringLiteral("Sendspin"), &sendspin);
    view->rootContext()->setContextProperty(QStringLiteral("SendspinAvailable"), true);
#else
    view->rootContext()->setContextProperty(QStringLiteral("SendspinAvailable"), false);
#endif

    view->setSource(SailfishApp::pathTo(QStringLiteral("qml/harbour-tonarm.qml")));
    view->show();

    return app->exec();
}
