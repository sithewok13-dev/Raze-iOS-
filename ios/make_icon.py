#!/usr/bin/env python3
"""Draws the app's home-screen icon, ios/AppIcon-1024.png.

An original picture, nothing from any game: a blocky orange "R" standing on
a receding floor grid (a nod to the Build engine's sectors), on a dark
background. The build (source/CMakeLists.txt) scales the PNG down to the
sizes iOS uses. Re-run after a change and commit the PNG with it:

    python3 ios/make_icon.py

Needs Pillow (pip install pillow).
"""
import os
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SS = 4                      # drawn 4x bigger, then scaled down (smooth edges)
W = SIZE * SS
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "AppIcon-1024.png")


def u(v):
    """A position on a 0..100 grid, in pixels of the big drawing"""
    return v * W / 100.0


def pts(poly):
    return [(u(x), u(y)) for x, y in poly]


def vgradient(top, bottom, y0=0.0, y1=100.0):
    """An RGB picture the whole size, top colour at y0 to bottom at y1"""
    g = Image.new("RGB", (1, 256))
    for i in range(256):
        t = i / 255.0
        g.putpixel((0, i), tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    band = g.resize((W, max(1, int(u(y1) - u(y0)))), Image.BILINEAR)
    img = Image.new("RGB", (W, W), top)
    img.paste(Image.new("RGB", (W, W - int(u(y1))), bottom), (0, int(u(y1))))
    img.paste(band, (0, int(u(y0))))
    return img


# Background: near black, a little blue, lighter toward the floor
img = vgradient((8, 10, 18), (22, 26, 40))

# The floor grid, below a horizon, its lines meeting at one point
HORIZON = 60.0
VX = 50.0
grid = Image.new("L", (W, W), 0)
gd = ImageDraw.Draw(grid)
line = max(1, int(u(0.55)))
for i in range(-9, 10):                  # lines running away from us
    gd.line([(u(VX), u(HORIZON)), (u(VX + i * 16.0), u(100))], fill=255, width=line)
z = 1.0
while True:                              # lines across, closer together far off
    y = HORIZON + 40.0 / z
    if y > 100:
        z += 0.6
        continue
    if y - HORIZON < 0.8:
        break
    gd.line([(0, u(y)), (W, u(y))], fill=255, width=line)
    z += 0.6
# Fade the grid out toward the horizon
fade = vgradient((0, 0, 0), (255, 255, 255), HORIZON, 100).convert("L")
grid = Image.composite(grid, Image.new("L", (W, W), 0), fade)
grid = grid.point(lambda v: v * 150 // 255)
img.paste((255, 120, 30), (0, 0), grid)

# A soft glow along the horizon
glow = Image.new("L", (W, W), 0)
ImageDraw.Draw(glow).rectangle([0, u(HORIZON - 0.6), W, u(HORIZON + 0.6)], fill=255)
glow = glow.filter(ImageFilter.GaussianBlur(u(2.2)))
img.paste((255, 140, 50), (0, 0), glow.point(lambda v: v * 170 // 255))
img.paste((255, 170, 90), (0, 0), Image.eval(glow, lambda v: 255 if v > 200 else 0))

# The "R": a blocky letter with cut corners, its hole showing the grid
R_OUTER = [(25, 17), (62, 17), (75, 30), (75, 44), (65, 53.5), (78, 83), (62.5, 83),
           (51.5, 57), (40, 57), (40, 83), (25, 83)]
R_HOLE = [(40, 30), (57, 30), (61, 34), (61, 41), (57, 45), (40, 45)]
mask = Image.new("L", (W, W), 0)
md = ImageDraw.Draw(mask)
md.polygon(pts(R_OUTER), fill=255)
md.polygon(pts(R_HOLE), fill=0)

# Its depth: the letter pushed back down and to the right, in dark red
DEPTH = 3.2
steps = 24
for s in range(steps, 0, -1):
    d = u(DEPTH * s / steps)
    t = s / steps
    colour = (int(110 - 60 * t), int(22 - 12 * t), int(8 - 4 * t))
    img.paste(colour, (int(d), int(d)), mask)

# A dark shadow on the floor
shadow = Image.new("L", (W, W), 0)
shadow.paste(mask, (int(u(DEPTH + 1.5)), int(u(DEPTH + 1.5))))
shadow = shadow.filter(ImageFilter.GaussianBlur(u(1.8)))
face_and_depth = Image.new("L", (W, W), 0)
for s in range(steps + 1):
    face_and_depth.paste(255, (int(u(DEPTH * s / steps)),) * 2, mask)
shadow = Image.composite(Image.new("L", (W, W), 0), shadow, face_and_depth)
img.paste((0, 0, 0), (0, 0), shadow.point(lambda v: v * 160 // 255))

# The face: bright amber at the top to deep orange-red at the bottom
face = vgradient((255, 214, 92), (232, 72, 18), 17, 83)
img.paste(face, (0, 0), mask)

# A thin light edge on the top-left sides of the face
edge = Image.new("L", (W, W), 0)
edge.paste(mask, (0, 0))
inner = Image.new("L", (W, W), 0)
inner.paste(mask, (int(u(0.9)), int(u(0.9))))
edge = Image.composite(Image.new("L", (W, W), 0), edge, inner)
img.paste((255, 244, 200), (0, 0), edge.point(lambda v: v * 200 // 255))

img = img.resize((SIZE, SIZE), Image.LANCZOS)
img.save(OUT, optimize=True)
print("Wrote", OUT)
