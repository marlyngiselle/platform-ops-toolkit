#!/usr/bin/env bats

load test_helper

setup() {
  common_setup
  export K8S_SET="${FIXTURES}/k8s"
  stub kubectl \
    'case "$args" in' \
    '  *"get namespace missing"*) exit 1 ;;' \
    '  *"get namespace"*) echo "namespace/shop" ;;' \
    '  *"config current-context"*) echo "kind-lab" ;;' \
    '  *"get pods"*) cat "$K8S_SET/pods.json" ;;' \
    '  *"get deployments"*) cat "$K8S_SET/deployments.json" ;;' \
    '  *"get pvc"*) cat "$K8S_SET/pvcs.json" ;;' \
    '  *"get events"*) cat "$K8S_SET/events.json" ;;' \
    '  *"top pod"*) [[ -n "${NO_METRICS:-}" ]] && exit 1' \
    '               printf "api-7d9c6b5f4-x2k8p 12m 180Mi\nworker-5c8f7d9b8-q4m2z 250m 1Gi\n" ;;' \
    'esac'
}

@test "namespace is required" {
  run "$BIN/k8s-triage"
  [ "$status" -eq 64 ]
}

@test "unknown namespace exits 3" {
  run "$BIN/k8s-triage" -n missing -o -
  [ "$status" -eq 3 ]
}

@test "report lists the failing pod with its waiting reason" {
  run --separate-stderr "$BIN/k8s-triage" -n shop -o -
  [ "$status" -eq 0 ]
  [[ "$output" == *"| worker-5c8f7d9b8-q4m2z | Running | CrashLoopBackOff | 1/2 |"* ]]
  [[ "$output" == *"| report-job-28741-abcde | Pending | Unschedulable | 0/1 | unscheduled |"* ]]
}

@test "completed job pods are not reported as not ready" {
  run --separate-stderr "$BIN/k8s-triage" -n shop -o -
  [[ "$output" != *"migrate-29001-zzzzz"* ]]
}

@test "restarts, degraded deployments and pending PVCs are reported" {
  run --separate-stderr "$BIN/k8s-triage" -n shop -o -
  [[ "$output" == *"| worker-5c8f7d9b8-q4m2z | worker | 14 | OOMKilled | 137 |"* ]]
  [[ "$output" == *"| worker | 3 | 1 | 3 |"* ]]
  [[ "$output" == *"| reports-cache | Pending | premium-zrs | 50Gi |"* ]]
}

@test "warning events are newest first and pipes are escaped" {
  run --separate-stderr "$BIN/k8s-triage" -n shop -o -
  [[ "$output" != *"Container image pulled"* ]]
  [[ "$output" == *'Insufficient memory \| preemption'* ]]
  first_event="$(grep -m1 -n 'BackOff' <<<"$output" | cut -d: -f1)"
  second_event="$(grep -m1 -n 'FailedScheduling' <<<"$output" | cut -d: -f1)"
  [ "$first_event" -lt "$second_event" ]
}

@test "top pods are sorted by memory" {
  run --separate-stderr "$BIN/k8s-triage" -n shop -o -
  [[ "$output" == *"| worker-5c8f7d9b8-q4m2z | 250m | 1Gi |"*"| api-7d9c6b5f4-x2k8p | 12m | 180Mi |"* ]]
}

@test "missing metrics API degrades gracefully" {
  export NO_METRICS=1
  run --separate-stderr "$BIN/k8s-triage" -n shop -o -
  [ "$status" -eq 0 ]
  [[ "$output" == *"Metrics API not available"* ]]
}

@test "--fail-on-findings exits 1 when something is wrong" {
  run --separate-stderr "$BIN/k8s-triage" -n shop -o - --fail-on-findings
  [ "$status" -eq 1 ]
}

@test "a healthy namespace reports None and exits 0 with --fail-on-findings" {
  export K8S_SET="${FIXTURES}/k8s/healthy"
  run --separate-stderr "$BIN/k8s-triage" -n shop -o - --fail-on-findings
  [ "$status" -eq 0 ]
  [[ "$output" == *"| Pods not ready | 0 |"* ]]
  [[ "$output" == *"_None._"* ]]
}

@test "report is written to a file" {
  run "$BIN/k8s-triage" -n shop -o "${BATS_TEST_TMPDIR}/report.md"
  [ "$status" -eq 0 ]
  grep -q '^# Kubernetes triage: `shop`' "${BATS_TEST_TMPDIR}/report.md"
}

@test "--context is passed to every kubectl call" {
  run "$BIN/k8s-triage" -n shop --context kind-lab -o -
  [ "$status" -eq 0 ]
  refute_called "^kubectl get pods"
  assert_called "^kubectl --context kind-lab get pods"
}
