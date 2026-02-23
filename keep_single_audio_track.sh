#!/usr/bin/env bash

set -euo pipefail

show_help() {
  cat <<'EOF'
Usage:
  ./keep_single_audio_track.sh -i <input_file> [-o <output_file>] [-t <audio_track_position>] [--dry-run]

Description:
  Keeps all non-audio streams (video, subtitles, chapters, attachments)
  and keeps exactly one audio track.

Defaults:
  - audio track position: 1 (second audio track, 0-based among audio streams)
  - output: <input_basename>.english-only.<ext>

Examples:
  ./keep_single_audio_track.sh -i "data/movie.mkv"
  ./keep_single_audio_track.sh -i "data/movie.mkv" -t 1
  ./keep_single_audio_track.sh -i "data/movie.mkv" -o "data/movie.en-only.mkv"
  ./keep_single_audio_track.sh -i "data/movie.mkv" --dry-run
EOF
}

input_file=""
output_file=""
audio_track_position="1"
dry_run="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--input)
      input_file="$2"
      shift 2
      ;;
    -o|--output)
      output_file="$2"
      shift 2
      ;;
    -t|--track)
      audio_track_position="$2"
      shift 2
      ;;
    --dry-run)
      dry_run="true"
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      show_help
      exit 1
      ;;
  esac
done

if [[ -z "$input_file" ]]; then
  echo "Error: input file is required." >&2
  show_help
  exit 1
fi

if [[ ! -f "$input_file" ]]; then
  echo "Error: input file not found: $input_file" >&2
  exit 1
fi

if ! [[ "$audio_track_position" =~ ^[0-9]+$ ]]; then
  echo "Error: audio track position must be a non-negative integer." >&2
  exit 1
fi

if [[ -z "$output_file" ]]; then
  input_dir="$(dirname "$input_file")"
  input_name="$(basename "$input_file")"
  input_ext="${input_name##*.}"
  input_base="${input_name%.*}"
  output_file="${input_dir}/${input_base}.english-only.${input_ext}"
fi

if [[ "$input_file" == "$output_file" ]]; then
  echo "Error: output file must be different from input file." >&2
  exit 1
fi

audio_count="$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$input_file" | wc -l | tr -d ' ')"

if (( audio_count == 0 )); then
  echo "Error: no audio streams found in input." >&2
  exit 1
fi

if (( audio_track_position >= audio_count )); then
  echo "Error: requested audio track position $audio_track_position does not exist (audio streams: $audio_count)." >&2
  exit 1
fi

ffmpeg_cmd=(
  ffmpeg
  -y
  -i "$input_file"
  -map 0
  -map -0:a
  -map "0:a:${audio_track_position}"
  -c copy
  "$output_file"
)

echo "Input:  $input_file"
echo "Output: $output_file"
echo "Audio:  keeping 0:a:${audio_track_position} (0-based among audio streams)"

if [[ "$dry_run" == "true" ]]; then
  printf 'Command:'
  printf ' %q' "${ffmpeg_cmd[@]}"
  printf '\n'
  exit 0
fi

"${ffmpeg_cmd[@]}"

echo "Done."
echo "Verifying resulting audio streams:"
ffprobe -v error -select_streams a -show_entries stream=index:stream_tags=language,title -of default=noprint_wrappers=1 "$output_file"
