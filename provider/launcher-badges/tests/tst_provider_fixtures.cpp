#include "LauncherBadgeModel.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QtTest>

#include <optional>

using smartdock::launcherbadges::LauncherBadgeModel;

class LauncherBadgeProviderFixtures : public QObject {
  Q_OBJECT

 private:
  static QJsonObject loadFixture(const QString& name) {
    QFile file(QStringLiteral(SMARTDOCK_LAUNCHER_BADGE_FIXTURE_DIR) + '/' + name);
    if (!file.open(QIODevice::ReadOnly)) return {};
    const auto document = QJsonDocument::fromJson(file.readAll());
    return document.isObject() ? document.object() : QJsonObject{};
  }

  static void runFixture(const QString& name) {
    const QJsonObject fixture = loadFixture(name);
    QVERIFY2(!fixture.isEmpty(), qPrintable(QStringLiteral("missing fixture: ") + name));

    LauncherBadgeModel model;
    const QJsonArray updates = fixture.value(QStringLiteral("updates")).toArray();
    for (const auto& value : updates) {
      const QJsonObject update = value.toObject();
      std::optional<std::int64_t> count;
      std::optional<bool> visible;
      const QJsonValue countValue = update.value(QStringLiteral("count"));
      if (countValue.isDouble())
        count = static_cast<std::int64_t>(countValue.toDouble());
      const QJsonValue visibleValue = update.value(QStringLiteral("visible"));
      if (visibleValue.isBool()) visible = visibleValue.toBool();

      model.applyUpdate(
          update.value(QStringLiteral("uri")).toString().toStdString(),
          update.value(QStringLiteral("sender")).toString().toStdString(),
          count,
          visible);
    }

    const QJsonArray disconnects = fixture.value(QStringLiteral("disconnects")).toArray();
    for (const auto& value : disconnects)
      model.removeSender(value.toString().toStdString());

    const QJsonObject expected = fixture.value(QStringLiteral("expected")).toObject();
    QCOMPARE(static_cast<int>(model.entries().size()), expected.size());
    for (auto it = expected.constBegin(); it != expected.constEnd(); ++it) {
      const auto* entry = model.entry(it.key().toStdString());
      QVERIFY2(entry != nullptr, qPrintable(QStringLiteral("missing entry: ") + it.key()));
      const QJsonObject record = it.value().toObject();

      if (record.contains(QStringLiteral("count"))) {
        QVERIFY(entry->count.has_value());
        QCOMPARE(*entry->count,
                 static_cast<std::int64_t>(record.value(QStringLiteral("count")).toDouble()));
      } else {
        QVERIFY(!entry->count.has_value());
      }

      if (record.contains(QStringLiteral("visible"))) {
        QVERIFY(entry->visible.has_value());
        QCOMPARE(*entry->visible, record.value(QStringLiteral("visible")).toBool());
      } else {
        QVERIFY(!entry->visible.has_value());
      }

      if (record.contains(QStringLiteral("sender")))
        QCOMPARE(QString::fromStdString(entry->sender),
                 record.value(QStringLiteral("sender")).toString());
    }
  }

 private slots:
  void initial() { runFixture(QStringLiteral("initial.json")); }
  void partial() { runFixture(QStringLiteral("partial.json")); }
  void hide() { runFixture(QStringLiteral("hide.json")); }
  void clear() { runFixture(QStringLiteral("clear.json")); }
  void reconnect() { runFixture(QStringLiteral("reconnect.json")); }
  void malformed() { runFixture(QStringLiteral("malformed.json")); }
  void unknownLauncher() { runFixture(QStringLiteral("unknown.json")); }
};

QTEST_MAIN(LauncherBadgeProviderFixtures)
#include "tst_provider_fixtures.moc"
