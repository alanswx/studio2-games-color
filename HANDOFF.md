# Handoff — Race colour, 2026-08-31

State at the end of the session that added a CDP1864 colour build for azya52's
*Race*. Everything below is on disk; nothing of value is left in a temp
directory.

## Where things are

| | |
| --- | --- |
| Games repo | `~/Documents/development/studio2-games-color`, branch `visicom-pacman` |
| Core / emulator | `~/Documents/development/RCAStudioII_Mister`, branch `cdp1864` |

**The games repo is clean and fully pushed** (`origin/visicom-pacman`), through
`67db7ee`.

**The core repo has two commits that are NOT pushed**, because its only remote is
`meauxdal/RCAStudioII_Mister` and we do not have write access there
(`remote rejected … permission denied`). Push them somewhere or add your own
remote, or they only exist on this machine:

- `6caed01` Headless sim: expose Studio III colour and the Visicom's second plane
- `af94bdb` Headless sim: add a DMA-address trace

(`verilator/imgui.ini` is also modified there. It was already modified before
this session started — window positions — and was left alone.)

## What was built

`Games/RaceColour/` — colour for azya52's *Race*
(<https://github.com/azya52/rcastudioii>) on the **Studio III NTSC** machine.

```
cd ~/Documents/development/RCAStudioII_Mister/verilator
./obj_dir/Vtop --machine studio3ntsc \
  --bios ~/Documents/development/studio2-games-color/Games/RaceColour/race_colour_lower.rom \
  --cart ~/Documents/development/studio2-games-color/Games/RaceColour/race_colour_upper.st2
```

It loads as **two files**: Race is a 4 KB image and the core only hands a
cartridge the top half, so the lower half goes in as *firmware*. `build.sh`
regenerates both from `race_colour.asm`; `tune.sh` rebuilds with a different band
table and renders two frames so a colour choice can be looked at.

`shots/` holds the screenshots the design was signed off against.

## Status

Verified **in the headless sim only** — `colour: enabled 1`, the table loads as
designed, and the game plays through the title, four in-race frames and
game-over. **It has never been played by a human or run on hardware.** That is
the obvious next thing to do.

## Things that cost time — worth not rediscovering

**A hand-built `.st2` must carry page `$04`.** The core's loader cannot know a
file is a `.st2` until byte 3 is latched, but `cart_we`/`cart_a` are evaluated as
each byte arrives, so the file's own `"RCA2"` magic is written straight to
`$0400-$0403` on the raw-`.bin` path first. An ordinary `.st2` hides this by also
paging `$04`. This is a real bug in `rtl/rcastudioii.sv` and is still unfixed —
we worked around it in the cartridge. It affects hardware too.

**Race takes its colour from the ROM address, not the screen.** There is no
framebuffer; the ISR re-points R0 at ROM data per scanline, and the CDP1864 index
`{ram_a[7:5], ram_a[2:0]}` comes from whatever address the DMA presents. Colour
therefore attaches to *which graphic is on the bus*.

**Value 2 is blue — identical to the background, so it is never usable.** The
full map, measured rather than assumed: 0 black, 1 red, 2 blue, 3 magenta,
4 green, 5 yellow, 6 cyan, 7 white.

**Groups 2, 3 and 4 must share a value.** Every text string straddles a boundary:

| display rows | what | groups |
| --- | --- | --- |
| 0-4 | `SPEED TIME SCORE` | 3 on row 0, 4 below |
| 8-15 | the digit line | 2 on row 8, 3 below |
| 44-59 | mountains | 4, 5, 6, 7 |
| 59-66 | the big `AZYA,2020` line | 2, then 3, then 4 |
| 64-127 | road and car | 0-7, 8 rows each |

Give them different values and all three strings come out banded — which is what
the first version did, and why the score digits had a green top row on a yellow
body. Current table `1,3,7,7,7,6,1,3`.

**azya52's Reset has a bug.** It loads the entry address with `phi r3` where the
comment says `R3.Low = main`; it must be `plo r3`, or the machine hangs. Fixed in
our copy only — nothing has been reported upstream, and their repo is untouched.

## How to verify a colour change

```
# is the table even landing?  colour_on latches on the first write to $B00
Vtop --machine studio3ntsc --bios … --cart … --frames 700 --dump 700 --vram | grep -A9 "colour: enabled"

# which cell does a given pixel read?  (only way to know on a beam-raced game)
DMA_TRACE=400 Vtop --machine studio3ntsc --bios … --cart … --frames 402

# a write is issued but does not land?
COL_TRACE=1 Vtop … | head
```

`--trace-r0` cannot answer the second one: R0 is sampled at HSync, after the
line's DMA has already run.

## Open items

- **Push the two core-repo commits.** They only exist locally.
- **Play it.** Nothing here has been through a human's hands.
- **The `.st2` loader bug is still in the RTL.** The fix is to defer the first
  four cartridge writes until the format is known, rather than writing them on
  the raw-`.bin` path and hoping page `$04` repairs them later.
- **Per-element colour.** The band table is indexed by ROM address, so colouring
  each graphic individually is possible — pick values per element's own address
  instead of by band. Not attempted.
- **Decide whether Race belongs in this repo at all.** It is azya52's game under
  their terms; the other eight colour ports are our own work on RCA-era titles.
- Upstream `StudioII_MiSTer` (not this checkout) has split the single `dpram`
  into four per-machine BRAMs `rom0..rom3`, which breaks `sim_main.cpp` at the
  memory-editor window. Not applicable here — this tree still uses `dpram`.
