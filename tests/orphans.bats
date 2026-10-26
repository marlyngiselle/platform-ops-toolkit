#!/usr/bin/env bats
# az-orphans and aws-orphans. Clock frozen at 2027-01-01T00:00:00Z.

load test_helper

setup() {
  common_setup
  stub az \
    'case "$args" in' \
    '  disk\ list*) cat "$FIXTURES/az/disks.json" ;;' \
    '  network\ public-ip\ list*) cat "$FIXTURES/az/public-ips.json" ;;' \
    '  network\ nic\ list*) cat "$FIXTURES/az/nics.json" ;;' \
    '  snapshot\ list*) cat "$FIXTURES/az/snapshots.json" ;;' \
    '  account\ show*) printf "sub-sandbox-01\n00000000-0000-0000-0000-000000000001\n" ;;' \
    '  *delete*) [[ -n "${FAIL_DELETE:-}" ]] && exit 1; exit 0 ;;' \
    'esac'
  stub aws \
    'case "$args" in' \
    '  *describe-volumes*) cat "$FIXTURES/aws/volumes.json" ;;' \
    '  *describe-addresses*) cat "$FIXTURES/aws/addresses.json" ;;' \
    '  *describe-network-interfaces*) cat "$FIXTURES/aws/enis.json" ;;' \
    '  *describe-snapshots*) cat "$FIXTURES/aws/snapshots.json" ;;' \
    '  *"sts get-caller-identity"*) echo "111122223333" ;;' \
    '  *"configure get region"*) echo "eu-west-1" ;;' \
    'esac'
}

# ---------------------------------------------------------------- az-orphans

@test "az-orphans reports each orphan kind" {
  run --separate-stderr "$BIN/az-orphans"
  [ "$status" -eq 0 ]
  [[ "$output" == *"disk"*"disk-old-vm-os"*"128GB Premium_LRS"*"213"* ]]
  [[ "$output" == *"public-ip"*"pip-old-lb"* ]]
  [[ "$output" == *"nic"*"nic-old-vm"*"10.10.1.4"* ]]
  [[ "$output" == *"snapshot"*"snap-2026-03"*"306"* ]]
}

@test "az-orphans ignores attached, in-use, kept and recent resources" {
  run --separate-stderr "$BIN/az-orphans"
  [[ "$output" != *"disk-in-use"* ]]
  [[ "$output" != *"disk-golden-image"* ]]
  [[ "$output" != *"pip-in-use"* ]]
  [[ "$output" != *"nic-pe"* ]]
  [[ "$output" != *"snap-recent"* ]]
}

@test "az-orphans --keep-tag changes which resources are protected" {
  run --separate-stderr "$BIN/az-orphans" --keep-tag retain=yes --format json
  [ "$(jq '[.[] | select(.name == "disk-golden-image")] | length' <<<"$output")" -eq 1 ]
}

@test "az-orphans --format csv has a header and one row per orphan" {
  run --separate-stderr "$BIN/az-orphans" --format csv
  [ "${lines[0]}" = "kind,name,resource_group,location,detail,age_days,id" ]
  [ "${#lines[@]}" -eq 5 ]
}

@test "az-orphans --fail-on-findings exits 1" {
  run --separate-stderr "$BIN/az-orphans" --fail-on-findings
  [ "$status" -eq 1 ]
}

@test "az-orphans --dry-run prints delete commands and deletes nothing" {
  run --separate-stderr "$BIN/az-orphans" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN: az disk delete --ids /subscriptions/"*"/disks/disk-old-vm-os --yes"* ]]
  [[ "$output" == *"DRY-RUN: az network public-ip delete"* ]]
  [[ "$output" == *"DRY-RUN: az network nic delete"* ]]
  [[ "$output" != *"snapshot delete"* ]]
  refute_called "delete"
}

@test "az-orphans --delete without a terminal is refused" {
  run "$BIN/az-orphans" --delete </dev/null
  [ "$status" -eq 77 ]
  refute_called "delete"
}

@test "az-orphans --delete --yes deletes disks, IPs and NICs but never snapshots" {
  run "$BIN/az-orphans" --delete --yes
  [ "$status" -eq 0 ]
  assert_called "^az disk delete --ids"
  assert_called "^az network public-ip delete --ids"
  assert_called "^az network nic delete --ids"
  refute_called "snapshot delete"
}

@test "az-orphans reports failed deletions with exit 2" {
  export FAIL_DELETE=1
  run "$BIN/az-orphans" --delete --yes
  [ "$status" -eq 2 ]
}

@test "az-orphans rejects an invalid format" {
  run "$BIN/az-orphans" --format yaml
  [ "$status" -eq 64 ]
}

# --------------------------------------------------------------- aws-orphans

@test "aws-orphans reports volumes, EIPs, ENIs and old snapshots" {
  run --separate-stderr "$BIN/aws-orphans"
  [ "$status" -eq 0 ]
  [[ "$output" == *"volume"*"vol-0aaa1111bbbb2222c"*"old-build-agent"* ]]
  [[ "$output" == *"eip"*"eipalloc-0123456789abcdef0"*"198.51.100.20"* ]]
  [[ "$output" == *"eni"*"eni-0a1b2c3d4e5f60718"* ]]
  [[ "$output" == *"snapshot"*"snap-0old0000000000001"* ]]
}

@test "aws-orphans skips associated EIPs, kept volumes and recent snapshots" {
  run --separate-stderr "$BIN/aws-orphans"
  [[ "$output" != *"eipalloc-0fedcba9876543210"* ]]
  [[ "$output" != *"vol-0keep1111bbbb222d"* ]]
  [[ "$output" != *"snap-0new0000000000002"* ]]
}

@test "aws-orphans --dry-run prints region-scoped commands only" {
  run --separate-stderr "$BIN/aws-orphans" -r eu-west-1 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN: aws ec2 delete-volume --region eu-west-1 --volume-id vol-0aaa1111bbbb2222c"* ]]
  [[ "$output" == *"DRY-RUN: aws ec2 release-address --region eu-west-1 --allocation-id eipalloc-0123456789abcdef0"* ]]
  [[ "$output" != *"delete-snapshot"* ]]
  refute_called "delete-volume"
}

@test "aws-orphans --delete --yes calls the delete APIs" {
  run "$BIN/aws-orphans" -r eu-west-1 --delete --yes
  [ "$status" -eq 0 ]
  assert_called "ec2 delete-volume --region eu-west-1 --volume-id vol-0aaa1111bbbb2222c"
  assert_called "ec2 delete-network-interface --region eu-west-1"
}

@test "aws-orphans json output is valid" {
  run --separate-stderr "$BIN/aws-orphans" --format json
  [ "$(jq length <<<"$output")" -eq 4 ]
}
