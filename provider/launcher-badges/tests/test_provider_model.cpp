#include "LauncherBadgeModel.h"

#include <cassert>
#include <cstdint>
#include <iostream>

using smartdock::launcherbadges::LauncherBadgeModel;

int main() {
  const auto discord = LauncherBadgeModel::normalizeLauncherIdentity(
      " application://Com.DiscordApp.Discord.desktop ");
  assert(discord && *discord == "com.discordapp.discord");
  const auto encoded = LauncherBadgeModel::normalizeLauncherIdentity(
      "application://My%20App.desktop");
  assert(encoded && *encoded == "my app");
  const auto terminalDesktop = LauncherBadgeModel::normalizeLauncherIdentity(
      "application://org.telegram.desktop.desktop");
  assert(terminalDesktop && *terminalDesktop == "org.telegram.desktop");
  assert(!LauncherBadgeModel::normalizeLauncherIdentity(
      "https://example.test/app.desktop"));
  assert(!LauncherBadgeModel::normalizeLauncherIdentity(
      "application://../bad.desktop"));
  assert(!LauncherBadgeModel::normalizeLauncherIdentity(
      "application://foo\\bar.desktop"));
  assert(!LauncherBadgeModel::normalizeLauncherIdentity(
      "application://%ZZ.desktop"));

  LauncherBadgeModel model;
  assert(model.applyUpdate("application://org.telegram.desktop.desktop",
                           ":1.9", 101, true));
  const auto* entry = model.entry("org.telegram.desktop");
  assert(entry && entry->count && *entry->count == 101);

  assert(model.applyUpdate("application://com.discordapp.Discord.desktop",
                           ":1.10", 4, true));
  entry = model.entry("com.discordapp.discord");
  assert(entry && entry->count && *entry->count == 4);
  assert(entry->visible && *entry->visible);

  // Partial hide preserves the last authoritative count.
  assert(model.applyUpdate("com.discordapp.Discord.desktop",
                           ":1.10", std::nullopt, false));
  entry = model.entry("com.discordapp.Discord");
  assert(entry && entry->count && *entry->count == 4);
  assert(entry->visible && !*entry->visible);

  // Partial count update preserves visibility.
  assert(model.applyUpdate("com.discordapp.Discord.desktop",
                           ":1.10", 8, std::nullopt));
  entry = model.entry("com.discordapp.Discord");
  assert(entry && entry->count && *entry->count == 8);
  assert(entry->visible && !*entry->visible);

  // Explicit zero is authoritative and distinct from an absent count.
  assert(model.applyUpdate("com.discordapp.Discord.desktop",
                           ":1.10", 0, true));
  entry = model.entry("com.discordapp.Discord");
  assert(entry && entry->count && *entry->count == 0);
  assert(entry->visible && *entry->visible);

  // Unknown but syntactically valid launchers remain provider-neutral state.
  assert(model.applyUpdate("application://org.example.Unknown.desktop",
                           ":1.11", 3, true));
  assert(model.entry("org.example.unknown") != nullptr);

  // A new sender owns a fresh record so stale fields never cross reconnects.
  assert(model.applyUpdate("application://com.discordapp.Discord.desktop",
                           ":1.12", std::nullopt, true));
  entry = model.entry("com.discordapp.Discord");
  assert(entry && !entry->count.has_value());
  assert(entry->visible && *entry->visible);

  // Sender loss clears only state owned by that sender.
  assert(model.removeSender(":1.12"));
  assert(model.entry("com.discordapp.Discord") == nullptr);
  assert(model.entry("org.example.Unknown") != nullptr);

  // Reconnect can establish fresh authoritative state.
  assert(model.applyUpdate("application://com.discordapp.Discord.desktop",
                           ":1.20", 11, true));
  entry = model.entry("com.discordapp.Discord");
  assert(entry && entry->count && *entry->count == 11);

  // Malformed/empty updates are ignored.
  assert(!model.applyUpdate("application://../bad.desktop", ":1.20", 99, true));
  assert(!model.applyUpdate("application://com.example.App.desktop", "", 1, true));
  assert(!model.applyUpdate("application://com.example.App.desktop",
                            ":1.20", std::nullopt, std::nullopt));

  std::cout << "launcher badge provider model tests: PASS\n";
  return 0;
}
