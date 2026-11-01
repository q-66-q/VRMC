#!/usr/bin/env python3
"""Generate the VRMC app icon into an Amethyst 1.2.0 tree.

Usage: python3 scripts/make_icon.py /path/to/Amethyst-1.2.0-tree
Requires Pillow. The committed PNGs in assets/branding/ are the canonical output; this script
documents/regenerates them (gradient + isometric cube + VRMC wordmark).
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve() / "Natives/Assets.xcassets"

def font(size):
    for p in ["/System/Library/Fonts/Supplemental/Arial Bold.ttf",
              "/System/Library/Fonts/Supplemental/Arial.ttf"]:
        try:
            return ImageFont.truetype(p, size)
        except OSError:
            pass
    return ImageFont.load_default()

def gradient(size=1024, top=(9, 24, 38), bottom=(14, 74, 92)):
    im = Image.new("RGB", (size, size), top)
    d = ImageDraw.Draw(im)
    for y in range(size):
        t = y / (size - 1)
        d.line([(0, y), (size, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return im

def glyph(im, fg=(255, 255, 255), accent=(64, 224, 208)):
    d = ImageDraw.Draw(im)
    s = im.size[0]
    d.rounded_rectangle([int(s*0.10), int(s*0.10), int(s*0.90), int(s*0.90)],
                        radius=int(s*0.18), outline=accent, width=int(s*0.012))
    text = "VRMC"
    f = font(int(s*0.17))
    bb = d.textbbox((0, 0), text, font=f)
    d.text(((s-(bb[2]-bb[0]))/2 - bb[0], int(s*0.40) - (bb[3]-bb[1])/2 - bb[1]), text, font=f, fill=fg)
    sub, f2 = "VISION", font(int(s*0.045))
    bb2 = d.textbbox((0, 0), sub, font=f2)
    d.text(((s-(bb2[2]-bb2[0]))/2 - bb2[0], int(s*0.60)), sub, font=f2, fill=accent)
    cx, cy, r = int(s*0.5), int(s*0.30), int(s*0.075)
    pts = [(cx, cy-r), (cx+r, cy-r//2), (cx+r, cy+r//2), (cx, cy+r), (cx-r, cy+r//2), (cx-r, cy-r//2)]
    d.polygon(pts, outline=accent, width=int(s*0.008))
    for a, b in [((cx, cy-r), (cx, cy)), ((cx-r, cy-r//2), (cx, cy)), ((cx+r, cy-r//2), (cx, cy))]:
        d.line([a, b], fill=accent, width=int(s*0.008))
    return im

def main():
    base = glyph(gradient())
    base.save(OUT / "AppIcon-Light.appiconset/1024x1024.png")
    tr = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    glyph(tr, fg=(255, 255, 255), accent=(94, 234, 212))
    tr.save(OUT / "AppIcon-Light.appiconset/1024x1024-Transparent.png")
    mono = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    glyph(mono, fg=(255, 255, 255), accent=(255, 255, 255))
    mono.save(OUT / "AppIcon-Light.appiconset/1024x1024-Monochrome-White.png")
    base.save(OUT / "AppIcon-Dark.appiconset/AppIcon-Dark_1024x1024.png")
    base.save(OUT / "AppIcon-Development.appiconset/AppIcon-Development_1024x1024.png")
    print(f"icons written under {OUT}")

if __name__ == "__main__":
    main()
