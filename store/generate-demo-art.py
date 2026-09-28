#!/usr/bin/env python3
# Erzeugt die Cover des Demomodus nach qml/demo/art/*.jpg: abstrakte Motive
# (Verläufe, Kreise, Wellen) ohne Schrift, Marken oder echte Alben -- die
# Demo zeigt erfundene Musik, und Store-Bildschirmfotos dürfen keine fremden
# Cover enthalten. Deterministisch: derselbe Aufruf ergibt dieselben Bilder.
# Braucht python3-pil. Aufruf aus dem Projektverzeichnis:
#   python3 store/generate-demo-art.py
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

SIZE = 512
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "qml", "demo", "art")

# Schlüssel -> (Farbe oben links, Farbe unten rechts, Motiv). Die Schlüssel
# benutzt qml/lib/DemoData.js.
ART = {
    "weite-felder":   ((0x1f, 0x3b, 0x2d), (0xd9, 0xc2, 0x6a), "horizon"),
    "sommerregen":    ((0x21, 0x4e, 0x78), (0x9f, 0xd3, 0xe8), "drops"),
    "kleine-stunden": ((0x2a, 0x1b, 0x3d), (0xf2, 0x9e, 0x6b), "moon"),
    "nachtzug":       ((0x0e, 0x12, 0x24), (0x5b, 0x4b, 0xc4), "lines"),
    "studio":         ((0x3d, 0x1c, 0x12), (0xe0, 0x7a, 0x3a), "rings"),
    "glas-und-sand":  ((0xe8, 0xd8, 0xb8), (0x5f, 0x8f, 0x8a), "dunes"),
    "low-tide":       ((0x06, 0x2a, 0x3a), (0x3f, 0xc1, 0xb0), "waves"),
    "ostwind":        ((0x44, 0x44, 0x4c), (0xc9, 0xcc, 0xd6), "strokes"),
    "nordlicht":      ((0x05, 0x1a, 0x24), (0x49, 0xe0, 0x9a), "aurora"),
    "mira":           ((0x4a, 0x1d, 0x3f), (0xf5, 0xb8, 0xc4), "circle"),
    "kupferbahn":     ((0x2b, 0x14, 0x0c), (0xc8, 0x6b, 0x33), "rings"),
    "leonie":         ((0x1c, 0x2e, 0x4a), (0xe6, 0xe1, 0xd3), "circle"),
    "tidal":          ((0x0b, 0x33, 0x2e), (0x86, 0xd0, 0xc0), "waves"),
    "kollektiv":      ((0x30, 0x30, 0x30), (0xf0, 0xc0, 0x40), "strokes"),
    "sonntag":        ((0xf6, 0xd3, 0x65), (0xfd, 0xa0, 0x85), "circle"),
    "kochen":         ((0x7a, 0x2e, 0x1d), (0xf4, 0xa2, 0x61), "drops"),
    "fokus":          ((0x10, 0x10, 0x18), (0x3a, 0x6e, 0xa5), "lines"),
    "alpenwelle":     ((0x1d, 0x4e, 0x89), (0xff, 0xff, 0xff), "horizon"),
    "jazz-express":   ((0x1a, 0x0a, 0x2e), (0xd4, 0xa0, 0x17), "rings"),
    "sternwarte":     ((0x08, 0x0c, 0x2a), (0x6c, 0x7b, 0xd9), "stars"),
    "hoersaal":       ((0x2f, 0x2a, 0x6b), (0xb0, 0x6a, 0xb3), "waves"),
    "klangwelle-1":   ((0x3a, 0x0c, 0x3d), (0xff, 0x6f, 0x91), "circle"),
    "klangwelle-2":   ((0x0c, 0x3a, 0x2d), (0xc6, 0xf6, 0x8d), "dunes"),
}


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(c1, c2):
    img = Image.new("RGB", (SIZE, SIZE))
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            px[x, y] = lerp(c1, c2, (x + y) / (2.0 * (SIZE - 1)))
    return img


def motif(img, kind, rnd, c1, c2):
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    white = (255, 255, 255)
    if kind == "horizon":
        d.ellipse((136, 150, 376, 390), fill=white + (70,))
        d.rectangle((0, 330, SIZE, SIZE), fill=c1 + (220,))
    elif kind == "drops":
        for _ in range(26):
            x, y, r = rnd.randint(0, SIZE), rnd.randint(0, SIZE), rnd.randint(8, 42)
            d.ellipse((x - r, y - r, x + r, y + r), outline=white + (110,), width=3)
    elif kind == "moon":
        d.ellipse((150, 110, 380, 340), fill=white + (190,))
        d.ellipse((210, 90, 430, 310), fill=c1 + (255,))
    elif kind == "lines":
        for i in range(14):
            y = 60 + i * 30
            d.line((0, y, SIZE, y - 120), fill=white + (40 + i * 10,), width=4)
    elif kind == "rings":
        for r in range(40, 250, 26):
            d.ellipse((256 - r, 256 - r, 256 + r, 256 + r), outline=white + (150,), width=5)
        d.ellipse((236, 236, 276, 276), fill=white + (200,))
    elif kind == "dunes":
        for i in range(5):
            pts = [(x, 250 + i * 55 + 30 * math.sin(x / 60.0 + i)) for x in range(0, SIZE + 8, 8)]
            d.polygon(pts + [(SIZE, SIZE), (0, SIZE)], fill=lerp(c2, c1, i / 5.0) + (150,))
    elif kind == "waves":
        for i in range(9):
            pts = [(x, 90 + i * 45 + 18 * math.sin(x / 38.0 + i * 0.8)) for x in range(0, SIZE + 4, 4)]
            d.line(pts, fill=white + (170,), width=5)
    elif kind == "strokes":
        for _ in range(12):
            x = rnd.randint(-100, SIZE)
            d.line((x, SIZE, x + 260, 0), fill=white + (rnd.randint(60, 200),), width=rnd.randint(6, 26))
    elif kind == "aurora":
        for i in range(6):
            pts = [(x, 120 + i * 22 + 70 * math.sin(x / 90.0 + i * 0.5)) for x in range(0, SIZE + 4, 4)]
            d.line(pts, fill=(120, 255, 190, 90), width=18)
    elif kind == "circle":
        d.ellipse((96, 96, 416, 416), fill=white + (60,))
        d.ellipse((176, 176, 336, 336), fill=c1 + (230,))
    elif kind == "stars":
        for _ in range(140):
            x, y, r = rnd.randint(0, SIZE), rnd.randint(0, SIZE), rnd.choice((1, 1, 2, 3))
            d.ellipse((x - r, y - r, x + r, y + r), fill=white + (rnd.randint(120, 255),))
        d.arc((60, 300, 452, 700), 180, 360, fill=white + (200,), width=6)
    layer = layer.filter(ImageFilter.GaussianBlur(1.2))
    img.paste(layer, (0, 0), layer)
    return img


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for index, (key, (c1, c2, kind)) in enumerate(sorted(ART.items())):
        rnd = random.Random(index * 7919 + 17)
        img = motif(gradient(c1, c2), kind, rnd, c1, c2)
        img.save(os.path.join(OUT_DIR, key + ".jpg"), quality=82, optimize=True)
    print("%d Bilder nach %s" % (len(ART), os.path.normpath(OUT_DIR)))


if __name__ == "__main__":
    main()
