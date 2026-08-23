# Colour for the Studio III / MPT-02 family

This fork adds CDP1864 colour to Pacman, and this note explains how the hardware
works, what the first version does, and how much further it can be pushed.

The change is deliberately small: **one new ROM page**, no edits to any existing
game logic, and the resulting binary is byte-identical in behaviour on a
Studio II — verified frame-for-frame against the original build.

---

## 1. How colour works on this hardware

The CDP1864 (Studio III PAL, MPT-02, Victory) and the CDP1862 beside a CDP1861
(Studio III NTSC) take colour from **64 cells behind a one-page window at
`$B00`**. There is no per-pixel colour and no sprite colour.

**Geometry.** The cell for a given screen byte is indexed
`{row[4:2], byte_column}`, which is `(row / 4) * 8 + column`. The 64×32 screen is
therefore an **8 × 8 grid of blocks, each 8 pixels across by 4 rows down**, and
the table is in natural reading order — eight entries per band, top band first.

**Bits.** Three bits per cell, in the 1864's *pin* order, which is not RGB:

```
bit 0 = RED     bit 1 = BLUE     bit 2 = GREEN

0 black   1 red   2 blue   3 magenta   4 green   5 yellow   6 cyan   7 white
```

**Lit vs unlit.** A lit pixel takes its cell's colour. An unlit pixel takes the
*global* background, which powers up blue and is stepped by `OUT 1`. Colour stays
off entirely until something writes `$B00` — before that the part is monochrome,
white on black, exactly like an 1861.

---

## 2. What this version does

`Games/Pacman/pacman.asm` gains a `$A00` page holding a 15-instruction loop and a
64-byte table. The cartridge entry vector at `$400` now points at `ColourInit`,
which writes the table and long-branches to `StartGame` — that hook costs nothing
in the crowded pages, which matters because **the ROM was full**: 4 bytes free in
`$400-$7FF` and 2 in `$C00-$DFF`.

The table is eight horizontal bands, symmetric about the middle: white for the
top and bottom walls, yellow through the upper and lower maze, cyan across the
tunnel band. Against the default blue background that reads as a designed maze
rather than an accident.

### Two deliberate non-choices

**We do not issue `OUT 1`.** It would step the background to black, which is the
classic Pacman look — but on a Studio II that same port *turns the display off*,
so the game would boot to a black screen there. Leaving it alone is what keeps
this one binary working on both machines, and it is what RCA themselves did:
their dual-machine cartridges leave the background at its default blue.

**We do not colour sprites.** Pacman and the ghosts take whatever band they are
crossing. See §3.

### Why it is safe on a Studio II

On a Studio II the whole of `$B00` is undecoded — A9 is high, so it is neither
RAM nor, unless a cartridge pages it, ROM. Every store goes nowhere. Measured:
the colour build's Studio II output is byte-identical to the original at the same
frame.

### Building

```sh
cd asmx/src && make          # see the note below, then
cp asmx ../../bin/asmx
cd ../../Games/Pacman && ../../bin/asmx -s9 -l -ew -C 1802 pacman.asm \
  && python3 ../s9tobinary.py pacman.asm.s9 && python3 ../makest2.py
```

Three portability fixes were needed and are included: `asmx` is K&R-era C that
modern clang rejects, so build it with
`make CFLAGS='-O2 -std=gnu89 -Wno-implicit-int -Wno-implicit-function-declaration -Wno-return-type -DVERSION=\"2.0b5\" -I.'`
(and delete the committed `.o` files first — they are someone else's platform).
`s9tobinary.py` and `makest2.py` were Python 2 and are now Python 3. With those,
the toolchain reproduces the original `pacman.st2` **byte-identically**, which is
how it was validated before anything was changed.

---

## 3. How to improve the colour

Roughly in order of value per byte spent.

### 3a. Per-cell tuning — free

The table is 64 *independent* cells; this version wastes that by using eight
uniform bands. Hand-picking each cell to follow the maze's own structure — the
ghost house, the tunnel mouths, the corner blocks — costs exactly the same 64
bytes and no extra code. This is the cheapest visible win and should be done
first.

### 3b. Per-level palettes — ~8 bytes a level

Arcade Pacman recolours the maze each level. Here that is a second table indexed
by the level counter, which the game already keeps (`Level`, in RAM). Even
cycling three palettes makes the game feel far less static. Call `ColourInit`
from `NextLevel` instead of only at start-up, with the table pointer chosen from
`Level`.

### 3c. Power-pill flash — **done**

This is the one piece of colour on this hardware that costs nothing in fidelity,
because it is a *global* state: it needs no alignment between the 8x4 grid and
anything the game draws. While `ChasingTimer` is non-zero the whole board flashes
**white / magenta** on the same 8-frame cycle the beeper already uses.

`FrameColour` on the `$A00` page now owns the per-frame chasing work -- the timer
decrement and the alternate-frame beeper, which used to be inline -- and sets the
palette from it. That swap paid for itself: the call is 7 bytes where the inline
block was 16, so it *freed* 9 bytes in the `$C00-$DFF` page.

Repainting is not done every frame. While chasing it happens only when the low
three bits of the timer are zero, which is exactly when the flash bit flips, so it
costs 64 stores every eighth frame rather than every frame; leaving the chase
repaints once, guarded by a `ColourState` byte.

Two things worth recording. **Do not flash to blue** -- the background is blue, so
blue cells make lit and unlit pixels identical and the board vanishes. That was
the first attempt, and 20 of 70 sampled frames came back completely blank. White
and magenta are both legible against the background and neither appears in the
normal palette. And note the game *already* signalled this state in monochrome by
swapping the ghost sprite to the hollow `GhostReverse` shape -- this makes it
unmissable rather than adding information that was not there.

### 3d. Sprite colour, the honest way — the big one, and the one that hurts

Measured first, because the numbers decide it. A sprite is 5 pixels wide and 4
rows tall; its top-left lands at pixel `x+1`, row `y+1`, with `x` pixel-granular
and `y` row-granular. So against an 8-wide, 4-tall cell:

- horizontally it fits one cell only when `(x+1) & 7 <= 3` — half the time
- vertically it fits one band only when `(y+1) & 3 == 0` — a quarter of the time

Which gives 1 cell 12.5% of the time, 2 cells 50%, and 4 cells 37.5% —
**2.6 cells on average, 84 pixels of colour to show a 20-pixel sprite, a 4.2x
overspill.** Every wall and pellet inside that region takes the sprite's colour
too.

This is what makes it look like a colour game rather than a coloured maze.
Because colour is per-block, a sprite can only be given its own colour by
rewriting the block it currently occupies:

- On draw, note the sprite's cell index, save the cell's current value, write the
  sprite's colour.
- On erase, restore the saved value.

The game already has exactly the right hooks — `SpritePlot` and
`SpriteLoadAndPlot` do XOR draw/erase, so both edges already exist. Cost is a few
bytes of state per sprite (cell index + saved colour) and two stores per sprite
per frame, which is nothing against a 1321-instruction frame.

The catch is honest and unavoidable: **two sprites in one 8×4 block still share a
colour**, and a sprite straddling a block boundary colours both. Pacman and a
ghost meeting will clash. That is the hardware, not the implementation.

### 3e. Design the maze around the grid — the real fix

The previous item fights the hardware; this one works with it. If the maze is
redrawn so that corridors align to the 8×4 block grid, a sprite travelling along
a corridor stays inside blocks of one colour, and the clash largely disappears.
That means:

- corridors on 4-row boundaries vertically, 8-pixel boundaries horizontally
- the ghost house occupying whole blocks
- pellets placed so a block is never shared by two things that need to differ

This is a game-design job rather than a coding one, and it is how a title
*written* for the 1864 would have been laid out in the first place. Pacman's
current maze is a 10×6 array of 6×5-pixel cells — deliberately not aligned to
anything, because on a Studio II nothing needed aligning.

### 3f. Background stepping — needs a machine test

`OUT 1` steps the background blue → black → green → red. Black would give the
classic look. It is only safe if the program knows it is not on a Studio II.
There is no clean way to detect that from software, so the practical options are
a separate Studio III-only build, or a menu key at start-up that the player uses
once. A separate build is one line in `st2file` and costs nothing but a filename.

### 3g. Target NTSC rather than PAL

The PAL 1864 frame is 50.37 Hz against the Studio II's 59.99, and this game times
off the frame interrupt, so on a Studio III PAL it runs about 16 % slow. The NTSC
Studio III (CDP1861 + CDP1862 + CDP1863) keeps 60 Hz and takes the same colour
RAM writes, so it is the better target for anything where speed matters.

---

## 4. What cannot be done

Worth stating plainly so nobody spends a weekend on it:

- **No per-pixel or per-sprite colour.** 8×4 blocks is the hardware limit.
- **Only 8 colours**, one of which is black, and one of which the background is
  already using.
- **One background for the whole screen.** There is no per-block background; an
  unlit pixel anywhere takes the same colour.
- **No mid-frame palette changes.** The DMA-driven video gives no reliable
  raster-time hook, and the BIOS ISR's cycle budget is already load-bearing.
