# Race — CDP1864 colour

Colour for azya52's beam-raced *Race* (<https://github.com/azya52/rcastudioii>,
write-up at <https://habr.com/ru/articles/422277/>), running on the Studio III
NTSC machine.

## Loading it

Race is a 4 KB image and the core only hands a cartridge the top half, so this
loads as **two files**, not one:

| file | loads as |
| --- | --- |
| `race_colour_lower.rom` | firmware (`--bios`), **not** a cartridge |
| `race_colour_upper.st2` | the cartridge — pages `$04`, `$0C`-`$0F` |

Machine must be **Studio III NTSC**:

```
obj_dir/Vtop --machine studio3ntsc \
  --bios .../Games/RaceColour/race_colour_lower.rom \
  --cart .../Games/RaceColour/race_colour_upper.st2
```

`./build.sh` regenerates both from `race_colour.asm` (needs `bin/asmx`).

## Why the cartridge carries page $04

It has to, even though the firmware image already covers `$0400-$04FF`.

In the core's cartridge loader `st2_mode` is a register that is not resolved
until ioctl byte 3 has been latched, but `cart_we`/`cart_a` are evaluated on the
same cycle each byte arrives. For addresses 0-3 `st2_mode` is still 0, so the
loader takes the raw-`.bin` path and writes the file's own `"RCA2"` magic
straight to `$0400-$0403`. An ordinary `.st2` hides this because it also carries
page `$04` and its block overwrites the damage later in the download; a
cartridge whose page map omits `$04` leaves those four bytes live.

That is what broke the first version of this: the stray magic landed on
`colourInit`'s opening `sex r3 / dis / $23 / ldi $0B`, so the `dis` never ran, an
interrupt arrived between `ldi $0B` and `phi r4`, and R4 came out as `$4100`
instead of `$0B00`.

## How the colour works

Race has no framebuffer — its ISR re-points R0 at ROM data per scanline on exact
cycle counts. The CDP1864 colour index is `{ram_a[7:5], ram_a[2:0]}` of whatever
address the DMA presents, so **a pixel's colour follows the ROM address of the
graphic being displayed, not where it lands on screen.**

This is the opposite of every other colour port here, where the 64 cells act as
fixed screen bands. It is why a plain 8-band table still reads as deliberate: the
perspective road markers gradient red -> magenta -> green -> yellow -> white
toward the viewer for free, because their data sits at ascending ROM addresses.

A more considered colouring would pick values per graphic's ROM address rather
than by screen region. That is the obvious next step and has not been done.

`colourInit` sits at `$0400`, which is `$FF` filler in the original image, and
ends with `lbr start`. It disables interrupts first (`sex r3 / dis / $23`),
because Reset still has R1 pointing at the `VideoInt` stub and the table loop is
long enough to be caught by it.

`OUT 1` would step the background off blue, but on the 1861/1862 NTSC path
`OUT 1` is also display-off, so it is left alone. Blue reads as sky anyway.

## Changes to azya52's source

`race_multicart.asm` is their original with one byte fixed: Reset loaded the
entry address with `phi r3` where the comment says `R3.Low = main`; it must be
`plo r3`, or the machine jumps to `$0000` and hangs. `race_colour.asm` is that
file plus `colourInit` and the band table.

## Status

Verified in the headless sim only — `colour: enabled 1`, the table loads as
designed, and the game plays through frames 60/200/400/650/880 (title screen,
mountains, road markers, speed 164, score 00063). It has not been played by a
human or run on hardware.
