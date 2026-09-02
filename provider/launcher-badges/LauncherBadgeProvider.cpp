#include "LauncherBadgeProvider.h"

#include <QDBusConnection>
#include <QDebug>
#include <QDir>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaType>
#include <QSaveFile>

#include <algorithm>
#include <limits>
#include <utility>

namespace smartdock::launcherbadges {
namespace {

constexpr auto kLauncherInterface = "com.canonical.Unity.LauncherEntry";
constexpr auto kLauncherSignal = "Update";
constexpr auto kUnityObjectPath = "/Unity";
constexpr auto kUnityService = "com.canonical.Unity";

}  // namespace

LauncherBadgeProvider::LauncherBadgeProvider(QString stateFile, QObject* parent)
    : QObject(parent),
      stateFile_(std::move(stateFile)),
      senderWatcher_(this) {
  senderWatcher_.setConnection(QDBusConnection::sessionBus());
  senderWatcher_.setWatchMode(QDBusServiceWatcher::WatchForUnregistration);
  connect(&senderWatcher_, &QDBusServiceWatcher::serviceUnregistered,
          this, &LauncherBadgeProvider::serviceUnregistered);
}

LauncherBadgeProvider::~LauncherBadgeProvider() {
  auto bus = QDBusConnection::sessionBus();
  if (unityServiceOwned_) bus.unregisterService(kUnityService);
  if (unityObjectRegistered_) bus.unregisterObject(kUnityObjectPath);
}

bool LauncherBadgeProvider::start() {
  auto bus = QDBusConnection::sessionBus();
  if (!bus.isConnected()) {
    qWarning() << "launcher badge provider: session bus unavailable";
    return false;
  }

  if (!bus.connect(QString(), QString(), kLauncherInterface, kLauncherSignal,
                   this, SLOT(update(QString,QVariantMap)))) {
    qWarning() << "launcher badge provider: failed to subscribe to Update";
    return false;
  }

  // Match the established Unity/KDE service shape. The object does not expose
  // a polling/query API; LauncherEntry state still arrives only through typed
  // Update signals.
  unityObjectRegistered_ = bus.registerObject(kUnityObjectPath, this);
  if (!unityObjectRegistered_) {
    qWarning() << "launcher badge provider: failed to register /Unity";
    return false;
  }

  // Matching established Unity/KDE behavior makes late-starting providers
  // visible to applications that only publish launcher state when this well-
  // known bus name appears. If another compatible owner already has the name,
  // signal listening remains valid and we do not replace it.
  unityServiceOwned_ = bus.registerService(kUnityService);
  if (!unityServiceOwned_)
    qInfo() << "launcher badge provider: com.canonical.Unity already owned";

  return publishSnapshot();
}

std::optional<std::int64_t> LauncherBadgeProvider::typedCount(
    const QVariant& value) {
  std::uint64_t raw = 0;
  bool unsignedValue = false;
  switch (value.metaType().id()) {
    case QMetaType::Char:
      return std::max<std::int64_t>(0, value.value<char>());
    case QMetaType::SChar:
      return std::max<std::int64_t>(0, value.value<signed char>());
    case QMetaType::UChar:
      raw = value.value<unsigned char>();
      unsignedValue = true;
      break;
    case QMetaType::Short:
      return std::max<std::int64_t>(0, value.value<short>());
    case QMetaType::UShort:
      raw = value.value<unsigned short>();
      unsignedValue = true;
      break;
    case QMetaType::Int:
      return std::max<std::int64_t>(0, value.toInt());
    case QMetaType::UInt:
      raw = value.toUInt();
      unsignedValue = true;
      break;
    case QMetaType::Long:
      return std::max<std::int64_t>(0, value.value<long>());
    case QMetaType::ULong:
      raw = value.value<unsigned long>();
      unsignedValue = true;
      break;
    case QMetaType::LongLong:
      return std::max<std::int64_t>(0, value.toLongLong());
    case QMetaType::ULongLong:
      raw = value.toULongLong();
      unsignedValue = true;
      break;
    default:
      return std::nullopt;
  }

  if (unsignedValue) {
    return static_cast<std::int64_t>(std::min<std::uint64_t>(
        raw, static_cast<std::uint64_t>(std::numeric_limits<int>::max())));
  }
  return std::nullopt;
}

std::optional<bool> LauncherBadgeProvider::typedBool(const QVariant& value) {
  if (value.metaType().id() != QMetaType::Bool) return std::nullopt;
  return value.toBool();
}

void LauncherBadgeProvider::update(
    const QString& launcherUri, const QVariantMap& properties) {
  if (!calledFromDBus()) return;
  const QString sender = message().service();
  if (sender.isEmpty()) return;

  std::optional<std::int64_t> count;
  std::optional<bool> visible;
  const auto countIt = properties.constFind(QStringLiteral("count"));
  if (countIt != properties.constEnd()) count = typedCount(*countIt);
  const auto visibleIt = properties.constFind(QStringLiteral("count-visible"));
  if (visibleIt != properties.constEnd()) visible = typedBool(*visibleIt);
  if (!count && !visible) return;

  // The display contract only needs 0..99+. Cap large protocol values before
  // JSON serialization while preserving authoritative positive/zero meaning.
  if (count) *count = std::min<std::int64_t>(
      *count, std::numeric_limits<int>::max());

  if (!model_.applyUpdate(launcherUri.toStdString(), sender.toStdString(),
                          count, visible)) {
    return;
  }

  watchSender(sender);
  publishSnapshot();
}

void LauncherBadgeProvider::watchSender(const QString& sender) {
  if (!senderWatcher_.watchedServices().contains(sender))
    senderWatcher_.addWatchedService(sender);
}

void LauncherBadgeProvider::serviceUnregistered(const QString& service) {
  senderWatcher_.removeWatchedService(service);
  if (!model_.removeSender(service.toStdString())) return;
  publishSnapshot();
}

bool LauncherBadgeProvider::publishSnapshot() {
  QFileInfo stateInfo(stateFile_);
  if (!stateInfo.dir().mkpath(QStringLiteral("."))) {
    qWarning() << "launcher badge provider: cannot create state directory"
               << stateInfo.dir().absolutePath();
    return false;
  }

  QJsonObject counts;
  for (const auto& [desktopId, entry] : model_.entries()) {
    QJsonObject record;
    if (entry.count)
      record.insert(QStringLiteral("count"), static_cast<int>(*entry.count));
    if (entry.visible)
      record.insert(QStringLiteral("visible"), *entry.visible);
    counts.insert(QString::fromStdString(desktopId), record);
  }

  QJsonObject root;
  root.insert(QStringLiteral("schemaVersion"), 1);
  root.insert(QStringLiteral("available"), true);
  root.insert(QStringLiteral("revision"), static_cast<qint64>(++revision_));
  root.insert(QStringLiteral("counts"), counts);

  QSaveFile output(stateFile_);
  output.setDirectWriteFallback(false);
  if (!output.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
    qWarning() << "launcher badge provider: cannot open state file"
               << stateFile_ << output.errorString();
    return false;
  }
  const QByteArray payload = QJsonDocument(root).toJson(QJsonDocument::Compact)
      + '\n';
  if (output.write(payload) != payload.size() || !output.commit()) {
    qWarning() << "launcher badge provider: cannot commit state file"
               << stateFile_ << output.errorString();
    return false;
  }
  return true;
}

}  // namespace smartdock::launcherbadges
