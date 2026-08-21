#!/bin/bash
# Turn shadowing-content.txt into paced shadowing audio for the "listen,
# listen again, say it yourself, then hear the meaning" technique.
#
# Same architecture as render-audio.sh: every voice goes in as a real -v
# argument to its own separate `say` call, never as text inside a bracketed
# command — so a compound name like "Paola (Enhanced)" can't get half-parsed
# and end up spoken aloud instead of acted on. Silence between pieces is
# generated directly with ffmpeg, so pause lengths are exact and don't
# depend on say's own [[slnc]] markers.
#
#   ./render-shadowing.sh
#   ./render-shadowing.sh shadowing-content.txt "Luca (Enhanced)" "Ava (Premium)"
#
# Produces, next to this script:
#   shadowing-audio/completo.m4a       every theme, in order
#   shadowing-audio/per-theme/*.m4a    one file per theme
#
# Requires: say, afconvert (both ship with macOS), ffmpeg (brew install ffmpeg).

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CONTENT_FILE="${1:-$HERE/shadowing-content.txt}"
VOICE="${2:-Paola (Enhanced)}"
EN_VOICE="${3:-Ava (Premium)}"
BITRATE=64000

if [ ! -f "$CONTENT_FILE" ]; then
  echo "error: content file not found: $CONTENT_FILE" >&2
  echo "usage: $(basename "$0") [content.txt] [Italian voice] [English voice]" >&2
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

OUT="$HERE/shadowing-audio"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

rm -rf "$OUT"
mkdir -p "$OUT/per-theme" "$WORK/themes" "$WORK/segaiff" "$WORK/aiff"

# Split the content file into one file per theme. Each line becomes a tagged
# row: the theme's own readable title (for the spoken announcement), an
# optional "## Tense name" sub-announcement, then alternating Italian/
# English phrase lines, in source order.
awk -v dir="$WORK/themes" '
  /^### / {
    n++
    title = $0
    sub(/^### /, "", title)
    name = title
    gsub(/[^A-Za-z0-9]+/, "_", name)
    file = sprintf("%s/%02d_%s.txt", dir, n, name)
    print "title\t" title > file
    next
  }
  /^## / { sub(/^## /, ""); print "tense\t" $0 > file; next }
  /^IT: / { sub(/^IT: /, ""); print "it\t" $0 > file; next }
  /^EN: / { sub(/^EN: /, ""); print "en\t" $0 > file; next }
' "$CONTENT_FILE"

COUNT=$(ls "$WORK/themes" | wc -l | tr -d ' ')
[ "$COUNT" -gt 0 ] || { echo "error: no themes found — check the content file's ### headers" >&2; exit 1; }
echo "Rendering $COUNT theme(s) with '$VOICE' (English lines: '$EN_VOICE')…"

# A real script file, not an inline one-liner (same reasoning as
# render-audio.sh): renders one theme's phrases into its own per-theme m4a.
cat > "$WORK/render_theme.sh" << 'HELPER'
#!/bin/bash
set -euo pipefail
f="$1"
b="$(basename "$f" .txt)"
seg=0

render_segment() {           # $1 = text, $2 = voice
  local text="$1" voice="$2"
  local segfile
  segfile=$(printf "%s/%s__%03d" "$RA_WORK/segaiff" "$b" "$seg")
  printf '%s' "$text" > "$segfile.txt"
  say -v "$voice" -f "$segfile.txt" -o "$segfile.aiff" --file-format=AIFF < /dev/null
  seg=$((seg+1))
}
render_silence() {           # $1 = duration in seconds
  local dur="$1"
  local segfile
  segfile=$(printf "%s/%s__%03d" "$RA_WORK/segaiff" "$b" "$seg")
  # -nostdin (and the redirect, belt-and-suspenders) matters here: this runs
  # inside a `while read ... done < "$f"` loop below, and ffmpeg reading
  # stdin by default silently steals bytes meant for that loop's own input,
  # skipping later lines in the file with no error at all.
  ffmpeg -nostdin -y -loglevel error -f lavfi -i "anullsrc=r=22050:cl=mono" -t "$dur" "$segfile.aiff" < /dev/null
  seg=$((seg+1))
}

while IFS=$'\t' read -r lang text; do
  case "$lang" in
    title)
      render_segment "$text" "$RA_VOICE"
      render_silence 1.0
      ;;
    tense)
      render_segment "$text" "$RA_VOICE"     # names the tense before its example
      render_silence 0.6
      ;;
    it)
      render_segment "$text" "$RA_VOICE"     # hear it at natural pace
      render_silence 0.6
      render_segment "$text" "$RA_VOICE"     # hear it again, lock in the rhythm
      render_silence 3.0                     # your turn — say it out loud
      ;;
    en)
      render_segment "$text" "$RA_EN_VOICE"  # confirm the meaning
      render_silence 1.5
      ;;
  esac
done < "$f"

concat="$RA_WORK/segaiff/${b}.concat.txt"
: > "$concat"
for a in "$RA_WORK/segaiff/${b}__"*.aiff; do
  printf "file '%s'\n" "$a" >> "$concat"
done
ffmpeg -y -loglevel error -f concat -safe 0 -i "$concat" -c copy "$RA_WORK/aiff/$b.aiff"
afconvert -f m4af -d aac -s 2 -b "$RA_BITRATE" "$RA_WORK/aiff/$b.aiff" "$RA_OUT/per-theme/$b.m4a"
echo "  $b"
HELPER
chmod +x "$WORK/render_theme.sh"

export RA_VOICE="$VOICE" RA_EN_VOICE="$EN_VOICE" RA_WORK="$WORK" RA_BITRATE="$BITRATE" RA_OUT="$OUT"
find "$WORK/themes" -name '*.txt' -print0 | xargs -0 -P 4 -n 1 "$WORK/render_theme.sh"

# The whole-track completo.m4a: every segment aiff, across every theme, in
# order — the "NN_Theme__SSS" naming sorts correctly as plain text since
# both the theme index and the segment index are zero-padded.
find "$WORK/segaiff" -name '*.aiff' | sort | while IFS= read -r f; do printf "file '%s'\n" "$f"; done > "$WORK/concat.txt"
ffmpeg -y -loglevel error -f concat -safe 0 -i "$WORK/concat.txt" -c copy "$WORK/full.aiff"
afconvert -f m4af -d aac -s 2 -b "$BITRATE" "$WORK/full.aiff" "$OUT/completo.m4a"

DUR=$(afinfo "$OUT/completo.m4a" | awk -F': ' '/estimated duration/{printf "%d", $2}')
printf '\nDone — %dh %02dm across %s theme(s)\n' $((DUR/3600)) $(((DUR%3600)/60)) "$COUNT"
echo "  $OUT/completo.m4a"
echo "  $OUT/per-theme/  ($COUNT files)"
