// Added (iOS touch): the touch buttons' pictures made from the game's own
// art (IOSIconLook.h). Done once per picture, as it is fed, never a frame.
#include "IOSIconLook.h"
#include "IOSTouch.h"
#include "../source/common/textures/hires/hqnx/hqx.h"
#include <math.h>
#include <string.h>
#include <algorithm>

namespace {

// A picture in floats, 0..255, RGBA not premultiplied
struct Pic
{
	int w = 0, h = 0;
	std::vector<float> px;
	Pic() {}
	Pic(int ww, int hh) : w(ww), h(hh), px((size_t)ww * hh * 4, 0.0f) {}
	float* at(int x, int y) { return &px[((size_t)y * w + x) * 4]; }
	const float* at(int x, int y) const { return &px[((size_t)y * w + x) * 4]; }
};

// A single channel (alpha, masks)
struct Mask
{
	int w = 0, h = 0;
	std::vector<float> v;
	Mask(int ww, int hh) : w(ww), h(hh), v((size_t)ww * hh, 0.0f) {}
};

inline float clamp255(float f) { return f < 0 ? 0 : (f > 255 ? 255 : f); }
inline float clamp01(float f) { return f < 0 ? 0 : (f > 1 ? 1 : f); }

Pic FromBytes(const uint8_t* rgba, int w, int h)
{
	Pic p(w, h);
	for (size_t i = 0; i < p.px.size(); i++) p.px[i] = rgba[i];
	return p;
}

void ToBytes(const Pic& p, std::vector<uint8_t>& out)
{
	out.resize(p.px.size());
	for (size_t i = 0; i < p.px.size(); i++) out[i] = (uint8_t)(clamp255(p.px[i]) + 0.5f);
}

// Source over destination (both not premultiplied)
void Over(Pic& d, const Pic& s, int ox = 0, int oy = 0)
{
	for (int y = 0; y < s.h; y++)
		for (int x = 0; x < s.w; x++)
		{
			const int dx = x + ox, dy = y + oy;
			if (dx < 0 || dy < 0 || dx >= d.w || dy >= d.h) continue;
			const float* q = s.at(x, y);
			float* p = d.at(dx, dy);
			const float sa = q[3] / 255.0f, da = p[3] / 255.0f, oa = sa + da * (1 - sa);
			if (oa <= 0) { p[0] = p[1] = p[2] = p[3] = 0; continue; }
			for (int c = 0; c < 3; c++) p[c] = (q[c] * sa + p[c] * da * (1 - sa)) / oa;
			p[3] = oa * 255.0f;
		}
}

// A solid colour through a mask (0..1)
Pic Solid(const Mask& m, float r, float g, float b, float k = 1.0f)
{
	Pic p(m.w, m.h);
	for (int i = 0; i < m.w * m.h; i++)
	{
		float* q = &p.px[(size_t)i * 4];
		q[0] = r; q[1] = g; q[2] = b; q[3] = 255.0f * clamp01(m.v[i] * k);
	}
	return p;
}

// A disc's coverage, its edge smoothed over a pixel
Mask Disc(int n, double cx, double cy, double rad)
{
	Mask m(n, n);
	for (int y = 0; y < n; y++)
		for (int x = 0; x < n; x++)
		{
			const double d = hypot(x + 0.5 - cx, y + 0.5 - cy);
			m.v[(size_t)y * n + x] = clamp01((float)(rad - d + 0.5));
		}
	return m;
}

Mask Ring(int n, double c, double r0, double r1)
{
	Mask a = Disc(n, c, c, r1), b = Disc(n, c, c, r0);
	for (size_t i = 0; i < a.v.size(); i++) a.v[i] = clamp01(a.v[i] - b.v[i]);
	return a;
}

Mask AlphaOf(const Pic& p)
{
	Mask m(p.w, p.h);
	for (size_t i = 0; i < m.v.size(); i++) m.v[i] = p.px[i * 4 + 3] / 255.0f;
	return m;
}

// Gaussian blur (sigma in pixels), nothing beyond the edges
Mask Blur(const Mask& m, double sigma)
{
	if (sigma <= 0.05) return m;
	const int rad = (int)ceil(sigma * 3);
	std::vector<float> k(2 * rad + 1);
	float sum = 0;
	for (int i = -rad; i <= rad; i++) sum += k[i + rad] = (float)exp(-0.5 * i * i / (sigma * sigma));
	for (float& f : k) f /= sum;
	Mask t(m.w, m.h), o(m.w, m.h);
	for (int y = 0; y < m.h; y++)
		for (int x = 0; x < m.w; x++)
		{
			float s = 0;
			for (int i = -rad; i <= rad; i++)
			{
				const int xx = x + i;
				if (xx >= 0 && xx < m.w) s += m.v[(size_t)y * m.w + xx] * k[i + rad];
			}
			t.v[(size_t)y * m.w + x] = s;
		}
	for (int y = 0; y < m.h; y++)
		for (int x = 0; x < m.w; x++)
		{
			float s = 0;
			for (int i = -rad; i <= rad; i++)
			{
				const int yy = y + i;
				if (yy >= 0 && yy < m.h) s += t.v[(size_t)yy * m.w + x] * k[i + rad];
			}
			o.v[(size_t)y * m.w + x] = s;
		}
	return o;
}

// A glow of a picture's shape: its alpha blurred and strengthened, coloured
Pic GlowOf(const Pic& p, float r, float g, float b, double sigma, float strength)
{
	return Solid(Blur(AlphaOf(p), sigma), r, g, b, 2.2f * strength);
}

double Lanczos(double x)
{
	x = fabs(x);
	if (x < 1e-8) return 1.0;
	if (x >= 3.0) return 0.0;
	const double px = M_PI * x;
	return 3.0 * sin(px) * sin(px / 3.0) / (px * px);
}

// One direction of a Lanczos-3 resample, on premultiplied values
void ResampleAxis(const std::vector<float>& src, int sw, int sh, std::vector<float>& dst, int dw, bool bX)
{
	const int sn = bX ? sw : sh, other = bX ? sh : sw;
	const double scale = (double)sn / dw, fs = std::max(1.0, scale), support = 3.0 * fs;
	dst.assign((size_t)(bX ? dw * sh : sw * dw) * 4, 0.0f);
	std::vector<double> wts;
	for (int o = 0; o < dw; o++)
	{
		const double centre = (o + 0.5) * scale;
		const int i0 = std::max(0, (int)floor(centre - support)), i1 = std::min(sn - 1, (int)ceil(centre + support));
		wts.assign(i1 - i0 + 1, 0.0);
		double tot = 0;
		for (int i = i0; i <= i1; i++) tot += wts[i - i0] = Lanczos((i + 0.5 - centre) / fs);
		if (tot == 0) tot = 1;
		for (int j = 0; j < other; j++)
		{
			double acc[4] = { 0, 0, 0, 0 };
			for (int i = i0; i <= i1; i++)
			{
				const float* s = &src[(bX ? ((size_t)j * sw + i) : ((size_t)i * sw + j)) * 4];
				const double wt = wts[i - i0] / tot;
				for (int c = 0; c < 4; c++) acc[c] += s[c] * wt;
			}
			float* d = &dst[(bX ? ((size_t)j * dw + o) : ((size_t)o * sw + j)) * 4];
			for (int c = 0; c < 4; c++) d[c] = (float)acc[c];
		}
	}
}

Pic Resize(const Pic& p, int nw, int nh)
{
	std::vector<float> pre(p.px.size()), a, b;
	for (size_t i = 0; i < p.px.size(); i += 4)
	{
		const float al = p.px[i + 3] / 255.0f;
		pre[i] = p.px[i] * al; pre[i + 1] = p.px[i + 1] * al; pre[i + 2] = p.px[i + 2] * al; pre[i + 3] = p.px[i + 3];
	}
	ResampleAxis(pre, p.w, p.h, a, nw, true);
	ResampleAxis(a, nw, p.h, b, nh, false);
	Pic o(nw, nh);
	for (size_t i = 0; i < o.px.size(); i += 4)
	{
		const float al = clamp255(b[i + 3]);
		o.px[i + 3] = al;
		for (int c = 0; c < 3; c++) o.px[i + c] = al > 0.01f ? clamp255(b[i + c] * 255.0f / al) : 0.0f;
	}
	return o;
}

// hq4x on the colour and on the alpha apart (hqx compares colours only):
// two pixels of room round it, the see-through texels next to the picture
// given their neighbours' colours first so its edge doesn't go dark
Pic Hq4(const Pic& src)
{
	static bool bInit = false;
	if (!bInit) { hqxInit(); bInit = true; }
	const int w = src.w + 4, h = src.h + 4;
	Pic p(w, h);
	for (int y = 0; y < src.h; y++) memcpy(p.at(2, y + 2), src.at(0, y), (size_t)src.w * 4 * sizeof(float));
	std::vector<uint8_t> known((size_t)w * h);
	for (int i = 0; i < w * h; i++) known[i] = p.px[(size_t)i * 4 + 3] > 0;
	for (int it = 0; it < 6; it++)
	{
		std::vector<uint8_t> k2 = known;
		Pic q = p;
		for (int y = 0; y < h; y++)
			for (int x = 0; x < w; x++)
			{
				if (known[(size_t)y * w + x]) continue;
				float acc[3] = { 0, 0, 0 };
				int ct = 0;
				for (int dy = -1; dy <= 1; dy++)
					for (int dx = -1; dx <= 1; dx++)
					{
						const int xx = x + dx, yy = y + dy;
						if ((!dx && !dy) || xx < 0 || yy < 0 || xx >= w || yy >= h || !known[(size_t)yy * w + xx]) continue;
						const float* s = p.at(xx, yy);
						acc[0] += s[0]; acc[1] += s[1]; acc[2] += s[2];
						ct++;
					}
				if (!ct) continue;
				float* d = q.at(x, y);
				d[0] = acc[0] / ct; d[1] = acc[1] / ct; d[2] = acc[2] / ct;
				k2[(size_t)y * w + x] = 1;
			}
		p = q;
		known = k2;
	}
	std::vector<uint32_t> in((size_t)w * h), inA((size_t)w * h), out((size_t)w * h * 16), outA((size_t)w * h * 16);
	for (int i = 0; i < w * h; i++)
	{
		const float* s = &p.px[(size_t)i * 4];
		const uint32_t r = (uint32_t)(s[0] + 0.5f), g = (uint32_t)(s[1] + 0.5f), b = (uint32_t)(s[2] + 0.5f), a = (uint32_t)(s[3] + 0.5f);
		in[i] = 0xff000000u | (r << 16) | (g << 8) | b;
		inA[i] = 0xff000000u | (a << 16) | (a << 8) | a;
	}
	hq4x_32(in.data(), out.data(), w, h);
	hq4x_32(inA.data(), outA.data(), w, h);
	Pic o(w * 4, h * 4);
	for (size_t i = 0; i < out.size(); i++)
	{
		float* d = &o.px[i * 4];
		d[0] = (float)((out[i] >> 16) & 255); d[1] = (float)((out[i] >> 8) & 255); d[2] = (float)(out[i] & 255);
		d[3] = (float)((outA[i] >> 16) & 255);
	}
	return o;
}

float Luma(const float* p) { return 0.299f * p[0] + 0.587f * p[1] + 0.114f * p[2]; }

// Brightness, contrast (about the mean grey of the whole picture), colour,
// then a gamma, each step clipped, as an image editor's enhancers do
void Enhance(Pic& p, float fBright, float fContrast, float fColour, float fGamma)
{
	const size_t n = (size_t)p.w * p.h;
	for (size_t i = 0; i < n; i++)
		for (int c = 0; c < 3; c++) p.px[i * 4 + c] = clamp255(p.px[i * 4 + c] * fBright);
	double mean = 0;
	for (size_t i = 0; i < n; i++) mean += Luma(&p.px[i * 4]);
	mean = floor(mean / std::max<size_t>(n, 1) + 0.5);
	for (size_t i = 0; i < n; i++)
		for (int c = 0; c < 3; c++) p.px[i * 4 + c] = clamp255((float)(mean + (p.px[i * 4 + c] - mean) * fContrast));
	for (size_t i = 0; i < n; i++)
	{
		float* q = &p.px[i * 4];
		const float l = Luma(q);
		for (int c = 0; c < 3; c++) q[c] = clamp255(l + (q[c] - l) * fColour);
		for (int c = 0; c < 3; c++) q[c] = 255.0f * powf(q[c] / 255.0f, fGamma);
	}
}

// A light outline round the picture's shape (wpx wide), under it
Pic Outline(const Pic& p, float wpx, float r, float g, float b, float alpha)
{
	const int pad = (int)wpx + 2, n = std::max(3, (int)wpx * 2 + 1), half = n / 2;
	Pic P(p.w + 2 * pad, p.h + 2 * pad);
	for (int y = 0; y < p.h; y++) memcpy(P.at(pad, y + pad), p.at(0, y), (size_t)p.w * 4 * sizeof(float));
	Mask a = AlphaOf(P), big(P.w, P.h);
	for (int y = 0; y < P.h; y++)
		for (int x = 0; x < P.w; x++)
		{
			float m = 0;
			for (int dy = -half; dy <= half; dy++)
				for (int dx = -half; dx <= half; dx++)
				{
					const int xx = x + dx, yy = y + dy;
					if (xx >= 0 && yy >= 0 && xx < P.w && yy < P.h) m = std::max(m, a.v[(size_t)yy * P.w + xx]);
				}
			big.v[(size_t)y * P.w + x] = m;
		}
	Pic o = Solid(Blur(big, wpx * 0.25), r, g, b, alpha);
	Over(o, P);
	return o;
}

} // namespace

// The item buttons' look (the owner's pick, "C"): sized for a 22 pt button
// at IOSTOUCH_PICTURE_PER_PT a point: fitting 1.5 x 22 pt square, its
// diagonal at most 1.85 x 22 pt; a 0.9 pt outline
bool IOSIconLook_ItemPicture(const uint8_t* rgba, int w, int h, std::vector<uint8_t>& out, int& ow, int& oh, float fEnhance)
{
	if (!rgba || w <= 0 || h <= 0 || w > 1024 || h > 1024) return false;
	const double K = IOSTOUCH_PICTURE_PER_PT, R = 22.0;
	Pic p = Hq4(FromBytes(rgba, w, h));
	const float e = fEnhance;
	Enhance(p, 1 + 0.25f * e, 1 + 0.25f * e, 1 + 0.45f * e, 1 - 0.15f * e);
	// (the picture's own size within hq4x's room: 4 x w, h)
	const double box = 1.5 * R * K, diag = 1.85 * R * K;
	const double k = std::min({ box / w, box / h, diag / hypot(w, h) }) / 4.0;
	// (the room hq4x added, 8 pixels a side, scaled along with it)
	const int nw = std::max(1, (int)lround(p.w * k)), nh = std::max(1, (int)lround(p.h * k));
	Pic f = Resize(p, nw, nh);
	// trim back to what shows
	int x0 = f.w, y0 = f.h, x1 = -1, y1 = -1;
	for (int y = 0; y < f.h; y++)
		for (int x = 0; x < f.w; x++)
			if (f.at(x, y)[3] > 2) { x0 = std::min(x0, x); x1 = std::max(x1, x); y0 = std::min(y0, y); y1 = std::max(y1, y); }
	if (x1 < x0) return false;
	Pic t(x1 - x0 + 1, y1 - y0 + 1);
	for (int y = 0; y < t.h; y++) memcpy(t.at(0, y), f.at(x0, y0 + y), (size_t)t.w * 4 * sizeof(float));
	Pic o = Outline(t, (float)(0.9 * K), 255, 250, 235, 0.85f);
	if (o.w > IOSTOUCH_ICON_MAX || o.h > IOSTOUCH_ICON_MAX) o = Resize(o, std::min(o.w, IOSTOUCH_ICON_MAX), std::min(o.h, IOSTOUCH_ICON_MAX));
	ow = o.w;
	oh = o.h;
	ToBytes(o, out);
	return true;
}

namespace {

// The face (the sign's own picture, hq4x's room cut off) made into CHEAT's
// two pictures: a black disc, the face in it, a thin grey line at its edge;
// off grey and dim; on the face lit (Duke: its yellow orange-hot; else
// brighter, warmer, more colour), a wide halo of the game's colour and a
// tighter, lighter one, a bloom over the rim, the rim kept crisp on top
bool MakeSign(const Pic& face4, int n, bool bDukeHot, const uint8_t aGlow[3], const uint8_t aLight[3], const uint8_t aBloom[3],
              std::vector<uint8_t>& on, std::vector<uint8_t>& off)
{
	const double R = 22.0, RIM = 2.4, K = n / (2 * R * IOSTOUCH_CHEAT_PICTURE_SPAN), c = n * 0.5;
	const double faceRad = (R - RIM) * K;
	const int F = (int)ceil(2 * faceRad);
	const Pic face = Resize(face4, F, F);
	const int fo = (int)lround(c - F * 0.5);
	const Mask faceDisc = Disc(F, c - fo, c - fo, faceRad - 0.5 * 0.25);
	const float g0 = aGlow[0], g1 = aGlow[1], g2 = aGlow[2], l0 = aLight[0], l1 = aLight[1], l2 = aLight[2];

	for (int st = 0; st < 2; st++)
	{
		const bool bOn = st == 0;
		Pic f = face;
		if (bOn && !bDukeHot) Enhance(f, 1.18f, 1.18f, 1.35f, 0.9f);
		for (int i = 0; i < F * F; i++)
		{
			float* q = &f.px[(size_t)i * 4];
			if (bOn && bDukeHot)
			{
				// the yellow orange-hot: deep orange to a hot yellow by its
				// brightness; the blades, dark, stay as they are
				const float lum = (q[0] + q[1] + q[2]) / 3.0f, yel = clamp01((q[0] - q[2] - 40) / 80.0f), t = clamp01(lum / 200.0f);
				const float tgt[3] = { 255.0f, 128 * (1 - t) + 226 * t, 10 * (1 - t) + 70 * t };
				for (int k = 0; k < 3; k++) q[k] = clamp255(q[k] * (1 - yel) + tgt[k] * yel * (0.75f + 0.35f * t));
			}
			else if (bOn)
			{
				// warmed a little towards the game's colour
				const float g[3] = { g0, g1, g2 };
				for (int k = 0; k < 3; k++) q[k] = clamp255(q[k] * 0.88f + g[k] * 0.12f * (Luma(q) / 255.0f + 0.3f));
			}
			else
			{
				// grey and dim
				const float l = Luma(q);
				for (int k = 0; k < 3; k++) q[k] = clamp255((l * 0.85f + q[k] * 0.15f) * 0.72f);
			}
			q[3] *= faceDisc.v[i];
		}
		Pic lay = Solid(Disc(n, c, c, R * K), 8, 8, 8);
		Over(lay, f, fo, fo);
		const double rLine = (R - 0.5) * K;
		const Pic line = Solid(Ring(n, c, rLine - std::max(1.0, 0.35 * K), rLine), 70, 70, 70);
		Over(lay, line);
		if (!bOn)
		{
			ToBytes(lay, off);
			continue;
		}
		Pic o(n, n);
		Over(o, GlowOf(lay, g0, g1, g2, 4.5 * K, 1.3f));
		Over(o, GlowOf(lay, l0, l1, l2, 1.6 * K, 0.8f));
		Over(o, lay);
		Mask m = Blur(Disc(n, c, c, R * K + 1.5 * K), 2.5 * K), in = Blur(Disc(n, c, c, (R - RIM - 2.5) * K), 1.5 * K);
		for (size_t i = 0; i < m.v.size(); i++) m.v[i] = clamp01(m.v[i] - in.v[i]) * 0.55f;
		Over(o, Solid(m, aBloom[0], aBloom[1], aBloom[2]));
		Over(o, Solid(Ring(n, c, faceRad, R * K), 8, 8, 8));
		Over(o, line);
		ToBytes(o, on);
	}
	return true;
}

// A part of a picture (out of it: see-through)
Pic Cut(const uint8_t* rgba, int w, int h, int x0, int y0, int cw, int ch)
{
	Pic crop(cw, ch);
	for (int y = 0; y < ch; y++)
		for (int x = 0; x < cw; x++)
		{
			const int sx = x + x0, sy = y + y0;
			float* d = crop.at(x, y);
			if (sx < 0 || sy < 0 || sx >= w || sy >= h) continue;
			const uint8_t* s = rgba + ((size_t)sy * w + sx) * 4;
			d[0] = s[0]; d[1] = s[1]; d[2] = s[2]; d[3] = s[3];
		}
	return crop;
}

// hq4x for small pictures, its room cut off again; large ones as they are
Pic Smooth(const Pic& p)
{
	if (p.w > 160 || p.h > 160) return p;
	Pic big = Hq4(p);
	Pic o(big.w - 16, big.h - 16);
	for (int y = 0; y < o.h; y++) memcpy(o.at(0, y), big.at(8, y + 8), (size_t)o.w * 4 * sizeof(float));
	return o;
}

} // namespace

// CHEAT's sign (the owner's pick: tile 3392 cropped to its circle; on, the
// "hot" look with a crisp black rim). Sizes in points of a 22 pt button,
// the picture n pixels across covering 2 x 22 x SPAN points
bool IOSIconLook_CheatSign(const uint8_t* rgba, int w, int h, int n, std::vector<uint8_t>& on, std::vector<uint8_t>& off)
{
	if (!rgba || w < 32 || h < 32 || n < 32) return false;
	// the sign's yellow: its box is the circle
	int x0 = w, y0 = h, x1 = -1, y1 = -1, ct = 0;
	for (int y = 0; y < h; y++)
		for (int x = 0; x < w; x++)
		{
			const uint8_t* p = rgba + ((size_t)y * w + x) * 4;
			if (p[3] > 128 && p[0] > 140 && p[1] > 110 && p[2] < 90)
			{
				x0 = std::min(x0, x); x1 = std::max(x1, x); y0 = std::min(y0, y); y1 = std::max(y1, y);
				ct++;
			}
		}
	if (x1 < x0) return false;
	const int bw = x1 - x0 + 1, bh = y1 - y0 + 1;
	// (a round sign: square, most of the picture, mostly yellow)
	if (bw < w * 0.7 || bh < h * 0.7 || bw > bh * 1.12 || bh > bw * 1.12 || ct < bw * bh * 0.3) return false;
	const double cx = (x0 + x1 + 1) * 0.5, cy = (y0 + y1 + 1) * 0.5, rad = std::max(bw, bh) * 0.5 - 0.5;
	const int cx0 = (int)lround(cx - rad), cy0 = (int)lround(cy - rad), cx1 = (int)lround(cx + rad), cy1 = (int)lround(cy + rad);
	static const uint8_t orange[3] = { 255, 140, 20 }, yellow[3] = { 255, 200, 60 }, bloom[3] = { 255, 170, 40 };
	return MakeSign(Smooth(Cut(rgba, w, h, cx0, cy0, cx1 - cx0, cy1 - cy0)), n, true, orange, yellow, bloom, on, off);
}

// The other games' signs (IOSIconLook.h)
bool IOSIconLook_CheatSignStyled(const uint8_t* rgba, int w, int h, int n, const IOSIconSignStyle& st, std::vector<uint8_t>& on,
                                 std::vector<uint8_t>& off)
{
	// (the tighter halo: the colour lifted towards white; the bloom between)
	uint8_t light[3], bloom[3];
	for (int c = 0; c < 3; c++)
	{
		light[c] = (uint8_t)(st.aGlow[c] + (255 - st.aGlow[c]) * 0.45f);
		bloom[c] = (uint8_t)((st.aGlow[c] + light[c]) / 2);
	}
	if (!rgba || w < 12 || h < 12 || n < 32) return false;
	int x0 = w, y0 = h, x1 = -1, y1 = -1;
	for (int y = 0; y < h; y++)
		for (int x = 0; x < w; x++)
			if (rgba[((size_t)y * w + x) * 4 + 3] > 128) { x0 = std::min(x0, x); x1 = std::max(x1, x); y0 = std::min(y0, y); y1 = std::max(y1, y); }
	if (x1 < x0) return false;
	const int bw = x1 - x0 + 1, bh = y1 - y0 + 1;
	if (!st.bEmblem)
	{
		// a round sign (its shape may be an ellipse: made round), cropped to
		// a circle about a point of it
		if (bw < 24 || bh < 24 || bw > bh * 1.3 || bh > bw * 1.3) return false;
		const double hx = bw * 0.5 * st.fCrop, hy = bh * 0.5 * st.fCrop;
		const double cx = x0 + bw * 0.5 + st.fCx * bw * 0.5, cy = y0 + bh * 0.5 + st.fCy * bh * 0.5;
		const int cx0 = (int)lround(cx - hx), cy0 = (int)lround(cy - hy);
		return MakeSign(Smooth(Cut(rgba, w, h, cx0, cy0, (int)lround(cx + hx) - cx0, (int)lround(cy + hy) - cy0)), n, false, st.aGlow, light, bloom, on, off);
	}
	// an emblem: on a disc of the game's colour, darkening to its edge, the
	// emblem's larger side fEmblem of the disc across, a soft shadow under it
	Pic em = Smooth(Cut(rgba, w, h, x0, y0, bw, bh));
	Enhance(em, 1.1f, 1.1f, 1.15f, 0.95f);
	const int D = 512;
	const double k = D * st.fEmblem / std::max(em.w, em.h);
	const int ew = std::max(1, (int)lround(em.w * k)), eh = std::max(1, (int)lround(em.h * k));
	const Pic e = Resize(em, ew, eh);
	Pic face(D, D);
	for (int y = 0; y < D; y++)
		for (int x = 0; x < D; x++)
		{
			const float r = (float)(hypot(x + 0.5 - D * 0.5, y + 0.5 - D * 0.42) / (D * 0.5)), t = clamp01(1.0f - r * 0.75f);
			float* q = face.at(x, y);
			for (int c = 0; c < 3; c++) q[c] = st.aBack[c] * (0.25f + 0.75f * t);
			q[3] = 255;
		}
	const int ex = (D - ew) / 2, ey = (D - eh) / 2;
	Pic shadow = Solid(Blur(AlphaOf(e), D * 0.02), 0, 0, 0, 0.8f);
	Over(face, shadow, ex + D / 80, ey + D / 50);
	Over(face, e, ex, ey);
	return MakeSign(face, n, false, st.aGlow, light, bloom, on, off);
}
