# k8s-triage

One command that gathers the first ten minutes of a Kubernetes incident into a Markdown report: pods not ready and why, containers that keep restarting, degraded deployments, PVCs stuck pending, the latest warning events and the top memory consumers.

The report is meant to be pasted into a ticket or a chat so the next person starts from the same facts.

## Prerequisites

- `kubectl` with a working context, `jq`
- `metrics-server` in the cluster for the "top pods" section (optional; the section degrades gracefully)

## Permissions

Read-only. `get`/`list` on pods, deployments, persistentvolumeclaims, events and namespaces in the target namespace, plus `pods.metrics.k8s.io` for the top section. The built-in `view` ClusterRole bound to the namespace is enough.

## Usage

```text
k8s-triage -n NAMESPACE [--context NAME] [-o FILE|-] [-r N] [-e N] [--fail-on-findings]
```

| Option | Default | Notes |
| --- | --- | --- |
| `-o`, `--output` | `k8s-triage-<ns>-<UTC>.md` | `-` writes to stdout |
| `-r`, `--restart-threshold` | 3 | Containers restarted at least N times are listed |
| `-e`, `--events` | 20 | Most recent warning events kept |
| `--fail-on-findings` | off | Exit 1 when anything needs attention |

Completed pods (phase `Succeeded`) are not counted as "not ready". Pipe characters in event messages are escaped so the tables stay intact.

## Example (abridged)

```console
$ k8s-triage -n payments -o -
```

```markdown
# Kubernetes triage: `payments`

- Context: `aks-dev-weu`
- Generated: 2027-01-01T08:00:00Z

## Summary

| Check | Count |
| --- | --- |
| Pods | 4 |
| Pods not ready | 2 |
| Containers with 3+ restarts | 1 |
| Degraded deployments | 1 |
| PVCs not bound | 1 |
| Warning events | 3 |

## Pods not ready

| Pod | Phase | Reason | Ready | Node |
| --- | --- | --- | --- | --- |
| worker-5c8f7d9b8-q4m2z | Running | CrashLoopBackOff | 1/2 | aks-system-12345678-vmss000001 |
| report-job-28741-abcde | Pending | Unschedulable | 0/1 | unscheduled |

## Containers restarted 3+ times

| Pod | Container | Restarts | Last termination | Exit code |
| --- | --- | --- | --- | --- |
| worker-5c8f7d9b8-q4m2z | worker | 14 | OOMKilled | 137 |

## PersistentVolumeClaims not bound

| PVC | Phase | StorageClass | Requested |
| --- | --- | --- | --- |
| reports-cache | Pending | premium-zrs | 50Gi |

## Recent warning events (last 20)

| Last seen | Object | Reason | Count | Message |
| --- | --- | --- | --- | --- |
| 2026-12-31T23:58:00Z | Pod/worker-5c8f7d9b8-q4m2z | BackOff | 42 | Back-off restarting failed container worker |
| 2026-12-31T23:40:00Z | PersistentVolumeClaim/reports-cache | ProvisioningFailed | 3 | storageclass "premium-zrs" not found |
```

Read in one pass, the story is already there: the worker is OOM-killed (exit 137) and the report job cannot schedule because a storage class does not exist.

## Exit codes

`0` report written · `1` findings with `--fail-on-findings` · `3` namespace not found or cluster unreachable · `64` usage · `69` missing dependency.
