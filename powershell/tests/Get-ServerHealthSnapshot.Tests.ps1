BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')

    function Set-HealthyServerMock {
        Mock -ModuleName PlatformOps Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' } {
            [pscustomobject]@{
                LastBootUpTime         = (Get-Date).AddDays(-12)
                TotalVisibleMemorySize = 16777216   # 16 GB in KB
                FreePhysicalMemory     = 8388608    # 8 GB in KB
            }
        }
        Mock -ModuleName PlatformOps Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Processor' } {
            [pscustomobject]@{ LoadPercentage = 20 }
            [pscustomobject]@{ LoadPercentage = 30 }
        }
        Mock -ModuleName PlatformOps Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' } {
            [pscustomobject]@{ DeviceID = 'C:'; Size = 100GB; FreeSpace = 40GB }
            [pscustomobject]@{ DeviceID = 'D:'; Size = 200GB; FreeSpace = 150GB }
        }
        Mock -ModuleName PlatformOps Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Service' } {
            [pscustomobject]@{ Name = 'gupdate'; State = 'Stopped' }
        }
        Mock -ModuleName PlatformOps Test-PendingReboot { $false }
        Mock -ModuleName PlatformOps Get-WinEvent { @() }
    }
}

Describe 'Get-ServerHealthSnapshot' {
    BeforeEach {
        Set-HealthyServerMock
    }

    It 'reports OK for a healthy server' {
        $result = Get-ServerHealthSnapshot
        $result.Status | Should -Be 'OK'
        $result.Findings | Should -HaveCount 0
        $result.CpuLoadPercent | Should -Be 25
        $result.MemoryUsedPercent | Should -Be 50
        $result.UptimeDays | Should -BeGreaterOrEqual 11.9
        $result.PSObject.TypeNames | Should -Contain 'PlatformOps.ServerHealth'
    }

    It 'returns one entry per fixed volume with free space percentage' {
        $result = Get-ServerHealthSnapshot
        $result.Disks | Should -HaveCount 2
        ($result.Disks | Where-Object Drive -eq 'C:').FreePercent | Should -Be 40
    }

    It 'ignores excluded automatic services' {
        (Get-ServerHealthSnapshot).StoppedAutoServices | Should -HaveCount 0
    }

    It 'flags a volume below the free space threshold' {
        Mock -ModuleName PlatformOps Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' } {
            [pscustomobject]@{ DeviceID = 'C:'; Size = 100GB; FreeSpace = 5GB }
        }
        $result = Get-ServerHealthSnapshot
        $result.Status | Should -Be 'WARNING'
        $result.Findings | Should -Contain 'disk C: has 5% free (5 GB)'
    }

    It 'honours a custom disk threshold' {
        (Get-ServerHealthSnapshot -DiskFreePercent 45).Findings | Should -Contain 'disk C: has 40% free (40 GB)'
    }

    It 'flags stopped automatic services that are not excluded' {
        Mock -ModuleName PlatformOps Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Service' } {
            [pscustomobject]@{ Name = 'W3SVC'; State = 'Stopped' }
            [pscustomobject]@{ Name = 'gupdate'; State = 'Stopped' }
        }
        $result = Get-ServerHealthSnapshot
        $result.StoppedAutoServices -join ',' | Should -Be 'W3SVC'
        $result.Findings | Should -Contain 'automatic services not running: W3SVC'
    }

    It 'flags a pending reboot' {
        Mock -ModuleName PlatformOps Test-PendingReboot { $true }
        $result = Get-ServerHealthSnapshot
        $result.PendingReboot | Should -BeTrue
        $result.Findings | Should -Contain 'reboot pending'
    }

    It 'counts error events and lists the noisiest sources' {
        Mock -ModuleName PlatformOps Get-WinEvent {
            [pscustomobject]@{ ProviderName = 'Service Control Manager' }
            [pscustomobject]@{ ProviderName = 'Service Control Manager' }
            [pscustomobject]@{ ProviderName = 'Application Error' }
        }
        $result = Get-ServerHealthSnapshot
        $result.ErrorEventCount | Should -Be 3
        $result.TopEventSources[0] | Should -Be 'Service Control Manager (2)'
    }

    It 'keeps going when the event log cannot be read' {
        Mock -ModuleName PlatformOps Get-WinEvent { throw 'access denied' }
        $result = Get-ServerHealthSnapshot
        $result.ErrorEventCount | Should -BeNullOrEmpty
        $result.Status | Should -Be 'OK'
    }

    It 'returns UNREACHABLE instead of throwing when CIM fails' {
        Mock -ModuleName PlatformOps Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' } {
            throw 'The WinRM client cannot process the request'
        }
        $result = Get-ServerHealthSnapshot -ComputerName 'srv-offline-01' -WarningAction SilentlyContinue
        $result.Status | Should -Be 'UNREACHABLE'
        $result.ComputerName | Should -Be 'srv-offline-01'
    }

    It 'queries remote servers by name and accepts pipeline input' {
        $results = @('web-01', 'web-02' | Get-ServerHealthSnapshot)
        $results | Should -HaveCount 2
        Should -Invoke -ModuleName PlatformOps Get-CimInstance -ParameterFilter {
            $ComputerName -eq 'web-02' -and $ClassName -eq 'Win32_OperatingSystem'
        } -Times 1 -Exactly
    }
}

Describe 'Get-HealthFinding' {
    It 'returns nothing when every value is under its threshold' {
        InModuleScope PlatformOps {
            @(Get-HealthFinding -CpuLoadPercent 10 -MemoryUsedPercent 40 -ErrorEventCount 0) | Should -HaveCount 0
        }
    }

    It 'reports CPU and memory at or above the threshold' {
        InModuleScope PlatformOps {
            $findings = @(Get-HealthFinding -CpuLoadPercent 95 -MemoryUsedPercent 90 -CpuThreshold 90 -MemoryThreshold 90)
            $findings | Should -HaveCount 2
        }
    }

    It 'treats unknown values as no finding' {
        InModuleScope PlatformOps {
            @(Get-HealthFinding -CpuLoadPercent $null -PendingReboot $null) | Should -HaveCount 0
        }
    }
}
