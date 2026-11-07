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

static void Pick(int w)
{
	// Blood's weapon slots are its weapon numbers
	if (w >= kWeapPitchFork && w <= kWeapRemote) gameInput.SendWeapon(w);
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

END_BLD_NS

const IOSGamePart iosBloodPart = { BLD_NS::Weapons, BLD_NS::Pick, nullptr, BLD_NS::State, BLD_NS::FillAmmo, true };
