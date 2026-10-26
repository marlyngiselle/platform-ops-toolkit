# aws-inventory

Export the resources of an AWS account to CSV, with the service, resource type and id parsed out of each ARN, selected tags as columns, and all tags flattened.

It uses the Resource Groups Tagging API, which covers most services in one paginated call per region instead of one call per service.

## Prerequisites

- AWS CLI v2 (`aws`) with valid credentials, and `jq`

## Permissions

`tag:GetResources`, `ec2:DescribeRegions` (only for `--all-regions`) and `sts:GetCallerIdentity`. The AWS managed policy `ReadOnlyAccess` covers them; a three-action custom policy is enough.

## Usage

```text
aws-inventory [-r REGION]... [--all-regions] [-p PROFILE] [-t TAG]... [-o FILE]
```

| Option | Default | Notes |
| --- | --- | --- |
| `-r`, `--region` | `AWS_REGION`, then the profile's region | Repeatable |
| `--all-regions` | off | Every region enabled for the account |
| `-p`, `--profile` | `AWS_PROFILE` | |
| `-t`, `--tag` | `owner`, `environment` | Case-insensitive |

Global resources (S3 buckets) are reported once with region `global`, even when several regions return them.

> [!NOTE]
> The Tagging API returns resources that are tagged, or were tagged at some point. A resource that never had a tag does not appear. Combine with service-specific listings when you need a complete count; the gap is itself a tagging finding.

## Example

```console
$ aws-inventory -r eu-west-1
2027-01-01T08:00:00Z [INFO ] aws-inventory: scanning account 111122223333 in eu-west-1
account_id,region,service,resource_type,resource_id,tag_owner,tag_environment,tags,arn
"111122223333","eu-west-1","ec2","instance","i-0abc1234def567890","team-web","dev","Owner=team-web;environment=dev","arn:aws:ec2:eu-west-1:111122223333:instance/i-0abc1234def567890"
"111122223333","eu-west-1","lambda","function","thumbnail-resizer","","","cost-center=cc-2002","arn:aws:lambda:eu-west-1:111122223333:function:thumbnail-resizer"
"","global","s3","","example-artifacts-bucket","team-platform","","owner=team-platform","arn:aws:s3:::example-artifacts-bucket"
```

## Exit codes

`0` written · `64` usage · `69` `aws`/`jq` missing or no valid credentials.
