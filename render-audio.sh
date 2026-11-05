#!/bin/bash
# Render an audio script exported from italianverbs.html into m4a files.
# Lives in the same folder as italianverbs.html — italianverbs.html's "Copy
# command" button (Deck settings > Export audio script) builds the exact
# command to paste, using that co-location to find this script.
#
# Every io (first-person) line in the export is followed by its English
# translation, on its own line marked with a leading "¶EN¶ ". Each language
# is rendered with its own separate `say -v` call — the voice always goes in
# as a real command-line argument, never as text inside a bracketed command,
# so a compound voice name like "Paola (Enhanced)" can't get half-parsed and
# end up spoken aloud instead of acted on. The pieces are stitched back
# together with ffmpeg afterwards.
#
#   ./render-audio.sh ~/Downloads/audio-script-12verbs-2s.txt
#   ./render-audio.sh audio-script.txt "Luca (Enhanced)" "Alex"   # bare filename -> looked up in ~/Downloads
#
# Produces, next to this script (and so next to italianverbs.html too):
#   <name>/completo.m4a     one track, all verbs
#   <name>/per-verbo/*.m4a  one file per verb, numbered in selection order
#
# Requires: say, afconvert (both ship with macOS), ffmpeg (brew install ffmpeg).

set -euo pipefail

SCRIPT_FILE="${1:-}"
VOICE="${2:-Paola (Enhanced)}"
EN_VOICE="${3:-Samantha}"
BITRATE=64000

if [ -z "$SCRIPT_FILE" ] || [ ! -f "$SCRIPT_FILE" ]; then
  # A bare filename (no "/") that doesn't exist where we are: try the
  # browser's default Downloads folder before giving up — this is the
  # common case when the copy-paste command from the html couldn't
  # detect your actual download location.
  if [ -n "$SCRIPT_FILE" ] && [[ "$SCRIPT_FILE" != */* ]] && [ -f "$HOME/Downloads/$SCRIPT_FILE" ]; then
    SCRIPT_FILE="$HOME/Downloads/$SCRIPT_FILE"
  fi
fi

if [ -z "$SCRIPT_FILE" ] || [ ! -f "$SCRIPT_FILE" ]; then
  echo "usage: $(basename "$0") <exported-script.txt> [Italian voice] [English voice]" >&2
  echo >&2
  echo "Italian voices installed on this Mac:" >&2
  say -v '?' | grep it_IT | grep -viE "eddy|flo|grandma|grandpa|reed|rocko|sandy|shelley" | sed 's/^/  /' >&2
  exit 1
fi

if ! say -v '?' | grep -qF "$VOICE"; then
  echo "error: voice '$VOICE' is not installed." >&2
  echo "Install more in System Settings > Accessibility > Spoken Content > Manage Voices." >&2
  exit 1
fi

if ! say -v '?' | grep -qF "$EN_VOICE"; then
  echo "error: English voice '$EN_VOICE' is not installed." >&2
  echo "Install more in System Settings > Accessibility > Spoken Content > Manage Voices." >&2
  exit 1
fi

command -v ffmpeg >/dev/null || { echo "error: ffmpeg not found (brew install ffmpeg)" >&2; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
NAME="$(basename "$SCRIPT_FILE" .txt)"
OUT="$HERE/$NAME"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

rm -rf "$OUT"
mkdir -p "$OUT/per-verbo" "$WORK/parts" "$WORK/segs" "$WORK/segaiff" "$WORK/aiff"

# Pass 1 — split on verb-announcement lines. Two formats are accepted:
#   old: "[[slnc NNNN]] <infinitive>. [[slnc 1000]]"
#   new: "[[slnc NNNN]] [[rate -40]] <Tense>. [[rate +40]] [[slnc 700]] <infinitive>. [[slnc 1000]]"
# The infinitive is everything after the last "]] " and before ". [[slnc 1000]]"
# — it can be several words (rendersi conto, legarsela al dito). In the new
# format every tense block repeats the announcement, so a new file is started
# only when the infinitive changes — one file per verb, all its tenses inside.
# Spaces become hyphens in the file name: 07_rendersi-conto.m4a.
awk -v dir="$WORK/parts" '
  /^\[\[slnc [0-9]+\]\] .*[a-zà-ù]+\. \[\[slnc 1000\]\]$/ {
    line = $0; sub(/\. \[\[slnc 1000\]\]$/, "", line)
    sub(/^.*\]\] /, "", line); verb = line
    if (verb != last) {
      if (file) close(file)
      fname = verb; gsub(/[ \/]+/, "-", fname)
      file = sprintf("%s/%02d_%s.txt", dir, n++, fname); last = verb
    }
  }
  file && NF { print > file }
' "$SCRIPT_FILE"

COUNT=$(ls "$WORK/parts" | wc -l | tr -d ' ')
[ "$COUNT" -gt 0 ] || { echo "error: no verbs found — is this an exported script?" >&2; exit 1; }
echo "Rendering $COUNT verb(s) with '$VOICE' (English lines: '$EN_VOICE')…"

# A real script file, not an inline one-liner — cramming an awk program inside
# a bash -c string inside an xargs call gets the quoting wrong sooner or
# later. This one splits a single verb's file into alternating Italian/
# English segments, voices each separately, then stitches them back into
# that verb's own per-verbo/*.m4a.
cat > "$WORK/render_one.sh" << 'HELPER'
#!/bin/bash
set -euo pipefail
f="$1"
b="$(basename "$f" .txt)"

# Pass 2 — split this verb into alternating language segments. Every line
# starting with "¶EN¶ " is a standalone English sentence; everything else
# accumulates as Italian until the next one (or end of file).
awk -v outdir="$RA_WORK/segs" -v base="$b" '
  BEGIN { seg = 0; lang = "it"; buf = "" }
  function flush() {
    if (buf != "") {
      fname = sprintf("%s/%s__%03d.%s.txt", outdir, base, seg, lang)
      print buf > fname
      close(fname)
      seg++
      buf = ""
    }
  }
  /^¶EN¶ / {
    flush()
    sub(/^¶EN¶ /, "")
    lang = "en"; buf = $0
    flush()
    lang = "it"
    next
  }
  { buf = buf $0 "\n" }
  END { flush() }
' "$f"

# Voice each segment on its own — the voice is always a real -v argument,
# never text inside [[ ]], so it can never get spoken instead of switched to.
for seg in "$RA_WORK/segs/${b}__"*.txt; do
  [ -e "$seg" ] || continue
  sb="$(basename "$seg" .txt)"
  case "$sb" in
    *.en) v="$RA_EN_VOICE" ;;
    *)    v="$RA_VOICE" ;;
  esac
  say -v "$v" -f "$seg" -o "$RA_WORK/segaiff/$sb.aiff" --file-format=AIFF
done

# Stitch this verb's segments back into one file, in order (the zero-padded
# segment index sorts correctly as plain text).
concat="$RA_WORK/segaiff/${b}.concat.txt"
: > "$concat"
for a in "$RA_WORK/segaiff/${b}__"*.aiff; do
  printf "file '%s'\n" "$a" >> "$concat"
done
ffmpeg -y -loglevel error -f concat -safe 0 -i "$concat" $RA_FLOOR "$RA_WORK/aiff/$b.aiff"
afconvert -f m4af -d aac -s 2 -b "$RA_BITRATE" "$RA_WORK/aiff/$b.aiff" "$RA_OUT/per-verbo/$b.m4a"
echo "  $b"
HELPER
chmod +x "$WORK/render_one.sh"

# Values go through the environment: `xargs -I` caps the built command at 255
# chars, which long iCloud paths overrun.
# Noise floor: a very faint pink hiss (~-70 dB, inaudible) mixed under the
# whole track so it never contains pure digital silence. Bluetooth headphones,
# AirPods and car stereos go to sleep during long stretches of exact silence
# and need ~0.5 s to wake — which swallowed the first word after each pause
# ("Passato prossimo" heard as just "prossimo"). amix halves each input, so
# volume=2 restores the speech to its original level.
RA_FLOOR='-f lavfi -i anoisesrc=color=pink:amplitude=0.002:sample_rate=22050 -filter_complex [0:a][1:a]amix=inputs=2:duration=first,volume=2'
export RA_FLOOR
export RA_VOICE="$VOICE" RA_EN_VOICE="$EN_VOICE" RA_WORK="$WORK" RA_BITRATE="$BITRATE" RA_OUT="$OUT"
find "$WORK/parts" -name '*.txt' -print0 | xargs -0 -P 6 -n 1 "$WORK/render_one.sh"

# The whole-track completo.m4a: every segment aiff, across every verb, in
# order — the "NN_verb__SSS.lang" naming sorts correctly as plain text since
# both the verb index and the segment index are zero-padded.
# Sort numerically on the item index (field 1) then by segment (field 4), so
# 100_x comes after 99_y — a plain text sort would put 100_ before 10_.
(cd "$WORK/segaiff" && ls | grep '\.aiff$' | sort -t_ -k1,1n -k4,4) | while IFS= read -r f; do printf "file '%s'\n" "$WORK/segaiff/$f"; done > "$WORK/concat.txt"
ffmpeg -y -loglevel error -f concat -safe 0 -i "$WORK/concat.txt" $RA_FLOOR "$WORK/full.aiff"
afconvert -f m4af -d aac -s 2 -b "$BITRATE" "$WORK/full.aiff" "$OUT/completo.m4a"

DUR=$(afinfo "$OUT/completo.m4a" | awk -F': ' '/estimated duration/{printf "%d", $2}')
printf '\nDone — %dh %02dm across %s verb(s)\n' $((DUR/3600)) $(((DUR%3600)/60)) "$COUNT"
echo "  $OUT/completo.m4a"
echo "  $OUT/per-verbo/  ($COUNT files)"
