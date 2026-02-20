#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

OMATSURI_DIR="${ROOT_DIR}/数据端/OMATSURI"
CONTENT_DIR="${OMATSURI_DIR}/data/content"
LATEST_RUN_JSON="${OMATSURI_DIR}/data/latest_run.json"
ENRICH_SCRIPT="${ROOT_DIR}/数据端/scripts/enrich_event_content.py"
PYTHON_BIN_DEFAULT="${ROOT_DIR}/数据端/HANABI/.venv/bin/python"

RUN_PREFIX="${RUN_PREFIX:-20260218_omatsuri_codex_polish}"
BATCH_SIZE="${BATCH_SIZE:-30}"
QPS="${QPS:-0.12}"
REQUEST_TIMEOUT_SEC="${REQUEST_TIMEOUT_SEC:-120}"
CODEX_TIMEOUT_SEC="${CODEX_TIMEOUT_SEC:-120}"
CODEX_MODEL="${CODEX_MODEL:-auto}"
POLISH_MODE="${POLISH_MODE:-auto}"
OPENAI_MODEL="${OPENAI_MODEL:-gpt-5-mini}"
OPENAI_BASE_URL="${OPENAI_BASE_URL:-https://api.openai.com/v1/responses}"
OPENAI_ONE_LINER_MODEL="${OPENAI_ONE_LINER_MODEL:-}"
OPENAI_ONE_LINER_BASE_URL="${OPENAI_ONE_LINER_BASE_URL:-}"
OPENAI_TRANSLATION_MODEL="${OPENAI_TRANSLATION_MODEL:-}"
OPENAI_TRANSLATION_BASE_URL="${OPENAI_TRANSLATION_BASE_URL:-}"
PYTHON_BIN="${PYTHON_BIN:-$PYTHON_BIN_DEFAULT}"
SKIP_PAST_DAYS="${SKIP_PAST_DAYS:-31}"
ONLY_PAST_DAYS="${ONLY_PAST_DAYS:--1}"
FAILED_ONLY_FLAG="${FAILED_ONLY_FLAG:---failed-only}"
PRIORITIZE_NEAR_START_FLAG="${PRIORITIZE_NEAR_START_FLAG:---prioritize-near-start}"
SINGLE_PASS_I18N_FLAG="${SINGLE_PASS_I18N_FLAG:---codex-single-pass-i18n}"

START_BATCH="${START_BATCH:-auto}"
END_BATCH="${END_BATCH:-}"
FORCE_FLAG="${FORCE_FLAG:---no-force}"
UPDATE_LATEST_FLAG="${UPDATE_LATEST_FLAG:---update-latest-run}"

if [[ ! -f "${LATEST_RUN_JSON}" ]]; then
  echo "[auto-batch] latest run file missing: ${LATEST_RUN_JSON}" >&2
  exit 1
fi

if [[ ! -x "${PYTHON_BIN}" ]]; then
  echo "[auto-batch] python bin missing or not executable: ${PYTHON_BIN}" >&2
  exit 1
fi

if [[ ! -f "${ENRICH_SCRIPT}" ]]; then
  echo "[auto-batch] enrich script missing: ${ENRICH_SCRIPT}" >&2
  exit 1
fi

fused_run_id="$(jq -r '.fused_run_id // empty' "${LATEST_RUN_JSON}")"
if [[ -z "${fused_run_id}" ]]; then
  echo "[auto-batch] fused_run_id missing in ${LATEST_RUN_JSON}" >&2
  exit 1
fi

fused_jsonl="${OMATSURI_DIR}/data/fused/${fused_run_id}/events_fused.jsonl"
if [[ ! -f "${fused_jsonl}" ]]; then
  echo "[auto-batch] fused jsonl missing: ${fused_jsonl}" >&2
  exit 1
fi

total_rows="$(wc -l < "${fused_jsonl}" | tr -d ' ')"
if [[ "${total_rows}" -le 0 ]]; then
  echo "[auto-batch] no rows in fused jsonl: ${fused_jsonl}" >&2
  exit 1
fi

total_batches="$(( (total_rows + BATCH_SIZE - 1) / BATCH_SIZE ))"

mkdir -p "${CONTENT_DIR}"
master_log="${CONTENT_DIR}/${RUN_PREFIX}_auto_runner.log"

detect_last_completed_batch() {
  local last=0
  local summary
  shopt -s nullglob
  for summary in "${CONTENT_DIR}/${RUN_PREFIX}"_b*_live/content_summary.json; do
    local dir_name batch_num
    dir_name="$(basename "$(dirname "${summary}")")"
    batch_num="$(echo "${dir_name}" | sed -n 's/.*_b\([0-9][0-9][0-9]\)_live$/\1/p')"
    if [[ -n "${batch_num}" ]]; then
      local batch_int
      batch_int="$((10#${batch_num}))"
      if [[ "${batch_int}" -gt "${last}" ]]; then
        last="${batch_int}"
      fi
    fi
  done
  shopt -u nullglob
  echo "${last}"
}

if [[ "${START_BATCH}" == "auto" ]]; then
  last_completed="$(detect_last_completed_batch)"
  START_BATCH="$((last_completed + 1))"
fi

if [[ -z "${END_BATCH}" ]]; then
  END_BATCH="${total_batches}"
fi

if [[ "${START_BATCH}" -gt "${END_BATCH}" ]]; then
  echo "[auto-batch] nothing to run: START_BATCH=${START_BATCH} END_BATCH=${END_BATCH}" | tee -a "${master_log}"
  exit 0
fi

echo "[auto-batch] run_prefix=${RUN_PREFIX} fused_run_id=${fused_run_id} total_rows=${total_rows} total_batches=${total_batches} start_batch=${START_BATCH} end_batch=${END_BATCH}" | tee -a "${master_log}"

for batch in $(seq "${START_BATCH}" "${END_BATCH}"); do
  start_index="$(( (batch - 1) * BATCH_SIZE ))"
  remaining="$(( total_rows - start_index ))"
  if [[ "${remaining}" -le 0 ]]; then
    break
  fi
  max_events="${BATCH_SIZE}"
  if [[ "${remaining}" -lt "${BATCH_SIZE}" ]]; then
    max_events="${remaining}"
  fi

  run_id="${RUN_PREFIX}_b$(printf "%03d" "${batch}")_live"
  run_dir="${CONTENT_DIR}/${run_id}"
  run_log="${run_dir}/runner.log"
  summary_json="${run_dir}/content_summary.json"
  mkdir -p "${run_dir}"

  if [[ -f "${summary_json}" ]]; then
    existing_total="$(jq -r '.counts.total // 0' "${summary_json}")"
    if [[ "${existing_total}" -eq "${max_events}" ]]; then
      echo "[auto-batch] skip batch=${batch} run_id=${run_id} (already complete total=${existing_total})" | tee -a "${master_log}"
      continue
    fi
  fi

  echo "[auto-batch] start batch=${batch} run_id=${run_id} start_index=${start_index} max_events=${max_events}" | tee -a "${master_log}"
  "${PYTHON_BIN}" -u "${ENRICH_SCRIPT}" \
    --project omatsuri \
    --run-id "${run_id}" \
    --start-index "${start_index}" \
    --max-events "${max_events}" \
    --progress-every 1 \
    --qps "${QPS}" \
    --request-timeout-sec "${REQUEST_TIMEOUT_SEC}" \
    --polish-mode "${POLISH_MODE}" \
    --openai-model "${OPENAI_MODEL}" \
    --openai-base-url "${OPENAI_BASE_URL}" \
    --openai-one-liner-model "${OPENAI_ONE_LINER_MODEL}" \
    --openai-one-liner-base-url "${OPENAI_ONE_LINER_BASE_URL}" \
    --openai-translation-model "${OPENAI_TRANSLATION_MODEL}" \
    --openai-translation-base-url "${OPENAI_TRANSLATION_BASE_URL}" \
    --codex-model "${CODEX_MODEL}" \
    --codex-timeout-sec "${CODEX_TIMEOUT_SEC}" \
    --skip-past-days "${SKIP_PAST_DAYS}" \
    --only-past-days "${ONLY_PAST_DAYS}" \
    "${FAILED_ONLY_FLAG}" \
    "${PRIORITIZE_NEAR_START_FLAG}" \
    "${SINGLE_PASS_I18N_FLAG}" \
    --download-images \
    --max-images 1 \
    "${FORCE_FLAG}" \
    "${UPDATE_LATEST_FLAG}" \
    > "${run_log}" 2>&1

  if [[ ! -f "${summary_json}" ]]; then
    echo "[auto-batch] failed: summary missing for run_id=${run_id}" | tee -a "${master_log}"
    exit 1
  fi

  ok="$(jq -r '.counts.ok // 0' "${summary_json}")"
  partial="$(jq -r '.counts.partial // 0' "${summary_json}")"
  empty="$(jq -r '.counts.empty // 0' "${summary_json}")"
  with_images="$(jq -r '.counts.with_images // 0' "${summary_json}")"
  echo "[auto-batch] done batch=${batch} run_id=${run_id} ok=${ok} partial=${partial} empty=${empty} with_images=${with_images}" | tee -a "${master_log}"
done

echo "[auto-batch] all requested batches completed" | tee -a "${master_log}"
