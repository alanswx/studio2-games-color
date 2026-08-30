#!/usr/bin/env bash
# Build the colour Race multicart: assemble, then split the 4K image the way the
# core wants it -- $0000-$07FF as firmware, and a .st2 carrying pages $04 and
# $0C-$0F.  Page $04 has to be in the cartridge even though the firmware image
# already covers it: the loader writes the file's "RCA2" magic through to
# $0400-$0403 before it has read enough of the header to know the format, so the
# cartridge must re-lay that page afterwards to repair it.
set -e
cd "$(dirname "$0")"
../../bin/asmx -C 1802 -s9 -l -ew -o race_colour.asm.s9 race_colour.asm
python3 - <<'PY'
img = bytearray(b'\xFF' * 0x1000)
for line in open('race_colour.asm.s9'):
    line = line.strip()
    if not line.startswith('S1'):
        continue
    n    = int(line[2:4], 16)
    addr = int(line[4:8], 16)
    data = bytes.fromhex(line[8:8 + (n - 3) * 2])
    img[addr:addr + len(data)] = data

open('race_colour_lower.rom', 'wb').write(bytes(img[:0x800]))

pages  = [0x04, 0x0C, 0x0D, 0x0E, 0x0F]
hdr    = bytearray(256)
hdr[0:4] = b'RCA2'
hdr[4]   = len(pages) + 1
hdr[5]   = 1
for i, p in enumerate(pages):
    hdr[64 + i] = p
body = b''.join(bytes(img[p << 8:(p << 8) + 256]) for p in pages)
open('race_colour_upper.st2', 'wb').write(bytes(hdr) + body)
print('lower 2048 bytes, st2 %d bytes, pages %s' % (256 + len(body), [hex(p) for p in pages]))
PY
