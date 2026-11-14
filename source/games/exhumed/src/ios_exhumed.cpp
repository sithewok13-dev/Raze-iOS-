// Added: the iOS touch controls' part for Exhumed / PowerSlave
// (ios/IOSGame.h): the player's weapons for the weapon wheel, a pick from
// it, the item buttons and the cheat's noclip.

#include "ns.h"
#include "build.h"
#include "exhumed.h"
#include "names.h"
#include "engine.h"
#include "player.h"
#include "aistuff.h"
#include "gameinput.h"
#include "sound.h"
#include "sequence.h"
#include "texturemanager.h"
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
	pHud->bNoclip = bSlipMode;
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

// The item buttons: the heart (dimmed at full health), scarab, torch, hand,
// eye and Sobek mask, each a count (up to 5), dimmed without the mana it
// takes, glowing while its effect runs
static void Items(IOSTouchItems* pi)
{
	auto pPlayer = getPlayer(myconnectindex);
	if (!pPlayer || !pPlayer->GetActor()) return;
	const bool running[6] = { false, pPlayer->invincibility > 0, pPlayer->nTorch > 0, pPlayer->nDouble > 0, pPlayer->nInvisible > 0,
	                          pPlayer->nMaskAmount > 0 };
	for (int i = 0; i < 6; i++)
	{
		if (pPlayer->items[i] <= 0) continue;
		bool dim = nItemMagic[i] > pPlayer->nMagic;
		if (i == 0 && pPlayer->nHealth >= kMaxHealth) dim = true;
		AddItem(pi, i + 1, IOSTOUCH_ITEM_COUNT, 0, pPlayer->items[i], running[i], dim);
	}
}

// ...their pictures: the status bar's (the item shown on the magic pool)
static const char* const* ItemIcon(int iUse)
{
	static const int seqOf[] = { 91, 72, 76, 79, 68, 87 };
	static FString names[6];
	static const char* list[2] = { nullptr, nullptr };
	if (iUse < 1 || iUse > 6) return nullptr;
	auto seq = getSequence("status", seqOf[iUse - 1]);
	if (!seq || seq->frames.Size() == 0) return nullptr;
	auto tex = TexMan.GetGameTexture(seq->getFirstFrameTexture());
	if (!tex) return nullptr;
	names[iUse - 1] = tex->GetName();
	list[0] = names[iUse - 1].GetChars();
	return list;
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

#ifndef RAZE_IOS
// The Linux test rig's: the player's items, for its log (ITEM)
CCMD(ios_riginv_exhumed)
{
	auto pPlayer = getPlayer(myconnectindex);
	if (!pPlayer || !pPlayer->GetActor()) return;
	FString s;
	for (int i = 0; i < 8; i++) s.AppendFormat(" %d:%d", i, pPlayer->items[i]);
	Printf("riginv item %d health %d%s\n", pPlayer->nItem, pPlayer->nHealth, s.GetChars());
}
#endif

END_PS_NS

const IOSGamePart iosExhumedPart = { PS_NS::Weapons, PS_NS::Pick, nullptr, PS_NS::State, PS_NS::FillAmmo, true,
                                     PS_NS::Alive, PS_NS::GodOn, nullptr, PS_NS::Icon, PS_NS::CheatIcon, PS_NS::CheatSound,
                                     PS_NS::Items, PS_NS::ItemIcon };
