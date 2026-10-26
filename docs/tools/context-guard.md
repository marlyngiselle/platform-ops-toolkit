# context-guard

Show the active Azure subscription, AWS identity and kubectl context, assert them against what you expect, and only then run a command.

The classic incident is not a bad command. It is a good command in the wrong terminal. `context-guard` makes the target visible and checkable before anything runs.

## Prerequisites

- Any of `az`, `aws`, `kubectl` (only the ones you check are required)
- Signed-in sessions for those CLIs

## Permissions

None beyond what the wrapped command needs. The checks call `az account show`, `aws sts get-caller-identity` and `kubectl config current-context`, which every identity can run.

## Usage

```text
context-guard [--azure] [--aws] [--kube]
              [--expect-az-sub PATTERN] [--expect-aws-account PATTERN]
              [--expect-kube-context PATTERN] [--protect PATTERN]...
              [--yes] [--dry-run] [-- COMMAND [ARGS...]]
```

Patterns are shell globs. Without a provider flag, every installed CLI is checked.

## Examples

Show where you are:

```console
$ context-guard
Active context:
  azure    subscription=sub-sandbox-01 id=00000000-0000-0000-0000-000000000001 user=operator@example.com
  aws      profile=lab account=111122223333 arn=arn:aws:iam::111122223333:user/operator
  kube     context=aks-dev-weu namespace=payments
```

Refuse to run if the context is not the one expected:

```console
$ context-guard --expect-kube-context 'aks-prod-*' -- kubectl delete namespace scratch
Active context:
  kube     context=aks-dev-weu namespace=payments
2027-01-01T08:00:00Z [ERROR] context-guard: kube: context 'aks-dev-weu' does not match 'aks-prod-*'
2027-01-01T08:00:00Z [ERROR] context-guard: 1 context check(s) failed; refusing to continue
$ echo $?
77
```

Make production contexts require the name to be typed:

```console
$ context-guard --kube --protect '*prod*' -- kubectl rollout restart deploy/api
Active context:
  kube     context=aks-prod-weu namespace=payments
2027-01-01T08:00:00Z [WARN ] context-guard: context 'aks-prod-weu' is protected
About to run on a PROTECTED context: kubectl rollout restart deploy/api
Type "aks-prod-weu" to continue:
```

Preview only:

```console
$ context-guard --kube --yes --dry-run -- kubectl delete namespace scratch
Active context:
  kube     context=aks-dev-weu namespace=payments
DRY-RUN: kubectl delete namespace scratch
```

A handy alias for daily use:

```bash
alias kprod="context-guard --kube --protect '*prod*' --"
kprod kubectl drain aks-nodepool1-12345678-vmss000002 --ignore-daemonsets
```

## Exit codes

`0` checks passed (and the command, if any, exited 0) · `77` assertion failed, protected context refused, or confirmation declined · `64` usage · `69` CLI missing · otherwise the command's own exit code.
