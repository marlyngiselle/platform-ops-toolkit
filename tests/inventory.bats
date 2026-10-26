#!/usr/bin/env bats
# az-inventory and aws-inventory.

load test_helper

setup() {
  common_setup
  stub az \
    'case "$args" in' \
    '  "account show --query id -o tsv") echo "00000000-0000-0000-0000-000000000001" ;;' \
    '  account\ list*) printf "00000000-0000-0000-0000-000000000001\n00000000-0000-0000-0000-000000000002\n" ;;' \
    '  resource\ list*) cat "$FIXTURES/az/resources.json" ;;' \
    'esac'
  stub aws \
    'case "$args" in' \
    '  *"sts get-caller-identity"*) echo "111122223333" ;;' \
    '  *"configure get region"*) echo "eu-west-1" ;;' \
    '  *"describe-regions"*) printf "eu-west-1\teu-central-1\n" ;;' \
    '  *"resourcegroupstaggingapi get-resources"*) cat "$FIXTURES/aws/tagged-resources.json" ;;' \
    'esac'
}

@test "az-inventory writes a header with default tag columns" {
  run --separate-stderr "$BIN/az-inventory"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "subscription_id,resource_group,name,type,location,tag_owner,tag_environment,tags" ]
}

@test "az-inventory matches tag keys case-insensitively and handles null tags" {
  run --separate-stderr "$BIN/az-inventory"
  [[ "$output" == *'"app-web-dev-01","Microsoft.Web/sites","westeurope","team-web","dev"'* ]]
  [[ "$output" == *'"pip-untagged","Microsoft.Network/publicIPAddresses","northeurope","","",""'* ]]
}

@test "az-inventory quotes tag values that contain commas" {
  run --separate-stderr "$BIN/az-inventory" -t cost-center
  [ "${lines[0]}" = "subscription_id,resource_group,name,type,location,tag_cost-center,tags" ]
  [[ "$output" == *'"cc-1001, shared"'* ]]
}

@test "az-inventory --all-subscriptions queries each enabled subscription" {
  run --separate-stderr "$BIN/az-inventory" --all-subscriptions
  [ "$status" -eq 0 ]
  assert_called "resource list --subscription 00000000-0000-0000-0000-000000000001"
  assert_called "resource list --subscription 00000000-0000-0000-0000-000000000002"
}

@test "az-inventory rejects --all-subscriptions with --subscription" {
  run "$BIN/az-inventory" --all-subscriptions -s sub-a
  [ "$status" -eq 64 ]
}

@test "az-inventory writes to a file" {
  run "$BIN/az-inventory" -g rg-web-dev -o "${BATS_TEST_TMPDIR}/inv.csv"
  [ "$status" -eq 0 ]
  [ "$(wc -l <"${BATS_TEST_TMPDIR}/inv.csv" | tr -d ' ')" -eq 4 ]
  assert_called "--resource-group rg-web-dev"
}

@test "aws-inventory parses service, type and id from ARNs" {
  run --separate-stderr "$BIN/aws-inventory"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "account_id,region,service,resource_type,resource_id,tag_owner,tag_environment,tags,arn" ]
  [[ "$output" == *'"111122223333","eu-west-1","ec2","instance","i-0abc1234def567890","team-web","dev"'* ]]
  [[ "$output" == *'"","global","s3","","example-artifacts-bucket","team-platform"'* ]]
  [[ "$output" == *'"lambda","function","thumbnail-resizer"'* ]]
}

@test "aws-inventory uses the configured region by default" {
  run --separate-stderr "$BIN/aws-inventory"
  assert_called "get-resources --region eu-west-1"
}

@test "aws-inventory --all-regions de-duplicates resources seen in every region" {
  run --separate-stderr "$BIN/aws-inventory" --all-regions
  [ "$status" -eq 0 ]
  assert_called "get-resources --region eu-central-1"
  # header + 3 unique resources
  [ "${#lines[@]}" -eq 4 ]
}

@test "aws-inventory passes --profile to every call" {
  run --separate-stderr "$BIN/aws-inventory" -p lab -r eu-west-1
  assert_called "^aws --profile lab sts get-caller-identity"
  assert_called "^aws --profile lab resourcegroupstaggingapi"
}

@test "aws-inventory fails cleanly without credentials" {
  stub aws 'exit 255'
  run "$BIN/aws-inventory"
  [ "$status" -eq 69 ]
}
