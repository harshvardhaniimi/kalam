#pragma once

#include <QList>
#include <QString>
#include <QVariantList>

// A personal-dictionary correction applied to every transcript: whatever
// the engine heard (`from`) becomes what the user means (`to`).
struct DictionaryRule {
    QString from;
    QString to;
};

namespace Dictionary {

// Case-insensitive, whole-word, longest rule first so a multi-word entry
// wins over the words inside it.
QString apply(const QString &text, const QList<DictionaryRule> &rules);

QList<DictionaryRule> fromJson(const QByteArray &json);
QByteArray toJson(const QList<DictionaryRule> &rules);
QVariantList toVariant(const QList<DictionaryRule> &rules);

}
