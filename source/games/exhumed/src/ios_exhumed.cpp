// Added: the iOS touch controls' part for Exhumed / PowerSlave
// (ios/IOSGame.h): the player's weapons for the weapon wheel, a pick from
// it, ITEM and the cheat's noclip.

#include "ns.h"
#include "build.h"
#include "exhumed.h"
#include "names.h"
#include "engine.h"
#include "player.h"
#include "aistuff.h"
#include "gameinput.h"
#include "sound.h"
#include "../../../../ios/IOSGame.h"

BEGIN_PS_NS

static void Weapons(IOSTouchWeapons* pw)
{
	auto pPlayer = getPlayer(myconnectindex);
	if (!pPlayer || !pPlayer->GetActor()) return;
	pw->bValid = 1;
	pw->bCanSelect = pPlayer->nHealth > 0 && !pPlayer->bIsMummified;
	pw->iMap = IOSTOUCH_WHEEL_EXHUMED;
	pw->iWanted = pPlayer->nCurrentWeapon;
	for (int w = 0; w < IOSTOUCH_WPN_MAX; w++)
	{
		pw->aiAmmo[w] = pw->aiMaxAmmo[w] = -1;
		if (w >= kMaxWeapons || !(pPlayer->nPlayerWeapons & (1 << w))) continue;
		pw->ulOwned |= 1u << w;
		if (w == kWeaponSword)
		{
			pw->ulReady |= 1u << w;
			continue;
		}
		pw->aiAmmo[w] = pPlayer->nAmmo[w];
		if (pPlayer->nAmmo[w] > 0) pw->ulReady |= 1u << w;
	}
}

static void Pick(int w)
{
	// Exhumed's weapon slots are its weapon numbers + 1
	if (w >= 0 && w < kMaxWeapons) gameInput.SendWeapon(w + 1);
}

static void State(IOSTouchHud* pHud)
{
	auto pPlayer = getPlayer(myconnectindex);
	if (!pPlayer || !pPlayer->GetActor()) return;
	pHud->iSecondary = IOSTOUCH_SEC_NONE;
	pHud->bItem = pPlayer->nItem >= 0 && pPlayer->nItem < 8 && pPlayer->items[pPlayer->nItem] > 0;
	pHud->bNoclip = bSlipMode;
}

// The cheat's ammo kept full: as the game's own weapons cheat fills it (300)
static void FillAmmo()
{
	auto pPlayer = getPlayer(myconnectindex);
	if (!pPlayer || !pPlayer->GetActor() || pPlayer->nHealth <= 0) return;
	for (int w = 0; w < kMaxWeapons; w++)
	{
		if ((pPlayer->nPlayerWeapons & (1 << w)) && WeaponInfo[w].d && pPlayer->nAmmo[w] < 300) pPlayer->nAmmo[w] = 300;
	}
}

static bool Alive()
{
	auto pPlayer = getPlayer(myconnectindex);
	return pPlayer && pPlayer->GetActor() && pPlayer->nHealth > 0;
}

static bool GodOn()
{
	auto pPlayer = getPlayer(myconnectindex);
	return pPlayer && pPlayer->invincibility < 0;
}

// The wheel's pictures: the weapon pickups (the alternate HUD's weapon
// icons), the grenades' their ammo's; the machete and the ring of Ra have
// none (their names show)
static const char* const* Icon(int w)
{
	static const char* const list[][2] = {
		{ nullptr }, { "WeaponSpriteMagnum" }, { "WeaponSpriteM60" }, { "WeaponSpriteFlamethrower" }, { "AmmoSpriteGrenade" },
		{ "WeaponSpriteCobra" }, { nullptr },
	};
	return (w >= 0 && w < (int)countof(list) && list[w][0]) ? list[w] : nullptr;
}

// CHEAT: no picture of the game's (its drawn ankh)
static const char* const* CheatIcon()
{
	return nullptr;
}

// The game's own fanfare for a special item as the cheat comes on (its
// title screen's sound)
static void CheatSound()
{
	PlayLocalSound(StaticSound[kSoundItemSpecial], 0, false, CHANF_UI);
}

END_PS_NS

const IOSGamePart iosExhumedPart = { PS_NS::Weapons, PS_NS::Pick, nullptr, PS_NS::State, PS_NS::FillAmmo, true,
                                     PS_NS::Alive, PS_NS::GodOn, nullptr, PS_NS::Icon, PS_NS::CheatIcon, PS_NS::CheatSound };
