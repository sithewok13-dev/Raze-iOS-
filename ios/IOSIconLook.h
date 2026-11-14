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
// three quarters of the button across). false: nothing to make.
bool IOSIconLook_ItemPicture(const uint8_t* rgba, int w, int h, std::vector<uint8_t>& out, int& ow, int& oh);

// CHEAT's picture from a round sign (Duke's worn radiation sign): its
// yellow circle cropped, scaled up smoothly, in a black rim; on (its
// yellow orange-hot, a wide orange halo, the rim crisp over it) and off
// (grey, dim). Both n x n (IOSTOUCH_CHEAT_PICTURE_SIZE), covering
// IOSTOUCH_CHEAT_PICTURE_SPAN of the button's diameter. false: it isn't
// such a sign (another edition's tile): the usual picture then.
bool IOSIconLook_CheatSign(const uint8_t* rgba, int w, int h, int n, std::vector<uint8_t>& on, std::vector<uint8_t>& off);
