# aws-orphans

Find AWS resources that are billed but serve nothing, per region, and optionally remove them with a reviewed, confirmed cleanup.

| Kind | Rule |
| --- | --- |
| `volume` | EBS volume in state `available` (attached to nothing) |
| `eip` | Elastic IP with no association (charged while idle) |
| `eni` | Network interface in state `available` |
| `snapshot` | Snapshot owned by the account, older than `--snapshot-age` days (default 90) |

Resources tagged `keep=true` are skipped (change with `--keep-tag KEY=VALUE`).

## Prerequisites

- AWS CLI v2 (`aws`) with valid credentials, and `jq`

## Permissions

- Report: `ec2:DescribeVolumes`, `ec2:DescribeAddresses`, `ec2:DescribeNetworkInterfaces`, `ec2:DescribeSnapshots`, `ec2:DescribeRegions`
- Cleanup adds: `ec2:DeleteVolume`, `ec2:ReleaseAddress`, `ec2:DeleteNetworkInterface`

## Usage

```text
aws-orphans [-r REGION]... [--all-regions] [-p PROFILE] [--snapshot-age DAYS]
            [--keep-tag KEY=VALUE] [-f table|csv|json] [--fail-on-findings]
            [--delete] [--dry-run] [--yes]
```

## Examples

```console
$ aws-orphans -r eu-west-1
KIND      ID                         NAME                     REGION         DETAIL             AGE_DAYS
volume    vol-0aaa1111bbbb2222c      old-build-agent          eu-west-1      100GiB gp3         244
eip       eipalloc-0123456789abcdef0 -                        eu-west-1      198.51.100.20      -
eni       eni-0a1b2c3d4e5f60718      -                        eu-west-1      10.20.1.15         -
snapshot  snap-0old0000000000001     -                        eu-west-1      100GiB             334
2027-01-01T08:00:00Z [INFO ] aws-orphans: 4 orphaned resource(s) found across 1 region(s)
```

```console
$ aws-orphans -r eu-west-1 --dry-run
...
2027-01-01T08:00:00Z [WARN ] aws-orphans: cleanup target: account 111122223333, 3 resource(s); snapshots are never deleted
DRY-RUN: aws ec2 delete-volume --region eu-west-1 --volume-id vol-0aaa1111bbbb2222c
DRY-RUN: aws ec2 release-address --region eu-west-1 --allocation-id eipalloc-0123456789abcdef0
DRY-RUN: aws ec2 delete-network-interface --region eu-west-1 --network-interface-id eni-0a1b2c3d4e5f60718
```

Scheduled check that fails the job when waste appears:

```bash
aws-orphans --all-regions --fail-on-findings --format json > orphans.json
```

## Exit codes

`0` success · `1` orphans found with `--fail-on-findings` · `2` at least one deletion failed · `64` usage · `69` missing dependency · `77` confirmation declined.
