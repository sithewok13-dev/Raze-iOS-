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
		if (!IsMelee(cur) && !netgame) pp->WpnFirstType = (uint8_t)w; // (single player: this isn't sent over the network)
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
	pHud->bNoclip = (pp->Flags & PF_CLIP_CHEAT) != 0;
	pHud->bFlying = (pp->Flags & PF_FLYING) != 0;
	pHud->bCanFly = 1;
}

// (an item button: its useitem number, a charge (0..1) or a count, on, dimmed)
static void AddItem(IOSTouchItems* pi, int iUse, int iKind, double fCharge, int iCount, bool bOn, bool bDim)
{
	if (pi->ctItems >= IOSTOUCH_ITEM_MAX) return;
	IOSTouchItem& it = pi->aItems[pi->ctItems++];
	it.iUse = iUse;
	it.iKind = iKind;
	it.fCharge = (float)clamp(fCharge, 0.0, 1.0);
	it.iCount = iCount;
	it.bOn = bOn;
	it.bDim = bDim;
}

// The item buttons: the medkit (dimmed at full health), the smoke bomb
// (running: it can't be stopped), night vision (on and off), each its
// charge; the gas bomb, flash bombs and caltrops, counts. The repair kit
// works by itself: no button.
static void Items(IOSTouchItems* pi)
{
	auto pp = getPlayer(myconnectindex);
	auto act = pp ? pp->GetActor() : nullptr;
	if (!act || !act->hasU()) return;
	const bool climbing = (pp->Flags & PF_CLIMBING) != 0;
	for (int i = 0; i < MAX_INVENTORY; i++)
	{
		if (i == INVENTORY_REPAIR_KIT || pp->InventoryAmount[i] <= 0) continue;
		const bool count = (InventoryData[i].Flags & INVF_COUNT) != 0;
		const bool on = pp->InventoryActive[i];
		bool dim = climbing;
		if (i == INVENTORY_MEDKIT && act->user.Health >= 100) dim = true;
		if (i == INVENTORY_CLOAK && on) dim = false; // (running: it glows)
		AddItem(pi, i + 1, count ? IOSTOUCH_ITEM_COUNT : IOSTOUCH_ITEM_CHARGE, pp->InventoryPercent[i] / 100.0,
		        pp->InventoryAmount[i], on, dim);
	}
}

// ...their pictures: the status bar's inventory icons
static const char* const* ItemIcon(int iUse)
{
	static const char* const icons[][2] = { { "PanelMedkit" }, { "PanelRepairKit" }, { "PanelCloak" }, { "PanelNightVision" },
	                                        { "PanelChemBomb" }, { "PanelFlashBomb" }, { "PanelCaltrops" } };
	return (iUse >= 1 && iUse <= 7) ? icons[iUse - 1] : nullptr;
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

static bool Alive()
{
	auto pp = getPlayer(myconnectindex);
	auto act = pp ? pp->GetActor() : nullptr;
	return act && act->hasU() && !(pp->Flags & PF_DEAD) && act->user.Health > 0;
}

static bool GodOn()
{
	return GodMode != 0;
}

// The wheel's pictures: the pickup sprites (the alternate HUD's weapon
// icons); the fists and the sword the HUD's own
static const char* const* Icon(int w)
{
	static const char* const list[][3] = {
		{ "FIST_REST" }, { "ICON_STAR" }, { "ICON_SHOTGUN" }, { "ICON_UZI" }, { "ICON_MICRO_GUN" }, { "ICON_GRENADE_LAUNCHER" },
		{ "ICON_LG_MINE" }, { "ICON_RAIL_GUN" }, { "ICON_GUARD_HEAD" }, { "ICON_HEART" }, { nullptr }, { nullptr }, { nullptr },
		{ "SWORD_REST" },
	};
	return (w >= 0 && w < (int)countof(list) && list[w][0]) ? list[w] : nullptr;
}

// CHEAT: the fortune cookie
static const char* const* CheatIcon()
{
	static const char* const list[] = { "ICON_BOOSTER", nullptr };
	return list;
}

// Lo Wang's line as the cheat comes on: "Who wants some Wang?" or "No mess
// with Wang"
static void CheatSound()
{
	static const int lines[] = { DIGI_WHOWANTSWANG, DIGI_NOMESSWITHWANG };
	PlaySound(lines[rand() % countof(lines)], v3df_none, CHAN_VOICE, CHANF_UI);
}

#ifndef RAZE_IOS
// The Linux test rig's: the player's items, for its log (ITEM)
CCMD(ios_riginv_sw)
{
	auto pp = getPlayer(myconnectindex);
	if (!pp || !pp->GetActor()) return;
	FString s;
	for (int i = 0; i < MAX_INVENTORY; i++) s.AppendFormat(" %d:%d/%d%s", i, pp->InventoryAmount[i], pp->InventoryPercent[i], pp->InventoryActive[i] ? "on" : "");
	Printf("riginv item %d health %d%s\n", pp->InventoryNum, pp->GetActor()->user.Health, s.GetChars());
}
#endif

END_SW_NS

const IOSGamePart iosSWPart = { SW_NS::Weapons, SW_NS::Pick, nullptr, SW_NS::State, SW_NS::FillAmmo, false,
                                SW_NS::Alive, SW_NS::GodOn, nullptr, SW_NS::Icon, SW_NS::CheatIcon, SW_NS::CheatSound,
                                SW_NS::Items, SW_NS::ItemIcon };
