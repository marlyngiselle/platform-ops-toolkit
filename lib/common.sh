# shellcheck shell=bash
#
# common.sh - shared helpers for platform-ops-toolkit.
#
# Sourced by every tool in bin/. Provides logging, dependency checks,
# dry-run aware execution, confirmation prompts and portable date maths.
# Compatible with bash 3.2 (macOS default) and later.
#
# Environment variables honoured:
#   LOG_LEVEL       debug | info | warn | error   (default: info)
#   NO_COLOR        disable ANSI colours when set (https://no-color.org)
#   DRY_RUN         1 to print mutating commands instead of running them
#   ASSUME_YES      1 to skip interactive confirmations
#   TOOLKIT_NOW     fixed "now" as epoch seconds (used by tests)

# Guard against double sourcing.
if [[ -n "${_TOOLKIT_COMMON_LOADED:-}" ]]; then
  return 0
fi
_TOOLKIT_COMMON_LOADED=1

TOOLKIT_VERSION="1.0.0"

# Exit codes. See docs/conventions.md.
# shellcheck disable=SC2034  # consumed by the tools that source this file
readonly EX_OK=0 EX_WARN=1 EX_CRIT=2 EX_UNKNOWN=3 EX_USAGE=64 EX_UNAVAILABLE=69 EX_REFUSED=77

TOOL_NAME="${TOOL_NAME:-$(basename "${0:-toolkit}")}"
LOG_LEVEL="${LOG_LEVEL:-info}"
DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${ASSUME_YES:-0}"

# --------------------------------------------------------------------------
# Logging (always to stderr, so stdout stays clean for data)
# --------------------------------------------------------------------------

_log_level_num() {
  case "$1" in
    debug) echo 10 ;;
    info) echo 20 ;;
    warn) echo 30 ;;
    error) echo 40 ;;
    *) echo 20 ;;
  esac
}

_use_color() {
  [[ -z "${NO_COLOR:-}" && -t 2 ]]
}

_log() {
  local level="$1"
  shift
  if (($(_log_level_num "$level") < $(_log_level_num "$LOG_LEVEL"))); then
    return 0
  fi
  local ts color="" reset="" label
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  label="$(printf '%-5s' "$(echo "$level" | tr '[:lower:]' '[:upper:]')")"
  if _use_color; then
    reset=$'\033[0m'
    case "$level" in
      debug) color=$'\033[2m' ;;
      info) color=$'\033[36m' ;;
      warn) color=$'\033[33m' ;;
      error) color=$'\033[31m' ;;
    esac
  fi
  printf '%s %s[%s]%s %s: %s\n' "$ts" "$color" "$label" "$reset" "$TOOL_NAME" "$*" >&2
}

log_debug() { _log debug "$@"; }
log_info() { _log info "$@"; }
log_warn() { _log warn "$@"; }
log_error() { _log error "$@"; }

# die MESSAGE [EXIT_CODE]
die() {
  log_error "$1"
  exit "${2:-1}"
}

# usage_error MESSAGE - report a bad invocation and exit with EX_USAGE.
usage_error() {
  log_error "$1"
  echo "Run '${TOOL_NAME} --help' for usage." >&2
  exit "$EX_USAGE"
}

# --------------------------------------------------------------------------
# Dependencies and argument helpers
# --------------------------------------------------------------------------

# require_cmd CMD... - exit with EX_UNAVAILABLE if any command is missing.
require_cmd() {
  local cmd missing=()
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if ((${#missing[@]} > 0)); then
    die "missing required command(s): ${missing[*]}" "$EX_UNAVAILABLE"
  fi
}

# require_arg FLAG VALUE - fail when an option that needs a value has none.
require_arg() {
  if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
    usage_error "option $1 requires a value"
  fi
}

# is_positive_int VALUE
is_positive_int() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

# handle_common_flag FLAG - process flags shared by every tool.
# Returns 0 if the flag was handled, 1 otherwise.
handle_common_flag() {
  case "$1" in
    -v | --verbose) LOG_LEVEL=debug ;;
    -q | --quiet) LOG_LEVEL=warn ;;
    --no-color) NO_COLOR=1 ;;
    --version)
      echo "${TOOL_NAME} ${TOOLKIT_VERSION}"
      exit 0
      ;;
    *) return 1 ;;
  esac
  return 0
}

# --------------------------------------------------------------------------
# Execution safety
# --------------------------------------------------------------------------

# quote_cmd ARGS... - render a command line safely quoted for display.
quote_cmd() {
  local out="" arg
  for arg in "$@"; do
    out+="$(printf '%q' "$arg") "
  done
  printf '%s' "${out% }"
}

# run_cmd CMD [ARGS...] - execute a mutating command, or print it under DRY_RUN=1.
run_cmd() {
  if [[ "$DRY_RUN" == 1 ]]; then
    printf 'DRY-RUN: %s\n' "$(quote_cmd "$@")"
    return 0
  fi
  log_debug "exec: $(quote_cmd "$@")"
  "$@"
}

# confirm PROMPT [EXPECTED]
# Ask for confirmation on the terminal. With EXPECTED, the operator must type
# that exact string (used for protected contexts). Without a TTY and without
# ASSUME_YES=1 the answer is always "no": automation must opt in explicitly.
confirm() {
  local prompt="$1" expected="${2:-}" answer=""
  if [[ "$ASSUME_YES" == 1 ]]; then
    log_info "confirmation skipped (--yes): ${prompt}"
    return 0
  fi
  if [[ ! -t 0 && "${TOOLKIT_FORCE_PROMPT:-0}" != 1 ]]; then
    log_error "no terminal available to confirm; re-run with --yes to proceed non-interactively"
    return 1
  fi
  if [[ -n "$expected" ]]; then
    printf '%s\nType "%s" to continue: ' "$prompt" "$expected" >&2
    IFS= read -r answer || true
    [[ "$answer" == "$expected" ]]
  else
    printf '%s [y/N] ' "$prompt" >&2
    IFS= read -r answer || true
    case "$answer" in
      y | Y | yes | YES | Yes) return 0 ;;
      *) return 1 ;;
    esac
  fi
}

# --------------------------------------------------------------------------
# Time helpers (portable across GNU and BSD date)
# --------------------------------------------------------------------------

now_epoch() {
  if [[ -n "${TOOLKIT_NOW:-}" ]]; then
    echo "$TOOLKIT_NOW"
  else
    date -u +%s
  fi
}

# to_epoch DATE_STRING - convert a timestamp to epoch seconds (UTC).
# Accepts ISO 8601 (2027-01-10T12:00:00Z, with optional fraction/offset),
# plain dates (2027-01-10) and OpenSSL style (Jan 10 12:00:00 2027 GMT).
to_epoch() {
  local input out fmt
  input="$(echo "$1" | tr -s ' ')"
  [[ -n "$input" ]] || return 1
  if out="$(date -u -d "$input" +%s 2>/dev/null)"; then
    echo "$out"
    return 0
  fi
  # BSD date: reduce ISO 8601 to "YYYY-MM-DDTHH:MM:SS". Cloud APIs return UTC,
  # so a trailing Z or +00:00 offset is dropped rather than interpreted.
  local iso_re='^([0-9]{4}-[0-9]{2}-[0-9]{2})([T ]([0-9]{2}:[0-9]{2}:[0-9]{2}))?'
  if [[ "$input" =~ $iso_re ]]; then
    input="${BASH_REMATCH[1]}T${BASH_REMATCH[3]:-00:00:00}"
  fi
  for fmt in "%Y-%m-%dT%H:%M:%S" "%b %d %H:%M:%S %Y %Z"; do
    if out="$(date -u -j -f "$fmt" "$input" +%s 2>/dev/null)"; then
      echo "$out"
      return 0
    fi
  done
  return 1
}

# days_until EPOCH - whole days from now until EPOCH (negative if past).
days_until() {
  local now
  now="$(now_epoch)"
  echo $((($1 - now) / 86400))
}

# epoch_to_iso EPOCH - format epoch seconds as an ISO 8601 UTC string.
epoch_to_iso() {
  date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null ||
    date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ
}

# --------------------------------------------------------------------------
# Output helpers
# --------------------------------------------------------------------------

# csv_field VALUE - quote a value for CSV (RFC 4180).
csv_field() {
  local v="$1"
  if [[ "$v" == *[,\"$'\n']* ]]; then
    v="\"${v//\"/\"\"}\""
  fi
  printf '%s' "$v"
}

# csv_row VALUES... - print one CSV row.
csv_row() {
  local first=1 v
  for v in "$@"; do
    ((first)) || printf ','
    csv_field "$v"
    first=0
  done
  printf '\n'
}

# open_output PATH - redirect stdout to PATH unless PATH is "-" (stdout).
open_output() {
  if [[ -n "$1" && "$1" != "-" ]]; then
    exec >"$1"
  fi
}
