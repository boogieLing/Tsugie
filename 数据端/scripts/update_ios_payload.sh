#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)"

DEFAULT_INDEX_OUTPUT="${REPO_ROOT}/ios开发/tsugie/tsugie/Resources/he_places.index.json"
DEFAULT_PAYLOAD_OUTPUT="${REPO_ROOT}/ios开发/tsugie/tsugie/Resources/he_places.payload.bin"
DEFAULT_IMAGE_PAYLOAD_OUTPUT="${REPO_ROOT}/ios开发/tsugie/tsugie/Resources/he_images.payload.bin"
DEFAULT_KEY="tsugie-ios-seed-v1"

INDEX_OUTPUT="${DEFAULT_INDEX_OUTPUT}"
PAYLOAD_OUTPUT="${DEFAULT_PAYLOAD_OUTPUT}"
IMAGE_PAYLOAD_OUTPUT="${DEFAULT_IMAGE_PAYLOAD_OUTPUT}"
KEY="${DEFAULT_KEY}"
PRETTY=0
GEOHASH_PRECISION=""
GEO_OVERLAP_GATE=1
MAX_HIGH_RISK_GROUPS=0
GEO_GATE_REPORT_OUTPUT="${REPO_ROOT}/数据端/reports/latest_geo_overlap_quality_gate.json"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [OPTIONS]

Options:
  --index-output PATH       Output index JSON path (default: ${DEFAULT_INDEX_OUTPUT})
  --payload-output PATH     Output payload bin path (default: ${DEFAULT_PAYLOAD_OUTPUT})
  --image-payload-output PATH
                            Output image payload bin path (default: ${DEFAULT_IMAGE_PAYLOAD_OUTPUT})
  --key STRING              Obfuscation key seed (default: ${DEFAULT_KEY})
  --geohash-precision N     Geohash precision (3-8)
  --max-high-risk-groups N  Geo overlap gate threshold (default: 0)
  --skip-geo-overlap-gate   Skip geo overlap quality gate before export
  --geo-gate-report PATH    Geo overlap gate report output path
  --pretty                  Pretty-print index json
  -h, --help                Show this help message
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --index-output)
      INDEX_OUTPUT="$2"
      shift 2
      ;;
    --payload-output)
      PAYLOAD_OUTPUT="$2"
      shift 2
      ;;
    --image-payload-output)
      IMAGE_PAYLOAD_OUTPUT="$2"
      shift 2
      ;;
    --key)
      KEY="$2"
      shift 2
      ;;
    --geohash-precision)
      GEOHASH_PRECISION="$2"
      shift 2
      ;;
    --max-high-risk-groups)
      MAX_HIGH_RISK_GROUPS="$2"
      shift 2
      ;;
    --skip-geo-overlap-gate)
      GEO_OVERLAP_GATE=0
      shift
      ;;
    --geo-gate-report)
      GEO_GATE_REPORT_OUTPUT="$2"
      shift 2
      ;;
    --pretty)
      PRETTY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[error] unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    esac
done

if [[ "${GEO_OVERLAP_GATE}" -eq 1 ]]; then
  echo "[step] geo overlap quality gate"
  python3 "${REPO_ROOT}/数据端/scripts/geo_overlap_quality_gate.py" \
    --project all \
    --max-high-risk-groups "${MAX_HIGH_RISK_GROUPS}" \
    --report-output "${GEO_GATE_REPORT_OUTPUT}"
  echo "[ok] geo overlap quality gate passed"
else
  echo "[warn] geo overlap quality gate is skipped"
fi

EXPORT_CMD=(
  python3 "${REPO_ROOT}/数据端/scripts/export_ios_seed.py"
  --index-output "${INDEX_OUTPUT}"
  --payload-output "${PAYLOAD_OUTPUT}"
  --image-payload-output "${IMAGE_PAYLOAD_OUTPUT}"
  --key "${KEY}"
)

if [[ -n "${GEOHASH_PRECISION}" ]]; then
  EXPORT_CMD+=(--geohash-precision "${GEOHASH_PRECISION}")
fi

if [[ "${PRETTY}" -eq 1 ]]; then
  EXPORT_CMD+=(--pretty)
fi

"${EXPORT_CMD[@]}"

python3 - "${INDEX_OUTPUT}" "${PAYLOAD_OUTPUT}" "${IMAGE_PAYLOAD_OUTPUT}" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

index_path = Path(sys.argv[1])
payload_path = Path(sys.argv[2])
image_payload_path = Path(sys.argv[3])
if not index_path.exists():
    raise SystemExit(f"[error] index not found: {index_path}")
if not payload_path.exists():
    raise SystemExit(f"[error] payload not found: {payload_path}")
if not image_payload_path.exists():
    raise SystemExit(f"[error] image payload not found: {image_payload_path}")

index_raw = index_path.read_bytes()
payload_raw = payload_path.read_bytes()
image_payload_raw = image_payload_path.read_bytes()
index_doc = json.loads(index_raw)
counts = index_doc.get("record_counts", {})
spatial = index_doc.get("spatial_index", {})
codec = index_doc.get("codec", {})
content_counts = index_doc.get("content_counts", {})
image_payload = index_doc.get("image_payload", {})

print(f"[ok] index_output: {index_path}")
print(f"[ok] payload_output: {payload_path}")
print(f"[ok] image_payload_output: {image_payload_path}")
print(f"[ok] index_size_bytes: {len(index_raw)}")
print(f"[ok] index_sha256: {hashlib.sha256(index_raw).hexdigest()}")
print(f"[ok] payload_size_bytes: {len(payload_raw)}")
print(f"[ok] payload_sha256: {hashlib.sha256(payload_raw).hexdigest()}")
print(f"[ok] image_payload_size_bytes: {len(image_payload_raw)}")
print(f"[ok] image_payload_sha256: {hashlib.sha256(image_payload_raw).hexdigest()}")
print(f"[ok] record_counts: hanabi={counts.get('hanabi', 0)} matsuri={counts.get('matsuri', 0)} total={counts.get('total', 0)}")
print(
    "[ok] content_counts: "
    f"description={content_counts.get('with_description', 0)} "
    f"one_liner={content_counts.get('with_one_liner', 0)} "
    f"source_urls={content_counts.get('with_source_urls', 0)} "
    f"images={content_counts.get('with_image_ref', 0)}"
)
print(
    "[ok] spatial_index: "
    f"scheme={spatial.get('scheme', '')} "
    f"precision={spatial.get('precision', '')} "
    f"bucket_count={spatial.get('bucket_count', '')}"
)
print(
    "[ok] codec: "
    f"compression={codec.get('compression', '')} "
    f"obfuscation={codec.get('obfuscation', '')} "
    f"encoding={codec.get('encoding', '')}"
)
print(
    "[ok] image_codec: "
    f"compression={image_payload.get('codec', {}).get('compression', '')} "
    f"obfuscation={image_payload.get('codec', {}).get('obfuscation', '')} "
    f"encoding={image_payload.get('codec', {}).get('encoding', '')} "
    f"format={image_payload.get('codec', {}).get('image_format', '')}"
)
PY
