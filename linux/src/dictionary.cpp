#include "dictionary.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QVariantMap>
#include <algorithm>

namespace Dictionary {

QString apply(const QString &text, const QList<DictionaryRule> &rules) {
    QList<DictionaryRule> ordered = rules;
    std::stable_sort(ordered.begin(), ordered.end(),
                     [](const DictionaryRule &a, const DictionaryRule &b) { return a.from.size() > b.from.size(); });

    QString result = text;
    for (const auto &rule : ordered) {
        const QString from = rule.from.trimmed();
        if (from.isEmpty())
            continue;
        // \b treats Devanagari vowel signs as word breaks, so a Hindi rule
        // would match inside a longer word. Spell the boundary out instead:
        // no letter, mark, or digit on either side.
        const QRegularExpression pattern(
            "(?<![\\p{L}\\p{M}\\p{N}_])" + QRegularExpression::escape(from) + "(?![\\p{L}\\p{M}\\p{N}_])",
            QRegularExpression::CaseInsensitiveOption | QRegularExpression::UseUnicodePropertiesOption);
        if (!pattern.isValid())
            continue;
        // Replace by hand so a "\1" or "&" in the replacement stays literal.
        QString replaced;
        qsizetype last = 0;
        auto matches = pattern.globalMatch(result);
        while (matches.hasNext()) {
            const auto match = matches.next();
            replaced += result.mid(last, match.capturedStart() - last) + rule.to;
            last = match.capturedEnd();
        }
        result = replaced + result.mid(last);
    }
    return result;
}

QList<DictionaryRule> fromJson(const QByteArray &json) {
    QList<DictionaryRule> rules;
    for (const auto &value : QJsonDocument::fromJson(json).array()) {
        const QJsonObject object = value.toObject();
        if (!object.value("from").toString().trimmed().isEmpty())
            rules.append({object.value("from").toString(), object.value("to").toString()});
    }
    return rules;
}

QByteArray toJson(const QList<DictionaryRule> &rules) {
    QJsonArray array;
    for (const auto &rule : rules)
        array.append(QJsonObject{{"from", rule.from}, {"to", rule.to}});
    return QJsonDocument(array).toJson(QJsonDocument::Indented);
}

QVariantList toVariant(const QList<DictionaryRule> &rules) {
    QVariantList list;
    for (const auto &rule : rules)
        list.append(QVariantMap{{"from", rule.from}, {"to", rule.to}});
    return list;
}

}
