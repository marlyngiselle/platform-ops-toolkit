# shellcheck shell=bash
#
# Shared setup for the bats suites. Every external CLI (az, aws, kubectl,
# openssl) is replaced by a stub on PATH, so the tests never touch a real
# cloud account and run the same on a laptop and in CI.

bats_require_minimum_version 1.5.0

TOOLKIT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
export BIN="${TOOLKIT_ROOT}/bin"
export FIXTURES="${TOOLKIT_ROOT}/tests/fixtures"

common_setup() {
  STUB_DIR="${BATS_TEST_TMPDIR}/stubs"
  mkdir -p "$STUB_DIR"
  PATH="${STUB_DIR}:${PATH}"
  export STUB_LOG="${BATS_TEST_TMPDIR}/stub.log"
  : >"$STUB_LOG"
  export NO_COLOR=1
  # Freeze "now" at 2027-01-01T00:00:00Z so expiry maths is deterministic.
  export TOOLKIT_NOW=1798761600
  unset AWS_PROFILE AWS_REGION AWS_DEFAULT_REGION DRY_RUN ASSUME_YES
}

# stub NAME [BODY_LINES...]
# Create an executable NAME on PATH. Each invocation is appended to
# $STUB_LOG as "NAME ARGS..." before BODY runs with "$*" available as $args.
stub() {
  local name="$1"
  shift
  {
    echo '#!/usr/bin/env bash'
    echo "echo \"${name} \$*\" >>\"\$STUB_LOG\""
    echo 'args="$*"'
    printf '%s\n' "$@"
  } >"${STUB_DIR}/${name}"
  chmod +x "${STUB_DIR}/${name}"
}

# assert_called PATTERN - the stub log has a line matching the grep pattern.
assert_called() {
  if ! grep -q -- "$1" "$STUB_LOG"; then
    echo "expected a call matching: $1" >&2
    echo "--- stub log ---" >&2
    cat "$STUB_LOG" >&2
    return 1
  fi
}

# refute_called PATTERN - no stub log line matches the grep pattern.
refute_called() {
  if grep -q -- "$1" "$STUB_LOG"; then
    echo "unexpected call matching: $1" >&2
    cat "$STUB_LOG" >&2
    return 1
  fi
}
