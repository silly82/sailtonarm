#ifdef QT_QML_DEBUG
#include <QtQuick>
#endif

#include "credentials.h"

#include <sailfishapp.h>
#include <QGuiApplication>
#include <QQmlContext>
#include <QQuickView>

int main(int argc, char *argv[])
{
    QScopedPointer<QGuiApplication> app(SailfishApp::application(argc, argv));
    QScopedPointer<QQuickView> view(SailfishApp::createView());

    // Serveradresse + Token leben in C++, weil Sailfish.Secrets aus QML nicht
    // ansteuerbar ist (siehe src/credentials.h). Als Kontext-Property
    // bereitgestellt: in QML einfach `Credentials.baseUrl` / `Credentials.token`.
    Credentials credentials;
    view->rootContext()->setContextProperty(QStringLiteral("Credentials"), &credentials);

    view->setSource(SailfishApp::pathTo(QStringLiteral("qml/harbour-tonarm.qml")));
    view->show();

    return app->exec();
}
