#!/usr/bin/env bats
# Clock frozen at 2027-01-01T00:00:00Z.

load test_helper

setup() {
  common_setup
  stub az \
    'case "$args" in' \
    '  *"--vault-name kv-denied"*) echo "Forbidden" >&2; exit 1 ;;' \
    '  "keyvault list"*) echo "[\"kv-app-dev\"]" ;;' \
    '  "keyvault secret list"*) cat "$FIXTURES/az/kv-secrets.json" ;;' \
    '  "keyvault certificate list"*) cat "$FIXTURES/az/kv-certificates.json" ;;' \
    'esac'
}

@test "a vault is required" {
  run "$BIN/kv-secret-expiry"
  [ "$status" -eq 64 ]
}

@test "expired and critical items make the exit code 2" {
  run --separate-stderr "$BIN/kv-secret-expiry" -k kv-app-dev
  [ "$status" -eq 2 ]
  [[ "$output" == *"old-key"*"-17"*"EXPIRED"* ]]
  [[ "$output" == *"db-password"*"3"*"CRITICAL"* ]]
  [[ "$output" == *"api-token"*"20"*"WARNING"* ]]
}

@test "items that are OK or have no expiry are hidden by default" {
  run --separate-stderr "$BIN/kv-secret-expiry" -k kv-app-dev
  [[ "$output" != *"long-lived"* ]]
  [[ "$output" != *"no-expiry"* ]]
}

@test "certificate-backed secrets are not reported twice" {
  run --separate-stderr "$BIN/kv-secret-expiry" -k kv-app-dev --format json
  [ "$(jq '[.[] | select(.name == "tls-web")] | length' <<<"$output")" -eq 1 ]
  [ "$(jq -r '.[] | select(.name == "tls-web") | .kind' <<<"$output")" = "certificate" ]
}

@test "--no-certificates lists secrets only" {
  run --separate-stderr "$BIN/kv-secret-expiry" -k kv-app-dev --no-certificates --format json
  [ "$(jq '[.[] | select(.kind == "certificate")] | length' <<<"$output")" -eq 0 ]
  refute_called "certificate list"
}

@test "--warn-no-expiry surfaces secrets without an expiry date" {
  run --separate-stderr "$BIN/kv-secret-expiry" -k kv-app-dev --warn-no-expiry
  [[ "$output" == *"no-expiry"*"NO_EXPIRY"* ]]
}

@test "--all includes OK items" {
  run --separate-stderr "$BIN/kv-secret-expiry" -k kv-app-dev --all --format json
  [ "$(jq -r '.[] | select(.name == "long-lived") | .status' <<<"$output")" = "OK" ]
}

@test "json output is sorted by days left" {
  run --separate-stderr "$BIN/kv-secret-expiry" -k kv-app-dev --format json
  [ "$(jq -r '.[0].name' <<<"$output")" = "old-key" ]
}

@test "a narrow warning window only flags critical items" {
  run --separate-stderr "$BIN/kv-secret-expiry" -k kv-app-dev -w 5 -c 2 --format json
  [ "$(jq -r '[.[].name] | sort | join(",")' <<<"$output")" = "db-password,old-key,tls-web" ]
}

@test "an unreadable vault alone exits 3" {
  run "$BIN/kv-secret-expiry" -k kv-denied
  [ "$status" -eq 3 ]
  [[ "$output" == *"cannot list secrets"* ]]
}

@test "--all-vaults discovers vaults in the subscription" {
  run --separate-stderr "$BIN/kv-secret-expiry" --all-vaults
  [ "$status" -eq 2 ]
  assert_called "keyvault secret list --vault-name kv-app-dev"
}

@test "only metadata list operations are called, never secret show" {
  run --separate-stderr "$BIN/kv-secret-expiry" -k kv-app-dev
  refute_called "secret show"
  refute_called "secret download"
}
