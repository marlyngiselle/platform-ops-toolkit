# az-inventory

Export every Azure resource the signed-in identity can see to CSV: subscription, resource group, name, type, location, the tags you care about as their own columns, and all tags flattened in a last column.

Useful for cost reviews, ownership clean-up, audit evidence, and simply answering "what do we have and who owns it?".

## Prerequisites

- Azure CLI (`az`), signed in (`az login`), and `jq`

## Permissions

`Reader` on the subscriptions or resource group in scope. Nothing else.

## Usage

```text
az-inventory [-s SUB]... [--all-subscriptions] [-g RG] [-t TAG]... [-o FILE]
```

| Option | Default | Notes |
| --- | --- | --- |
| `-s`, `--subscription` | current | Repeatable |
| `--all-subscriptions` | off | Every subscription in state `Enabled` |
| `-g`, `--resource-group` | all | |
| `-t`, `--tag` | `owner`, `environment` | Repeatable; matched case-insensitively (`Owner` = `owner`) |
| `-o`, `--output` | stdout | |

Rows are sorted by resource group, type and name, so two exports diff cleanly.

## Example

```console
$ az-inventory -o inventory.csv
2027-01-01T08:00:00Z [INFO ] az-inventory: listing resources in subscription 00000000-0000-0000-0000-000000000001
2027-01-01T08:00:00Z [INFO ] az-inventory: inventory written to inventory.csv
$ cat inventory.csv
subscription_id,resource_group,name,type,location,tag_owner,tag_environment,tags
"00000000-0000-0000-0000-000000000001","rg-data-dev","pip-untagged","Microsoft.Network/publicIPAddresses","northeurope","","",""
"00000000-0000-0000-0000-000000000001","rg-data-dev","stdatadev001","Microsoft.Storage/storageAccounts","westeurope","team-data","","owner=team-data;cost-center=cc-1001, shared"
"00000000-0000-0000-0000-000000000001","rg-web-dev","app-web-dev-01","Microsoft.Web/sites","westeurope","team-web","dev","Owner=team-web;environment=dev"
```

Resources with no owner, straight from the CSV:

```bash
az-inventory --all-subscriptions | awk -F'","' 'NR > 1 && $6 == ""' | wc -l
```

## Exit codes

`0` written · `64` usage · `69` `az`/`jq` missing or not signed in.
