#!/usr/bin/env bats

load test_helper

setup() {
  common_setup
  stub kubectl \
    'case "$args" in' \
    '  "config current-context") echo "${KUBE_CTX:-aks-dev-weu}" ;;' \
    '  config\ view*) echo "payments" ;;' \
    'esac'
  stub az \
    'printf "sub-sandbox-01\t00000000-0000-0000-0000-000000000001\toperator@example.com\n"'
  stub aws \
    'printf "111122223333\tarn:aws:iam::111122223333:user/operator\n"'
}

@test "--help prints usage and exits 0" {
  run "$BIN/context-guard" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: context-guard"* ]]
}

@test "unknown option is a usage error (64)" {
  run "$BIN/context-guard" --bogus
  [ "$status" -eq 64 ]
}

@test "shows the kubectl context and namespace" {
  run "$BIN/context-guard" --kube
  [ "$status" -eq 0 ]
  [[ "$output" == *"context=aks-dev-weu namespace=payments"* ]]
}

@test "shows all three providers" {
  run "$BIN/context-guard" --azure --aws --kube
  [ "$status" -eq 0 ]
  [[ "$output" == *"subscription=sub-sandbox-01"* ]]
  [[ "$output" == *"account=111122223333"* ]]
  [[ "$output" == *"context=aks-dev-weu"* ]]
}

@test "matching glob assertion passes" {
  run "$BIN/context-guard" --expect-kube-context 'aks-dev-*'
  [ "$status" -eq 0 ]
}

@test "mismatching assertion refuses with 77" {
  run "$BIN/context-guard" --expect-kube-context 'aks-prod-*'
  [ "$status" -eq 77 ]
  [[ "$output" == *"does not match"* ]]
}

@test "azure subscription can be asserted by ID" {
  run "$BIN/context-guard" --expect-az-sub '00000000-0000-0000-0000-000000000001'
  [ "$status" -eq 0 ]
}

@test "aws account mismatch refuses with 77" {
  run "$BIN/context-guard" --expect-aws-account 999999999999
  [ "$status" -eq 77 ]
}

@test "a failed assertion never runs the command" {
  run "$BIN/context-guard" --expect-kube-context 'aks-prod-*' --yes -- touch "${BATS_TEST_TMPDIR}/ran"
  [ "$status" -eq 77 ]
  [ ! -e "${BATS_TEST_TMPDIR}/ran" ]
}

@test "without a terminal and without --yes the command is refused" {
  run "$BIN/context-guard" --kube -- touch "${BATS_TEST_TMPDIR}/ran" </dev/null
  [ "$status" -eq 77 ]
  [ ! -e "${BATS_TEST_TMPDIR}/ran" ]
}

@test "--yes runs the command after the checks" {
  run "$BIN/context-guard" --kube --yes -- touch "${BATS_TEST_TMPDIR}/ran"
  [ "$status" -eq 0 ]
  [ -e "${BATS_TEST_TMPDIR}/ran" ]
}

@test "the command's exit code is propagated" {
  run "$BIN/context-guard" --kube --yes -- sh -c 'exit 5'
  [ "$status" -eq 5 ]
}

@test "--dry-run prints the command instead of running it" {
  run "$BIN/context-guard" --kube --yes --dry-run -- touch "${BATS_TEST_TMPDIR}/ran"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN: touch"* ]]
  [ ! -e "${BATS_TEST_TMPDIR}/ran" ]
}

@test "protected context requires the context name to be typed" {
  export KUBE_CTX=aks-prod-weu TOOLKIT_FORCE_PROMPT=1
  run "$BIN/context-guard" --kube --protect '*prod*' -- touch "${BATS_TEST_TMPDIR}/ran" <<<"y"
  [ "$status" -eq 77 ]
  [ ! -e "${BATS_TEST_TMPDIR}/ran" ]

  run "$BIN/context-guard" --kube --protect '*prod*' -- touch "${BATS_TEST_TMPDIR}/ran" <<<"aks-prod-weu"
  [ "$status" -eq 0 ]
  [ -e "${BATS_TEST_TMPDIR}/ran" ]
}

@test "missing kubectl context is reported as a failed check" {
  stub kubectl 'exit 1'
  run "$BIN/context-guard" --kube
  [ "$status" -eq 77 ]
  [[ "$output" == *"no current context"* ]]
}
