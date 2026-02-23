#!/usr/bin/env bash

set -euo pipefail

show_help() {
  cat <<'EOF'
Usage:
  ./mkv_to_mp4.sh -i <input.mkv> [-o <output.mp4>] [--reencode] [--quiet] [--dry-run]

Description:
  Converts MKV to MP4.

  Default mode (no --reencode):
    - copies video stream (no video quality loss)
    - re-encodes audio to AAC 192k (Windows Media Player friendly)
    - drops subtitles/data/attachments for MP4 compatibility

  Re-encode mode (--reencode):
    - video: libx264 (CRF 18, preset medium)
    - audio: aac (192k)
    - drops subtitles/data/attachments

Examples:
  ./mkv_to_mp4.sh -i "data/movie.mkv"
  ./mkv_to_mp4.sh -i "data/movie.mkv" -o "data/movie.mp4"
  ./mkv_to_mp4.sh -i "data/movie.mkv" --reencode
  ./mkv_to_mp4.sh -i "data/movie.mkv" --quiet
  ./mkv_to_mp4.sh -i "data/movie.mkv" --dry-run
EOF
}

input_file=""
output_file=""
reencode="false"
quiet="false"
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
    --reencode)
      reencode="true"
      shift
      ;;
    --quiet)
      quiet="true"
      shift
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

if [[ "${input_file##*.}" != "mkv" ]]; then
  echo "Warning: input extension is not .mkv. Continuing anyway."
fi

if [[ -z "$output_file" ]]; then
  input_dir="$(dirname "$input_file")"
  input_name="$(basename "$input_file")"
  input_base="${input_name%.*}"
  output_file="${input_dir}/${input_base}.mp4"
fi

if [[ "${output_file##*.}" != "mp4" ]]; then
  output_file="${output_file}.mp4"
fi

if [[ "$input_file" == "$output_file" ]]; then
  echo "Error: output file must be different from input file." >&2
  exit 1
fi

ffmpeg_runtime_flags=(
  -nostdin
  -hide_banner
  -y
)

if [[ "$quiet" == "true" ]]; then
  ffmpeg_runtime_flags+=(
    -loglevel error
    -nostats
  )
else
  ffmpeg_runtime_flags+=(
    -loglevel info
    -stats
  )
fi

if [[ "$reencode" == "true" ]]; then
  ffmpeg_cmd=(
    ffmpeg
    "${ffmpeg_runtime_flags[@]}"
    -i "$input_file"
    -map 0:v
    -map 0:a?
    -sn
    -dn
    -c:v libx264
    -preset medium
    -crf 18
    -c:a aac
    -b:a 192k
    "$output_file"
  )
else
  ffmpeg_cmd=(
    ffmpeg
    "${ffmpeg_runtime_flags[@]}"
    -i "$input_file"
    -map 0:v
    -map 0:a?
    -sn
    -dn
    -c:v copy
    -c:a aac
    -b:a 192k
    "$output_file"
  )
fi

echo "Input:  $input_file"
echo "Output: $output_file"
echo "Mode:   $([[ "$reencode" == "true" ]] && echo "full re-encode (h264+aac)" || echo "copy video + AAC audio")"
echo "Logs:   $([[ "$quiet" == "true" ]] && echo "quiet" || echo "showing ffmpeg progress")"

if [[ "$dry_run" == "true" ]]; then
  printf 'Command:'
  printf ' %q' "${ffmpeg_cmd[@]}"
  printf '\n'
  exit 0
fi

"${ffmpeg_cmd[@]}"

echo "Done."
echo "Resulting streams:"
ffprobe -v error -show_entries stream=index,codec_type,codec_name:stream_tags=language,title -of default=noprint_wrappers=1 "$output_file"
