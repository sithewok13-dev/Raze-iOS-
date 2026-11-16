#pragma once
// LAN games (netgame.cpp)
struct MapRecord;
extern int netGameMode;	// the mode the host sent (-1: single player)
extern int netGameFlags;	// what else the host sent:
enum { NETF_FRIENDLYFIRE = 1 };	// players hurt each other in co-op
void Net_SetupPlayers();
void Net_HostSettings();
void Net_InitCommands();
bool Net_StartGame(MapRecord* map, int skill);
void Net_LogStatus(); // (Added: iOS LAN games: the log every 5 s)
void Net_LogChecksum();
void Net_WritePending();
void Net_ResetRandom();
