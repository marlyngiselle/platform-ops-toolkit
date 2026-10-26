#!/usr/bin/env bats
# Contract every tool must honour: --help, --version, usage errors, install.

load test_helper

setup() {
  common_setup
}

tools() {
  local tool
  for tool in "$BIN"/*; do basename "$tool"; done
}

@test "every tool prints usage with --help and exits 0" {
  local tool
  for tool in $(tools); do
    run "$BIN/$tool" --help
    [ "$status" -eq 0 ] || { echo "$tool --help exited $status"; return 1; }
    [[ "$output" == *"Usage: ${tool}"* ]] || { echo "$tool usage line missing"; return 1; }
  done
}

@test "every tool documents its exit codes" {
  local tool
  for tool in $(tools); do
    run "$BIN/$tool" --help
    [[ "$output" == *"Exit codes"* ]] || { echo "$tool has no exit code section"; return 1; }
  done
}

@test "every tool reports a version" {
  local tool
  for tool in $(tools); do
    run "$BIN/$tool" --version
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^${tool}\ [0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "$tool: $output"; return 1; }
  done
}

@test "every tool rejects an unknown option with exit 64" {
  local tool
  for tool in $(tools); do
    run "$BIN/$tool" --definitely-not-an-option
    [ "$status" -eq 64 ] || { echo "$tool exited $status"; return 1; }
  done
}

@test "every tool runs in strict mode" {
  local tool
  for tool in $(tools); do
    grep -q '^set -euo pipefail$' "$BIN/$tool" || { echo "$tool lacks strict mode"; return 1; }
  done
}

@test "make install creates working symlinks" {
  command -v make >/dev/null || skip "make not installed"
  run make -C "$TOOLKIT_ROOT" install PREFIX="${BATS_TEST_TMPDIR}/prefix"
  [ "$status" -eq 0 ]
  [ -L "${BATS_TEST_TMPDIR}/prefix/bin/cert-expiry" ]
  run "${BATS_TEST_TMPDIR}/prefix/bin/cert-expiry" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "cert-expiry "* ]]
}
