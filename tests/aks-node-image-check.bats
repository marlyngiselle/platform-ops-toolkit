#!/usr/bin/env bats

load test_helper

LATEST="AKSUbuntu-2204gen2containerd-202610.01.0"

setup() {
  common_setup
  export LATEST
  stub az \
    'case "$args" in' \
    '  "aks list"*) cat "$FIXTURES/az/aks-list.json" ;;' \
    '  "aks nodepool list"*) cat "$FIXTURES/az/aks-nodepools.json" ;;' \
    '  "aks nodepool get-upgrades"*) echo "{\"latestNodeImageVersion\": \"$LATEST\"}" ;;' \
    '  "aks nodepool upgrade"*) exit 0 ;;' \
    'esac'
}

@test "--cluster without --resource-group is a usage error" {
  run "$BIN/aks-node-image-check" -c aks-dev-weu
  [ "$status" -eq 64 ]
}

@test "an outdated pool is flagged and exits 1" {
  run --separate-stderr "$BIN/aks-node-image-check"
  [ "$status" -eq 1 ]
  [[ "$output" == *"aks-dev-weu"*"system"*"CURRENT"* ]]
  [[ "$output" == *"aks-dev-weu"*"user"*"202609.15.0"*"202610.01.0"*"OUTDATED"* ]]
}

@test "all pools current exits 0" {
  export LATEST="AKSUbuntu-2204gen2containerd-202609.15.0"
  stub az \
    'case "$args" in' \
    '  "aks list"*) cat "$FIXTURES/az/aks-list.json" ;;' \
    '  "aks nodepool list"*) jq "map(.nodeImageVersion = \"$LATEST\")" "$FIXTURES/az/aks-nodepools.json" ;;' \
    '  "aks nodepool get-upgrades"*) echo "{\"latestNodeImageVersion\": \"$LATEST\"}" ;;' \
    'esac'
  run --separate-stderr "$BIN/aks-node-image-check"
  [ "$status" -eq 0 ]
}

@test "json output carries one record per pool" {
  run --separate-stderr "$BIN/aks-node-image-check" -f json
  [ "$(jq length <<<"$output")" -eq 2 ]
  [ "$(jq -r '.[] | select(.pool == "user") | .status' <<<"$output")" = "OUTDATED" ]
  [ "$(jq -r '.[0].kubernetesVersion' <<<"$output")" = "1.31.2" ]
}

@test "--dry-run prints an upgrade only for the outdated pool" {
  run --separate-stderr "$BIN/aks-node-image-check" -g rg-aks-dev -c aks-dev-weu --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN: az aks nodepool upgrade --resource-group rg-aks-dev --cluster-name aks-dev-weu --name user --node-image-only --no-wait"* ]]
  [[ "$output" != *"--name system"* ]]
  refute_called "nodepool upgrade"
}

@test "--upgrade without a terminal is refused" {
  run "$BIN/aks-node-image-check" --upgrade </dev/null
  [ "$status" -eq 77 ]
  refute_called "nodepool upgrade"
}

@test "--upgrade --yes requests the node image upgrade" {
  run "$BIN/aks-node-image-check" --upgrade --yes
  [ "$status" -eq 0 ]
  assert_called "aks nodepool upgrade --resource-group rg-aks-dev --cluster-name aks-dev-weu --name user --node-image-only"
}

@test "unknown latest image is reported as UNKNOWN, not CURRENT" {
  export LATEST=""
  stub az \
    'case "$args" in' \
    '  "aks list"*) cat "$FIXTURES/az/aks-list.json" ;;' \
    '  "aks nodepool list"*) cat "$FIXTURES/az/aks-nodepools.json" ;;' \
    '  "aks nodepool get-upgrades"*) exit 1 ;;' \
    'esac'
  run --separate-stderr "$BIN/aks-node-image-check" -f json
  [ "$(jq -r '[.[].status] | unique | join(",")' <<<"$output")" = "UNKNOWN" ]
}
