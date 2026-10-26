#!/usr/bin/env bats
# Unit tests for lib/common.sh.

load test_helper

setup() {
  common_setup
  # shellcheck source=../lib/common.sh
  source "${TOOLKIT_ROOT}/lib/common.sh"
}

@test "csv_field leaves plain values untouched" {
  run csv_field "team-web"
  [ "$output" = "team-web" ]
}

@test "csv_field quotes commas and doubles embedded quotes" {
  run csv_row a 'b,c' 'say "hi"'
  [ "$output" = 'a,"b,c","say ""hi"""' ]
}

@test "to_epoch understands ISO 8601 with fraction and offset" {
  run to_epoch "2027-01-10T12:00:00.1234567+00:00"
  [ "$status" -eq 0 ]
  [ "$output" = "1799582400" ]
}

@test "to_epoch understands the OpenSSL notAfter format" {
  run to_epoch "Jan 10 12:00:00 2027 GMT"
  [ "$output" = "1799582400" ]
}

@test "to_epoch understands a plain date" {
  run to_epoch "2027-01-10"
  [ "$output" = "1799539200" ]
}

@test "to_epoch fails on garbage" {
  run to_epoch "not a date"
  [ "$status" -ne 0 ]
}

@test "days_until counts whole days from the frozen clock" {
  run days_until 1799582400
  [ "$output" = "9" ]
}

@test "days_until is negative for past dates" {
  run days_until $((TOOLKIT_NOW - 3 * 86400))
  [ "$output" = "-3" ]
}

@test "run_cmd prints the command under DRY_RUN and does not execute it" {
  DRY_RUN=1
  run run_cmd touch "${BATS_TEST_TMPDIR}/created"
  [ "$status" -eq 0 ]
  [[ "$output" == "DRY-RUN: touch "* ]]
  [ ! -e "${BATS_TEST_TMPDIR}/created" ]
}

@test "run_cmd executes the command when not in dry-run" {
  run run_cmd touch "${BATS_TEST_TMPDIR}/created"
  [ "$status" -eq 0 ]
  [ -e "${BATS_TEST_TMPDIR}/created" ]
}

@test "quote_cmd escapes arguments with spaces" {
  run quote_cmd az group delete -n "rg with space"
  [ "$output" = 'az group delete -n rg\ with\ space' ]
}

@test "confirm refuses without a terminal and without --yes" {
  run confirm "Delete things?" </dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"re-run with --yes"* ]]
}

@test "confirm accepts automatically with ASSUME_YES=1" {
  ASSUME_YES=1
  run confirm "Delete things?" </dev/null
  [ "$status" -eq 0 ]
}

@test "confirm with an expected string requires the exact text" {
  export TOOLKIT_FORCE_PROMPT=1
  run confirm "Protected" "aks-prod-weu" <<<"aks-prod-weu"
  [ "$status" -eq 0 ]
  run confirm "Protected" "aks-prod-weu" <<<"y"
  [ "$status" -ne 0 ]
}

@test "require_cmd exits 69 when a command is missing" {
  run bash -c "source '${TOOLKIT_ROOT}/lib/common.sh'; require_cmd definitely-not-installed-xyz"
  [ "$status" -eq 69 ]
  [[ "$output" == *"definitely-not-installed-xyz"* ]]
}

@test "LOG_LEVEL=warn hides info messages" {
  LOG_LEVEL=warn
  run log_info "hidden"
  [ -z "$output" ]
  run log_warn "shown"
  [[ "$output" == *"[WARN ]"*"shown"* ]]
}

@test "is_positive_int accepts digits only" {
  is_positive_int 30
  ! is_positive_int -3
  ! is_positive_int 3d
}
