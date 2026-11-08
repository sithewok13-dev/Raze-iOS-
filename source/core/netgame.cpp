/*
** netgame.cpp: LAN games (added with the iOS port; the same on every platform)
**
** Raze has the GZDoom-style lockstep network (i_net.cpp, d_net.cpp: -host N
** and -join <address>, UDP port 5029), but the games were always set up as
** one player. This file:
**
** - sets the players up from the network once it is connected (numplayers,
**   myconnectindex, the connect chain) and lets the game set its own mode
**   variables (GameInterface::SetupNetGame),
** - starts every machine's game on the same tic: the host's new game (from
**   the game's own New Game menu, or -map) goes out as DEM_NETSTART with the
**   mode, the skill and the map; a guest's own new game waits for the host,
** - answers a LAN search (i_net.cpp asks Net_DiscoveryInfo),
** - for testing: net_checksums 1 prints a checksum of every actor's place
**   once a second, so two machines' logs show whether they stayed in step.
*/

#include "gamecontrol.h"
#include "gamestruct.h"
#include "d_net.h"
#include "d_protocol.h"
#include "c_cvars.h"
#include "c_dispatch.h"
#include "mapinfo.h"
#include "gamestate.h"
#include "printf.h"
#include "coreactor.h"
#include "coreplayer.h"
#include "netgame.h"
#include "i_net.h"
#include "startupinfo.h"
#include "i_protocol.h"
#include "menu.h"
#include "m_random.h"
#include "gamefuncs.h"
#include "maptypes.h"
#include "d_eventbase.h"
#include "keydef.h"

extern int gametic;

// The host's choice (set before the network starts: the iOS host screen, or
// +set net_mode N on a command line). The game's own mode number: see each
// game's SetupNetGame. Sent to everyone with the start of the game.
CVAR(Int, net_mode, 0, CVAR_NOSAVE)
// (the host's) players hurt each other in co-op
CVAR(Bool, net_ffire, false, CVAR_NOSAVE)
// (the host's) the console cheats for everyone: sv_cheats, which the host
// sends to the others as the game starts
CVAR(Bool, net_cheats, false, CVAR_NOSAVE)
EXTERN_CVAR(Bool, sv_cheats)

// Before the host sends its settings (D_CheckNetGame, after the saved
// network settings were read): the host's choice, not an old game's
void Net_HostSettings()
{
	if (doomcom.consoleplayer == 0) sv_cheats = (bool)net_cheats;
}
// (the rig) a checksum of the game's state every second in the log
CVAR(Int, net_checksums, 0, CVAR_NOSAVE)	// 1: once a second, 2: every tic, with the random seed

int netGameMode = -1;	// what the host sent (-1: single player)
int netGameFlags = 0;	// NETF_*

//---------------------------------------------------------------------------
//
// Once the network is connected (D_CheckNetGame): the players
//
//---------------------------------------------------------------------------

void Net_SetupPlayers()
{
	if (!netgame) return;
	numplayers = doomcom.numplayers;
	myconnectindex = doomcom.consoleplayer;
	connecthead = 0;
	for (int i = 0; i < MAXPLAYERS; i++)
		connectpoint2[i] = (i + 1 < numplayers) ? i + 1 : -1;
	netGameMode = net_mode;
	netGameFlags = net_ffire ? NETF_FRIENDLYFIRE : 0;
	gi->SetupNetGame(netGameMode, true);
	Printf("Network game: player %d of %d\n", myconnectindex + 1, numplayers);
}

//---------------------------------------------------------------------------
//
// The start of the game, on every machine on the same tic
//
//---------------------------------------------------------------------------

static void netStart(int player, TArrayView<uint8_t>& stream, bool skip)
{
	int mode = ReadInt8(stream);
	int flags = ReadInt8(stream);
	int skill = (int8_t)ReadInt8(stream);
	auto mapname = ReadStringConst(stream);
	if (skip) return;
	auto map = FindMapByName(mapname);
	if (!map)
	{
		Printf("Network game: the host's map %s is not here\n", mapname);
		return;
	}
	netGameMode = mode;
	netGameFlags = flags;
	gi->SetupNetGame(mode, false);
	Printf("Network game: starting %s, skill %d, mode %d\n", mapname, skill, mode);
	DeferredStartGame(map, skill);
}

void Net_InitCommands()
{
	Net_SetCommandHandler(DEM_NETSTART, netStart);
}

static FString pendingStart;
static int pendingSkill;

void Net_WritePending()
{
	if (pendingStart.IsEmpty() || gamestate == GS_STARTUP) return;
	Net_WriteByte(DEM_NETSTART);
	Net_WriteByte((uint8_t)netGameMode);
	Net_WriteByte((uint8_t)netGameFlags);
	Net_WriteByte((uint8_t)pendingSkill);
	Net_WriteString(pendingStart.GetChars());
	pendingStart = "";
}

// A new game (the menu or -map): in a network game only the host starts it,
// for everyone. Returns true when it was taken care of here.
bool Net_StartGame(MapRecord* map, int skill)
{
	if (!netgame) return false;
	if (myconnectindex != 0)
	{
		M_StartMessage("The host starts the game: wait for it here", 1, NAME_None);
		return true;
	}
	// (-1, "the skill already set", is this machine's own: everyone must
	// have the same, so it is the game's second, the usual one)
	if (skill < 0) skill = 1;
	// (sent with the next tic's commands: G_BuildTiccmd, Net_WritePending)
	Printf("Network game: sending the start (%s, skill %d)\n", map->labelName.GetChars(), skill);
	pendingStart = map->labelName;
	pendingSkill = skill;
	return true;
}

//---------------------------------------------------------------------------
//
// Each level of a network game starts every machine's random numbers from
// the same place: the screens between levels (and the menus) draw random
// numbers on each machine as it shows them, so they don't stay the same
//
//---------------------------------------------------------------------------

void Net_ResetRandom()
{
	if (!netgame) return;
	FRandom::StaticClearRandom();
	randomseed = 17;
	gi->ResetNetRandom();
}

//---------------------------------------------------------------------------
//
// The host's answer to a LAN search
//
//---------------------------------------------------------------------------

const char* Net_DiscoveryInfo(int present, int wanted)
{
	static FString info;
	FString game = GameStartupInfo.Name;
	game.ReplaceChars('|', '/');
	FString mode = gi->NetModeName(net_mode);
	info.Format("RAZE1|%s|%s|%d|%d", game.GetChars(), mode.GetChars(), present, wanted);
	return info.GetChars();
}

//---------------------------------------------------------------------------
//
// The rig: whether the machines stay in step
//
//---------------------------------------------------------------------------

void Net_LogChecksum()
{
	if (!net_checksums || !netgame || gamestate != GS_LEVEL || (net_checksums < 2 && (gametic % GameTicRate) != 0)) return;
	uint32_t sum = 0x12345, count = 0;
	auto mix = [&](double v) { sum = sum * 31 + (uint32_t)(int64_t)(v * 16); };
	TSpriteIterator<DCoreActor> it;
	while (auto ac = it.Next())
	{
		mix(ac->spr.pos.X); mix(ac->spr.pos.Y); mix(ac->spr.pos.Z);
		mix(ac->spr.Angles.Yaw.Degrees());
		sum = sum * 31 + ac->spr.statnum;
		sum = sum * 31 + ac->spr.extra;
		sum = sum * 31 + ac->spr.cstat;
		mix(ac->vel.X); mix(ac->vel.Z);
		count++;
	}
	FString players;
	for (int i = connecthead; i >= 0; i = connectpoint2[i])
	{
		auto act = PlayerArray[i] ? PlayerArray[i]->GetActor() : nullptr;
		if (act) players.AppendFormat(" p%d=%.0f,%.0f,%.0f/%d", i, act->spr.pos.X, act->spr.pos.Y, act->spr.pos.Z, act->spr.extra);
	}
	if (net_checksums >= 2)
	{
		// (the sectors and walls too)
		uint32_t ssum = 0;
		auto smix = [&](double v) { ssum = ssum * 31 + (uint32_t)(int64_t)(v * 16); };
		for (auto& sec : sector) { smix(sec.floorz); smix(sec.ceilingz); ssum = ssum * 31 + sec.lotag + sec.floorstat * 7 + sec.ceilingstat * 13; }
		for (auto& wal : wall) { smix(wal.pos.X); smix(wal.pos.Y); ssum = ssum * 31 + wal.cstat; }
		players.AppendFormat(" seed=%08x sect=%08x", randomseed, ssum);
	}
	if (net_checksums >= 3)
	{
		// (which kinds of actors: the class names and how many)
		TMap<FName, int> kinds;
		TSpriteIterator<DCoreActor> it2;
		while (auto ac = it2.Next()) { auto v = kinds.CheckKey(ac->GetClass()->TypeName); if (v) (*v)++; else kinds.Insert(ac->GetClass()->TypeName, 1); }
		TMap<FName, int>::Iterator ki(kinds);
		TMap<FName, int>::Pair* pair;
		while (ki.NextPair(pair)) players.AppendFormat(" %s:%d", pair->Key.GetChars(), pair->Value);
	}
	if (net_checksums >= 4)
	{
		// (every actor in the log, for a close look)
		TSpriteIterator<DCoreActor> it3;
		while (auto ac = it3.Next())
			Printf(PRINT_NONOTIFY, "NETACT %d %s %.3f,%.3f,%.3f o%.3f,%.3f,%.3f v%.3f,%.3f a%.2f s%d c%d x%d\n", gametic, ac->GetClass()->TypeName.GetChars(), ac->opos.X, ac->opos.Y, ac->opos.Z,
				ac->spr.pos.X, ac->spr.pos.Y, ac->spr.pos.Z, ac->vel.X, ac->vel.Z, ac->spr.Angles.Yaw.Degrees(), ac->spr.statnum, ac->spr.cstat, ac->spr.extra);
	}
	Printf(PRINT_NONOTIFY, "NETSUM tic %d %08x actors %u%s\n", gametic, sum, count, players.GetChars());
}

// (the rig) a key press, for screens that wait for one: net_presskey
CCMD(net_presskey)
{
	event_t ev = {};
	ev.type = EV_KeyDown;
	ev.data1 = KEY_SPACE;
	D_PostEvent(&ev);
	ev.type = EV_KeyUp;
	D_PostEvent(&ev);
}
