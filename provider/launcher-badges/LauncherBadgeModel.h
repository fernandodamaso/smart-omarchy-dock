#pragma once

#include <cstdint>
#include <map>
#include <optional>
#include <string>

namespace smartdock::launcherbadges {

struct Entry {
  std::string sender;
  std::optional<std::int64_t> count;
  std::optional<bool> visible;
};

class LauncherBadgeModel {
 public:
  using Entries = std::map<std::string, Entry>;

  static std::optional<std::string> normalizeLauncherIdentity(
      const std::string& value);

  bool applyUpdate(const std::string& launcherUri,
                   const std::string& sender,
                   std::optional<std::int64_t> count,
                   std::optional<bool> visible);
  bool removeSender(const std::string& sender);

  const Entries& entries() const { return entries_; }
  const Entry* entry(const std::string& desktopId) const;

 private:
  Entries entries_;
};

}  // namespace smartdock::launcherbadges
