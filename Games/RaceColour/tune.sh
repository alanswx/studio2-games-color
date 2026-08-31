#!/usr/bin/env bash
# tune.sh "g0,g1,g2,g3,g4,g5,g6,g7" [tag]
#
# Rebuild with a different band table and render the title screen and a frame
# mid-race, so a colour choice can be looked at rather than guessed. Restores
# race_colour.asm afterwards -- pass the values you want to keep to build.sh
# instead, or edit bandTable directly.
#
# Values: 0 black, 1 red, 2 blue (INVISIBLE, same as the background),
#         3 magenta, 4 green, 5 yellow, 6 cyan, 7 white.
#
# Set SIM to the headless Vtop if it is not in the default place.
set -e
cd "$(dirname "$0")"
SIM=${SIM:-/Users/alans/Documents/development/RCAStudioII_Mister/verilator/obj_dir_headless/Vtop}
TAG=${2:-tune}
[ -x "$SIM" ] || { echo "no headless sim at $SIM (set SIM=...)"; exit 1; }
cp race_colour.asm race_colour.asm.bak
trap 'mv race_colour.asm.bak race_colour.asm' EXIT
sed -i '' "s|^bandTable:.*|bandTable:	.db $1|" race_colour.asm
./build.sh >/dev/null
"$SIM" --machine studio3ntsc --bios race_colour_lower.rom --cart race_colour_upper.st2 \
       --frames 130 --shot 118 --outdir . --prefix "${TAG}_title" >/dev/null 2>&1
"$SIM" --machine studio3ntsc --bios race_colour_lower.rom --cart race_colour_upper.st2 \
       --frames 3010 --shot 3000 --outdir . --prefix "${TAG}_race" --press b2@100:2900 >/dev/null 2>&1
echo "wrote ${TAG}_title_f00118.png and ${TAG}_race_f03000.png"
echo "note: race_colour.asm is restored on exit; the built .rom/.st2 are NOT"
