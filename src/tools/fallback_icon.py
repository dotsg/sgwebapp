#!/usr/bin/env python3
"""Generate a placeholder app icon when no favicon could be fetched.

Produces a solid rounded square whose hue is derived from the app name, so
different apps at least get visually distinct icons instead of a blank square.
"""

import hashlib
import struct
import sys
import zlib

SIZE = 512
RADIUS = 114  # matches the macOS icon corner proportion


def hsv_to_rgb(h, s, v):
    i = int(h * 6.0)
    f = h * 6.0 - i
    p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    r, g, b = [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)][i % 6]
    return int(r * 255), int(g * 255), int(b * 255)


def png_chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


def main():
    if len(sys.argv) != 3:
        print("usage: fallback_icon.py <app-name> <out.png>", file=sys.stderr)
        return 2
    name, out_path = sys.argv[1], sys.argv[2]

    digest = hashlib.sha256(name.encode("utf-8")).digest()
    r, g, b = hsv_to_rgb(digest[0] / 255.0, 0.55, 0.85)

    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)  # PNG filter type 0
        for x in range(SIZE):
            # Corner rounding: transparent outside the rounded rect.
            dx = min(x, SIZE - 1 - x)
            dy = min(y, SIZE - 1 - y)
            inside = True
            if dx < RADIUS and dy < RADIUS:
                inside = (RADIUS - dx) ** 2 + (RADIUS - dy) ** 2 <= RADIUS ** 2
            rows.extend((r, g, b, 255) if inside else (0, 0, 0, 0))

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)  # 8-bit RGBA
    png = (b"\x89PNG\r\n\x1a\n"
           + png_chunk(b"IHDR", header)
           + png_chunk(b"IDAT", zlib.compress(bytes(rows), 9))
           + png_chunk(b"IEND", b""))
    with open(out_path, "wb") as f:
        f.write(png)
    return 0


if __name__ == "__main__":
    sys.exit(main())
