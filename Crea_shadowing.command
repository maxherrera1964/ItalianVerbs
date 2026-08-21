#!/bin/bash
# Double-click this in Finder to build the shadowing audio.
# Edit these two lines to change voices — no prompts, just runs.
ITALIAN_VOICE="Paola (Enhanced)"
ENGLISH_VOICE="Ava (Premium)"

cd "$(dirname "$0")"
./render-shadowing.sh shadowing-content.txt "$ITALIAN_VOICE" "$ENGLISH_VOICE"

echo
read -n 1 -s -r -p "Press any key to close."
