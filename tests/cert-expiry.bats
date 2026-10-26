#!/usr/bin/env bats

load test_helper

# The openssl stub answers "s_client" with a marker naming the host, and
# "x509" with a notAfter date chosen per host. The clock is frozen at
# 2027-01-01T00:00:00Z by common_setup.
setup() {
  common_setup
  stub openssl \
    'if [[ "$1" == s_client ]]; then' \
    '  prev=""; for a in "$@"; do [[ "$prev" == -connect ]] && echo "HOST=${a%%:*}"; prev="$a"; done' \
    '  exit 0' \
    'fi' \
    'read -r line || true' \
    'case "${line#HOST=}" in' \
    '  ok.example.test) echo "notAfter=Dec 31 00:00:00 2027 GMT" ;;' \
    '  warn.example.test) echo "notAfter=Jan 20 00:00:00 2027 GMT" ;;' \
    '  crit.example.test) echo "notAfter=Jan  3 00:00:00 2027 GMT" ;;' \
    '  expired.example.test) echo "notAfter=Dec  1 00:00:00 2026 GMT" ;;' \
    '  *) exit 1 ;;' \
    'esac'
}

@test "no endpoints is a usage error" {
  run "$BIN/cert-expiry"
  [ "$status" -eq 64 ]
}

@test "critical threshold above warning is rejected" {
  run "$BIN/cert-expiry" -w 5 -c 10 ok.example.test
  [ "$status" -eq 64 ]
}

@test "non-numeric threshold is rejected" {
  run "$BIN/cert-expiry" -w soon ok.example.test
  [ "$status" -eq 64 ]
}

@test "healthy certificate exits 0" {
  run "$BIN/cert-expiry" ok.example.test
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok.example.test"*"OK"* ]]
}

@test "certificate inside the warning window exits 1" {
  run "$BIN/cert-expiry" warn.example.test
  [ "$status" -eq 1 ]
  [[ "$output" == *"19"*"WARNING"* ]]
}

@test "certificate inside the critical window exits 2" {
  run "$BIN/cert-expiry" crit.example.test
  [ "$status" -eq 2 ]
  [[ "$output" == *"CRITICAL"* ]]
}

@test "expired certificate exits 2" {
  run "$BIN/cert-expiry" expired.example.test
  [ "$status" -eq 2 ]
  [[ "$output" == *"EXPIRED"* ]]
}

@test "unreachable endpoint is UNKNOWN (3)" {
  run "$BIN/cert-expiry" down.example.test
  [ "$status" -eq 3 ]
  [[ "$output" == *"UNKNOWN"* ]]
}

@test "the worst result wins and UNKNOWN does not mask CRITICAL" {
  run "$BIN/cert-expiry" ok.example.test crit.example.test down.example.test
  [ "$status" -eq 2 ]
}

@test "custom port is passed to openssl" {
  run "$BIN/cert-expiry" ok.example.test:8443
  [ "$status" -eq 0 ]
  assert_called "s_client -servername ok.example.test -connect ok.example.test:8443"
}

@test "endpoints file skips comments and blank lines" {
  printf '# monitored endpoints\nok.example.test\n\nwarn.example.test  # renew soon\n' >"${BATS_TEST_TMPDIR}/hosts.txt"
  run "$BIN/cert-expiry" -f "${BATS_TEST_TMPDIR}/hosts.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ok.example.test"* ]]
  [[ "$output" == *"warn.example.test"* ]]
}

@test "--json emits valid JSON with days_left and status" {
  run --separate-stderr "$BIN/cert-expiry" --json ok.example.test down.example.test
  [ "$status" -eq 3 ]
  [ "$(jq -r '.[0].status' <<<"$output")" = "OK" ]
  [ "$(jq -r '.[0].days_left' <<<"$output")" = "364" ]
  [ "$(jq -r '.[1].days_left' <<<"$output")" = "null" ]
}

@test "custom thresholds change the classification" {
  run "$BIN/cert-expiry" -w 10 -c 5 warn.example.test
  [ "$status" -eq 0 ]
}
