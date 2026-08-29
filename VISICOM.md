# Pacman on the Toshiba Visicom COM-100

`Games/PacmanVisicom/` is a second colour port of Pacman, to a machine that is
often described as a Studio II relative and is not one. It is a separate source
tree, not a build option: `Games/Pacman/` is untouched and still produces the
byte-identical Studio II / CDP1864 cartridge described in [COLOUR.md](COLOUR.md).

The interesting part is that the Visicom is the only machine in this family with
**per-pixel colour**, so the compromise that shapes the whole CDP1864 build —
8x4 colour blocks, and a sprite that mostly-but-not-quite fits inside one —
simply does not exist here. What replaces it is a different constraint: three
foreground colours instead of eight.

---

## 1. What the machine actually is

Not a Studio III and not a Studio II. Toshiba's 1978 Japanese console shares the
CDP1802 and the CDP1861, and nothing else that matters to a program:

| | Studio II | Visicom COM-100 |
|---|---|---|
| System ROM | `$0000-$07FF` | `$0000-$07FF` (a different program) |
| Cartridge | `$0400-$07FF`, `$0A00-$0BFF`, … paged by the `.st2` | `$0800-$0FFF` flat, 2 KB, no mapper |
| Data RAM | `$0800-$08FF` | `$1000-$10FF` |
| Display | `$0900-$09FF` | `$1100-$11FF` |
| Colour | none (the CDP1864 adds 64 cells at `$B00`) | a second bit plane at `$1300-$13FF` |
| Colours | 1 (or 8 on a CDP1864, in 8x4 blocks) | 4 fixed, **per pixel** |

There is no colour RAM. The 1861's DMA fetches **two** bytes per cycle, `M(R0)`
and `M(R0+$200)`, and takes the top bit of each; the two bits index a fixed
four-entry palette for that one pixel:

```
plane 1 ($13xx)   plane 0 ($11xx)   colour
       0                 0          dark green   $004000   (the background)
       0                 1          light cyan   $AFDFE4
       1                 0          yellow-green $B9C42F
       1                 1          red          $EF454A
```

There is no palette register, no background control and no per-pixel anything
else. The only way to change a pixel's colour is to change which planes it is
drawn into.

**Three foreground colours is one fewer than there are ghosts**, so the CDP1864
build's colour-per-ghost cannot be reproduced. See §3 for what replaces it.

---

## 2. The port

### The BIOS is a relocated cousin, which is what makes this cheap

The Visicom ROM is only 33% byte-identical to the Studio II's, but disassembling
it shows the same program with the same RAM offsets moved one page up. Its
interrupt routine at `$02B1` is instruction-for-instruction the Studio II's
`VideoInt` with `$09` become `$11` and `$08` become `$10`, down to decrementing
the same three counters and gating `Q` off the same one. So:

- `Studio2BeepTimer = $CD` still works — the Visicom ISR decrements `$10CD` and
  drives the beeper from it, exactly as the Studio II does with `$08CD`.
- `RB.0` is still the display start, `R9` is still bumped every frame, and the
  same registers (`R0,R1,R2,R8,R9,RB.0`) are the ones a cartridge must not touch.
- The `0xxx` = "call 1802 code at `xxx`" bytecode is the same, handled at `$02A5`
  the way the Studio II handles it at `$0094`. A cartridge is entered at `$0800`
  as interpreted bytecode, so the first two bytes are the native entry vector,
  exactly as `$0400` works on a Studio II. Ours are `0C 00` → `ColourInit`.

One thing did move: the BIOS digit graphics. The Studio II's offset table is at
`$0210` with the glyphs from `$021A`; the Visicom's are at `$0480` and `$048A` —
the same table, `$270` higher. The score routine's `adi $10` / `ldi $02` became
`adi $80` / `ldi $04`, and that is the whole change.

### What the port therefore is

`RamPage` `$08`→`$10`, `VideoPage` `$09`→`$11`, the three `.org`s moved into
`$0800-$0FFF`, and those two bytes in the score routine. That is all of it. The
cartridge is eight pages, `$08-$0F`, a 2304-byte `.st2` — the same shape as all
six dumped Visicom cartridges.

### Validated before anything was changed

Built as a straight relocation with the CDP1864 colour code left inert (its
stores to `$B00` land in cartridge ROM on this machine and do nothing), the port
was checked against the Studio II build in the Verilator model of the MiSTer core
([MiSTer-devel/StudioII_MiSTer](https://github.com/MiSTer-devel/StudioII_MiSTer),
`--machine visicom`, with Emma 02's Visicom BIOS):

- the maze renders **pixel-identical** to the Studio II build, 497 lit pixels
  either way;
- 901 frames take **26,442,404 cycles on both machines** — same frame rate, same
  CPU budget, so the second DMA fetch costs the program nothing;
- the beeper runs (`Q` toggles) and the game animates.

### And how the colour is checked

Plane 1 has no equivalent of "does it look right" — a wrong bit there is a
coloured pixel in a plausible place. What it does have is an exact invariant: at
any instant plane 1 must equal the XOR of every graphic whose plane mask has bit 1
set, stamped at the position held in its sprite record (plus the uneaten power
pills, from the maze bytes at `$1000-$103B`). `Games/PacmanVisicom/checkplane1.py`
builds that model from a state dump and diffs it against the plane read straight
out of the RTL's `sram2` array — the twelve lines of `dump_state()` needed to
print it are quoted at the top of the script. Zero mismatch is the pass; the only
legitimate non-zero is one sprite's worth, when the dump catches a draw or erase
in progress. Reading plane 1 off the *rendered frame* instead does not work — the
picture is assembled over a whole DMA scan, so a moving sprite tears across it,
which is exactly how the bug in §4 stayed hidden.

---

## 3. The colour design

Colour is chosen per sprite by which planes it is drawn into. One pass for one
plane, two passes for red.

| | planes | colour | passes |
|---|---|---|---|
| maze walls, dots | 0 | cyan | (drawn directly, not via the plotter) |
| Pacman | 1 | yellow-green | 1 |
| power pills, the cherry | 1 | yellow-green | 1 |
| ghosts, hunting | 0 + 1 | red | 2 |
| ghosts, edible | 0 | cyan | 1 |

**Red means danger and nothing else.** That is the whole design. Eating a power
pill turns all four ghosts from red to cyan for as long as they are edible, and
turns them back when the timer runs out — which is a stronger cue than the
CDP1864 build's white/magenta board flash and costs nothing per frame.

### The plane mask is looked up from the graphic, and that is why it stays correct

`PlaneTable` on the `$F00` page has one entry per four-byte slot in `Graphics`,
and `SPRP_Planes` indexes it with `(graphic - <Graphics)/4`. Nothing else stores
the plane anywhere.

That matters because a sprite is erased by XORing back the graphic held in its
record at `+2` — the same byte the mask is derived from. Erase and draw therefore
always agree about the planes even when the sprite changed colour in between, so
a ghost that becomes edible between one frame and the next is removed from both
planes at its old position and drawn into one at its new one. No extra state, and
nothing that can fall out of step.

### One game-logic change

`Ghost_GetSprite` tested the X+Y parity first and only consulted the chase timer
on alternate steps, so an edible ghost was hollow every *other* frame and normal
in between. In monochrome that reads as a flicker; in colour it would read as a
ghost flashing red, and red has to mean one thing. The chase test now comes first
and wins outright, so edible is cyan for the whole duration — which is what the
arcade does with blue. The hunting animation (Ghost1/Ghost2, both red) is
unchanged, and the routine is the same size it was.

### What it cost

`SpriteColour` and its 64-cell repaint are gone entirely — about 500 instructions
a frame — and `FrameColour` is down to the chasing timer and the beeper. The
second plane pass for the four ghosts costs a bit more than that freed. Measured
by the game's own loop counter (`Frame`, `$104C`) over 300 video frames of the
same play sequence:

| | video frames per game step |
|---|---|
| Studio II, CDP1864 colour build | 6.67 |
| Visicom, this build | 7.69 |

So it runs about **15 % slower** than the CDP1864 build — roughly one notch on
the game's own per-level speed ramp, and the price of red ghosts. Making the
ghosts single-plane would buy it back and cost the colour.

The cartridge holds 1761 bytes in eight pages, with page `$C00` almost empty
(222 bytes) and 50 free on `$F00`.

### One deliberate 15-byte hole

Moving the plotter's row loop to `$F00` freed 25 bytes on the `$900` page, and
clearing the second plane at `IL_ClearScreen` spent 10 of them. The remaining 15
are padded rather than reclaimed, because everything below that point is laid out
around the old size and an 1802 short branch cannot cross a page: pull the code up
and `UpdateLegalMoves` straddles `$0B00`, putting `ULM_Exit` on the far side of
the boundary from two of the branches that reach it. The pad keeps every address
after the plotter exactly where the validated monochrome port left it.

---

## 4. Three traps, recorded

**Never park data below the stack pointer.** This one cost the most to find. The
plane loop needs the sprite's screen offset to survive from the first pass to the
second, and the obvious place to keep it is the stack — push it under the graphic
byte `SpritePlot` already pushed, and read it back each pass. That is wrong on
this machine, and quietly so. The BIOS interrupt routine begins

```
        dec r2 / sav          ; (X,P) at R2-1
        dec r2 / stxd         ; D     at R2-2, R2 -> R2-3
        shlc   / str r2       ; DF    at R2-3
```

— three bytes written *below* R2 and popped again on exit. During the row loop R2
points at the graphic byte, so a second item pushed under it sits exactly where
`SAV` lands. Roughly once a frame the offset came back as `$F5` or `$FC`, which
are not offsets at all: they are the saved `(X,P)` for `X=F, P=5` (the plotter)
and `X=F, P=C` (the shift/XOR drawer). The sprite was then drawn into plane 1 at
a junk address and never erased from it, so colour debris accumulated across the
board — about nine plots in every fifty-five. The offset now lives in a RAM byte
(`PlaneBase`, `$1056`) and R2 never moves from where `SpritePlot` left it, which
is exactly the invariant the original single-plane loop relied on.

Worth noting because it is invisible in the obvious places: the picture looks
plausible (the game's own XOR sprites already make the middle of the board busy),
the arithmetic is right, and a CPU trace of any single plot shows it working. It
only shows up against a model of what plane 1 *should* contain, compared with the
plane read straight out of memory rather than off the screen — the rendered frame
is assembled over a whole DMA scan, so a moving sprite tears across it and hides
a real error inside a plausible amount of noise.

**`inc re` carries.** The screen clear runs twice, once per plane, and the
obvious way to write that — clear `$1100-$11FF`, toggle bit 1 of `RE.1`, go round
again — is wrong. `inc re` is a 16-bit increment, so when `RE.0` wraps past `$FF`
it carries and `RE.1` is already `$12`, not `$11`. Toggling from there walks the
pointer through `$10` (which is the work RAM: maze data, lives and level all
zeroed, so the walls stop being drawn) and then off into undecoded pages, and the
exit test never matches. The loop reloads `RE.1` explicitly and tests against
`$14`, which is what `RE.1` reads after the second plane.

**Sprites no longer cancel the maze.** In monochrome, a sprite XORed over a wall
punches a hole in it. Here a sprite on plane 1 leaves plane 0 alone, so where
Pacman crosses a wall those pixels go red rather than dark; where a red ghost
crosses one, plane 0 cancels and the pixel goes yellow-green. Both are a few
pixels at a time and only at junctions, and the second is arguably an improvement
— but it is the reason the middle of the board looks busier in colour than in
monochrome, and it is not a bug. The monochrome build has the same clutter in the
den; colour just makes it legible.

---

## 5. What is not done

- **The board flash is gone.** There is no global palette to toggle, and
  repainting a plane is 256 stores rather than 64, which will not fit in a frame.
  The ghosts changing colour carries the same information.
- **Per-ghost colour is not possible.** Three foreground colours, four ghosts.
  The CDP1864 build is the one to look at for that, block granularity and all.
- **Input is still the keypad scan.** The Visicom shipped two joysticks; the
  `out 2` / `EF3` scan in `ScanKeypad` works in the core, but the joystick has not
  been wired up.
- **Not tried on real hardware.** Everything here is against the MiSTer core's
  Verilator model, whose Visicom behaviour is matched to Emma 02 and whose palette
  is MAME's, backed by a hardware capture of the built-in Freeway. The core's own
  notes record intermittent instability on this machine that nobody has explained
  yet; if this cartridge misbehaves on a real Visicom, that is the first thing to
  read.

---

## 6. Building

```sh
cd asmx/src && make CFLAGS='-O2 -std=gnu89 -Wno-implicit-int \
    -Wno-implicit-function-declaration -Wno-return-type \
    -DVERSION=\"2.0b5\" -I.' && cp asmx ../../bin/asmx
cd ../../Games/PacmanVisicom && ../../bin/asmx -s9 -l -ew -C 1802 pacman.asm \
  && python3 ../s9tobinary.py pacman.asm.s9 && python3 ../makest2.py
```

To run it:

```sh
Vtop --machine visicom --bios visicom.rom --cart Games/PacmanVisicom/pacman.st2 \
     --press a0@40:20 --press a0@200:20 --frames 900 --shot 700
```

The first `0` starts the cartridge from the Visicom's menu, the second starts the
level.
