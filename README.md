# platform-ops-toolkit

[![ci](https://github.com/marlyngiselle/platform-ops-toolkit/actions/workflows/ci.yml/badge.svg)](https://github.com/marlyngiselle/platform-ops-toolkit/actions/workflows/ci.yml)
![Bash](https://img.shields.io/badge/bash-3.2%2B-4EAA25?logo=gnubash&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-7.2%2B-5391FE?logo=powershell&logoColor=white)
![License: MIT](https://img.shields.io/badge/license-MIT-blue)

Small, sharp command-line tools for day-to-day cloud and platform operations on Azure, AWS, Kubernetes and Windows servers.

Each tool answers one recurring operational question (*am I in the right context? what expires soon? what are we paying for that nobody uses? why is this namespace unhealthy?*) and does it the same way: **read-only by default, explicit about what it changes, honest in its exit codes, and tested.**

---

## Tool catalogue

| Tool | What it answers | Platform | Mode |
| --- | --- | --- | --- |
| [`context-guard`](docs/tools/context-guard.md) | Which subscription, account and cluster am I on? Assert it before a risky command runs | Azure · AWS · Kubernetes | Guard (runs your command only after checks and confirmation) |
| [`cert-expiry`](docs/tools/cert-expiry.md) | Which TLS certificates expire soon? Nagios-style exit codes, JSON output | Any endpoint | Read-only |
| [`k8s-triage`](docs/tools/k8s-triage.md) | Why is this namespace unhealthy? One Markdown report for the ticket | Kubernetes | Read-only |
| [`az-inventory`](docs/tools/az-inventory.md) | What resources exist, where, and who owns them? CSV with tag columns | Azure | Read-only |
| [`aws-inventory`](docs/tools/aws-inventory.md) | Same question for an AWS account, across regions | AWS | Read-only |
| [`az-orphans`](docs/tools/az-orphans.md) | Unattached disks, idle public IPs, detached NICs, old snapshots | Azure | Read-only · cleanup with `--delete` |
| [`aws-orphans`](docs/tools/aws-orphans.md) | Available EBS volumes, idle Elastic IPs, detached ENIs, old snapshots | AWS | Read-only · cleanup with `--delete` |
| [`kv-secret-expiry`](docs/tools/kv-secret-expiry.md) | Which Key Vault secrets and certificates are expired or expiring? Metadata only | Azure | Read-only |
| [`aks-node-image-check`](docs/tools/aks-node-image-check.md) | Which AKS node pools run an outdated node image? | Azure · AKS | Read-only · node image upgrade with `--upgrade` |
| [`Get-ServerHealthSnapshot`](docs/tools/powershell.md#get-serverhealthsnapshot) | CPU, memory, disk, stopped services, pending reboot, error events per server | Windows | Read-only |
| [`Get-IisSiteReport`](docs/tools/powershell.md#get-iissitereport) | IIS sites, app pool state and identity, bindings, certificate expiry | Windows · IIS | Read-only |
| [`Test-AzTagCompliance`](docs/tools/powershell.md#test-aztagcompliance) | Which resources break the tagging standard? Optionally merge default tags | Azure | Read-only · tags with `-DefaultValue` (`-WhatIf` aware) |

## Quick look

```console
$ cert-expiry www.example.com api.example.com legacy.example.com
HOST                                     PORT   DAYS_LEFT NOT_AFTER             STATUS
www.example.com                          443    364       2027-12-31T00:00:00Z  OK
api.example.com                          443    19        2027-01-20T00:00:00Z  WARNING
legacy.example.com                       443    2         2027-01-03T00:00:00Z  CRITICAL
$ echo $?
2
```

```console
$ az-orphans -g rg-lab --dry-run
KIND       NAME                             RESOURCE_GROUP       LOCATION       DETAIL                   AGE_DAYS
disk       disk-old-vm-os                   rg-lab               westeurope     128GB Premium_LRS        213
public-ip  pip-old-lb                       rg-lab               westeurope     Standard 203.0.113.10    -
nic        nic-old-vm                       rg-lab               westeurope     10.10.1.4                -
snapshot   snap-2026-03                     rg-lab               westeurope     128GB                    306
DRY-RUN: az disk delete --ids /subscriptions/0000.../disks/disk-old-vm-os --yes
DRY-RUN: az network public-ip delete --ids /subscriptions/0000.../publicIPAddresses/pip-old-lb
DRY-RUN: az network nic delete --ids /subscriptions/0000.../networkInterfaces/nic-old-vm
```

```console
$ context-guard --expect-kube-context 'aks-prod-*' -- kubectl delete namespace scratch
Active context:
  kube     context=aks-dev-weu namespace=payments
[ERROR] context-guard: kube: context 'aks-dev-weu' does not match 'aks-prod-*'
$ echo $?
77
```

All examples in this repository use synthetic data: zero GUIDs, the AWS documentation account `111122223333`, and the documentation IP ranges `203.0.113.0/24` and `198.51.100.0/24`.

## Install

Requirements: Bash 3.2+, `jq`, and the CLI of the platform you target (`az`, `aws`, `kubectl`, `openssl`). PowerShell 7.2+ for the module.

```bash
git clone https://github.com/marlyngiselle/platform-ops-toolkit.git
cd platform-ops-toolkit

# Option 1: install into ~/.local/bin (symlinks; tools find their library through them)
make install                 # or: make install PREFIX=/usr/local

# Option 2: run in place
export PATH="$PWD/bin:$PATH"

cert-expiry --help
```

PowerShell:

```powershell
Import-Module ./powershell/PlatformOps/PlatformOps.psd1
Get-Command -Module PlatformOps
```

Uninstall with `make uninstall`.

## Design principles

**Safe by default.** Every tool reports before it acts. Changes need an explicit flag, show the target (subscription, account, cluster) first, and ask for confirmation. Without a terminal, they refuse unless `--yes` is given, so a cron job can never delete something by accident. Snapshots are never deleted automatically.

**Dry-run everything that mutates.** `--dry-run` prints the exact, shell-quoted commands, prefixed with `DRY-RUN:`. The plan can be reviewed in a pull request or attached to a change before anything runs. In PowerShell the same role is played by `-WhatIf`.

**Idempotent.** Reports have no side effects. Cleanups act only on what is still orphaned at run time; the second run finds nothing to do. Tag remediation merges missing tags and never overwrites existing ones.

**Observable.** Data on stdout, logs on stderr with UTC timestamps and levels. Exit codes follow the monitoring convention (`0` OK, `1` warning, `2` critical, `3` unknown) plus `64` usage, `69` missing dependency and `77` refused. A scheduler or an alerting agent can act on the code alone.

**Least privilege.** Every page in [docs/tools](docs/tools) states the minimum role: `Reader`, `Key Vault Reader`, `ec2:Describe*`, the Kubernetes `view` role. Write roles are needed only for the remediation flags, and the narrowest built-in role is named (for example `Tag Contributor`).

**Boring, portable code.** One shared library ([`lib/common.sh`](lib/common.sh)), `set -euo pipefail` everywhere, no Bash 4-only features, GNU and BSD `date` both supported. The same scripts run on a macOS laptop, a Linux jump host and a CI runner.

The full contract is in [docs/conventions.md](docs/conventions.md).

## Quality

| Check | Tooling | Where |
| --- | --- | --- |
| Static analysis, Bash | ShellCheck (no warnings allowed) | `make lint-sh`, CI |
| Unit and behaviour tests, Bash | bats-core: argument parsing, thresholds, exit codes, dry-run, confirmation, install | `make test-sh`, CI |
| Static analysis, PowerShell | PSScriptAnalyzer, error and warning rules | `make lint-ps`, CI |
| Tests, PowerShell | Pester 5 with every Windows and Az command mocked | `make test-ps`, CI |

Tests never touch a real cloud. Each suite puts stub `az`, `aws`, `kubectl` and `openssl` executables first on `PATH`, serves synthetic API responses from [`tests/fixtures`](tests/fixtures), freezes the clock, and asserts both the output and the commands that would have been called.

```bash
make check      # lint + test, exactly what CI runs
```

## Repository layout

```text
bin/                     the tools (Bash)
lib/common.sh            logging, dry-run aware execution, confirmation, dates, CSV
powershell/PlatformOps/  PowerShell 7 module (Public/ and Private/ functions)
powershell/tests/        Pester suites
tests/                   bats suites, fixtures and the stub helper
docs/                    conventions and one page per tool
.github/workflows/ci.yml lint and test on every push and pull request
```

## License

[MIT](LICENSE) © 2026 Giselle Da Costa
