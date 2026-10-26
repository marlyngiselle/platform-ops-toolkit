# az-orphans

Find Azure resources that are billed but serve nothing, and optionally remove them with a reviewed, confirmed cleanup.

| Kind | Rule |
| --- | --- |
| `disk` | Managed disk in state `Unattached` |
| `public-ip` | Public IP with no IP configuration and no NAT gateway |
| `nic` | Network interface attached to no VM and no private endpoint |
| `snapshot` | Snapshot older than `--snapshot-age` days (default 90) |

Resources tagged `keep=true` are skipped (change with `--keep-tag KEY=VALUE`).

## Prerequisites

- Azure CLI (`az`), signed in, and `jq`

## Permissions

- Report: `Reader`
- Cleanup: delete rights on the resources, for example `Contributor` scoped to the resource group being cleaned. Prefer a scoped assignment over subscription-wide rights.

## Usage

```text
az-orphans [-s SUB] [-g RG] [--snapshot-age DAYS] [--keep-tag KEY=VALUE]
           [-f table|csv|json] [--fail-on-findings]
           [--delete] [--dry-run] [--yes]
```

## Examples

Report:

```console
$ az-orphans -s sub-sandbox-01
KIND       NAME                             RESOURCE_GROUP       LOCATION       DETAIL                   AGE_DAYS
disk       disk-old-vm-os                   rg-lab               westeurope     128GB Premium_LRS        213
public-ip  pip-old-lb                       rg-lab               westeurope     Standard 203.0.113.10    -
nic        nic-old-vm                       rg-lab               westeurope     10.10.1.4                -
snapshot   snap-2026-03                     rg-lab               westeurope     128GB                    306
2027-01-01T08:00:00Z [INFO ] az-orphans: 4 orphaned resource(s) found (keep tag: keep=true)
```

Review the cleanup plan, then apply it:

```console
$ az-orphans -g rg-lab --dry-run
...
2027-01-01T08:00:00Z [WARN ] az-orphans: cleanup target: subscription sub-sandbox-01 00000000-0000-0000-0000-000000000001, 3 resource(s); snapshots are never deleted
DRY-RUN: az disk delete --ids /subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-lab/providers/Microsoft.Compute/disks/disk-old-vm-os --yes
DRY-RUN: az network public-ip delete --ids /subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-lab/providers/Microsoft.Network/publicIPAddresses/pip-old-lb
DRY-RUN: az network nic delete --ids /subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-lab/providers/Microsoft.Network/networkInterfaces/nic-old-vm

$ az-orphans -g rg-lab --delete
...
Delete 3 orphaned resource(s)? [y/N]
```

Weekly report as CSV:

```bash
az-orphans -s sub-sandbox-01 --format csv > "orphans-$(date +%F).csv"
```

## Safety notes

- Snapshots are report-only: they may be the only copy of a deleted disk.
- The subscription name and id are printed before the confirmation prompt.
- Without a terminal, `--delete` refuses unless `--yes` is given.
- Already-deleted resources do not break a re-run: the next scan simply does not find them.

## Exit codes

`0` success · `1` orphans found with `--fail-on-findings` · `2` at least one deletion failed · `64` usage · `69` missing dependency · `77` confirmation declined.
