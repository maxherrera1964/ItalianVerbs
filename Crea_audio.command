#!/bin/bash
# Double-click this in Finder to turn the newest exported script into audio.
# Looks for it right next to itself first (where the html's "Export audio
# script" saves to, in Chrome/Edge), then falls back to your Downloads
# folder (where every other browser's ordinary download lands).

# Edit these two lines to change voices — no prompts, just runs.
ITALIAN_VOICE="Paola (Enhanced)"
ENGLISH_VOICE="Ava (Premium)"

cd "$(dirname "$0")"

SCRIPT=$(ls -t ./audio-script-*.txt 2>/dev/null | head -1)
FOUND_WHERE="this folder"
if [ -z "$SCRIPT" ]; then
  SCRIPT=$(ls -t ~/Downloads/audio-script-*.txt 2>/dev/null | head -1)
  FOUND_WHERE="Downloads"
fi

if [ -z "$SCRIPT" ]; then
  echo "No exported script found here or in ~/Downloads."
  echo
  echo "In the flashcard app: open Settings (the gear), choose your verbs and"
  echo "tenses, then tap 'Export audio script'. Run this again afterwards."
  echo
  read -n 1 -s -r -p "Press any key to close."
  exit 1
fi

echo "Found: $(basename "$SCRIPT")  (in $FOUND_WHERE)"
echo

./render-audio.sh "$SCRIPT" "$ITALIAN_VOICE" "$ENGLISH_VOICE"

echo
read -n 1 -s -r -p "Press any key to close."
