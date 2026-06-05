#!/usr/bin/env python3
"""Pack 4 weight + 1 input .bin into a $readmemh init file.
   BRAM: 14-bit address (16K entries), 128-bit data (16 bytes/word).

   Each matrix is pre-tiled into consecutive 16×16 blocks so the
   RTL can address them with a simple linear counter.

   Original row-major layout (COLS/16 words per row):
     addr = base + row * (COLS/16) + tile_col

   Pre-tiled layout (16 words per tile, tiles in row-major tile order):
     addr = base + (tile_row * n_tile_cols + tile_col) * 16 + intra_row
"""

S     = 16      # SYSTOLIC_SIZE
DEPTH = 1 << 14
WORD  = 16      # bytes per 128-bit word

#           filename                base    rows  cols
FILES = [
    ("layer1_weights.bin",          0x0000, 128,  768),
    ("layer2_weights.bin",          0x1800, 128,  128),
    ("layer3_weights.bin",          0x1C00, 128,  128),
    ("layer4_weights.bin",          0x2000,  16,  128),
    ("input_spectrogram.bin",       0x2400,  16,  768),
]
OUTPUT = "bram_init.txt"


def pretile(raw, rows, cols):
    """Rearrange row-major matrix bytes into 16×16 tile order."""
    n_tr = rows // S
    n_tc = cols // S
    wpr  = cols // S            # words per row in original layout
    out  = bytearray(len(raw))

    for tr in range(n_tr):
        for tc in range(n_tc):
            for r in range(S):
                actual_row = tr * S + r
                src = (actual_row * wpr + tc) * WORD
                dst = ((tr * n_tc + tc) * S + r) * WORD
                out[dst : dst + WORD] = raw[src : src + WORD]

    return out


mem = bytearray(DEPTH * WORD)

for name, base, rows, cols in FILES:
    d = open(name, "rb").read()
    t = pretile(d, rows, cols)
    o = base * WORD
    assert o + len(t) <= len(mem), f"{name} overflows BRAM"
    mem[o : o + len(t)] = t

with open(OUTPUT, "w") as f:
    for a in range(DEPTH):
        f.write(mem[a*WORD:(a+1)*WORD][::-1].hex() + "\n")

print(f"Wrote {DEPTH} lines to {OUTPUT}")
