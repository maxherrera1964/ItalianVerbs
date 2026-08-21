#!/bin/bash
# Double-click this in Finder to turn the newest exported script into audio.
# Looks for it right next to itself first (where the html's "Export audio
# script" saves to, in Chrome/Edge), then falls back to your Downloads
# folder (where every other browser's ordinary download lands).

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

# Offer the installed Italian voices
VOICES=()
while IFS= read -r line; do VOICES+=("$line"); done < <(
  say -v '?' | grep it_IT | grep -viE "eddy|flo|grandma|grandpa|reed|rocko|sandy|shelley" |
  sed 's/  *it_IT.*//'
)

echo "Voice:"
for i in "${!VOICES[@]}"; do echo "  $((i+1))) ${VOICES[$i]}"; done
echo
read -r -p "Number (Enter for Paola (Enhanced)): " PICK

if [ -n "$PICK" ] && [ "$PICK" -ge 1 ] 2>/dev/null && [ "$PICK" -le "${#VOICES[@]}" ]; then
  VOICE="${VOICES[$((PICK-1))]}"
else
  VOICE="Paola (Enhanced)"
fi
echo

./render-audio.sh "$SCRIPT" "$VOICE"

echo
read -n 1 -s -r -p "Press any key to close."
