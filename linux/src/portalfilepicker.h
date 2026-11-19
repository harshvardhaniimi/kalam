#pragma once

#include <QVariantMap>

#include "filepicker.h"

class QDBusPendingCallWatcher;

// File dialogs through xdg-desktop-portal, so they are the desktop's own.
// The request handling follows Omacut's portal picker (MIT, David
// Heinemeier Hansson).
class PortalFilePicker : public FilePicker {
    Q_OBJECT

public:
    explicit PortalFilePicker(QObject *parent = nullptr);

    void openAudio() override;
    void saveText(const QString &suggestedName) override;

private slots:
    void handleResponse(uint response, const QVariantMap &results);

private:
    enum class Action { None, Open, Save };

    void request(const QString &method, const QString &title, QVariantMap options, Action action);
    void clearPending();

    QString m_pendingPath;
    Action m_pendingAction = Action::None;
    // Bumped per request, so a late reply for a replaced request is ignored.
    int m_generation = 0;
};
