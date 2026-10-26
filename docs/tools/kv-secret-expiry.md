# kv-secret-expiry

List Azure Key Vault secrets and certificates that are expired or about to expire, across one vault or every vault in a subscription. It reads metadata only: secret values are never requested.

## Prerequisites

- Azure CLI (`az`), signed in, and `jq`
- Network access to the vault data plane (private endpoint or allowed IP when the vault firewall is on)

## Permissions

- RBAC vaults: `Key Vault Reader`. It can list secrets and certificates and read their attributes, and cannot read values.
- Access-policy vaults: `List` on secrets and on certificates.
- `--all-vaults` additionally needs `Reader` on the subscription to enumerate vaults.

## Usage

```text
kv-secret-expiry (-k VAULT... | --all-vaults) [-s SUB] [-w DAYS] [-c DAYS]
                 [--warn-no-expiry] [--no-certificates] [--all] [-f table|json]
```

| Status | Rule |
| --- | --- |
| `EXPIRED` | Expiry date in the past |
| `CRITICAL` | Expires within `--critical` days (default 7) |
| `WARNING` | Expires within `--warning` days (default 30) |
| `NO_EXPIRY` | No expiry date set; counted as a warning with `--warn-no-expiry` |
| `DISABLED` | Disabled item, shown with `--all` |
| `OK` | Shown with `--all` |

Secrets that back a certificate (`managed: true`) are skipped, so a certificate is reported once, as a certificate.

## Example

```console
$ kv-secret-expiry -k kv-app-dev --warn-no-expiry
2027-01-01T08:00:00Z [INFO ] kv-secret-expiry: reading metadata from kv-app-dev
VAULT                    KIND         NAME                                     DAYS_LEFT  EXPIRES                    STATUS
kv-app-dev               secret       old-key                                  -17        2026-12-15T00:00:00+00:00  EXPIRED
kv-app-dev               certificate  tls-web                                  1          2027-01-02T00:00:00+00:00  CRITICAL
kv-app-dev               secret       db-password                              3          2027-01-04T00:00:00+00:00  CRITICAL
kv-app-dev               secret       api-token                                20         2027-01-21T00:00:00+00:00  WARNING
kv-app-dev               secret       no-expiry                                -          -                          NO_EXPIRY
$ echo $?
2
```

JSON for a pipeline or a ticket:

```bash
kv-secret-expiry --all-vaults -w 45 --format json | jq -r '.[] | "\(.vault)/\(.name): \(.status) (\(.daysLeft) days)"'
```

## Exit codes

`0` nothing to report · `1` WARNING · `2` CRITICAL or EXPIRED · `3` a vault could not be read and nothing worse was found · `64` usage · `69` missing dependency.
