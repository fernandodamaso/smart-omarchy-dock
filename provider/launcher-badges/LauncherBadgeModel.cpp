#include "LauncherBadgeModel.h"

#include <algorithm>
#include <cctype>
#include <limits>

namespace smartdock::launcherbadges {
namespace {

std::string trim(std::string value) {
  auto first = std::find_if_not(value.begin(), value.end(), [](unsigned char ch) {
    return std::isspace(ch) != 0;
  });
  auto last = std::find_if_not(value.rbegin(), value.rend(), [](unsigned char ch) {
    return std::isspace(ch) != 0;
  }).base();
  if (first >= last) return {};
  return std::string(first, last);
}

bool startsWithApplicationScheme(const std::string& value) {
  constexpr char kPrefix[] = "application://";
  if (value.size() < sizeof(kPrefix) - 1) return false;
  for (std::size_t i = 0; i < sizeof(kPrefix) - 1; ++i) {
    if (std::tolower(static_cast<unsigned char>(value[i])) != kPrefix[i])
      return false;
  }
  return true;
}

int hexValue(char ch) {
  if (ch >= '0' && ch <= '9') return ch - '0';
  ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
  if (ch >= 'a' && ch <= 'f') return ch - 'a' + 10;
  return -1;
}

std::optional<std::string> percentDecode(const std::string& value) {
  std::string result;
  result.reserve(value.size());
  for (std::size_t i = 0; i < value.size(); ++i) {
    if (value[i] != '%') {
      result.push_back(value[i]);
      continue;
    }
    if (i + 2 >= value.size()) return std::nullopt;
    const int high = hexValue(value[i + 1]);
    const int low = hexValue(value[i + 2]);
    if (high < 0 || low < 0) return std::nullopt;
    result.push_back(static_cast<char>((high << 4) | low));
    i += 2;
  }
  return result;
}

std::optional<std::string> canonicalDesktopId(const std::string& value) {
  std::string normalized = trim(value);
  if (startsWithApplicationScheme(normalized)) return std::nullopt;
  auto decoded = percentDecode(normalized);
  if (!decoded) return std::nullopt;
  normalized = trim(*decoded);
  if (normalized.empty() || normalized == "." || normalized == ".."
      || normalized.find("://") != std::string::npos
      || normalized.find('/') != std::string::npos
      || normalized.find('\\') != std::string::npos) {
    return std::nullopt;
  }
  std::transform(normalized.begin(), normalized.end(), normalized.begin(),
                 [](unsigned char ch) {
                   return static_cast<char>(std::tolower(ch));
                 });
  return normalized;
}

}  // namespace

std::optional<std::string> LauncherBadgeModel::normalizeLauncherIdentity(
    const std::string& value) {
  std::string normalized = trim(value);
  if (startsWithApplicationScheme(normalized))
    normalized.erase(0, std::string("application://").size());

  auto decoded = percentDecode(normalized);
  if (!decoded) return std::nullopt;
  normalized = trim(*decoded);

  if (normalized.empty() || normalized == "." || normalized == ".."
      || normalized.find("://") != std::string::npos
      || normalized.find('/') != std::string::npos
      || normalized.find('\\') != std::string::npos) {
    return std::nullopt;
  }

  std::transform(normalized.begin(), normalized.end(), normalized.begin(),
                 [](unsigned char ch) {
                   return static_cast<char>(std::tolower(ch));
                 });

  constexpr char kDesktopSuffix[] = ".desktop";
  if (normalized.size() >= sizeof(kDesktopSuffix) - 1
      && normalized.compare(normalized.size() - (sizeof(kDesktopSuffix) - 1),
                            sizeof(kDesktopSuffix) - 1,
                            kDesktopSuffix) == 0) {
    normalized.erase(normalized.size() - (sizeof(kDesktopSuffix) - 1));
  }

  if (normalized.empty() || normalized == "." || normalized == "..")
    return std::nullopt;
  return normalized;
}

bool LauncherBadgeModel::applyUpdate(
    const std::string& launcherUri,
    const std::string& sender,
    std::optional<std::int64_t> count,
    std::optional<bool> visible) {
  const auto id = normalizeLauncherIdentity(launcherUri);
  if (!id || sender.empty() || (!count && !visible)) return false;

  if (count) *count = std::max<std::int64_t>(0, *count);

  auto found = entries_.find(*id);
  bool changed = false;
  if (found == entries_.end() || found->second.sender != sender) {
    Entry fresh;
    fresh.sender = sender;
    found = entries_.insert_or_assign(*id, std::move(fresh)).first;
    changed = true;
  }

  if (count && found->second.count != count) {
    found->second.count = count;
    changed = true;
  }
  if (visible && found->second.visible != visible) {
    found->second.visible = visible;
    changed = true;
  }
  return changed;
}

bool LauncherBadgeModel::removeSender(const std::string& sender) {
  if (sender.empty()) return false;
  bool changed = false;
  for (auto it = entries_.begin(); it != entries_.end();) {
    if (it->second.sender == sender) {
      it = entries_.erase(it);
      changed = true;
    } else {
      ++it;
    }
  }
  return changed;
}

const Entry* LauncherBadgeModel::entry(const std::string& desktopId) const {
  // Prefer the exact canonical desktop ID so IDs that themselves end in
  // `.desktop` are not shortened. Fall back to storage-filename normalization
  // for callers that pass `foo.desktop` instead of canonical `foo`.
  if (const auto exact = canonicalDesktopId(desktopId)) {
    const auto found = entries_.find(*exact);
    if (found != entries_.end()) return &found->second;
  }

  const auto storageId = normalizeLauncherIdentity(desktopId);
  if (!storageId) return nullptr;
  const auto found = entries_.find(*storageId);
  return found == entries_.end() ? nullptr : &found->second;
}

}  // namespace smartdock::launcherbadges
