#include "secretstore.h"

#include <QProcess>
#include <QStandardPaths>

namespace {
const QStringList attributes{"service", "kalam", "account", "sarvam"};
}

SecretStore::SecretStore(const QString &tool)
    : m_tool(tool.isEmpty() ? QStandardPaths::findExecutable("secret-tool") : tool) {}

QString SecretStore::load() const {
    if (m_tool.isEmpty())
        return {};
    QProcess process;
    process.start(m_tool, QStringList{"lookup"} + attributes);
    if (!process.waitForFinished(5000) || process.exitCode() != 0)
        return {};
    return QString::fromUtf8(process.readAllStandardOutput()).trimmed();
}

bool SecretStore::save(const QString &key) const {
    if (m_tool.isEmpty())
        return false;
    QProcess process;
    if (key.trimmed().isEmpty()) {
        process.start(m_tool, QStringList{"clear"} + attributes);
        return process.waitForFinished(5000) && process.exitCode() == 0;
    }
    // The key goes in on stdin so it never shows up in a process listing.
    process.start(m_tool, QStringList{"store", "--label=Kalam Sarvam API key"} + attributes);
    process.write(key.trimmed().toUtf8());
    process.closeWriteChannel();
    return process.waitForFinished(15000) && process.exitCode() == 0;
}
