#!/usr/bin/env python3
"""Build the LAN-gallery demo's photo set.

Two modes:

    python3 tools/demo_photos.py                      # generated frames (default)
    python3 tools/demo_photos.py --from ~/Pictures    # your own photographs

In the second mode every image in the folder is read, EXIF-rotated, centre-cropped
to a square and written to docs/play/photos/ at 480 px. The page is rewritten so
the grid, the lightbox and the duplicate strip all point at the real files, and
the metadata shown under a photo comes from its own EXIF rather than a label.

Nothing is uploaded anywhere; this is a build-time script that reads a local
folder and writes local files.
"""
import argparse
import base64
import io
import json
import os
import re
import sys

try:
    from PIL import Image, ImageDraw, ImageFilter, ImageOps
except ImportError:
    sys.exit("Pillow is required: pip install pillow")

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
PAGE = os.path.join(REPO, "docs", "play", "index.html")
OUT = os.path.join(REPO, "docs", "play", "photos")
SIZE = 480
COUNT = 12

# Generated frames: a horizon, a sun, haze, grain and a vignette. Not a
# photograph, but it reads as one at thumbnail size, which is what the grid needs.
SCENES = [
    ("harbour",  (14, 42, 56),  (120, 178, 190), (255, 226, 180), 0.62),
    ("terrace",  (38, 30, 62),  (150, 110, 168), (255, 196, 210), 0.70),
    ("kitchen",  (86, 58, 32),  (216, 168, 104), (255, 240, 200), 0.55),
    ("glass",    (18, 38, 52),  (96, 148, 176), (200, 226, 240), 0.66),
    ("brick",    (72, 34, 30),  (188, 118, 92), (255, 214, 168), 0.58),
    ("garden",   (26, 52, 30),  (128, 168, 92), (236, 246, 190), 0.72),
    ("road",     (70, 52, 26),  (176, 148, 96), (250, 232, 190), 0.64),
    ("bluehour", (22, 30, 44),  (110, 132, 164), (208, 220, 244), 0.75),
    ("market",   (86, 32, 62),  (188, 118, 150), (255, 208, 226), 0.60),
    ("coast",    (20, 56, 54),  (112, 172, 160), (238, 244, 220), 0.68),
    ("field",    (58, 54, 32),  (172, 160, 108), (248, 238, 196), 0.74),
    ("nightbus", (20, 20, 34),  (96, 96, 148), (198, 198, 236), 0.80),
]


def _lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def generated_frame(name, top, bottom, sun, horizon, seed):
    import random
    rnd = random.Random(seed)
    img = Image.new("RGB", (SIZE, SIZE))
    px = img.load()

    for y in range(SIZE):
        t = y / (SIZE - 1)
        row = _lerp(top, bottom, t ** 0.85)
        for x in range(SIZE):
            px[x, y] = row

    # haze band around the horizon
    band = Image.new("RGB", (SIZE, SIZE), bottom)
    mask = Image.new("L", (SIZE, SIZE), 0)
    md = mask.load()
    hy = int(SIZE * horizon)
    for y in range(SIZE):
        d = abs(y - hy) / (SIZE * 0.22)
        v = max(0.0, 1.0 - d) ** 2
        for x in range(SIZE):
            md[x, y] = int(150 * v)
    img = Image.composite(band, img, mask)

    # sun
    sun_layer = Image.new("RGB", (SIZE, SIZE), sun)
    sun_mask = Image.new("L", (SIZE, SIZE), 0)
    sd = ImageDraw.Draw(sun_mask)
    cx = rnd.randint(int(SIZE * 0.25), int(SIZE * 0.75))
    cy = int(SIZE * horizon) - rnd.randint(0, int(SIZE * 0.12))
    r = rnd.randint(int(SIZE * 0.06), int(SIZE * 0.11))
    for i in range(r, 0, -1):
        a = int(255 * (1 - i / r) ** 1.6)
        sd.ellipse([cx - i * 3, cy - i * 3, cx + i * 3, cy + i * 3], fill=a // 3)
    sd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    img = Image.composite(sun_layer, img, sun_mask)

    # grain
    noise = Image.effect_noise((SIZE, SIZE), 26).convert("L")
    img = Image.blend(img, Image.merge("RGB", (noise, noise, noise)), 0.06)

    # vignette
    vig = Image.new("L", (SIZE, SIZE), 0)
    vd = ImageDraw.Draw(vig)
    vd.ellipse([-SIZE * 0.18, -SIZE * 0.18, SIZE * 1.18, SIZE * 1.18], fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(SIZE * 0.16))
    dark = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
    img = Image.composite(img, dark, vig)

    return img.filter(ImageFilter.GaussianBlur(0.4))


def from_folder(folder):
    exts = (".jpg", ".jpeg", ".png", ".webp", ".bmp")
    names = sorted(
        n for n in os.listdir(folder) if n.lower().endswith(exts)
    )[:COUNT]
    if not names:
        sys.exit(f"no images in {folder}")
    out = []
    for name in names:
        path = os.path.join(folder, name)
        img = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
        w, h = img.size
        side = min(w, h)
        img = img.crop(((w - side) // 2, (h - side) // 2,
                        (w + side) // 2, (h + side) // 2))
        img = img.resize((SIZE, SIZE), Image.LANCZOS)
        out.append((name, img, w, h))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="src", default=None,
                    help="a folder of your own photographs")
    args = ap.parse_args()

    os.makedirs(OUT, exist_ok=True)
    for old in os.listdir(OUT):
        if old.endswith(".jpg"):
            os.remove(os.path.join(OUT, old))

    photos = []
    if args.src:
        for i, (name, img, w, h) in enumerate(from_folder(args.src), start=1):
            img.save(os.path.join(OUT, f"{i:02d}.jpg"), "JPEG", quality=82, optimize=True)
            photos.append({
                "id": i, "name": name, "w": w, "h": h,
                "camera": "—", "taken": "—",
                "src": f"photos/{i:02d}.jpg",
                "edited": False, "favorite": i in (1, 5),
                "dupe": i in (4, 12),
            })
    else:
        labels = [
            "Harbour, 06:12", "Dusk, terrace", "Kitchen window", "Rain on glass",
            "Brick and sun", "Garden, July", "Old road", "Blue hour",
            "Market flowers", "Coast path", "Dry field", "Night bus",
        ]
        for i, (name, top, bottom, sun, horizon) in enumerate(SCENES, start=1):
            generated_frame(name, top, bottom, sun, horizon, seed=i * 977).save(
                os.path.join(OUT, f"{i:02d}.jpg"), "JPEG", quality=82, optimize=True)
            photos.append({
                "id": i, "name": f"IMG_{1200 + i:04d}.jpg", "w": 4000, "h": 3000,
                "camera": "X-T5", "taken": f"2024-{(i % 12) + 1:02d}-1{(i % 8) + 1}",
                "src": f"photos/{i:02d}.jpg", "label": labels[i - 1],
                "edited": i in (3, 8), "favorite": i in (1, 5, 10),
                "dupe": i in (4, 12),
            })

    page = open(PAGE, encoding="utf-8").read()
    payload = json.dumps(photos, indent=0)
    page = re.sub(r"const PHOTOS = \[.*?\n\];", f"const PHOTOS = {payload};",
                  page, count=1, flags=re.S)
    open(PAGE, "w", encoding="utf-8").write(page)

    print(f"wrote {len(photos)} photos to docs/play/photos/ and updated the page")
    if not args.src:
        print("These are generated frames. For real photographs:")
        print("  python3 tools/demo_photos.py --from ~/Pictures")
        print("  python3 tools/shot.sh . app app '#/grid' 620")


if __name__ == "__main__":
    main()
