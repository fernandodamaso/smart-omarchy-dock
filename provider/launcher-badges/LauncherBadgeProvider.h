#pragma once

#include <QDBusContext>
#include <QDBusServiceWatcher>
#include <QObject>
#include <QString>
#include <QVariantMap>

#include <cstdint>
#include <optional>

#include "LauncherBadgeModel.h"

namespace smartdock::launcherbadges {

class LauncherBadgeProvider : public QObject, protected QDBusContext {
  Q_OBJECT

 public:
  explicit LauncherBadgeProvider(QString stateFile, QObject* parent = nullptr);
  ~LauncherBadgeProvider() override;

  bool start();

 private slots:
  void update(const QString& launcherUri, const QVariantMap& properties);
  void serviceUnregistered(const QString& service);

 private:
  static std::optional<std::int64_t> typedCount(const QVariant& value);
  static std::optional<bool> typedBool(const QVariant& value);

  void watchSender(const QString& sender);
  bool publishSnapshot();

  QString stateFile_;
  LauncherBadgeModel model_;
  QDBusServiceWatcher senderWatcher_;
  quint64 revision_ = 0;
  bool unityObjectRegistered_ = false;
  bool unityServiceOwned_ = false;
};

}  // namespace smartdock::launcherbadges
