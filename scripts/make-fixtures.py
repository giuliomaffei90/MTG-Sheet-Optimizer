#!/usr/bin/env python3
"""Deterministic fixture cards for the conformance run: a solid colour with a white bar along the top,
so a card drawn upside down is obvious. Run once; the PNGs are committed."""
import struct, zlib, pathlib

W, H, BAR = 300, 410, 40
COLOURS = {"card1": (200, 40, 40), "card2": (40, 90, 200), "card3": (40, 160, 70), "card4": (200, 150, 30),
           "card5": (150, 60, 190), "card6": (40, 170, 180), "card7": (230, 110, 40), "back": (70, 70, 80)}

def png(path, rgb):
    rows = b"".join(b"\x00" + bytes(((255, 255, 255, 255) if y < BAR else (*rgb, 255)) * W) for y in range(H))
    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))
    path.write_bytes(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(rows, 9))
                     + chunk(b"IEND", b""))

out = pathlib.Path(__file__).resolve().parent.parent / "spec" / "fixtures"
out.mkdir(parents=True, exist_ok=True)
for name, rgb in COLOURS.items():
    png(out / f"{name}.png", rgb)
print("wrote", len(COLOURS), "fixtures to", out)
