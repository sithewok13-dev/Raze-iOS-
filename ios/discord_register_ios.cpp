// iOS: there's no Discord app to register a launch command with.
#include "discord_register.h"

extern "C" {
void Discord_Register(const char*, const char*) {}
void Discord_RegisterSteamGame(const char*, const char*) {}
}
