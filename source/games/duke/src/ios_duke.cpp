// Added: the iOS touch controls' part for Duke Nukem 3D and Redneck Rampage
// (ios/IOSGame.h): the player's weapons for the weapon wheel, a pick from
// it, the item buttons, the cheat's noclip and its ammo kept full.

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
	pHud->bNoclip = ud.clipping != 0;
	pHud->bCanFly = 0;
	pHud->bFlying = 0;
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

// The item buttons: Duke's medkit, steroids (only whole: then they run),
// HoloDuke, jetpack and night vision (switched on and off); Redneck
// Rampage's whiskey, moonshine (as the steroids), beer and cow pies (counts:
// a can of beer is 400 of it, a pie 100). The scuba gear and boots, the
// snorkel and hip waders, work by themselves: no button; nor Redneck
// Rampage's slot 5, its "Yeehaa".
static void Items(IOSTouchItems* pi)
{
	auto p = getPlayer(myconnectindex);
	auto act = p ? p->GetActor() : nullptr;
	if (!act) return;
	const bool full = act->spr.extra >= gs.max_player_health;
	const bool steroidsOn = p->steroids_amount > 0 && p->steroids_amount < 400;
	if (!isRR())
	{
		if (p->firstaid_amount > 0) AddItem(pi, ICON_FIRSTAID, IOSTOUCH_ITEM_CHARGE, p->firstaid_amount / 100.0, 0, false, full);
		if (p->steroids_amount > 0) AddItem(pi, ICON_STEROIDS, IOSTOUCH_ITEM_CHARGE, p->steroids_amount / 400.0, 0, steroidsOn, false);
		if (p->holoduke_amount > 0) AddItem(pi, ICON_HOLODUKE, IOSTOUCH_ITEM_CHARGE, p->holoduke_amount / 2400.0, 0, p->holoduke_on != nullptr, false);
		if (p->jetpack_amount > 0) AddItem(pi, ICON_JETPACK, IOSTOUCH_ITEM_CHARGE, p->jetpack_amount / 1600.0, 0, p->jetpack_on != 0, false);
		if (p->heat_amount > 0) AddItem(pi, ICON_HEATS, IOSTOUCH_ITEM_CHARGE, p->heat_amount / 1200.0, 0, p->heat_on != 0, false);
	}
	else
	{
		if (p->firstaid_amount > 0) AddItem(pi, ICON_FIRSTAID, IOSTOUCH_ITEM_CHARGE, p->firstaid_amount / 100.0, 0, false, full);
		if (p->steroids_amount > 0) AddItem(pi, ICON_STEROIDS, IOSTOUCH_ITEM_CHARGE, p->steroids_amount / 400.0, 0, steroidsOn, false);
		if (p->holoduke_amount > 0) AddItem(pi, ICON_HOLODUKE, IOSTOUCH_ITEM_COUNT, 0, (p->holoduke_amount + 399) / 400, false, full);
		if (p->jetpack_amount > 0) AddItem(pi, ICON_JETPACK, IOSTOUCH_ITEM_COUNT, 0, (p->jetpack_amount + 99) / 100, false, full);
	}
}

// ...their pictures: the status bar's own item icons
static const char* const* ItemIcon(int iUse)
{
	static const char* const duke[][2] = { { "FIRSTAID_ICON" }, { "STEROIDS_ICON" }, { "HOLODUKE_ICON" }, { "JETPACK_ICON" }, { "HEAT_ICON" } };
	static const char* const rr[][2] = { { "WHISKEY_ICON" }, { "MOONSHINE_ICON" }, { "HOLODUKE_ICON" }, { "COWPIE_ICON" } };
	if (isRR()) return (iUse >= 1 && iUse <= 4) ? rr[iUse - 1] : nullptr;
	return (iUse >= 1 && iUse <= 5) ? duke[iUse - 1] : nullptr;
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
// The Linux test rig's: health and the ammo in hand set (the HUD's warnings)
CCMD(ios_rigset_duke)
{
	auto p = getPlayer(myconnectindex);
	if (!p || !p->GetActor() || argv.argc() < 3) return;
	const int v = atoi(argv[2]);
	if (!stricmp(argv[1], "health")) p->GetActor()->spr.extra = p->last_extra = v;
	else if (!stricmp(argv[1], "ammo")) p->ammo_amount[p->curr_weapon] = v;
}

// The Linux test rig's: the player's items, for its log
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
                                  DUKE_NS::Alive, DUKE_NS::GodOn, DUKE_NS::Reset, DUKE_NS::Icon, DUKE_NS::CheatIcon, DUKE_NS::CheatSound,
                                  DUKE_NS::Items, DUKE_NS::ItemIcon };
