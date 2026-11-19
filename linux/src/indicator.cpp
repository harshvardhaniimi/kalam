#include "indicator.h"

#include <LayerShellQt/Window>
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickWindow>

Indicator::Indicator(QQmlEngine *engine, QObject *parent) : QObject(parent), m_engine(engine) {}

void Indicator::setVisible(bool visible) {
    if (!m_window) {
        if (!visible)
            return;
        QQmlComponent component(m_engine, QUrl("qrc:/Indicator.qml"));
        m_window = qobject_cast<QQuickWindow *>(component.create());
        if (!m_window) {
            qWarning("%s", qPrintable(component.errorString()));
            return;
        }
        m_window->QObject::setParent(this);
        // Layer shell exists only on Wayland; elsewhere the pill is a plain
        // frameless window.
        if (QGuiApplication::platformName().startsWith("wayland")) {
            auto *layer = LayerShellQt::Window::get(m_window);
            layer->setLayer(LayerShellQt::Window::LayerOverlay);
            layer->setAnchors(LayerShellQt::Window::AnchorBottom);
            layer->setMargins({0, 0, 0, 56});
            layer->setExclusiveZone(-1);
            layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
            layer->setScope("kalam-indicator");
            // Let the compositor pick the monitor: the one with focus.
            layer->setWantsToBeOnActiveScreen(true);
        }
    }
    m_window->setVisible(visible);
}
