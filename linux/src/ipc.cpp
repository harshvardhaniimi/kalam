#include "ipc.h"

#include <QJsonDocument>
#include <QLocalSocket>
#include <QPointer>
#include <QStandardPaths>

namespace Ipc {

QString socketPath() {
    QString runtime = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    if (runtime.isEmpty())
        runtime = QStandardPaths::writableLocation(QStandardPaths::TempLocation);
    return runtime + "/kalam.sock";
}

bool send(const QJsonObject &command, QJsonObject *reply, int timeoutMs) {
    QLocalSocket socket;
    socket.connectToServer(socketPath());
    if (!socket.waitForConnected(500))
        return false;
    socket.write(QJsonDocument(command).toJson(QJsonDocument::Compact) + "\n");
    socket.flush();
    while (!socket.canReadLine()) {
        if (!socket.waitForReadyRead(timeoutMs))
            break;
    }
    if (reply)
        *reply = QJsonDocument::fromJson(socket.readLine()).object();
    return true;
}

Server::Server(Handler handler, QObject *parent) : QObject(parent), m_handler(std::move(handler)) {
    connect(&m_server, &QLocalServer::newConnection, this, [this] {
        while (QLocalSocket *socket = m_server.nextPendingConnection()) {
            connect(socket, &QLocalSocket::disconnected, socket, &QObject::deleteLater);
            connect(socket, &QLocalSocket::readyRead, socket, [this, socket] {
                if (!socket->canReadLine())
                    return;
                const QJsonObject command = QJsonDocument::fromJson(socket->readLine()).object();
                // The client may have gone by the time a slow command ends.
                QPointer<QLocalSocket> guard(socket);
                m_handler(command, [guard](const QJsonObject &reply) {
                    if (!guard)
                        return;
                    guard->write(QJsonDocument(reply).toJson(QJsonDocument::Compact) + "\n");
                    guard->flush();
                    guard->disconnectFromServer();
                });
            });
        }
    });
}

bool Server::listen() {
    // Only the user may talk to it, and a socket left by a crash is stale:
    // the caller already checked that nobody answers on it.
    m_server.setSocketOptions(QLocalServer::UserAccessOption);
    QLocalServer::removeServer(socketPath());
    return m_server.listen(socketPath());
}

}
