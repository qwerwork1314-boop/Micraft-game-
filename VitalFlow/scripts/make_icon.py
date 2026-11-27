"""Generates the original VitalFlow app icon (1024x1024) and logo.

Design: deep-blue to emerald diagonal gradient, a soft glow, and a white leaf
whose midrib is a heartbeat line — "vital" + "flow". Run: python3 scripts/make_icon.py
"""
import math, os, sys
from PIL import Image, ImageDraw, ImageFilter

S = 4  # supersampling
N = 1024 * S

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def gradient():
    top, mid, bot = (20, 36, 110), (30, 90, 200), (16, 185, 129)
    small = Image.new("RGB", (256, 256))
    px = small.load()
    for y in range(256):
        for x in range(256):
            t = (x + y) / 510
            px[x, y] = lerp(top, mid, t / 0.5) if t < 0.5 else lerp(mid, bot, (t - 0.5) / 0.5)
    return small.resize((N, N), Image.BICUBIC)

def leaf_points(cx, cy, length, width, angle):
    pts = []
    for side in (1, -1):
        rng = range(0, 101) if side == 1 else range(100, -1, -1)
        for i in rng:
            t = i / 100
            x = (t - 0.5) * length
            y = side * width * math.sin(math.pi * t) ** 0.9 * (1 - 0.25 * t)
            ca, sa = math.cos(angle), math.sin(angle)
            pts.append((cx + x * ca - y * sa, cy + x * sa + y * ca))
    return pts

def main(out_dir):
    img = gradient().convert("RGBA")
    glow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    r = int(N * 0.36)
    gd.ellipse((N // 2 - r, N // 2 - r, N // 2 + r, N // 2 + r), fill=(255, 255, 255, 38))
    glow = glow.filter(ImageFilter.GaussianBlur(N * 0.08))
    img = Image.alpha_composite(img, glow)

    layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    angle = -math.radians(40)
    cx, cy = N * 0.5, N * 0.52
    d.polygon(leaf_points(cx, cy, N * 0.66, N * 0.21, angle), fill=(255, 255, 255, 245))

    # Heartbeat midrib in emerald, flowing along the leaf axis.
    L = N * 0.50
    ca, sa = math.cos(angle), math.sin(angle)
    profile = [(0, 0), (0.30, 0), (0.38, -0.06), (0.46, 0.10), (0.54, -0.16), (0.62, 0.04), (0.70, 0), (1, 0)]
    pts = []
    for t, h in profile:
        x = (t - 0.5) * L
        y = h * N * 0.5
        pts.append((cx + x * ca - y * sa, cy + x * sa + y * ca))
    d.line(pts, fill=(4, 120, 87, 255), width=int(N * 0.028), joint="curve")
    for p in (pts[0], pts[-1]):
        rr = N * 0.014
        d.ellipse((p[0] - rr, p[1] - rr, p[0] + rr, p[1] + rr), fill=(4, 120, 87, 255))

    shadow = layer.split()[3].filter(ImageFilter.GaussianBlur(N * 0.02))
    sh = Image.new("RGBA", (N, N), (6, 20, 60, 0))
    sh.putalpha(shadow.point(lambda a: int(a * 0.45)))
    img = Image.alpha_composite(img, sh.transform(sh.size, Image.AFFINE, (1, 0, 0, 0, 1, -N * 0.012)))
    img = Image.alpha_composite(img, layer)
    final = img.resize((1024, 1024), Image.LANCZOS).convert("RGB")
    os.makedirs(out_dir, exist_ok=True)
    final.save(os.path.join(out_dir, "AppIcon-1024.png"))
    return final

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "build/icon")
