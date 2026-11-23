"""Event art for the S-Tier Eats "Best of 2026" In-App Event.

  python store/events/bestof2026/make_art.py
  -> card_1920x1080.png (EVENT_CARD 16:9) + details_1080x1920.png (EVENT_DETAILS_PAGE 9:16)

Brand: dark purple canvas, accent #6B5CF5 (Color.nightOut), tier colors S red / A orange / B yellow /
C green / F purple, Space Grotesk Bold. A podium (A, S, B) with a crown over S, "BEST OF 2026" above.
The bottom of the 9:16 page stays quiet because the App Store overlays the event text there.
"""
import math, os, random
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(HERE, "..", "..", "..", "WoodlandsEats", "Resources", "Fonts", "SpaceGrotesk-Bold.ttf")
SS = 2  # supersample

TIERS = {"S": (230, 56, 69), "A": (245, 140, 51), "B": (242, 199, 61), "C": (102, 186, 107), "F": (140, 89, 199)}
ACCENT = (107, 92, 245)
BG_TOP, BG_BOT = (20, 18, 28), (44, 30, 96)


def font(px):
    return ImageFont.truetype(FONT, int(px * SS))


def canvas(w, h, glow_xy):
    w, h = w * SS, h * SS
    grad = Image.linear_gradient("L").resize((w, h))
    img = Image.composite(Image.new("RGB", (w, h), BG_BOT), Image.new("RGB", (w, h), BG_TOP), grad)
    glow = Image.new("L", (w, h), 0)
    gx, gy = glow_xy[0] * SS, glow_xy[1] * SS
    r = int(min(w, h) * 0.55)
    ImageDraw.Draw(glow).ellipse((gx - r, gy - r, gx + r, gy + r), fill=150)
    glow = glow.filter(ImageFilter.GaussianBlur(r // 2))
    return Image.composite(Image.new("RGB", (w, h), ACCENT), img, glow)


def confetti(img, n, seed, avoid=None):
    rnd = random.Random(seed)
    d = ImageDraw.Draw(img, "RGBA")
    w, h = img.size
    cols = list(TIERS.values())
    for _ in range(n):
        x, y = rnd.uniform(0, w), rnd.uniform(0, h)
        if avoid and avoid[0] < x < avoid[2] and avoid[1] < y < avoid[3]:
            continue
        s = rnd.uniform(6, 16) * SS
        a = rnd.uniform(0, math.pi)
        c = rnd.choice(cols) + (int(rnd.uniform(110, 210)),)
        pts = [(x + s * math.cos(a + k * math.pi / 2) * (1 if k % 2 == 0 else 0.45),
                y + s * math.sin(a + k * math.pi / 2) * (1 if k % 2 == 0 else 0.45)) for k in range(4)]
        d.polygon(pts, fill=c)


def badge(d, cx, cy, size, letter, color):
    s = size * SS
    x0, y0 = cx * SS - s / 2, cy * SS - s / 2
    d.rounded_rectangle((x0, y0, x0 + s, y0 + s), radius=s * 0.26, fill=color)
    d.text((cx * SS, cy * SS + s * 0.02), letter, font=font(size * 0.6), fill="white", anchor="mm")


def crown(d, cx, base_y, width, color=(255, 214, 92)):
    w = width * SS
    x0, x1 = cx * SS - w / 2, cx * SS + w / 2
    by = base_y * SS
    hgt = w * 0.62
    pts = [(x0, by), (x0, by - hgt * 0.55), (x0 + w * 0.25, by - hgt * 0.25), (cx * SS, by - hgt),
           (x1 - w * 0.25, by - hgt * 0.25), (x1, by - hgt * 0.55), (x1, by)]
    d.polygon(pts, fill=color)
    for px_, py_ in ((x0, by - hgt * 0.55), (cx * SS, by - hgt), (x1, by - hgt * 0.55)):
        r = w * 0.07
        d.ellipse((px_ - r, py_ - r, px_ + r, py_ + r), fill=color)
    d.rectangle((x0, by, x1, by + w * 0.12), fill=(236, 186, 60))


def podium(img, cx, base_y, col_w, unit):
    """Three columns: A (2nd, left), S (1st, center), B (3rd, right)."""
    d = ImageDraw.Draw(img, "RGBA")
    gap = col_w * 0.08
    for letter, pos, hmul in (("A", -1, 2.1), ("S", 0, 3.0), ("B", 1, 1.5)):
        x = cx + pos * (col_w + gap)
        h = unit * hmul
        top = base_y - h
        c = TIERS[letter]
        x0, x1 = (x - col_w / 2) * SS, (x + col_w / 2) * SS
        d.rounded_rectangle((x0, top * SS, x1, base_y * SS), radius=col_w * 0.12 * SS, fill=c)
        d.rounded_rectangle((x0, top * SS, x1, (top + unit * 0.16) * SS), radius=col_w * 0.12 * SS,
                            fill=tuple(min(255, v + 40) for v in c))
        d.text((x * SS, (top + h * 0.5) * SS), letter, font=font(col_w * 0.62), fill="white", anchor="mm")
    crown(d, cx, base_y - unit * 3.0 - unit * 0.18, col_w * 0.62)


def finish(img, path):
    w, h = img.size
    img.resize((w // SS, h // SS), Image.LANCZOS).save(path, optimize=True)
    print("wrote", path)


def card():
    W, H = 1920, 1080
    img = canvas(W, H, (W * 0.5, H * 0.62))
    confetti(img, 160, 7, avoid=(W * 0.24 * SS, 0, W * 0.76 * SS, H * SS))
    d = ImageDraw.Draw(img, "RGBA")
    d.text((W / 2 * SS, 140 * SS), "BEST OF", font=font(64), fill=(255, 255, 255, 225), anchor="mm")
    d.text((W / 2 * SS, 250 * SS), "2026", font=font(150), fill="white", anchor="mm")
    podium(img, W / 2, 1000, 230, 185)
    finish(img, os.path.join(HERE, "card_1920x1080.png"))


def details():
    W, H = 1080, 1920
    img = canvas(W, H, (W * 0.5, H * 0.42))
    confetti(img, 170, 11, avoid=(W * 0.12 * SS, H * 0.1 * SS, W * 0.88 * SS, H * 0.72 * SS))
    d = ImageDraw.Draw(img, "RGBA")
    d.text((W / 2 * SS, 300 * SS), "BEST OF", font=font(78), fill=(255, 255, 255, 225), anchor="mm")
    d.text((W / 2 * SS, 440 * SS), "2026", font=font(190), fill="white", anchor="mm")
    podium(img, W / 2, 1180, 250, 165)
    for i, (letter, c) in enumerate(TIERS.items()):
        badge(d, W / 2 + (i - 2) * 112, 1290, 88, letter, c)
    finish(img, os.path.join(HERE, "details_1080x1920.png"))


if __name__ == "__main__":
    card()
    details()
