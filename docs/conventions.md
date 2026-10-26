# Conventions

Every tool in this repository follows the same contract, so learning one means knowing all of them.

## Command line

| Flag | Meaning | Available on |
| --- | --- | --- |
| `-h`, `--help` | Usage, options, exit codes, permissions and examples | all |
| `--version` | `<tool> <semver>` | all |
| `-v`, `--verbose` | Debug logging (commands executed, decisions taken) | all |
| `-q`, `--quiet` | Warnings and errors only | all |
| `--no-color` | Plain log output (also honoured: `NO_COLOR=1`) | all |
| `-n`, `--dry-run` | Print the mutating commands, run nothing | tools that change things |
| `-y`, `--yes` | Skip the interactive confirmation | tools that change things |
| `-f`, `--format` | `table`, `csv` or `json`, depending on the tool | report tools |
| `-o`, `--output` | Write to a file; `-` means stdout | report tools |

## Exit codes

Exit codes follow the Nagios plugin convention for checks, plus `sysexits.h` values for invocation problems. A scheduler, a CI job or a monitoring agent can act on them without parsing output.

| Code | Name | Meaning |
| --- | --- | --- |
| `0` | OK | Success, nothing to report |
| `1` | WARNING | Findings within the warning threshold, or findings with `--fail-on-findings` |
| `2` | CRITICAL | Critical or expired item, or a mutating operation failed |
| `3` | UNKNOWN | The check could not be completed (unreachable endpoint, unreadable vault) |
| `64` | USAGE | Bad flag, missing or invalid argument |
| `69` | UNAVAILABLE | A required CLI is missing, or there is no signed-in session |
| `77` | REFUSED | Context assertion failed, protected context, or confirmation declined |

When several items are checked, the worst result wins. `UNKNOWN` never hides a `CRITICAL`.

## Logging and output streams

- Data goes to **stdout**: tables, CSV, JSON, Markdown, dry-run plans. It can always be piped.
- Logs go to **stderr**, one line each, in UTC:

  ```text
  2027-01-01T08:00:00Z [WARN ] cert-expiry: down.example.com:443: could not retrieve certificate
  ```

- `LOG_LEVEL=debug|info|warn|error` sets the level from the environment.
- Colours are only used when stderr is a terminal and `NO_COLOR` is unset.

## Safety model

1. **Read-only by default.** Every tool reports first. Changing anything needs an explicit flag (`--delete`, `--upgrade`, or a command after `context-guard --`).
2. **Dry-run is a first-class mode.** `--dry-run` prints the exact commands, shell-quoted, prefixed with `DRY-RUN:`. The plan can be reviewed, saved, or attached to a change request.
3. **Confirmation needs a human or an explicit opt-in.** Without a terminal, a mutating tool refuses unless `--yes` is given. Automation has to say so.
4. **Protected contexts need the name typed back.** `context-guard --protect '*prod*'` turns "y/N" into "type `aks-prod-weu` to continue".
5. **Opt-out tag.** Cleanup tools skip resources tagged `keep=true` (configurable with `--keep-tag`).
6. **Snapshots are never deleted.** They are the last copy of something. Orphan tools report them and leave the decision to a person.
7. **No secrets, ever.** `kv-secret-expiry` reads metadata only. No tool prints tokens, keys or secret values.

## Idempotency

- Report tools have no side effects and can run on any schedule.
- Cleanup tools act on what they find at run time. Running them twice is safe: the second run finds nothing left to delete.
- `aks-node-image-check --upgrade` only targets pools that are behind, so re-running it after an upgrade does nothing.
- `Test-AzTagCompliance -DefaultValue` merges missing tags only. Existing tags are never overwritten.

## Least privilege

Each tool page lists the minimum role it needs. Reporting always works with read roles (`Reader`, `Key Vault Reader`, `ec2:Describe*`). Write roles are only needed for the explicit remediation flags.

## Portability

- Bash 3.2+ (macOS default) and Bash 5 (Linux). No associative arrays, no `mapfile`.
- GNU and BSD `date` are both supported through `to_epoch` in `lib/common.sh`.
- Dependencies are checked at start-up with `require_cmd`; a missing one exits `69` with its name.

## Code layout

```text
bin/<tool>           entry points, one file per tool
lib/common.sh        logging, run_cmd (dry-run aware), confirm, dates, CSV helpers
tests/<tool>.bats    bats suites; every cloud CLI is a stub on PATH
tests/fixtures/      synthetic API responses (documentation IP ranges, zero GUIDs)
powershell/          PlatformOps module, Pester tests, analyzer settings
```

Each tool resolves its own location through symlinks, so `make install` can link it into any `bin` directory and it still finds `lib/common.sh`.
