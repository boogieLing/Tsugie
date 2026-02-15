#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HANABI_DIR="${ROOT_DIR}/HANABI"
CONSOLE_SCRIPT="${HANABI_DIR}/scripts/data_ops_console.py"

OPS_DIR="${ROOT_DIR}/ops"
PID_FILE="${OPS_DIR}/console.pid"
LOG_FILE="${OPS_DIR}/console.out.log"

ENV_NAME="${HANABI_CONDA_ENV:-hanabi-ops}"
HOST="${HANABI_OPS_HOST:-127.0.0.1}"
PORT="${HANABI_OPS_PORT:-8788}"

mkdir -p "${OPS_DIR}"

require_conda() {
  if ! command -v conda >/dev/null 2>&1; then
    echo "[ops] conda not found. Please install Miniconda/Anaconda first."
    exit 1
  fi
}

env_exists() {
  conda env list | awk '{print $1}' | grep -Fxq "${ENV_NAME}"
}

ensure_env() {
  if env_exists; then
    return
  fi
  echo "[ops] conda env '${ENV_NAME}' not found, creating from HANABI/environment.yml ..."
  conda env create -n "${ENV_NAME}" -f "${HANABI_DIR}/environment.yml"
}

is_running() {
  if [[ ! -f "${PID_FILE}" ]]; then
    return 1
  fi
  local pid
  pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
  if [[ -z "${pid}" ]]; then
    return 1
  fi
  kill -0 "${pid}" >/dev/null 2>&1
}

start() {
  require_conda
  ensure_env

  if [[ ! -f "${CONSOLE_SCRIPT}" ]]; then
    echo "[ops] console script not found: ${CONSOLE_SCRIPT}"
    exit 1
  fi

  if is_running; then
    echo "[ops] already running (pid=$(cat "${PID_FILE}"))"
    echo "[ops] url: http://${HOST}:${PORT}"
    return 0
  fi

  echo "[ops] starting console at http://${HOST}:${PORT} ..."
  conda run -n "${ENV_NAME}" python "${CONSOLE_SCRIPT}" --host "${HOST}" --port "${PORT}" >"${LOG_FILE}" 2>&1 &
  local pid=$!
  echo "${pid}" > "${PID_FILE}"

  sleep 1
  if ! kill -0 "${pid}" >/dev/null 2>&1; then
    echo "[ops] start failed, see log: ${LOG_FILE}"
    exit 1
  fi

  echo "[ops] started (pid=${pid})"
  echo "[ops] log: ${LOG_FILE}"
  echo "[ops] stop: scripts/ops_console.sh stop"
}

stop() {
  if ! is_running; then
    rm -f "${PID_FILE}"
    echo "[ops] not running"
    return 0
  fi

  local pid
  pid="$(cat "${PID_FILE}")"
  kill "${pid}" >/dev/null 2>&1 || true
  sleep 1
  if kill -0 "${pid}" >/dev/null 2>&1; then
    kill -9 "${pid}" >/dev/null 2>&1 || true
  fi
  rm -f "${PID_FILE}"
  echo "[ops] stopped"
}

status() {
  if is_running; then
    echo "[ops] running (pid=$(cat "${PID_FILE}"))"
    echo "[ops] url: http://${HOST}:${PORT}"
  else
    echo "[ops] not running"
  fi
}

logs() {
  touch "${LOG_FILE}"
  tail -f "${LOG_FILE}"
}

case "${1:-start}" in
  start) start ;;
  stop) stop ;;
  restart) stop; start ;;
  status) status ;;
  logs) logs ;;
  *)
    echo "usage: $0 [start|stop|restart|status|logs]"
    exit 1
    ;;
esac
