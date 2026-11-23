"""Event art for the S-Tier Eats "Date Night Tiers" Valentine In-App Event.

  python store/events/datenight2027/make_art.py
  -> card_1920x1080.png (EVENT_CARD 16:9) + details_1080x1920.png (EVENT_DETAILS_PAGE 9:16)

Rose-to-plum canvas, Space Grotesk Bold, a stack of tier bars (S on top) under a big heart,
floating small hearts. The bottom of the 9:16 page stays quiet for the App Store text overlay.
"""
import math, os, random
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(HERE, "..", "..", "..", "WoodlandsEats", "Resources", "Fonts", "SpaceGrotesk-Bold.ttf")
SS = 2

TIERS = [("S", (230, 56, 69)), ("A", (245, 140, 51)), ("B", (242, 199, 61)), ("C", (102, 186, 107)), ("F", (140, 89, 199))]
ROSE = (232, 69, 120)
BG_TOP, BG_BOT = (38, 10, 36), (92, 22, 70)


def font(px):
    return ImageFont.truetype(FONT, int(px * SS))


def canvas(w, h, glow_xy):
    w, h = w * SS, h * SS
    grad = Image.linear_gradient("L").resize((w, h))
    img = Image.composite(Image.new("RGB", (w, h), BG_BOT), Image.new("RGB", (w, h), BG_TOP), grad)
    glow = Image.new("L", (w, h), 0)
    gx, gy, r = glow_xy[0] * SS, glow_xy[1] * SS, int(min(w, h) * 0.55)
    ImageDraw.Draw(glow).ellipse((gx - r, gy - r, gx + r, gy + r), fill=140)
    glow = glow.filter(ImageFilter.GaussianBlur(r // 2))
    return Image.composite(Image.new("RGB", (w, h), ROSE), img, glow)


def heart_pts(cx, cy, size, steps=90):
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((cx + x * size / 32, cy - y * size / 32))
    return pts


def hearts(img, n, seed, avoid):
    rnd = random.Random(seed)
    d = ImageDraw.Draw(img, "RGBA")
    w, h = img.size
    for _ in range(n):
        x, y = rnd.uniform(0, w), rnd.uniform(0, h)
        if avoid[0] < x < avoid[2] and avoid[1] < y < avoid[3]:
            continue
        s = rnd.uniform(14, 40) * SS
        c = rnd.choice([ROSE, (255, 140, 170), (255, 214, 92), (255, 255, 255)]) + (int(rnd.uniform(60, 170)),)
        d.polygon(heart_pts(x, y, s), fill=c)


def bars(d, cx, top_y, width, bar_h, gap):
    """Tier bars S..F, S widest, like the app icon."""
    for i, (letter, c) in enumerate(TIERS):
        w = width * (1 - i * 0.12)
        y = top_y + i * (bar_h + gap)
        x0, x1 = (cx - w / 2) * SS, (cx + w / 2) * SS
        d.rounded_rectangle((x0, y * SS, x1, (y + bar_h) * SS), radius=bar_h * 0.3 * SS, fill=c)
        d.text((x0 + bar_h * 0.55 * SS, (y + bar_h / 2) * SS), letter, font=font(bar_h * 0.62), fill="white", anchor="mm")


def finish(img, path):
    w, h = img.size
    img.resize((w // SS, h // SS), Image.LANCZOS).save(path, optimize=True)
    print("wrote", path)


def card():
    W, H = 1920, 1080
    img = canvas(W, H, (W * 0.5, H * 0.55))
    hearts(img, 70, 3, (W * 0.26 * SS, 0, W * 0.74 * SS, H * SS))
    d = ImageDraw.Draw(img, "RGBA")
    d.text((W / 2 * SS, 120 * SS), "DATE NIGHT", font=font(110), fill="white", anchor="mm")
    d.text((W / 2 * SS, 215 * SS), "TIERS", font=font(64), fill=(255, 220, 230, 235), anchor="mm")
    d.polygon(heart_pts(W / 2 * SS, 420 * SS, 230 * SS), fill=ROSE)
    d.polygon(heart_pts(W / 2 * SS, 412 * SS, 170 * SS), fill=(255, 120, 160))
    d.text((W / 2 * SS, 408 * SS), "S", font=font(110), fill="white", anchor="mm")
    bars(d, W / 2, 600, 640, 66, 14)
    finish(img, os.path.join(HERE, "card_1920x1080.png"))


def details():
    W, H = 1080, 1920
    img = canvas(W, H, (W * 0.5, H * 0.4))
    hearts(img, 80, 5, (W * 0.08 * SS, H * 0.1 * SS, W * 0.92 * SS, H * 0.7 * SS))
    d = ImageDraw.Draw(img, "RGBA")
    d.text((W / 2 * SS, 290 * SS), "DATE NIGHT", font=font(120), fill="white", anchor="mm")
    d.text((W / 2 * SS, 400 * SS), "TIERS", font=font(80), fill=(255, 220, 230, 235), anchor="mm")
    d.polygon(heart_pts(W / 2 * SS, 650 * SS, 300 * SS), fill=ROSE)
    d.polygon(heart_pts(W / 2 * SS, 640 * SS, 220 * SS), fill=(255, 120, 160))
    d.text((W / 2 * SS, 636 * SS), "S", font=font(140), fill="white", anchor="mm")
    bars(d, W / 2, 880, 720, 72, 16)
    finish(img, os.path.join(HERE, "details_1080x1920.png"))


if __name__ == "__main__":
    card()
    details()
