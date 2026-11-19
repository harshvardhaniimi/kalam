#pragma once

#include <QObject>

class QQmlEngine;
class QQuickWindow;

// The floating pill shown while recording and transcribing: elapsed time
// and the real voice level, at the bottom of the focused monitor. It is a
// layer-shell surface that never takes keyboard focus, so the window being
// dictated into stays focused for the paste.
class Indicator : public QObject {
    Q_OBJECT

public:
    explicit Indicator(QQmlEngine *engine, QObject *parent = nullptr);

    void setVisible(bool visible);

private:
    QQmlEngine *m_engine;
    QQuickWindow *m_window = nullptr;
};
