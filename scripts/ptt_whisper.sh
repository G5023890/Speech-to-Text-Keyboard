#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="${ROOT_DIR}/.runtime"
AUDIO_FILE="${RUNTIME_DIR}/ptt_input.wav"
PID_FILE="${RUNTIME_DIR}/recording.pid"
TRANSCRIPT_FILE="${RUNTIME_DIR}/ptt_input.txt"

FFMPEG_BIN="${FFMPEG_BIN:-ffmpeg}"
WHISPER_BIN="${WHISPER_BIN:-whisper-cli}"
WHISPER_PROFILE="${WHISPER_PROFILE:-balanced}" # fast | balanced | quality
WHISPER_APP_SUPPORT_DIR="${WHISPER_APP_SUPPORT_DIR:-${HOME}/Library/Application Support/Voice Input}"
MODEL_DIR="${WHISPER_MODEL_DIR:-${WHISPER_APP_SUPPORT_DIR}/models}"
MODEL_SMALL_Q5="${MODEL_DIR}/ggml-small-q5_1.bin"
MODEL_SMALL="${MODEL_DIR}/ggml-small.bin"
DEFAULT_MODEL_Q5="${MODEL_DIR}/ggml-medium-q5_0.bin"
DEFAULT_MODEL_FULL="${MODEL_DIR}/ggml-medium.bin"
if [[ -z "${WHISPER_MODEL:-}" ]]; then
  case "${WHISPER_PROFILE}" in
    fast)
      if [[ -f "${MODEL_SMALL_Q5}" ]]; then
        WHISPER_MODEL="${MODEL_SMALL_Q5}"
      elif [[ -f "${MODEL_SMALL}" ]]; then
        WHISPER_MODEL="${MODEL_SMALL}"
      elif [[ -f "${DEFAULT_MODEL_Q5}" ]]; then
        WHISPER_MODEL="${DEFAULT_MODEL_Q5}"
      else
        WHISPER_MODEL="${DEFAULT_MODEL_FULL}"
      fi
      ;;
    balanced)
      if [[ -f "${DEFAULT_MODEL_Q5}" ]]; then
        WHISPER_MODEL="${DEFAULT_MODEL_Q5}"
      else
        WHISPER_MODEL="${DEFAULT_MODEL_FULL}"
      fi
      ;;
    quality)
      if [[ -f "${DEFAULT_MODEL_FULL}" ]]; then
        WHISPER_MODEL="${DEFAULT_MODEL_FULL}"
      elif [[ -f "${DEFAULT_MODEL_Q5}" ]]; then
        WHISPER_MODEL="${DEFAULT_MODEL_Q5}"
      else
        WHISPER_MODEL="${MODEL_SMALL_Q5}"
      fi
      ;;
    *)
      echo "error: unknown WHISPER_PROFILE '${WHISPER_PROFILE}' (use fast|balanced|quality)" >&2
      exit 1
      ;;
  esac
fi
WHISPER_LANGUAGE="${WHISPER_LANGUAGE:-auto}"
WHISPER_PROMPT="${WHISPER_PROMPT:-The speaker may switch between Russian, English, and Hebrew.}"
WHISPER_THREADS="${WHISPER_THREADS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 8)}"
WHISPER_VAD="${WHISPER_VAD:-0}"
WHISPER_BEAM_SIZE="${WHISPER_BEAM_SIZE:-1}"
WHISPER_BEST_OF="${WHISPER_BEST_OF:-1}"
GLOSSARY_FILE="${GLOSSARY_FILE:-${ROOT_DIR}/config/glossary.txt}"

ensure_runtime() {
  mkdir -p "${RUNTIME_DIR}"
}

run_transcription() {
  local audio_input="${1:-}"
  if [[ -z "${audio_input}" || ! -f "${audio_input}" ]]; then
    echo "error: audio_not_found ${audio_input}" >&2
    exit 1
  fi

  if [[ ! -f "${WHISPER_MODEL}" ]]; then
    echo "error: model_not_found ${WHISPER_MODEL}" >&2
    exit 1
  fi

  ensure_runtime
  local out_base="${RUNTIME_DIR}/ptt_input"
  rm -f "${TRANSCRIPT_FILE}"

  local effective_prompt="${WHISPER_PROMPT}"
  if [[ -f "${GLOSSARY_FILE}" ]]; then
    local glossary_line
    glossary_line="$(sed -E '/^\s*($|#)/d' "${GLOSSARY_FILE}" | tr '\n' '; ' | sed -E 's/[[:space:]]+/ /g; s/[;[:space:]]+$//')"
    if [[ -n "${glossary_line}" ]]; then
      effective_prompt="${WHISPER_PROMPT} Preferred terms and names: ${glossary_line}."
    fi
  fi

  local cmd=(
    "${WHISPER_BIN}"
    -m "${WHISPER_MODEL}"
    -f "${audio_input}"
    -l "${WHISPER_LANGUAGE}"
    --prompt "${effective_prompt}"
    -t "${WHISPER_THREADS}"
    -bs "${WHISPER_BEAM_SIZE}"
    -bo "${WHISPER_BEST_OF}"
    -nt
    -otxt
    -of "${out_base}"
  )
  if [[ "${WHISPER_VAD}" == "1" ]]; then
    cmd+=(--vad)
  fi
  "${cmd[@]}" >/dev/null 2>&1

  local text_output=""
  if [[ -f "${TRANSCRIPT_FILE}" ]]; then
    text_output="$(sed -E 's/^[[:space:]]+|[[:space:]]+$//g' "${TRANSCRIPT_FILE}" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g')"
  fi

  local normalized_prompt normalized_output
  normalized_prompt="$(printf '%s' "${effective_prompt}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^[:alnum:]]+/ /g; s/[[:space:]]+/ /g; s/^ //; s/ $//')"
  normalized_output="$(printf '%s' "${text_output}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^[:alnum:]]+/ /g; s/[[:space:]]+/ /g; s/^ //; s/ $//')"
  if [[ -n "${normalized_output}" && "${normalized_output}" == "${normalized_prompt}" ]]; then
    text_output=""
  fi

  rm -f "${TRANSCRIPT_FILE}"
  echo "${text_output}"
}

is_recording() {
  [[ -f "${PID_FILE}" ]] || return 1
  local pid
  pid="$(cat "${PID_FILE}")"
  [[ -n "${pid}" ]] || return 1
  kill -0 "${pid}" 2>/dev/null
}

start_recording() {
  ensure_runtime
  if is_recording; then
    echo "already_recording"
    exit 0
  fi

  rm -f "${AUDIO_FILE}" "${TRANSCRIPT_FILE}"
  "${FFMPEG_BIN}" -hide_banner -loglevel error \
    -f avfoundation -i ":0" \
    -ac 1 -ar 16000 -c:a pcm_s16le \
    "${AUDIO_FILE}" >/dev/null 2>&1 &
  echo $! >"${PID_FILE}"
  echo "recording_started"
}

stop_recording() {
  if ! is_recording; then
    echo "not_recording"
    exit 0
  fi

  local pid
  pid="$(cat "${PID_FILE}")"
  kill -INT "${pid}" 2>/dev/null || true

  for _ in {1..50}; do
    if kill -0 "${pid}" 2>/dev/null; then
      sleep 0.05
    else
      break
    fi
  done
  rm -f "${PID_FILE}"

  if [[ ! -s "${AUDIO_FILE}" ]]; then
    echo ""
    exit 0
  fi

  local text_output
  text_output="$(run_transcription "${AUDIO_FILE}")"
  rm -f "${TRANSCRIPT_FILE}" "${AUDIO_FILE}"
  echo "${text_output}"
}

download_model() {
  ensure_runtime
  mkdir -p "$(dirname "${WHISPER_MODEL}")"

  local model_name
  model_name="$(basename "${WHISPER_MODEL}")"
  local url="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${model_name}"
  curl -L --fail --output "${WHISPER_MODEL}" "${url}"
  echo "model_downloaded ${WHISPER_MODEL}"
}

usage() {
  echo "Usage: $0 {start|stop|transcribe <audio_file>|download-model|download-fast-model|download-turbo-model}" >&2
  exit 1
}

case "${1:-}" in
start)
  start_recording
  ;;
stop)
  stop_recording
  ;;
transcribe)
  run_transcription "${2:-}"
  ;;
download-model)
  download_model
  ;;
download-fast-model)
  WHISPER_MODEL="${MODEL_DIR}/ggml-medium-q5_0.bin" download_model
  ;;
download-turbo-model)
  WHISPER_MODEL="${MODEL_DIR}/ggml-small-q5_1.bin" download_model
  ;;
*)
  usage
  ;;
esac
