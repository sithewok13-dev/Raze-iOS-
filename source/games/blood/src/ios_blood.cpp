// Added: the iOS touch controls' part for Blood (ios/IOSGame.h): the
// player's weapons for the weapon wheel, a pick from it, ITEM, the cheat's
// noclip and its ammo kept full.

// (as the rest of Blood is built: games/blood/all.cpp)
#ifndef NOONE_EXTENSIONS
#define NOONE_EXTENSIONS
#endif

#include "ns.h"
#include "build.h"
#include "blood.h"
#include "bloodactor.h"
#include "gameinput.h"
#include "qav.h"
#include "../../../../ios/IOSGame.h"

BEGIN_BLD_NS

// A weapon's ammo type (weapon.cpp's weaponModes: the flare gun's is 1 up
// to the remote TNT's 11), -1 for the pitchfork
static int AmmoType(int w)
{
	return (w >= kWeapFlareGun && w <= kWeapRemote) ? w - 1 : -1;
}

static void Weapons(IOSTouchWeapons* pw)
{
	auto pPlayer = getPlayer(myconnectindex);
	auto act = pPlayer ? pPlayer->GetActor() : nullptr;
	if (!act) return;
	pw->bValid = 1;
	pw->bCanSelect = act->xspr.health > 0 && pPlayer->curWeapon != kWeapBeast;
	pw->iMap = IOSTOUCH_WHEEL_BLOOD;
	pw->iWanted = pPlayer->nextWeapon ? pPlayer->nextWeapon : pPlayer->curWeapon;
	for (int w = 0; w < IOSTOUCH_WPN_MAX && w < kWeapMax; w++)
	{
		pw->aiAmmo[w] = pw->aiMaxAmmo[w] = -1;
		if (w < kWeapPitchFork || w > kWeapRemote || !pPlayer->hasWeapon[w]) continue;
		pw->ulOwned |= 1u << w;
		const int t = AmmoType(w);
		if (t < 0)
		{
			pw->ulReady |= 1u << w;
			continue;
		}
		// (the spray can's counts in tenths, as the HUD shows it)
		const int div = (t == 6) ? 10 : 1;
		pw->aiAmmo[w] = pPlayer->ammoCount[t] / div;
		pw->aiMaxAmmo[w] = gAmmoInfo[t].max / div;
		if (pPlayer->ammoCount[t] > 0) pw->ulReady |= 1u << w;
	}
}

// A TNT pick from the proximity or remote TNT in hand: Blood's TNT slot steps
// through the three kinds from the one in hand (weapon.cpp), so it is pressed
// again (PickTick) until the TNT bundle is in hand
static int pending = -1, pendingFrames = 0, pendingWait = 0;

static void Pick(int w)
{
	pending = -1;
	// Blood's weapon slots are its weapon numbers
	if (w < kWeapPitchFork || w > kWeapRemote) return;
	gameInput.SendWeapon(w);
	if (w == kWeapDynamite)
	{
		pending = w;
		pendingFrames = 0;
		pendingWait = 20;
	}
}

static void PickTick()
{
	if (pending < 0) return;
	auto pPlayer = getPlayer(myconnectindex);
	if (!pPlayer || !pPlayer->GetActor() || ++pendingFrames > 240 || pPlayer->curWeapon == pending)
	{
		pending = -1;
		return;
	}
	if (pendingWait > 0)
	{
		pendingWait--;
		return;
	}
	// another kind of TNT came up, and nothing else is on its way: the slot again
	if ((pPlayer->curWeapon == kWeapProximity || pPlayer->curWeapon == kWeapRemote) && pPlayer->newWeapon == kWeapNone && pPlayer->nextWeapon == kWeapNone)
	{
		gameInput.SendWeapon(kWeapDynamite);
		pendingWait = 20;
	}
}

static void Reset()
{
	pending = -1;
}

static bool Alive()
{
	auto pPlayer = getPlayer(myconnectindex);
	return pPlayer && pPlayer->GetActor() && pPlayer->GetActor()->xspr.health > 0;
}

static bool GodOn()
{
	auto pPlayer = getPlayer(myconnectindex);
	return pPlayer && pPlayer->godMode;
}

static void State(IOSTouchHud* pHud)
{
	auto pPlayer = getPlayer(myconnectindex);
	if (!pPlayer || !pPlayer->GetActor()) return;
	pHud->iSecondary = IOSTOUCH_SEC_ALTFIRE;
	const int i = pPlayer->packItemId;
	pHud->bItem = i >= 0 && i < 5 && pPlayer->packSlots[i].curAmount > 0;
	pHud->bNoclip = gNoClip;
}

static void FillAmmo()
{
	auto pPlayer = getPlayer(myconnectindex);
	if (!pPlayer || !pPlayer->GetActor() || pPlayer->GetActor()->xspr.health <= 0) return;
	for (int w = kWeapFlareGun; w <= kWeapRemote; w++)
	{
		const int t = AmmoType(w);
		if (pPlayer->hasWeapon[w] && t >= 0 && pPlayer->ammoCount[t] < gAmmoInfo[t].max) pPlayer->ammoCount[t] = gAmmoInfo[t].max;
	}
}

// The wheel's pictures: each weapon's pickup sprite (the game's own table
// of them; the proximity and remote bombs' from their ammo's), the
// pitchfork's from the HUD
static const char* const* Icon(int w)
{
	static char names[IOSTOUCH_WPN_MAX][16];
	static const char* lists[IOSTOUCH_WPN_MAX][2];
	if (w < 0 || w >= IOSTOUCH_WPN_MAX) return nullptr;
	int pic = -1;
	for (int i = 0; i < kItemWeaponMax - kItemWeaponBase && pic < 0; i++)
		if (gWeaponItemData[i].type == w && gWeaponItemData[i].picno > 0) pic = gWeaponItemData[i].picno;
	for (int i = 0; i < kItemAmmoMax - kItemAmmoBase && pic < 0; i++)
		if (gAmmoItemData[i].weaponType == w && gAmmoItemData[i].picno > 0) pic = gAmmoItemData[i].picno;
	// (the pitchfork: the biggest picture of its HUD's first frame held)
	if (pic < 0 && w == kWeapPitchFork)
	{
		auto qav = getQAV(kQAVFORKIDLE);
		int area = 0;
		for (int t = 0; qav && qav->nFrames > 0 && t < 8; t++)
		{
			auto tex = TexMan.GetGameTexture(qav->frames[0].tiles[t].texid);
			if (!tex || !tex->isValid()) continue;
			const int a = tex->GetTexelWidth() * tex->GetTexelHeight();
			if (a > area)
			{
				area = a;
				pic = legacyTileNum(qav->frames[0].tiles[t].texid);
			}
		}
	}
	if (pic < 0) return nullptr;
	snprintf(names[w], sizeof(names[w]), "#%d", pic);
	lists[w][0] = names[w];
	lists[w][1] = nullptr;
	return lists[w];
}

// CHEAT: the trapped soul (the life leech's ammo: a skull in a blue orb),
// else the skull key
static const char* const* CheatIcon()
{
	static const char* const list[] = { "#820", "KeyIcon1", nullptr };
	return list;
}

// Caleb's line as the cheat comes on: one of those he has for blowing
// something to pieces (the game's own list, gPlayerGibThingComments)
static void CheatSound()
{
	static const int lines[] = { 734, 735, 736, 737, 738, 739, 740, 741, 3038, 3049 };
	// channel 2, as the game's own lines for Caleb: replaces only an earlier
	// line (with -1 it would stop every unpositioned sound playing)
	sndStartSample(lines[rand() % countof(lines)], 255, 2, false, CHANF_UI);
}

END_BLD_NS

const IOSGamePart iosBloodPart = { BLD_NS::Weapons, BLD_NS::Pick, BLD_NS::PickTick, BLD_NS::State, BLD_NS::FillAmmo, true,
                                   BLD_NS::Alive, BLD_NS::GodOn, BLD_NS::Reset, BLD_NS::Icon, BLD_NS::CheatIcon, BLD_NS::CheatSound };
