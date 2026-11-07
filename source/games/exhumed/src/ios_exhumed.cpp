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

END_PS_NS

const IOSGamePart iosExhumedPart = { PS_NS::Weapons, PS_NS::Pick, nullptr, PS_NS::State, nullptr, true };
