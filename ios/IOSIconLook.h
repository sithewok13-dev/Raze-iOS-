// Added (iOS touch): the touch buttons' pictures made from the game's own
// art, once, as the game feeds them (IOSGame.cpp's FeedIcons). Pictures
// are RGBA, not premultiplied, rows packed.
#pragma once
#include <stdint.h>
#include <vector>

// An item button's picture from a world pickup sprite (cropped to what
// isn't see-through): scaled up smoothly (hq4x, then Lanczos), brighter,
// more contrast and colour, a thin light outline; sized to sit in a 22 pt
// button at IOSTOUCH_PICTURE_PER_PT pixels a point (its larger side about
// three quarters of the button across). fEnhance: how much brighter and
// more colour (1: Duke's; less for art already bright). false: nothing.
bool IOSIconLook_ItemPicture(const uint8_t* rgba, int w, int h, std::vector<uint8_t>& out, int& ow, int& oh, float fEnhance = 1.0f);

// CHEAT's picture from a round sign (Duke's worn radiation sign): its
// yellow circle cropped, scaled up smoothly, in a black rim; on (its
// yellow orange-hot, a wide orange halo, the rim crisp over it) and off
// (grey, dim). Both n x n (IOSTOUCH_CHEAT_PICTURE_SIZE), covering
// IOSTOUCH_CHEAT_PICTURE_SPAN of the button's diameter. false: it isn't
// such a sign (another edition's tile): the usual picture then.
bool IOSIconLook_CheatSign(const uint8_t* rgba, int w, int h, int n, std::vector<uint8_t>& on, std::vector<uint8_t>& off);

// The other games' CHEAT signs, the same look: bEmblem false, a round sign
// (alpha's box, an ellipse made round) cropped to fCrop of its radius
// about its middle moved fCx, fCy of the radius; true, an emblem (fEmblem
// of the disc across) on a disc of aBack. On: the picture lit, warmed and
// glowing in aGlow, the rim crisp; off grey and dim. fOnColour: how much
// more colour on (0: 1.35; an emblem with it keeps its own colour otherwise)
struct IOSIconSignStyle
{
	bool bEmblem;
	float fCrop, fCx, fCy, fEmblem;
	uint8_t aGlow[3], aBack[3];
	float fOnColour;
};
bool IOSIconLook_CheatSignStyled(const uint8_t* rgba, int w, int h, int n, const IOSIconSignStyle& st, std::vector<uint8_t>& on,
                                 std::vector<uint8_t>& off);
