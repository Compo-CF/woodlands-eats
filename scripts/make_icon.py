"""Generate the WoodlandsEats 1024x1024 app icon.

Motif: the S/A/B/C/F tier stack in the app's tier colors on a warm background —
instantly reads as "tier-list" and reuses the exact palette from Tier.color.
Output is flat RGB (no alpha) as App Store requires.
"""
from PIL import Image, ImageDraw, ImageFont

SIZE = 1024
OUT = "WoodlandsEats/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

# Tier colors — must match Tier.color in Enums.swift
TIERS = [
    ("S", (230, 56, 69)),
    ("A", (245, 140, 51)),
    ("B", (242, 199, 61)),
    ("C", (102, 186, 107)),
    ("F", (140, 89, 199)),
]

BG_TOP = (38, 30, 26)      # warm charcoal, subtle vertical gradient
BG_BOTTOM = (22, 16, 14)


def gradient_bg(size, top, bottom):
    img = Image.new("RGB", (size, size), top)
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        r = round(top[0] + (bottom[0] - top[0]) * t)
        g = round(top[1] + (bottom[1] - top[1]) * t)
        b = round(top[2] + (bottom[2] - top[2]) * t)
        for x in range(size):
            px[x, y] = (r, g, b)
    return img


def load_font(size):
    for path in ("C:/Windows/Fonts/ariblk.ttf", "C:/Windows/Fonts/arialbd.ttf"):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def main():
    img = gradient_bg(SIZE, BG_TOP, BG_BOTTOM)
    d = ImageDraw.Draw(img)

    margin_x = 188
    top = 196
    bottom = 828
    gap = 26
    n = len(TIERS)
    bar_h = (bottom - top - gap * (n - 1)) // n
    radius = bar_h // 3
    font = load_font(int(bar_h * 0.6))

    for i, (letter, color) in enumerate(TIERS):
        y0 = top + i * (bar_h + gap)
        y1 = y0 + bar_h
        d.rounded_rectangle([margin_x, y0, SIZE - margin_x, y1], radius=radius, fill=color)
        d.text((margin_x + 54, (y0 + y1) // 2), letter, font=font,
               fill=(255, 255, 255), anchor="lm")

    img.save(OUT, "PNG")
    print(f"Wrote {OUT} ({img.size[0]}x{img.size[1]}, mode={img.mode})")


if __name__ == "__main__":
    main()
