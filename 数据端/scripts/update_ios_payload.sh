#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)"

DEFAULT_INDEX_OUTPUT="${REPO_ROOT}/ios开发/tsugie/tsugie/Resources/he_places.index.json"
DEFAULT_PAYLOAD_OUTPUT="${REPO_ROOT}/ios开发/tsugie/tsugie/Resources/he_places.payload.bin"
DEFAULT_KEY="tsugie-ios-seed-v1"

INDEX_OUTPUT="${DEFAULT_INDEX_OUTPUT}"
PAYLOAD_OUTPUT="${DEFAULT_PAYLOAD_OUTPUT}"
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
  --key "${KEY}"
)

if [[ -n "${GEOHASH_PRECISION}" ]]; then
  EXPORT_CMD+=(--geohash-precision "${GEOHASH_PRECISION}")
fi

if [[ "${PRETTY}" -eq 1 ]]; then
  EXPORT_CMD+=(--pretty)
fi

"${EXPORT_CMD[@]}"

python3 - "${INDEX_OUTPUT}" "${PAYLOAD_OUTPUT}" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

index_path = Path(sys.argv[1])
payload_path = Path(sys.argv[2])
if not index_path.exists():
    raise SystemExit(f"[error] index not found: {index_path}")
if not payload_path.exists():
    raise SystemExit(f"[error] payload not found: {payload_path}")

index_raw = index_path.read_bytes()
payload_raw = payload_path.read_bytes()
index_doc = json.loads(index_raw)
counts = index_doc.get("record_counts", {})
spatial = index_doc.get("spatial_index", {})
codec = index_doc.get("codec", {})

print(f"[ok] index_output: {index_path}")
print(f"[ok] payload_output: {payload_path}")
print(f"[ok] index_size_bytes: {len(index_raw)}")
print(f"[ok] index_sha256: {hashlib.sha256(index_raw).hexdigest()}")
print(f"[ok] payload_size_bytes: {len(payload_raw)}")
print(f"[ok] payload_sha256: {hashlib.sha256(payload_raw).hexdigest()}")
print(f"[ok] record_counts: hanabi={counts.get('hanabi', 0)} matsuri={counts.get('matsuri', 0)} total={counts.get('total', 0)}")
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
PY
