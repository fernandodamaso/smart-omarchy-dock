#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QLockFile>
#include <QTextStream>

#include "LauncherBadgeProvider.h"

using smartdock::launcherbadges::LauncherBadgeProvider;

int main(int argc, char* argv[]) {
  QCoreApplication app(argc, argv);
  QCoreApplication::setApplicationName(
      QStringLiteral("smartdock-launcher-badge-provider"));
  QCoreApplication::setApplicationVersion(QStringLiteral("1"));

  QCommandLineParser parser;
  parser.setApplicationDescription(
      QStringLiteral("SmartDock Unity LauncherEntry badge provider"));
  parser.addHelpOption();
  parser.addVersionOption();
  QCommandLineOption stateFileOption(
      QStringList{QStringLiteral("state-file")},
      QStringLiteral("Atomic provider snapshot path"),
      QStringLiteral("path"));
  parser.addOption(stateFileOption);
  parser.process(app);

  const QString stateFile = parser.value(stateFileOption);
  if (stateFile.isEmpty()) {
    QTextStream(stderr) << "--state-file is required\n";
    return 2;
  }

  QFileInfo stateInfo(stateFile);
  if (!stateInfo.dir().mkpath(QStringLiteral("."))) {
    QTextStream(stderr) << "could not create launcher badge state directory\n";
    return 3;
  }

  QLockFile lock(stateFile + QStringLiteral(".lock"));
  lock.setStaleLockTime(10000);
  if (!lock.tryLock()) {
    QTextStream(stderr) << "launcher badge provider is already running\n";
    return 3;
  }

  // Never inherit authoritative state from a previous provider process. The
  // new provider publishes its own empty/fresh snapshot during start().
  if (QFile::exists(stateFile) && !QFile::remove(stateFile)) {
    QTextStream(stderr) << "could not remove stale launcher badge state\n";
    return 4;
  }

  LauncherBadgeProvider provider(stateFile);
  if (!provider.start()) return 5;
  return app.exec();
}
