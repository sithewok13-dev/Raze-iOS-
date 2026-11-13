// Added: the iOS touch controls' part for Duke Nukem 3D and Redneck Rampage
// (ios/IOSGame.h): the player's weapons for the weapon wheel, a pick from
// it, ITEM, the cheat's noclip and its ammo kept full.

#include "ns.h"
#include "duke3d.h"
#include "gameinput.h"
#include "../../../../ios/IOSGame.h"

BEGIN_DUKE_NS

// A weapon's alternate shares its slot with it (Duke's shrinker and
// expander, freezethrower and incinerator; Redneck Rampage's ripsaw and
// buzzsaw, powder keg and bowling ball, and in Rides Again the crowbar and
// the sling blade, the crossbow and the chicken bow): the base of each, or
// the weapon itself
static int BaseOf(int w)
{
	if (!isRR())
	{
		if (w == GROW_WEAPON) return SHRINKER_WEAPON;
		if (w == FLAMETHROWER_WEAPON) return FREEZE_WEAPON;
		return w;
	}
	if (w == BUZZSAW_WEAPON) return THROWSAW_WEAPON;
	if (w == BOWLING_WEAPON) return POWDERKEG_WEAPON;
	if (w == SLINGBLADE_WEAPON) return KNEE_WEAPON;
	if (w == CHICKEN_WEAPON) return CROSSBOW_WEAPON;
	return w;
}

static bool IsMelee(int w)
{
	return w == KNEE_WEAPON || (isRR() && w == SLINGBLADE_WEAPON);
}

// The weapon in hand as the wheel names it (the pipe bomb's detonator is the
// pipe bomb, Redneck Rampage's lit dynamite the dynamite)
static int InHand(DDukePlayer* p)
{
	int w = p->curr_weapon;
	if (!isRR() && w == HANDREMOTE_WEAPON) w = HANDBOMB_WEAPON;
	if (isRR() && w == THROWINGDYNAMITE_WEAPON) w = DYNAMITE_WEAPON;
	return w;
}

static void Weapons(IOSTouchWeapons* pw)
{
	auto p = getPlayer(myconnectindex);
	auto act = p ? p->GetActor() : nullptr;
	if (!act) return;
	pw->bValid = 1;
	pw->bCanSelect = act->spr.extra > 0 && p->newOwner == nullptr && !(isRR() && (p->OnMotorcycle || p->OnBoat));
	pw->iMap = isRR() ? (isRRRA() ? IOSTOUCH_WHEEL_RRRA : IOSTOUCH_WHEEL_RR)
	                  : (isWorldTour() ? IOSTOUCH_WHEEL_DUKEWT : IOSTOUCH_WHEEL_DUKE);
	pw->iWanted = InHand(p);
	for (int w = 0; w < IOSTOUCH_WPN_MAX && w < MAX_WEAPONS; w++)
	{
		pw->aiAmmo[w] = pw->aiMaxAmmo[w] = -1;
		if (!p->gotweapon[w]) continue;
		pw->ulOwned |= 1u << w;
		if (IsMelee(w))
		{
			pw->ulReady |= 1u << w;
			continue;
		}
		pw->aiAmmo[w] = p->ammo_amount[w];
		pw->aiMaxAmmo[w] = gs.max_ammo_amount[w];
		if (p->ammo_amount[w] > 0) pw->ulReady |= 1u << w;
	}
	// (the expander shows only with the Atomic Edition's weapons, the
	// incinerator with World Tour's: their maps)
}

// A pick that needs a second step: the alternate, once its base is in hand
static int pending = -1, pendingFrames = 0, pendingWait = 0;

static void Pick(int w)
{
	auto p = getPlayer(myconnectindex);
	if (!p || !p->GetActor() || w < 0 || w >= MAX_WEAPONS) return;
	const int cur = InHand(p);
	const int base = BaseOf(w);
	pending = -1;
	if (cur == w) return;
	if (BaseOf(cur) == base)
	{
		// the other one of the pair is in hand: its alternate
		gameInput.SendWeapon(WeaponSel_Alt);
		return;
	}
	// the pair's slot (the game may come up with either of the two: the
	// one wanted is put in hand next, PickTick)
	gameInput.SendWeapon(base + 1);
	pending = w;
	pendingFrames = 0;
	pendingWait = 0;
}

static void PickTick()
{
	if (pending < 0) return;
	auto p = getPlayer(myconnectindex);
	if (!p || !p->GetActor() || ++pendingFrames > 240)
	{
		pending = -1;
		return;
	}
	const int cur = InHand(p);
	if (cur == pending)
	{
		pending = -1;
		return;
	}
	if (pendingWait > 0)
	{
		pendingWait--;
		return;
	}
	// the other one of the pair came up, raised and still: its alternate
	if (BaseOf(cur) == BaseOf(pending) && p->weapon_pos == 0 && p->kickback_pic == 0)
	{
		gameInput.SendWeapon(WeaponSel_Alt);
		pendingWait = 20; // (frames, for the switch to start)
	}
}

static void State(IOSTouchHud* pHud)
{
	auto p = getPlayer(myconnectindex);
	if (!p || !p->GetActor()) return;
	pHud->iSecondary = isRR() ? IOSTOUCH_SEC_NONE : IOSTOUCH_SEC_KICK;
	// ITEM: the item the HUD shows. With items but none chosen (after a
	// cheat gave them all) one is chosen, as the game does when one runs out.
	const bool bAny = p->firstaid_amount > 0 || p->steroids_amount > 0 || p->holoduke_amount > 0 || p->jetpack_amount > 0
	                  || p->heat_amount > 0 || p->scuba_amount > 0 || p->boot_amount > 0;
	if (bAny && p->inven_icon == ICON_NONE && !paused && !netgame) checkavailinven(p);
	pHud->bItem = p->inven_icon > ICON_NONE;
	pHud->bNoclip = ud.clipping != 0;
	pHud->bCanFly = 0;
	pHud->bFlying = 0;
}

static void FillAmmo()
{
	auto p = getPlayer(myconnectindex);
	if (!p || !p->GetActor() || p->GetActor()->spr.extra <= 0) return;
	for (int w = 0; w < MAX_WEAPONS; w++)
	{
		// (not the detonator / lit dynamite, nor Rides Again's motorcycle and boat)
		if (w == HANDREMOTE_WEAPON || (isRR() && (w == MOTORCYCLE_WEAPON || w == BOAT_WEAPON))) continue;
		if (p->gotweapon[w] && !IsMelee(w) && p->ammo_amount[w] < gs.max_ammo_amount[w]) p->ammo_amount[w] = gs.max_ammo_amount[w];
	}
}

static void Reset()
{
	pending = -1;
}

static bool Alive()
{
	auto p = getPlayer(myconnectindex);
	return p && p->GetActor() && p->GetActor()->spr.extra > 0;
}

static bool GodOn()
{
	return ud.god != 0;
}

// The wheel's pictures: the pickup sprites (the alternate HUD's weapon
// icons; the buzzsaw's its saw blades, the chicken bow's its chicken
// arrows), the HUD's own picture where a weapon has no pickup (the foot,
// the crowbar, the sling blade)
static const char* const* Icon(int w)
{
	static const char* const duke[][3] = {
		{ "KNEE" }, { "FIRSTGUNSPRITE" }, { "SHOTGUNSPRITE" }, { "CHAINGUNSPRITE" }, { "RPGSPRITE" }, { "HEAVYHBOMB" },
		{ "SHRINKERSPRITE" }, { "DEVISTATORSPRITE" }, { "TRIPBOMBSPRITE" }, { "FREEZESPRITE" }, { nullptr },
		{ "GROWSPRITEICON" }, { "FLAMETHROWERSPRITE" },
	};
	static const char* const rr[][3] = {
		{ "CROWBAR" }, { "FIRSTGUNSPRITE" }, { "SHOTGUNSPRITE" }, { "RIFLEGUNSPRITE" }, { "DYNAMITE" }, { "CROSSBOWSPRITE" },
		{ "RIPSAWSPRITE" }, { "ALIENBLASTERSPRITE" }, { "POWDERKEG" }, { "TITSPRITE" }, { nullptr },
		{ "SAWAMMO" }, { "BOWLINGBALLSPRITE" }, { nullptr }, { nullptr }, { "SLINGBLADE" }, { "RPG2SPRITE", "CBOW2GUN" },
	};
	if (isRR()) return (w >= 0 && w < (int)countof(rr) && rr[w][0]) ? rr[w] : nullptr;
	return (w >= 0 && w < (int)countof(duke) && duke[w][0]) ? duke[w] : nullptr;
}

// CHEAT: Duke's nuke button (the radiation sign), Redneck Rampage's
// moonshine
static const char* const* CheatIcon()
{
	static const char* const duke[] = { "NUKEBUTTON", "ATOMICHEALTH", nullptr };
	static const char* const rr[] = { "MOONSHINE_ICON", "WHISKEY_ICON", nullptr };
	return isRR() ? rr : duke;
}

// The hero's line as the cheat comes on (the game's own sounds, by their
// numbers in the game's DEFS.CON): Duke's "Hail to the king, baby",
// "Come get some", "Groovy", "Let's rock"; Leonard's "Yeehaw" and "Hot
// damn"
static void CheatSound()
{
	static const int duke[] = { DUKE_GETWEAPON6, DUKE_GETWEAPON2, DUKE_GETWEAPON3, BONUS_SPEECH1 };
	static const int rr[] = { 390 /* YEHAA16 */, 78 /* LN_HOTDM */ };
	const int id = isRR() ? rr[rand() % countof(rr)] : duke[rand() % countof(duke)];
	S_PlaySound(id, CHAN_VOICE, CHANF_UI, 1.f);
}

#ifndef RAZE_IOS
// The Linux test rig's: the player's items, for its log (ITEM)
CCMD(ios_riginv_duke)
{
	auto p = getPlayer(myconnectindex);
	if (!p || !p->GetActor()) return;
	Printf("riginv icon %d health %d firstaid %d steroids %d holoduke %d (on %d) jetpack %d (on %d) heat %d (on %d) scuba %d boots %d\n",
		(int)p->inven_icon, (int)p->GetActor()->spr.extra, (int)p->firstaid_amount, (int)p->steroids_amount, (int)p->holoduke_amount,
		p->holoduke_on != nullptr, (int)p->jetpack_amount, (int)p->jetpack_on, (int)p->heat_amount, (int)p->heat_on, (int)p->scuba_amount,
		(int)p->boot_amount);
}
#endif

END_DUKE_NS

const IOSGamePart iosDukePart = { DUKE_NS::Weapons, DUKE_NS::Pick, DUKE_NS::PickTick, DUKE_NS::State, DUKE_NS::FillAmmo, false,
                                  DUKE_NS::Alive, DUKE_NS::GodOn, DUKE_NS::Reset, DUKE_NS::Icon, DUKE_NS::CheatIcon, DUKE_NS::CheatSound };
