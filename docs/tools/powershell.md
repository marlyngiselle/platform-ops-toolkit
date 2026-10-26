# PlatformOps PowerShell module

Three PowerShell 7 functions for the Windows and Azure governance side of operations. Each returns objects (not text), so results can be filtered, exported to CSV/JSON or fed into another command.

```powershell
Import-Module ./powershell/PlatformOps/PlatformOps.psd1
Get-Help Get-ServerHealthSnapshot -Full
```

| Function | What it does | Changes anything? |
| --- | --- | --- |
| `Get-ServerHealthSnapshot` | Uptime, CPU, memory, free disk per volume, stopped automatic services, pending reboot, error events, with a status per server | No |
| `Get-IisSiteReport` | Sites, app pool state and identity, bindings, HTTPS certificate expiry | No |
| `Test-AzTagCompliance` | Required tags and allowed values per Azure resource; optional merge of default tags | Only with `-DefaultValue`, honours `-WhatIf`/`-Confirm` |

## Get-ServerHealthSnapshot

Requirements: Windows, PowerShell 7.2+. Remote servers over WinRM with an account allowed to read WMI (local Administrators, or Remote Management Users plus WMI namespace rights).

```powershell
PS> 'web-01', 'web-02', 'srv-offline-01' | Get-ServerHealthSnapshot -DiskFreePercent 20 |
>>     Format-Table ComputerName, Status, UptimeDays, MemoryUsedPercent, Findings -Wrap

ComputerName   Status      UptimeDays MemoryUsedPercent Findings
------------   ------      ---------- ----------------- --------
web-01         OK                12.4              48.2 {}
web-02         WARNING           87.1              61.0 {disk D: has 7.5% free (15 GB), reboot pending}
srv-offline-01 UNREACHABLE                              {unreachable: WinRM cannot complete the operation}
```

Thresholds: `-DiskFreePercent` (15), `-MemoryUsedPercent` (90), `-CpuLoadPercent` (90), `-EventHours` (24). `-ExcludeService` lists automatic services that are expected to be stopped.

## Get-IisSiteReport

Requirements: Windows Server with IIS and the `IISAdministration` module. Run elevated.

```powershell
PS> Get-IisSiteReport -CertificateWarningDays 45 | Format-Table Name, State, AppPool, AppPoolState, CertificateExpiresInDays, Status

Name             State   AppPool        AppPoolState CertificateExpiresInDays Status
----             -----   -------        ------------ ------------------------ ------
Default Web Site Started DefaultAppPool Started                               OK
shop             Started ShopPool       Started                            21 WARNING
legacy-intranet  Started LegacyPool     Stopped                               WARNING
```

Findings raised: site or pool not started, pool missing, pool running as `LocalSystem`, bound certificate missing from the store, expired, or inside the warning window.

## Test-AzTagCompliance

Requirements: `Az.Resources`, a signed-in context (`Connect-AzAccount`).
Permissions: `Reader` to report; `Tag Contributor` for `-DefaultValue` (it can write tags and nothing else).

```powershell
PS> Test-AzTagCompliance -RequiredTag owner, environment -AllowedValue @{ environment = 'dev', 'test', 'prod' } |
>>     Format-Table Name, ResourceGroupName, MissingTags, InvalidTags

Name          ResourceGroupName MissingTags          InvalidTags
----          ----------------- -----------          -----------
stnotags      rg-lab            {owner, environment} {}
stbadenv      rg-lab            {}                   {environment=staging}
```

Preview, then apply, a default owner on the gaps:

```powershell
PS> Get-AzResource -ResourceGroupName rg-lab | Test-AzTagCompliance -RequiredTag owner -DefaultValue @{ owner = 'unassigned' } -WhatIf
What if: Performing the operation "Merge tags owner=unassigned" on target "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-lab/providers/Microsoft.Storage/storageAccounts/stnotags".
```

Tag names are compared case-insensitively, as Azure does. Existing tags are never overwritten: the merge only adds what is missing.

## Tests

```bash
make lint-ps test-ps        # or: pwsh -File powershell/Invoke-Checks.ps1
```

Pester mocks every Windows and Az command, so the suite runs on Linux in CI. `tests/TestHelpers.ps1` registers inert stand-ins for commands that do not exist on the runner, because Pester can only mock commands it can find.
