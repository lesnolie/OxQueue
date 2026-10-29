"""Generate OxQueue's anti-aliased textures (white + alpha TGAs, tinted in game).

circleN.tga  - discs at several sizes, so corners are never minified much (no mipmaps
               on addon TGAs, so heavy downscaling is what makes edges look jagged)
glyph_*.tga  - traffic-light symbols, pre-rendered instead of rotated 1px textures
shadow.tga   - one gaussian-blurred rounded rect, drawn as a 9-slice window shadow
"""
from pathlib import Path
import math
import struct

MEDIA = Path(__file__).resolve().parents[1] / "OxQueue" / "Media"
SS = 4  # supersamples per axis


def write_tga(path, size, alpha):
    px = bytearray()
    for a in alpha:
        px += bytes((255, 255, 255, max(0, min(255, round(a * 255)))))
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 0x28)
    path.write_bytes(header + px)


def coverage(size, inside):
    out = []
    for y in range(size):
        for x in range(size):
            hits = 0
            for sy in range(SS):
                for sx in range(SS):
                    hits += inside(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS)
            out.append(hits / (SS * SS))
    return out


def circle(n):
    c, r = n / 2, n / 2
    return coverage(n, lambda x, y: (x - c) ** 2 + (y - c) ** 2 <= r * r)


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def glyph(n, segments, width):
    def inside(x, y):
        return any(seg_dist(x, y, *s) <= width / 2 for s in segments)
    return coverage(n, inside)


def shadow(n=128, margin=32, radius=16, sigma=9.0, peak=1.0):
    lo, hi = margin, n - margin

    def rect(x, y):
        cx = min(max(x, lo + radius), hi - radius)
        cy = min(max(y, lo + radius), hi - radius)
        return 1.0 if (x - cx) ** 2 + (y - cy) ** 2 <= radius * radius else 0.0

    mask = [[rect(x + 0.5, y + 0.5) for x in range(n)] for y in range(n)]
    k = int(sigma * 3)
    kernel = [math.exp(-(i * i) / (2 * sigma * sigma)) for i in range(-k, k + 1)]
    total = sum(kernel)
    kernel = [v / total for v in kernel]

    def blur_rows(img):
        return [[sum(kernel[j + k] * row[min(n - 1, max(0, x + j))] for j in range(-k, k + 1))
                 for x in range(n)] for row in img]

    rows = blur_rows(mask)
    cols = blur_rows([list(c) for c in zip(*rows)])
    img = [list(r) for r in zip(*cols)]
    return [img[y][x] * peak for y in range(n) for x in range(n)]


def main():
    MEDIA.mkdir(parents=True, exist_ok=True)
    for n in (32, 64, 128, 256):
        write_tga(MEDIA / f"circle{n}.tga", n, circle(n))
    n = 32
    a, b = 9.5, 22.5
    write_tga(MEDIA / "glyph_close.tga", n, glyph(n, [(a, a, b, b), (a, b, b, a)], 3.2))
    write_tga(MEDIA / "glyph_mini.tga", n, glyph(n, [(8, 16, 24, 16)], 3.2))
    write_tga(MEDIA / "glyph_zoom.tga", n, glyph(n, [(9, 16, 23, 16), (16, 9, 16, 23)], 3.2))
    write_tga(MEDIA / "shadow.tga", 128, shadow())
    old = MEDIA / "circle.tga"
    if old.exists():
        old.unlink()


if __name__ == "__main__":
    main()
