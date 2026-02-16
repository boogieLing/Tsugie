#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash 设计/static/icon/scripts/generate-svg-from-png.sh [--root <dir>] [--mode <embed|trace>]

Options:
  --root <dir>   PNG root directory, default: 设计/static/icon
  --mode <mode>  SVG generation mode:
                 embed (default): preserve color/alpha by embedding PNG in SVG
                 trace: vectorize via ImageMagick + potrace (single-color path)
  -h, --help     Show this help.
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
default_root="$(cd "${script_dir}/.." && pwd)"

root_dir="${default_root}"
mode="embed"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      [[ $# -ge 2 ]] || { echo "Missing value for --root" >&2; exit 2; }
      root_dir="$2"
      shift 2
      ;;
    --mode)
      [[ $# -ge 2 ]] || { echo "Missing value for --mode" >&2; exit 2; }
      mode="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -d "${root_dir}" ]]; then
  echo "Root directory not found: ${root_dir}" >&2
  exit 1
fi

if [[ "${mode}" != "embed" && "${mode}" != "trace" ]]; then
  echo "Unsupported mode: ${mode}" >&2
  exit 2
fi

if ! command -v magick >/dev/null 2>&1; then
  echo "Missing required command: magick" >&2
  exit 1
fi

if [[ "${mode}" == "trace" ]] && ! command -v potrace >/dev/null 2>&1; then
  echo "Mode trace requires command: potrace" >&2
  exit 1
fi

count_png=0
count_svg=0

while IFS= read -r -d '' png_file; do
  count_png=$((count_png + 1))
  svg_file="${png_file%.png}.svg"

  if [[ "${mode}" == "trace" ]]; then
    magick "${png_file}" "${svg_file}"
    count_svg=$((count_svg + 1))
    continue
  fi

  read -r width height <<<"$(magick identify -format '%w %h' "${png_file}")"

  {
    printf '<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s" viewBox="0 0 %s %s" preserveAspectRatio="xMidYMid meet">\n' "${width}" "${height}" "${width}" "${height}"
    printf '  <image width="%s" height="%s" href="data:image/png;base64,' "${width}" "${height}"
    base64 < "${png_file}" | tr -d '\n'
    printf '"/>\n'
    printf '</svg>\n'
  } > "${svg_file}"

  count_svg=$((count_svg + 1))
done < <(find "${root_dir}" -type f -name '*.png' -print0)

echo "mode=${mode} root=${root_dir} png=${count_png} svg_written=${count_svg}"
