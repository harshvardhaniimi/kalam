#pragma once

#include <QString>

// The Sarvam API key lives in the desktop keyring (libsecret), never in a
// plain settings file. Tests point `tool` at a fake secret-tool.
class SecretStore {
public:
    explicit SecretStore(const QString &tool = {});

    bool available() const { return !m_tool.isEmpty(); }
    QString load() const;
    // An empty key removes the stored one. False when the keyring refused.
    bool save(const QString &key) const;

private:
    QString m_tool;
};
