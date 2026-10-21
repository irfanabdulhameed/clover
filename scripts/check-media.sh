#!/bin/bash
# Converts generated video and audio samples with every target Clover offers
# and checks each result with ffprobe. Nothing is downloaded and nothing is
# written inside the repo: the samples live in a temp folder that is deleted at the end.
#
#   scripts/check-media.sh            build, then run everything
#   scripts/check-media.sh clip       only samples whose name matches "clip"
#   CLOVER=/path/to/Clover scripts/check-media.sh    use this binary, skip the build
#
# Needs ffmpeg, ffprobe and jq. Exits 1 if any check fails.
set -u
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$SELF")/.."

# Runs at low priority so the Mac stays responsive; ffmpeg and Clover inherit it.
if [ -z "${CHECK_MEDIA_NICE:-}" ]; then
  CHECK_MEDIA_NICE=1 exec nice -n 15 "$SELF" "$@"
fi

ONLY="${1:-}"
FFMPEG="$(command -v ffmpeg || echo /opt/homebrew/bin/ffmpeg)"
FFPROBE="$(command -v ffprobe || echo /opt/homebrew/bin/ffprobe)"
for tool in "$FFMPEG" "$FFPROBE" jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing tool: $tool" >&2; exit 2; }
done

if [ -z "${CLOVER:-}" ]; then
  swift build --product Clover 2>&1 | tail -2
  CLOVER="$(swift build --show-bin-path)/Clover"
fi
[ -x "$CLOVER" ] || { echo "No Clover binary at $CLOVER" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/clover-media.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
IN="$WORK/in"
mkdir -p "$IN" "$WORK/tmp"
# Clover makes its temp folders under TMPDIR; pointing it here shows whether any are left behind.
export TMPDIR="$WORK/tmp"

HAS_VORBIS=0
"$FFMPEG" -hide_banner -encoders 2>/dev/null | grep -q " libvorbis " && HAS_VORBIS=1

now() { perl -MTime::HiRes=time -e 'printf "%.2f\n", time'; }
gen() { "$FFMPEG" -hide_banner -v error -y "$@"; }

# ---------------------------------------------------------------- samples

TONE="sine=frequency=440:duration=3:sample_rate=44100,aformat=channel_layouts=stereo"
TAGS=(-metadata "title=Clover Test" -metadata "artist=Test Artist")

echo "Making samples in $IN"
SAMPLE_START=$(now)
vid() { echo "testsrc2=size=$1:rate=${2:-30}:duration=3"; }

gen -f lavfi -i "$(vid 1920x1080)" -f lavfi -i "$TONE" -c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p -c:a aac "$IN/big.mov"
gen -f lavfi -i "$(vid 720x1280)" -f lavfi -i "$TONE" -c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p -c:a aac "$IN/phone.mkv"
gen -f lavfi -i "$(vid 640x360)" -f lavfi -i "$TONE" -c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p -c:a aac "$IN/clip.mp4"
gen -f lavfi -i "$(vid 640x360)" -f lavfi -i "$TONE" -c:v libvpx-vp9 -deadline realtime -cpu-used 8 -b:v 600k -c:a libopus "$IN/clip.webm"
gen -f lavfi -i "$(vid 640x360)" -f lavfi -i "$TONE" -c:v mpeg4 -q:v 5 -c:a libmp3lame -b:a 128k "$IN/clip.avi"
gen -f lavfi -i "$(vid 640x360)" -f lavfi -i "$TONE" -c:v libx265 -preset ultrafast -x265-params log-level=error -tag:v hvc1 -pix_fmt yuv420p -c:a aac "$IN/hevc.mov"
gen -f lavfi -i "$(vid 640x360)" -vf "format=yuv444p,crop=321:181:exact=1" -c:v ffv1 "$IN/odd.mkv"
# Stored 1920x1080 with a 90 degree turn, like a phone video held upright.
gen -f lavfi -i "$(vid 1280x720)" -f lavfi -i "$TONE" -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac "$WORK/flat.mp4"
gen -display_rotation:v:0 90 -i "$WORK/flat.mp4" -c copy "$IN/turned.mov"
gen -f lavfi -i "$(vid 640x360)" -c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p "$IN/silent.mp4"
gen -f lavfi -i "$(vid 320x180 10)" -loop 0 "$IN/anim.gif"
# Other containers, tried with a few targets each.
gen -f lavfi -i "$(vid 640x360)" -f lavfi -i "$TONE" -c:v wmv2 -c:a wmav2 "$IN/extra.wmv"
gen -f lavfi -i "$(vid 640x360)" -f lavfi -i "$TONE" -c:v flv -c:a libmp3lame "$IN/extra.flv"
gen -f lavfi -i "$(vid 640x360)" -f lavfi -i "$TONE" -c:v mpeg2video -c:a mp2 "$IN/extra.mpg"
gen -f lavfi -i "$(vid 640x360)" -f lavfi -i "$TONE" -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac "$IN/extra.ts"
gen -f lavfi -i "$(vid 352x288)" -f lavfi -i "$TONE" -c:v mpeg4 -c:a aac "$IN/extra.3gp"

gen -f lavfi -i "$TONE" "${TAGS[@]}" -c:a libmp3lame -q:a 2 "$IN/tone.mp3"
gen -f lavfi -i "$TONE" "${TAGS[@]}" -c:a aac -b:a 160k "$IN/tone.m4a"
gen -f lavfi -i "$TONE" "${TAGS[@]}" -c:a pcm_s16le "$IN/tone16.wav"
gen -f lavfi -i "$TONE" "${TAGS[@]}" -ar 48000 -c:a pcm_s24le "$IN/tone24.wav"
gen -f lavfi -i "$TONE" "${TAGS[@]}" -c:a flac "$IN/tone.flac"
gen -f lavfi -i "$TONE" "${TAGS[@]}" -ar 48000 -c:a flac -sample_fmt s32 -bits_per_raw_sample 24 "$IN/tone24.flac"
if [ $HAS_VORBIS = 1 ]; then
  gen -f lavfi -i "$TONE" "${TAGS[@]}" -c:a libvorbis "$IN/tone.ogg"
else
  gen -f lavfi -i "$TONE" "${TAGS[@]}" -c:a libopus "$IN/tone.ogg"
fi
gen -f lavfi -i "$TONE" "${TAGS[@]}" -c:a libopus "$IN/tone.opus"
gen -f lavfi -i "$TONE" "${TAGS[@]}" -c:a pcm_s16be "$IN/tone.aiff"
# Songs with album art: the picture must not turn up as video in the results.
gen -f lavfi -i "testsrc2=size=300x300:rate=1:duration=1" -frames:v 1 "$WORK/cover.jpg"
gen -f lavfi -i "$TONE" -i "$WORK/cover.jpg" -map 0 -map 1 -c:a libmp3lame -c:v copy -id3v2_version 3 -disposition:v attached_pic "${TAGS[@]}" "$IN/cover.mp3"
gen -f lavfi -i "$TONE" -i "$WORK/cover.jpg" -map 0 -map 1 -c:a aac -c:v copy -disposition:v attached_pic "${TAGS[@]}" "$IN/cover.m4a"
gen -f lavfi -i "sine=frequency=440:duration=3:sample_rate=96000,aformat=channel_layouts=stereo" -c:a pcm_s24le "$IN/hires.wav"
gen -f lavfi -i "sine=frequency=440:duration=3:sample_rate=44100,aformat=channel_layouts=5.1" -c:a pcm_s16le "$IN/surround.wav"
gen -f lavfi -i "$TONE" -c:a wmav2 "$IN/extra.wma"
gen -f lavfi -i "$TONE" -c:a pcm_s16le "$IN/extra.caf"
gen -f lavfi -i "$TONE" -c:a aac "$IN/extra.aac"
head -c 200000 /dev/urandom > "$IN/garbage.mp4"
rm -f "$WORK/flat.mp4" "$WORK/cover.jpg"
echo "Samples ready in $(awk -v a="$(now)" -v b="$SAMPLE_START" 'BEGIN { printf "%.1f", a - b }') s"
echo

# ---------------------------------------------------------------- probing

J=""
load() { J="$("$FFPROBE" -v error -print_format json -show_format -show_streams "$1" 2>/dev/null)"; }
jv() { printf '%s' "$J" | jq -r "$1"; }
vs() { jv "[.streams[]|select(.codec_type==\"video\")][0]|($1) // empty"; }
au() { jv "[.streams[]|select(.codec_type==\"audio\")][0]|($1) // empty"; }
count() { jv "[.streams[]|select(.codec_type==\"$1\")]|length"; }
fmtname() { jv '.format.format_name // empty'; }
brand() { jv '.format.tags.major_brand // empty'; }
duration() { jv '.format.duration // empty'; }
title() { jv '([.format.tags // {}, (.streams[0].tags // {})] | map(to_entries[] | select(.key|ascii_downcase=="title") | .value) | .[0]) // empty'; }
# Sizes of the first video packets: the same numbers before and after means the stream was copied, not re-encoded.
packet_sig() { "$FFPROBE" -v error -select_streams v:0 -read_intervals "%+#6" -show_entries packet=size -of csv=p=0 "$1" 2>/dev/null | tr '\n' ' '; }
size_of() { stat -f %z "$1"; }
# "width height" as shown, which swaps for a video turned 90 degrees.
dims() {
  local w h r
  w=$(vs .width); h=$(vs .height)
  r=$(vs '[.side_data_list[]? | select(.side_data_type=="Display Matrix") | .rotation] | .[0] // 0')
  r=${r#-}; r=${r%.*}
  if [ "$r" = 90 ] || [ "$r" = 270 ]; then echo "$h $w"; else echo "$w $h"; fi
}

ERR=""
fail() { ERR="$ERR${ERR:+; }$1"; }
want() { [ "$2" = "$3" ] || fail "$1 is '$2', want '$3'"; }
in_list() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }
near() { awk -v a="$1" -v b="$2" -v t="$3" 'BEGIN { d = a - b; if (d < 0) d = -d; exit !(d <= t) }'; }
even_down() { echo $(( $1 / 2 * 2 )); }

# Codecs each container takes as they are. Mirrors what the converter copies.
copy_v() {
  case "$1" in
    mp4|mov) in_list "$2" "h264 hevc" ;;
    mkv) in_list "$2" "h264 hevc vp8 vp9 av1 mpeg4 mpeg2video mpeg1video vc1 theora" ;;
    webm) in_list "$2" "vp8 vp9 av1" ;;
    *) return 1 ;;
  esac
}
copy_a() {
  case "$1" in
    mp4) in_list "$2" "aac mp3 ac3 eac3 alac" ;;
    mov) in_list "$2" "aac alac mp3 ac3 eac3 pcm_s16le pcm_s16be pcm_s24le pcm_s24be" ;;
    mkv) in_list "$2" "aac mp3 opus vorbis flac ac3 eac3 dts alac truehd pcm_s16le pcm_s24le pcm_s32le" ;;
    webm) in_list "$2" "opus vorbis" ;;
    *) return 1 ;;
  esac
}

# check_video_target <target> <option> <source file> <output file>
check_video_target() {
  local t=$1 opt=$2 src=$3 out=$4
  load "$src"
  local sv sa sw sh sdur ssig
  sv=$(vs .codec_name); sa=$(au .codec_name); read -r sw sh <<< "$(dims)"; sdur=$(duration); ssig=$(packet_sig "$src")
  local spix; spix=$(vs .pix_fmt)
  load "$out"
  local ov oa ow oh opix otag
  ov=$(vs .codec_name); oa=$(au .codec_name); read -r ow oh <<< "$(dims)"; opix=$(vs .pix_fmt); otag=$(vs .codec_tag_string)

  near "$(duration)" "$sdur" 0.3 || fail "duration $(duration) vs $sdur"

  # Container.
  case $t in
    mp4) b=$(brand); [ "$b" != "qt  " ] && [ "$b" != "M4A " ] && [ -n "$b" ] || fail "brand '$b' is not MP4" ;;
    mov) want "brand" "$(brand)" "qt  " ;;
    mkv) case "$(fmtname)" in *matroska*) ;; *) fail "format $(fmtname)" ;; esac ;;
    webm) case "$(fmtname)" in *matroska*|*webm*) ;; *) fail "format $(fmtname)" ;; esac ;;
  esac

  # Video codec: copied as it was when "original" allows it, else H.264 (VP9 for WebM).
  local newv=h264; [ $t = webm ] && newv=vp9
  local copied=0
  if [ "$opt" = original ] && copy_v $t "$sv" && { [ $t != mp4 ] && [ $t != mov ] || [ "$spix" = yuv420p ]; }; then
    want "video codec (copied)" "$ov" "$sv"; copied=1
  else
    want "video codec" "$ov" "$newv"
  fi
  if [ $t = mp4 ] || [ $t = mov ]; then
    if [ "$ov" = h264 ]; then want "pix_fmt" "$opix" yuv420p; want "video tag" "$otag" avc1; fi
    if [ "$ov" = hevc ]; then want "video tag" "$otag" hvc1; fi
  fi
  # H.264 and HEVC keep their packet sizes between MP4, MOV and MKV, so equal sizes mean a copy.
  case "$src" in *.mp4|*.mov|*.mkv)
    if [ $copied = 1 ] && in_list "$sv" "h264 hevc" && [ "$(packet_sig "$out")" != "$ssig" ]; then fail "video was re-encoded, expected a copy"; fi ;;
  esac

  # Audio.
  if [ -z "$sa" ]; then
    [ -z "$oa" ] || fail "audio appeared from nothing"
  elif [ "$opt" = original ] && copy_a $t "$sa"; then
    want "audio codec (copied)" "$oa" "$sa"
  elif [ $t = webm ]; then
    want "audio codec" "$oa" opus
  else
    want "audio codec" "$oa" aac
  fi
  [ "$(count video)" = 1 ] || fail "$(count video) video streams"

  # Size: never up, even numbers, and 720p really 720 on the short side.
  local limit=0
  case $opt in 1080p) limit=1080 ;; 720p) limit=720 ;; small) limit=480 ;; esac
  local sshort slong
  if [ "$sw" -le "$sh" ]; then sshort=$sw; slong=$sh; else sshort=$sh; slong=$sw; fi
  local eshort=$sshort
  [ $limit -gt 0 ] && [ $limit -lt $sshort ] && eshort=$limit
  eshort=$(even_down $eshort)
  local oshort olong
  if [ "$ow" -le "$oh" ]; then oshort=$ow; olong=$oh; else oshort=$oh; olong=$ow; fi
  want "short side" "$oshort" "$eshort"
  local elong; elong=$(( (slong * eshort + sshort / 2) / sshort ))
  near "$olong" "$elong" 2 || fail "long side $olong, want about $elong"
  [ $((ow % 2)) = 0 ] && [ $((oh % 2)) = 0 ] || fail "odd size ${ow}x${oh}"
  { [ "$ow" -le "$sw" ] && [ "$oh" -le "$sh" ]; } || fail "upscaled to ${ow}x${oh} from ${sw}x${sh}"
  NOTE="${ow}x${oh} $ov${oa:+/$oa}"
}

check_gif_target() {
  local opt=$1 src=$2 out=$3
  load "$src"
  local sw sh sdur; read -r sw sh <<< "$(dims)"; sdur=$(duration)
  load "$out"
  want "format" "$(fmtname)" gif
  want "video codec" "$(vs .codec_name)" gif
  [ -z "$(count audio)" ] || [ "$(count audio)" = 0 ] || fail "gif has audio"
  local wmax=480
  case $opt in large) wmax=720 ;; small) wmax=320 ;; esac
  local ew=$sw; [ $wmax -lt $sw ] && ew=$wmax
  want "width" "$(vs .width)" "$ew"   # GIFs carry no turn, the picture is already upright
  near "$(duration)" "$sdur" 0.3 || fail "duration $(duration) vs $sdur"
  # Frames per second actually shown: counted frames over the length.
  local frames; frames=$("$FFPROBE" -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 "$out")
  awk -v n="$frames" -v d="$(duration)" 'BEGIN { exit !(d > 0 && n / d <= 15.6) }' || fail "$frames frames in $(duration) s is above 15 fps"
  NOTE="$(vs .width)x$(vs .height)"
}

check_audio_target() {
  local t=$1 opt=$2 src=$3 out=$4
  load "$src"
  local sdur stitle sbits srate
  sdur=$(duration); stitle=$(title); srate=$(au .sample_rate)
  sbits=$(au '[(.bits_per_raw_sample // "0"|tonumber), (.bits_per_sample // 0)] | max')
  load "$out"
  near "$(duration)" "$sdur" 0.3 || fail "duration $(duration) vs $sdur"
  [ "$(count video)" = 0 ] || fail "output has a video stream"
  [ "$(count audio)" = 1 ] || fail "$(count audio) audio streams"
  local codec; codec=$(au .codec_name)
  local deep=0; [ "${sbits:-0}" -ge 24 ] && deep=1
  case $t in
    mp3) want "format" "$(fmtname)" mp3; want "codec" "$codec" mp3
         [ "$(au .sample_rate)" -le 48000 ] || fail "sample rate $(au .sample_rate)"
         [ "$(au .channels)" -le 2 ] || fail "$(au .channels) channels" ;;
    m4a) want "brand" "$(brand)" "M4A "
         if [ "$opt" = lossless ]; then want "codec" "$codec" alac; else want "codec" "$codec" aac; fi ;;
    wav) want "format" "$(fmtname)" wav
         if [ $deep = 1 ]; then want "codec" "$codec" pcm_s24le; else want "codec" "$codec" pcm_s16le; fi ;;
    aiff) want "format" "$(fmtname)" aiff
         if [ $deep = 1 ]; then want "codec" "$codec" pcm_s24be; else want "codec" "$codec" pcm_s16be; fi ;;
    flac) want "format" "$(fmtname)" flac; want "codec" "$codec" flac
         local bits; bits=$(au '[(.bits_per_raw_sample // "0"|tonumber), (.bits_per_sample // 0)] | max')
         if [ $deep = 1 ]; then want "bits" "$bits" 24; else want "bits" "$bits" 16; fi ;;
    ogg) want "format" "$(fmtname)" ogg
         if [ $HAS_VORBIS = 1 ]; then want "codec" "$codec" vorbis; else want "codec" "$codec" opus; fi ;;
    opus) want "format" "$(fmtname)" ogg; want "codec" "$codec" opus ;;
  esac
  # Tags survive.
  if [ -n "$stitle" ]; then want "title tag" "$(title)" "$stitle"; fi
  NOTE="$codec $(au .channels)ch"
}

# ---------------------------------------------------------------- running

ROWS="$WORK/rows.txt"
: > "$ROWS"
PASSED=0; FAILED=0
STARTED=$(now)

record() { # status case seconds size note
  printf '%-5s %-34s %6s %9s  %s\n' "$1" "$2" "$3" "$4" "$5" | tee -a "$ROWS"
}

is_audio_target() { case $1 in mp3|m4a|wav|flac|aiff|ogg|opus) return 0 ;; esac; return 1; }

run_case() { # sample target option
  local sample=$1 t=$2 opt=$3
  local name="$sample -> $t${opt:+ [$opt]}"
  local err="$WORK/stderr.txt"
  local t0 t1 out status
  ERR=""; NOTE=""
  t0=$(now)
  if [ -n "$opt" ]; then
    "$CLOVER" convert "$t" --option "$opt" "$IN/$sample" >"$WORK/stdout.txt" 2>"$err"; status=$?
  else
    "$CLOVER" convert "$t" "$IN/$sample" >"$WORK/stdout.txt" 2>"$err"; status=$?
  fi
  out=$(head -1 "$WORK/stdout.txt")
  t1=$(now)
  local secs; secs=$(awk -v a="$t1" -v b="$t0" 'BEGIN { printf "%.1f", a - b }')

  load "$IN/$sample"
  local src_audio src_video
  src_audio=$(count audio); src_video=$(count video)

  # A file with no audio can't make audio, and Clover must say so.
  if is_audio_target "$t" && [ "$src_audio" = 0 ]; then
    if [ "$status" != 0 ] && grep -qi "no audio track" "$err" && [ -z "$out" ]; then
      PASSED=$((PASSED + 1)); record PASS "$name" "$secs" "-" "refused: $(head -c 60 "$err" | tr '\n' ' ')"
    else
      FAILED=$((FAILED + 1)); record FAIL "$name" "$secs" "-" "expected the no-audio error, got status $status $(head -c 80 "$err")"
    fi
    [ -n "$out" ] && rm -f "$out"
    return
  fi

  if [ "$status" != 0 ] || [ -z "$out" ] || [ ! -s "$out" ]; then
    FAILED=$((FAILED + 1)); record FAIL "$name" "$secs" "-" "status $status: $(head -c 120 "$err" | tr '\n' ' ')"
    [ -n "$out" ] && rm -f "$out"
    return
  fi

  case $t in
    mp4|mov|mkv|webm) check_video_target "$t" "${opt:-original}" "$IN/$sample" "$out" ;;
    gif) check_gif_target "${opt:-medium}" "$IN/$sample" "$out" ;;
    *) check_audio_target "$t" "${opt:-balanced}" "$IN/$sample" "$out" ;;
  esac
  local size; size=$(size_of "$out")
  if [ -z "$ERR" ]; then
    PASSED=$((PASSED + 1)); record PASS "$name" "$secs" "$size" "$NOTE"
  else
    FAILED=$((FAILED + 1)); record FAIL "$name" "$secs" "$size" "$ERR"
  fi
  rm -f "$out"
}

run_sample() { # sample, all-options targets
  local sample=$1
  local targets
  targets=$("$CLOVER" targets "$IN/$sample" 2>/dev/null)
  echo "$targets" | while IFS=$'\t' read -r id title options; do
    case $id in mp4|mov|mkv|webm|gif|mp3|m4a|wav|flac|aiff|ogg|opus) echo "$id $options" ;; esac
  done > "$WORK/targets.txt"
  while read -r id options; do
    # Every option for MP4, GIF, MP3 and M4A; the default for the rest.
    local list=""
    for o in $(echo "$options" | tr -d '[]'); do list="$list $o"; done
    case $id in
      mp4|gif|mp3|m4a)
        if [ -z "$list" ]; then run_case "$sample" "$id" ""; else for o in $list; do run_case "$sample" "$id" "$o"; done; fi ;;
      *)
        local def; def=$(echo "$options" | tr ' ' '\n' | grep '^\[' | tr -d '[]' | head -1)
        run_case "$sample" "$id" "$def" ;;
    esac
  done < "$WORK/targets.txt"
}

load "$IN/odd.mkv"
{ [ $(( $(vs .width) % 2 )) = 1 ] && [ $(( $(vs .height) % 2 )) = 1 ]; } || echo "WARNING: odd.mkv is $(vs .width)x$(vs .height), not odd-sized"
load "$IN/turned.mov"
[ "$(vs '.side_data_list[0].rotation')" != "" ] || echo "WARNING: turned.mov has no rotation"

printf '%-5s %-34s %6s %9s  %s\n' STATUS CASE "SECS" BYTES NOTES
printf '%s\n' "-------------------------------------------------------------------------------------------"

for sample in big.mov phone.mkv turned.mov clip.mp4 clip.webm clip.avi hevc.mov odd.mkv silent.mp4 anim.gif \
              extra.wmv extra.flv extra.mpg extra.ts extra.3gp \
              tone.mp3 tone.m4a cover.mp3 cover.m4a tone16.wav tone24.wav tone.flac tone24.flac tone.ogg tone.opus tone.aiff \
              hires.wav surround.wav extra.wma extra.caf extra.aac; do
  if [ -n "$ONLY" ] && ! echo "$sample" | grep -Eq "$ONLY"; then continue; fi
  [ -f "$IN/$sample" ] || { FAILED=$((FAILED + 1)); record FAIL "$sample" "-" "-" "sample could not be made"; continue; }
  run_sample "$sample"
done

# ---------------------------------------------------------------- failure cases

echo
echo "Failure cases"
if [ -z "$ONLY" ] || echo "garbage" | grep -Eq "$ONLY"; then
  before=$(ls "$IN" | wc -l)
  "$CLOVER" convert mov "$IN/garbage.mp4" >"$WORK/out.txt" 2>"$WORK/err.txt"; status=$?
  after=$(ls "$IN" | wc -l)
  if [ $status != 0 ] && grep -qi "couldn't read" "$WORK/err.txt" && [ "$before" = "$after" ]; then
    PASSED=$((PASSED + 1)); record PASS "garbage.mp4 -> mov" "-" "-" "$(head -c 70 "$WORK/err.txt" | tr '\n' ' ')"
  else
    FAILED=$((FAILED + 1)); record FAIL "garbage.mp4 -> mov" "-" "-" "status $status $(head -c 100 "$WORK/err.txt" | tr '\n' ' ') (files $before -> $after)"
  fi
fi

LEFT=$(find "$WORK/tmp" -mindepth 2 2>/dev/null | wc -l | tr -d ' ')
if [ "$LEFT" = 0 ]; then
  PASSED=$((PASSED + 1)); record PASS "temp folders cleaned up" "-" "-" "nothing left behind"
else
  FAILED=$((FAILED + 1)); record FAIL "temp folders cleaned up" "-" "-" "$LEFT items left in Clover's temp folder"
fi

TOTAL=$(awk -v a="$(now)" -v b="$STARTED" 'BEGIN { printf "%.0f", a - b }')
echo
echo "$PASSED passed, $FAILED failed, ${TOTAL}s"
[ "$FAILED" = 0 ]
