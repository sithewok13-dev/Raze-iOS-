//============================================================================
//
// Added (iOS touch): the touch HUD (ios/IOSTouch.h, IOSTOUCH_HUD_*), drawn
// over the full-screen view in place of the game's status bar: dark
// translucent rounded pills at the bottom, of the game's own graphics.
// SPLIT: bottom left the player (the face where the game's status bar has
// one, health, armour or what stands for it); bottom right the ammo of the
// weapon in hand and the keys held. STRIP: all in one pill in the middle,
// between the buttons. Sizes are the approved mockups' (in their units: a
// pill 64 high), scaled to the pill's height the touch controls give
// (Raze.IOSHud); a pill too wide for its room shrinks. Health under 25
// pulses red; ammo strictly under a quarter of what can be carried, or
// none, turns red. Each game says what goes in (IOSHudParts, in its status
// bar's file); this draws it.
//
//============================================================================

enum EIOSHudPart
{
	IOSK_ICON,		// a picture, h high (a wide one is kept to at most 3h wide)
	IOSK_NUM,		// a number in one of the game's digit sets (IOSDigit)
	IOSK_GAP,		// a thin bar between groups
	IOSK_SP,		// a little space
	IOSK_POOL,		// Exhumed: a status bar pool (its texture in an oval, its frame and what's over it)

	IOSF_LOW = 1,	// (a number) the health warning: pulses red
	IOSF_RED = 2,	// (a number) the ammo warning: red
	IOSF_GOLD = 4,	// (a number in a font) gold
	IOSF_BRIGHT = 8,// (a picture) brighter
}

extend class RazeStatusBar
{
	Array<int> mIOSKind, mIOSFlags, mIOSPill;
	Array<TranslationID> mIOSTrans;
	Array<TextureID> mIOSTex, mIOSTex2, mIOSTex3;
	Array<double> mIOSH;
	Array<String> mIOSText;
	Shape2D mIOSFill, mIOSEdge, mIOSOval;
	double mIOSU;		// screen pixels per mockup unit
	double mIOSA;		// how strongly it shows (OPACITY's HUD slider)

	//---------------------------------------------------------------------------
	// What the games give
	//---------------------------------------------------------------------------

	// The parts of the two pills (pill 0: the player; pill 1: the gun and
	// the keys), with face on or off (only where the game has one)
	virtual void IOSHudParts(bool face) {}

	// The digit sets: a font ("font:big", "font:digi", "font:small") or the
	// game's own digit pictures (src the start of their names, digit after)
	virtual TextureID IOSDigit(String src, int d)
	{
		return TexMan.CheckForTexture(String.Format("%s%d", src, d), TexMan.Type_Any);
	}

	Font IOSFont(String src)
	{
		if (src == "font:digi") { let f = Font.FindFont("DigiFont"); if (f) return f; }
		if (src == "font:small") return SmallFont;
		return BigFont;
	}

	//---------------------------------------------------------------------------
	// Building the parts
	//---------------------------------------------------------------------------

	void IOSClear()
	{
		mIOSKind.Clear(); mIOSFlags.Clear(); mIOSPill.Clear(); mIOSTrans.Clear();
		mIOSTex.Clear(); mIOSTex2.Clear(); mIOSTex3.Clear(); mIOSH.Clear(); mIOSText.Clear();
	}

	void IOSAdd(int pill, int kind, TextureID tex, double h, String text = "", int flags = 0, TranslationID trans = 0)
	{
		mIOSPill.Push(pill); mIOSKind.Push(kind); mIOSTex.Push(tex); mIOSH.Push(h); mIOSText.Push(text);
		mIOSFlags.Push(flags); mIOSTrans.Push(trans);
		TextureID none;
		none.SetInvalid();
		mIOSTex2.Push(none);
		mIOSTex3.Push(none);
	}

	TextureID IOSTex(String name)
	{
		return TexMan.CheckForTexture(name, TexMan.Type_Any);
	}

	// a picture (nothing if the game hasn't it)
	void IOSIcon(int pill, String name, double h, int flags = 0, TranslationID trans = 0)
	{
		let tex = IOSTex(name);
		if (tex.IsValid()) IOSAdd(pill, IOSK_ICON, tex, h, "", flags, trans);
	}

	void IOSIconTex(int pill, TextureID tex, double h, int flags = 0, TranslationID trans = 0)
	{
		if (tex.IsValid()) IOSAdd(pill, IOSK_ICON, tex, h, "", flags, trans);
	}

	// a number: src a digit set (IOSDigit / IOSFont); the text kept with it
	void IOSNum(int pill, int value, String src, double h, int flags = 0)
	{
		TextureID none;
		none.SetInvalid();
		IOSAdd(pill, IOSK_NUM, none, h, String.Format("%s|%d", src, value), flags);
	}

	void IOSGap(int pill)
	{
		TextureID none;
		none.SetInvalid();
		IOSAdd(pill, IOSK_GAP, none, 0);
	}

	void IOSSpace(int pill)
	{
		TextureID none;
		none.SetInvalid();
		IOSAdd(pill, IOSK_SP, none, 0);
	}

	// Exhumed's pools: tex in an oval, frame round it, over on top
	void IOSPool(int pill, TextureID tex, TextureID frame, TextureID over, double h)
	{
		IOSAdd(pill, IOSK_POOL, frame, h);
		mIOSTex2[mIOSTex2.Size() - 1] = tex;
		mIOSTex3[mIOSTex3.Size() - 1] = over;
	}

	// the warnings
	static int IOSLowHealth(int health) { return health < 25 ? IOSF_LOW : 0; }
	static int IOSLowAmmo(int ammo, int maxammo) { return (ammo <= 0 || (maxammo > 0 && ammo * 4 < maxammo)) ? IOSF_RED : 0; }

	// The usual parts from the game's own list (GetAllStats): health, the
	// armours, the ammo in hand and the keys
	void IOSStandardParts(String digits, double iconH, double numH, double armorH, double ammoH, double keyH, int ammoFlags = 0)
	{
		HudStats st;
		GetAllStats(st);
		IOSIcon(0, st.healthicon, iconH);
		IOSNum(0, st.healthvalue, digits, numH, IOSLowHealth(st.healthvalue));
		for (int i = 0; i < st.armoricons.Size() && i < st.armorvalues.Size(); i++)
		{
			if (st.armorvalues[i] < 0) continue;
			if (i == 0) IOSGap(0); else IOSSpace(0);
			IOSIcon(0, st.armoricons[i], armorH);
			IOSNum(0, st.armorvalues[i], digits, numH);
		}
		int a = st.ammoselect;
		if (a >= 0 && a < st.ammoicons.Size() && a < st.ammovalues.Size())
		{
			IOSIcon(1, st.ammoicons[a], ammoH);
			int maxa = a < st.ammomaxvalues.Size() ? st.ammomaxvalues[a] : 0;
			IOSNum(1, st.ammovalues[a], digits, numH, ammoFlags | IOSLowAmmo(st.ammovalues[a], maxa));
		}
		if (st.keyicons.Size() > 0)
		{
			if (mIOSPill.Find(1) != mIOSPill.Size()) IOSGap(1);
			for (int i = 0; i < st.keyicons.Size(); i++)
			{
				TranslationID tr = 0;
				if (i < st.keytranslations.Size()) tr = st.keytranslations[i];
				IOSIcon(1, st.keyicons[i], keyH, 0, tr);
			}
		}
	}

	//---------------------------------------------------------------------------
	// Sizes and drawing
	//---------------------------------------------------------------------------

	double IOSIconW(TextureID tex, double h)
	{
		if (!tex.IsValid()) return 0;
		Vector2 sz = TexMan.GetScaledSize(tex);
		if (sz.Y <= 0) return 0;
		return min(sz.X * h / sz.Y, 3 * h);
	}

	// a number's width at height h, drawn at x (its left) when draw
	double IOSNumber(int i, double x, double ymid, bool draw)
	{
		String txt = mIOSText[i];
		int bar = txt.IndexOf("|");
		String src = txt.Left(bar);
		String str = txt.Mid(bar + 1);
		double h = mIOSH[i], u = mIOSU;
		int flags = mIOSFlags[i];
		double pulse = 0.5 + 0.5 * sin(MSTimeF() * 0.72); // (twice a second)
		if (src.Left(5) == "font:")
		{
			Font fnt = IOSFont(src);
			// (h is the digits' own height: the font's '0', not its line)
			int gh = fnt.GetGlyphHeight(48);
			if (gh <= 0) gh = fnt.GetHeight();
			double k = h / max(gh, 1);
			double w = fnt.StringWidth(str) * k;
			if (draw)
			{
				int cr = (flags & IOSF_RED) ? Font.CR_RED : (flags & IOSF_GOLD) ? Font.CR_GOLD : Font.CR_UNTRANSLATED;
				double y = (ymid - h / 2 - fnt.GetDisplayTopOffset(48) * k) * u;
				Screen.DrawText(fnt, cr, x * u, y, str, DTA_ScaleX, k * u, DTA_ScaleY, k * u, DTA_Alpha, mIOSA);
				if (flags & IOSF_LOW)
				{
					Screen.DrawText(fnt, Font.CR_RED, x * u, y, str, DTA_ScaleX, k * u, DTA_ScaleY, k * u,
						DTA_Alpha, pulse * 0.9 * mIOSA, DTA_LegacyRenderStyle, STYLE_Add);
				}
			}
			return w;
		}
		// the game's digit pictures, each h high, a unit apart
		double w = 0;
		for (int c = 0; c < int(str.Length()); c++)
		{
			int d = str.ByteAt(c) - 48;
			if (d < 0 || d > 9) continue;
			TextureID tex = IOSDigit(src, d);
			double dw = IOSIconW(tex, h);
			if (dw <= 0) continue;
			if (draw)
			{
				double dx = (x + w) * u, dy = (ymid - h / 2) * u;
				Screen.DrawTexture(tex, false, dx, dy, DTA_DestWidthF, dw * u, DTA_DestHeightF, h * u,
					DTA_LeftOffset, 0, DTA_TopOffset, 0, DTA_Alpha, mIOSA);
				if (flags & (IOSF_LOW | IOSF_RED))
				{
					double a = (flags & IOSF_LOW) ? pulse * 0.8 : 0.75;
					Screen.DrawTexture(tex, false, dx, dy, DTA_DestWidthF, dw * u, DTA_DestHeightF, h * u,
						DTA_LeftOffset, 0, DTA_TopOffset, 0, DTA_Alpha, a * mIOSA,
						DTA_FillColor, Color(255, 255, 30, 20), DTA_LegacyRenderStyle, STYLE_AddStencil);
				}
			}
			w += dw + 1;
		}
		return max(w - 1, 0);
	}

	// An oval of tex, w x h at (x0, y0) (screen pixels)
	void IOSOval(TextureID tex, double x0, double y0, double w, double h)
	{
		if (!mIOSOval) mIOSOval = new("Shape2D");
		mIOSOval.Clear();
		double cx = x0 + w / 2, cy = y0 + h / 2;
		mIOSOval.PushVertex((cx, cy));
		mIOSOval.PushCoord((0.5, 0.5));
		for (int k = 0; k < 24; k++)
		{
			double ang = 360.0 * k / 24;
			mIOSOval.PushVertex((cx + w / 2 * cos(ang), cy + h / 2 * sin(ang)));
			mIOSOval.PushCoord((0.5 + 0.5 * cos(ang), 0.5 + 0.5 * sin(ang)));
		}
		for (int k = 0; k < 24; k++) mIOSOval.PushTriangle(0, 1 + k, 1 + (k + 1) % 24);
		Screen.DrawShape(tex, false, mIOSOval, DTA_Alpha, mIOSA);
	}

	// A part's width (units), and drawn at x (its left) when draw
	double IOSPart(int i, double x, double ymid, bool draw)
	{
		double u = mIOSU;
		int kind = mIOSKind[i];
		if (kind == IOSK_GAP)
		{
			if (draw) Screen.DrawThickLine((x + 11) * u, (ymid - 14) * u, (x + 11) * u, (ymid + 14) * u, 2 * u, Color(255, 255, 255, 255), int(60 * mIOSA));
			return 22;
		}
		if (kind == IOSK_SP) return 6;
		if (kind == IOSK_NUM) return IOSNumber(i, x, ymid, draw);
		double h = mIOSH[i];
		TextureID tex = mIOSTex[i];
		double w = IOSIconW(tex, h);
		if (draw && w > 0)
		{
			double y0 = ymid - h / 2;
			if (kind == IOSK_POOL)
			{
				// the pool (an oval inside the frame), the frame, what's over it
				IOSOval(mIOSTex2[i], (x + w * 0.08) * u, (y0 + h * 0.2) * u, w * 0.84 * u, h * 0.6 * u);
				Screen.DrawTexture(tex, false, x * u, y0 * u, DTA_DestWidthF, w * u, DTA_DestHeightF, h * u,
					DTA_LeftOffset, 0, DTA_TopOffset, 0, DTA_Alpha, mIOSA);
				TextureID over = mIOSTex3[i];
				if (over.IsValid())
				{
					double ow = IOSIconW(over, h * 0.6);
					Screen.DrawTexture(over, false, (x + (w - ow) / 2) * u, (y0 + h * 0.2) * u, DTA_DestWidthF, ow * u, DTA_DestHeightF, h * 0.6 * u,
						DTA_LeftOffset, 0, DTA_TopOffset, 0, DTA_Alpha, mIOSA);
				}
			}
			else
			{
				Screen.DrawTexture(tex, false, x * u, y0 * u, DTA_DestWidthF, w * u, DTA_DestHeightF, h * u,
					DTA_LeftOffset, 0, DTA_TopOffset, 0, DTA_Alpha, mIOSA, DTA_TranslationIndex, mIOSTrans[i]);
				if (mIOSFlags[i] & IOSF_BRIGHT)
				{
					Screen.DrawTexture(tex, false, x * u, y0 * u, DTA_DestWidthF, w * u, DTA_DestHeightF, h * u,
						DTA_LeftOffset, 0, DTA_TopOffset, 0, DTA_Alpha, 0.35 * mIOSA, DTA_LegacyRenderStyle, STYLE_Add,
						DTA_TranslationIndex, mIOSTrans[i]);
				}
			}
		}
		return w;
	}

	double IOSPillWidth(int pill)
	{
		double w = 44;
		int n = 0;
		for (int i = 0; i < mIOSKind.Size(); i++)
		{
			if (pill >= 0 && mIOSPill[i] != pill) continue;
			double pw = IOSPart(i, 0, 0, false);
			if (pw <= 0) continue;
			w += pw;
			n++;
		}
		return w + 8 * max(n - 1, 0);
	}

	bool IOSPillEmpty(int pill)
	{
		for (int i = 0; i < mIOSKind.Size(); i++) if (mIOSPill[i] == pill && mIOSKind[i] != IOSK_GAP) return false;
		return true;
	}

	// A rounded box's outline as points, inset by d (screen pixels)
	void IOSRoundRect(Array<double> pts, double x0, double y0, double x1, double y1, double r, double d)
	{
		pts.Clear();
		x0 += d; y0 += d; x1 -= d; y1 -= d; r = max(r - d, 0.5);
		for (int c = 0; c < 4; c++)
		{
			double cx = (c == 0 || c == 3) ? x1 - r : x0 + r;
			double cy = (c < 2) ? y0 + r : y1 - r;
			for (int k = 0; k <= 8; k++)
			{
				double ang = 90.0 * c + 90.0 * k / 8; // (counter-clockwise from the right, up being -y)
				pts.Push(cx + r * cos(ang));
				pts.Push(cy - r * sin(ang));
			}
		}
	}

	// One pill (pill -1: every part): x0 its left, its bottom at y1 (units)
	void IOSDrawPill(int pill, double x0, double y1)
	{
		double u = mIOSU;
		double w = IOSPillWidth(pill), h = 64;
		double y0 = y1 - h;
		if (!mIOSFill) mIOSFill = new("Shape2D");
		if (!mIOSEdge) mIOSEdge = new("Shape2D");
		Array<double> outer, inner;
		IOSRoundRect(outer, x0 * u, y0 * u, (x0 + w) * u, y1 * u, 26 * u, 0);
		IOSRoundRect(inner, x0 * u, y0 * u, (x0 + w) * u, y1 * u, 26 * u, 2 * u);
		int n = outer.Size() / 2;
		// the inside: a fan; the edge: a band between the two outlines
		mIOSFill.Clear();
		mIOSFill.PushVertex(((x0 + w / 2) * u, (y0 + h / 2) * u));
		mIOSFill.PushCoord((0, 0));
		for (int i = 0; i < n; i++)
		{
			mIOSFill.PushVertex((inner[i * 2], inner[i * 2 + 1]));
			mIOSFill.PushCoord((0, 0));
		}
		for (int i = 0; i < n; i++) mIOSFill.PushTriangle(0, 1 + i, 1 + (i + 1) % n);
		mIOSEdge.Clear();
		for (int i = 0; i < n; i++)
		{
			mIOSEdge.PushVertex((outer[i * 2], outer[i * 2 + 1]));
			mIOSEdge.PushVertex((inner[i * 2], inner[i * 2 + 1]));
			mIOSEdge.PushCoord((0, 0));
			mIOSEdge.PushCoord((0, 0));
		}
		for (int i = 0; i < n; i++)
		{
			int a = i * 2, b = ((i + 1) % n) * 2;
			mIOSEdge.PushTriangle(a, a + 1, b);
			mIOSEdge.PushTriangle(b, a + 1, b + 1);
		}
		Screen.DrawShapeFill(Color(255, 10, 6, 4), 135 / 255. * mIOSA, mIOSFill);
		Screen.DrawShapeFill(Color(255, 255, 255, 255), 55 / 255. * mIOSA, mIOSEdge);
		double x = x0 + 22, ymid = y0 + h / 2;
		for (int i = 0; i < mIOSKind.Size(); i++)
		{
			if (pill >= 0 && mIOSPill[i] != pill) continue;
			double pw = IOSPart(i, 0, 0, false);
			if (pw <= 0) continue;
			IOSPart(i, x, ymid, true);
			x += pw + 8;
		}
	}

	// From statusbar2.cpp, after the game's own status bar (drawn as
	// "nothing" then: the full-screen view): SPLIT and STRIP
	virtual void DrawIOSHud()
	{
		int style = int(Raze.IOSHud(0));
		if (style != 0 && style != 1) return;
		double pillH = Raze.IOSHud(2), bottom = Raze.IOSHud(3), left = Raze.IOSHud(4), right = Raze.IOSHud(5), half = Raze.IOSHud(6);
		if (pillH <= 0) return;
		mIOSA = Raze.IOSHud(7);
		IOSClear();
		IOSHudParts(Raze.IOSHud(1) != 0);
		if (mIOSKind.Size() == 0) return;
		// a gap left at a pill's end is dropped
		for (int i = mIOSKind.Size() - 1; i >= 0; i--)
		{
			bool last = true;
			for (int j = i + 1; j < mIOSKind.Size(); j++) if (mIOSPill[j] == mIOSPill[i]) last = false;
			bool first = true;
			for (int j = 0; j < i; j++) if (mIOSPill[j] == mIOSPill[i]) first = false;
			if (mIOSKind[i] == IOSK_GAP && (last || first))
			{
				mIOSKind.Delete(i); mIOSFlags.Delete(i); mIOSPill.Delete(i); mIOSTrans.Delete(i);
				mIOSTex.Delete(i); mIOSTex2.Delete(i); mIOSTex3.Delete(i); mIOSH.Delete(i); mIOSText.Delete(i);
			}
		}

		// sizes: the pill's height the touch controls give; smaller where a
		// pill wouldn't fit its room (SPLIT: half the width each; STRIP:
		// between the buttons)
		double u = pillH / 64;
		mIOSU = u;
		bool you = !IOSPillEmpty(0), gun = !IOSPillEmpty(1);
		if (style == 0)
		{
			double room = ((right - left) / 2 - 12 * u) / u;
			double need = max(you ? IOSPillWidth(0) : 0, gun ? IOSPillWidth(1) : 0);
			if (need > room) u *= room / need;
			mIOSU = u;
			if (you) IOSDrawPill(0, left / u, bottom / u);
			if (gun) IOSDrawPill(1, right / u - IOSPillWidth(1), bottom / u);
		}
		else
		{
			// one pill: the player's parts, a gap, the gun's
			if (you && gun)
			{
				int firstGun = mIOSPill.Find(1);
				TextureID none;
				none.SetInvalid();
				TranslationID notr = 0;
				mIOSKind.Insert(firstGun, IOSK_GAP); mIOSFlags.Insert(firstGun, 0); mIOSPill.Insert(firstGun, 1); mIOSTrans.Insert(firstGun, notr);
				mIOSTex.Insert(firstGun, none); mIOSTex2.Insert(firstGun, none); mIOSTex3.Insert(firstGun, none); mIOSH.Insert(firstGun, 0); mIOSText.Insert(firstGun, "");
			}
			double need = IOSPillWidth(-1), room = 2 * half / u;
			if (need > room) u *= room / need;
			mIOSU = u;
			IOSDrawPill(-1, (Screen.GetWidth() / 2) / u - IOSPillWidth(-1) / 2, bottom / u);
		}
	}
}
