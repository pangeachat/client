#!/bin/bash
# Generates the route suite's fake-microphone fixtures (macOS: `say`,
# `afconvert`; plus `ffmpeg` for the noisy variants). Nothing here is
# committed: the wavs land in $ROUTES_FIXTURES (default
# $CALL_WORK_DIR/routes-fixtures).
#
# Each speaker has SENTINEL words that appear in no other speaker's script --
# they must match WORDS in lib.js. Every fixture runs about four minutes so a
# call of any route length is speech throughout (Chrome plays it %noloop).
#
#   CALL_WORK_DIR=... test/e2e/routes/make_fixtures.sh
set -euo pipefail
WORK="${CALL_WORK_DIR:-${TMPDIR:-/tmp}/callweb}"
OUT="${ROUTES_FIXTURES:-$WORK/routes-fixtures}"
mkdir -p "$OUT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# say VOICE TEXT -> 48k mono 16-bit wav
speak() { # name voice text
  say -v "$2" -r 155 -o "$TMP/$1.aiff" "$3"
  afconvert -f WAVE -d LEI16@48000 -c 1 "$TMP/$1.aiff" "$TMP/$1.wav"
}
# repeat a wav N times with 1s of silence between, into $OUT/name.wav
loop() { # name times
  local list="$TMP/$1.list"; : > "$list"
  ffmpeg -v error -y -f lavfi -i anullsrc=r=48000:cl=mono -t 1 -c:a pcm_s16le "$TMP/gap.wav"
  for _ in $(seq 1 "$2"); do echo "file '$TMP/$1.wav'" >> "$list"; echo "file '$TMP/gap.wav'" >> "$list"; done
  ffmpeg -v error -y -f concat -safe 0 -i "$list" -c:a pcm_s16le -ar 48000 -ac 1 "$OUT/$1.wav"
}
P='[[slnc 900]]'

speak learner Samantha "My compass is in the orchard by the old gate. $P I played the trumpet at the glacier festival last winter. $P A pelican landed on the marble fountain this morning. $P We added saffron to the soup before the thunder started. $P Can you hear the thunder over the orchard? $P The marble statue holds a little brass compass."
loop learner 8

speak learner2 Samantha "I left the lantern burning by the window all night. $P My bicycle is still chained to the railing outside. $P We walked down to the harbor before the rain started. $P Nothing much has happened here since November. $P There is cinnamon and walnut in the tin on the shelf. $P The ferry leaves from the far end of the meadow road."
loop learner2 8

speak peer Daniel "I keep my violin next to the tractor in the barn. $P The lighthouse keeper made a pancake for breakfast. $P We hiked up the volcano with one big umbrella. $P A giraffe at the zoo stole my picnic blanket. $P Did you see the lighthouse from the volcano? $P Bring the blanket and the violin tomorrow."
loop peer 8

# Spanish learner: L2 Spanish sentences interleaved with L1 English (#3351).
speak es_l2a "Mónica" "La biblioteca abre a las nueve de la mañana. $P Una mariposa amarilla entró por la ventana."
speak es_l1a Samantha "I put the kettle on before the sparrow came back. $P My keys are in my coat pocket."
speak es_l2b "Mónica" "Compré una zanahoria grande en el mercado. $P Desde la montaña se ve el río, y traje una cuchara de madera."
speak es_l1b Samantha "Smoke was coming out of the chimney all evening."
ffmpeg -v error -y -i "$TMP/es_l2a.wav" -i "$TMP/es_l1a.wav" -i "$TMP/es_l2b.wav" -i "$TMP/es_l1b.wav" \
  -filter_complex "[0][1][2][3]concat=n=4:v=0:a=1" -ar 48000 -ac 1 -c:a pcm_s16le "$TMP/es_mix.wav"
loop es_mix 8

# French learner: L2 French interleaved with L1 English (#3382, #3351).
speak fr_l2a Jacques "La boulangerie du village ouvre très tôt. $P Une grenouille verte dort sous mon parapluie."
speak fr_l1a Samantha "The ladder is leaning against the wall by the carpet."
speak fr_l2b Jacques "Nous avons mangé du fromage avec du pain. $P J'ai perdu une chaussette, et la citrouille est dans le jardin."
speak fr_l1b Samantha "The wizard in the story carved a pumpkin."
ffmpeg -v error -y -i "$TMP/fr_l2a.wav" -i "$TMP/fr_l1a.wav" -i "$TMP/fr_l2b.wav" -i "$TMP/fr_l1b.wav" \
  -filter_complex "[0][1][2][3]concat=n=4:v=0:a=1" -ar 48000 -ac 1 -c:a pcm_s16le "$TMP/fr_mix.wav"
loop fr_mix 8

# Acoustic variants (#3356): background noise + "music" (a synthetic chord
# progression with a beat), mixed under the speech.
for n in learner peer; do
  d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT/$n.wav")
  ffmpeg -v error -y -i "$OUT/$n.wav" \
    -f lavfi -t "$d" -i "anoisesrc=color=pink:amplitude=0.06:r=48000" \
    -f lavfi -t "$d" -i "aevalsrc='0.05*sin(2*PI*220*t)*(1+sin(2*PI*2*t))+0.04*sin(2*PI*277*t)+0.04*sin(2*PI*330*t)*gt(mod(t,2),1)':s=48000" \
    -filter_complex "[0][1][2]amix=inputs=3:normalize=0[a]" -map "[a]" -ar 48000 -ac 1 -c:a pcm_s16le "$OUT/${n}_noisy.wav"
done
ls -la "$OUT"
