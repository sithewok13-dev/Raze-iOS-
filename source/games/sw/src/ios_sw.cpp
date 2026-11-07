// Added: the iOS touch controls' part for Shadow Warrior (ios/IOSGame.h):
// the player's weapons for the weapon wheel, a pick from it, ITEM, the
// cheat's noclip and flying, and its ammo kept full.

#include "ns.h"
#include "build.h"
#include "names2.h"
#include "panel.h"
#include "game.h"
#include "misc.h"
#include "weapon.h"
#include "gameinput.h"
#include "../../../../ios/IOSGame.h"

BEGIN_SW_NS

// The wheel's weapons: the fists (0), the sword (13, sharing the fists'
// slot) and the shurikens up to the ripper heart (1..9)
static bool OnWheel(int w)
{
	return (w >= WPN_FIST && w <= WPN_HEART) || w == WPN_SWORD;
}

static bool IsMelee(int w)
{
	return w == WPN_FIST || w == WPN_SWORD;
}

static void Weapons(IOSTouchWeapons* pw)
{
	auto pp = getPlayer(myconnectindex);
	auto act = pp ? pp->GetActor() : nullptr;
	if (!act || !act->hasU()) return;
	pw->bValid = 1;
	pw->bCanSelect = !(pp->Flags & PF_DEAD) && pp->sop == nullptr && act->user.Health > 0;
	pw->iMap = IOSTOUCH_WHEEL_SW;
	int cur = act->user.WeaponNum;
	// (the guardian head's napalm and ring of fire are the head; the nuke, the missiles)
	if (cur == WPN_NAPALM || cur == WPN_RING) cur = WPN_HOTHEAD;
	if (cur == WPN_ROCKET) cur = WPN_MICRO;
	pw->iWanted = cur;
	for (int w = 0; w < IOSTOUCH_WPN_MAX; w++)
	{
		pw->aiAmmo[w] = pw->aiMaxAmmo[w] = -1;
		if (!OnWheel(w)) continue;
		// (the sword comes with the fists)
		const bool owned = (w == WPN_SWORD) ? (pp->WpnFlags & BIT(WPN_FIST)) != 0 : (pp->WpnFlags & BIT(w)) != 0;
		if (!owned) continue;
		pw->ulOwned |= 1u << w;
		if (IsMelee(w))
		{
			pw->ulReady |= 1u << w;
			continue;
		}
		pw->aiAmmo[w] = pp->WpnAmmo[w];
		pw->aiMaxAmmo[w] = DamageData[w].max_ammo;
		if (pp->WpnAmmo[w] > 0) pw->ulReady |= 1u << w;
	}
}

static void Pick(int w)
{
	auto pp = getPlayer(myconnectindex);
	auto act = pp ? pp->GetActor() : nullptr;
	if (!act || !act->hasU() || !OnWheel(w)) return;
	if (IsMelee(w))
	{
		// slot 1 is the fists or the sword, whichever came last (and in hand,
		// it switches to the other)
		const int cur = act->user.WeaponNum;
		if (cur == w) return;
		if (!IsMelee(cur)) pp->WpnFirstType = (uint8_t)w;
		gameInput.SendWeapon(1);
		return;
	}
	gameInput.SendWeapon(w + 1);
}

static void State(IOSTouchHud* pHud)
{
	auto pp = getPlayer(myconnectindex);
	if (!pp || !pp->GetActor()) return;
	pHud->iSecondary = IOSTOUCH_SEC_NONE;
	const int i = pp->InventoryNum;
	pHud->bItem = i >= 0 && i < MAX_INVENTORY && pp->InventoryAmount[i] > 0;
	pHud->bNoclip = (pp->Flags & PF_CLIP_CHEAT) != 0;
	pHud->bFlying = (pp->Flags & PF_FLYING) != 0;
	pHud->bCanFly = 1;
}

static void FillAmmo()
{
	auto pp = getPlayer(myconnectindex);
	auto act = pp ? pp->GetActor() : nullptr;
	if (!act || !act->hasU() || act->user.Health <= 0) return;
	for (int w = WPN_STAR; w <= WPN_HEART; w++)
	{
		if ((pp->WpnFlags & BIT(w)) && pp->WpnAmmo[w] < DamageData[w].max_ammo) pp->WpnAmmo[w] = DamageData[w].max_ammo;
	}
}

END_SW_NS

const IOSGamePart iosSWPart = { SW_NS::Weapons, SW_NS::Pick, nullptr, SW_NS::State, SW_NS::FillAmmo, false };
