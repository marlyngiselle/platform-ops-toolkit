function Get-ServerHealthSnapshot {
    <#
    .SYNOPSIS
        Capture a point-in-time health snapshot of one or more Windows servers.

    .DESCRIPTION
        Collects uptime, CPU load, memory use, free space per fixed volume,
        automatic services that are not running, the pending reboot state and
        the number of critical/error events in the System and Application logs.

        Each server is evaluated against the thresholds and returned as one
        object with a Status (OK, WARNING or UNREACHABLE) and a list of
        Findings, so the output can be filtered, exported or sent to a ticket.

        Read-only. Remote servers are queried over CIM (WinRM).

    .PARAMETER ComputerName
        Servers to inspect. Defaults to the local machine. Accepts pipeline input.

    .PARAMETER DiskFreePercent
        Flag fixed volumes with less free space than this percentage.

    .PARAMETER MemoryUsedPercent
        Flag servers whose memory use is at or above this percentage.

    .PARAMETER CpuLoadPercent
        Flag servers whose average CPU load is at or above this percentage.

    .PARAMETER EventHours
        How far back to count critical and error events.

    .PARAMETER ExcludeService
        Automatic services that are expected to be stopped (trigger-start or
        delayed services). They are not reported.

    .EXAMPLE
        Get-ServerHealthSnapshot

        Snapshot of the local server with default thresholds.

    .EXAMPLE
        'web-01', 'web-02' | Get-ServerHealthSnapshot -DiskFreePercent 20 |
            Where-Object Status -ne 'OK' | Select-Object ComputerName, Findings

        Only the servers that need attention, with the reasons.

    .EXAMPLE
        Get-ServerHealthSnapshot -ComputerName app-01 | ConvertTo-Json -Depth 4

        JSON output for a ticket or a monitoring pipeline.

    .OUTPUTS
        PlatformOps.ServerHealth

    .NOTES
        Requires Windows and PowerShell 7.2+. Remote use needs WinRM and an
        account allowed to read WMI on the target (local Administrators, or
        Remote Management Users plus WMI namespace read rights).
    #>
    [CmdletBinding()]
    [OutputType('PlatformOps.ServerHealth')]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'CN')]
        [string[]] $ComputerName = @([Environment]::MachineName),

        [ValidateRange(1, 99)]
        [int] $DiskFreePercent = 15,

        [ValidateRange(1, 100)]
        [int] $MemoryUsedPercent = 90,

        [ValidateRange(1, 100)]
        [int] $CpuLoadPercent = 90,

        [ValidateRange(1, 720)]
        [int] $EventHours = 24,

        [string[]] $ExcludeService = @(
            'edgeupdate', 'gupdate', 'MapsBroker', 'RemoteRegistry', 'sppsvc', 'WbioSrvc'
        )
    )

    process {
        foreach ($computer in $ComputerName) {
            $isLocal = $computer -in @('.', 'localhost', [Environment]::MachineName)
            $cim = @{ ErrorAction = 'Stop' }
            if (-not $isLocal) {
                $cim.ComputerName = $computer
            }
            $collectedAt = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')

            try {
                $os = Get-CimInstance -ClassName 'Win32_OperatingSystem' @cim
                $cpu = @(Get-CimInstance -ClassName 'Win32_Processor' @cim)
                $volumes = @(Get-CimInstance -ClassName 'Win32_LogicalDisk' -Filter 'DriveType = 3' @cim)
                $services = @(Get-CimInstance -ClassName 'Win32_Service' -Filter "StartMode = 'Auto' AND State <> 'Running'" @cim)
            }
            catch {
                Write-Warning "${computer}: unreachable ($($_.Exception.Message))"
                [pscustomobject]@{
                    PSTypeName          = 'PlatformOps.ServerHealth'
                    ComputerName        = $computer
                    Status              = 'UNREACHABLE'
                    Findings            = @("unreachable: $($_.Exception.Message)")
                    UptimeDays          = $null
                    LastBootUtc         = $null
                    CpuLoadPercent      = $null
                    MemoryUsedPercent   = $null
                    Disks               = @()
                    StoppedAutoServices = @()
                    PendingReboot       = $null
                    ErrorEventCount     = $null
                    TopEventSources     = @()
                    CollectedAtUtc      = $collectedAt
                }
                continue
            }

            $cpuLoad = [math]::Round(($cpu | Measure-Object -Property LoadPercentage -Average).Average, 1)
            $memoryUsed = $null
            if ($os.TotalVisibleMemorySize -gt 0) {
                $memoryUsed = [math]::Round((1 - ($os.FreePhysicalMemory / $os.TotalVisibleMemorySize)) * 100, 1)
            }
            $uptimeDays = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 1)

            $disks = foreach ($volume in $volumes) {
                $freePercent = $null
                if ($volume.Size -gt 0) {
                    $freePercent = [math]::Round($volume.FreeSpace / $volume.Size * 100, 1)
                }
                [pscustomobject]@{
                    Drive       = $volume.DeviceID
                    SizeGB      = [math]::Round($volume.Size / 1GB, 1)
                    FreeGB      = [math]::Round($volume.FreeSpace / 1GB, 1)
                    FreePercent = $freePercent
                }
            }
            $disks = @($disks)

            $stopped = @($services |
                    Where-Object { $_.Name -notin $ExcludeService } |
                    ForEach-Object { $_.Name } |
                    Sort-Object)

            $pendingReboot = $null
            try {
                $rebootArgs = @{}
                if (-not $isLocal) {
                    $rebootArgs.ComputerName = $computer
                }
                $pendingReboot = Test-PendingReboot @rebootArgs
            }
            catch {
                Write-Verbose "${computer}: pending reboot state unavailable ($($_.Exception.Message))"
            }

            $errorEvents = $null
            $topSources = @()
            try {
                $eventArgs = @{
                    FilterHashtable = @{
                        LogName   = @('System', 'Application')
                        Level     = @(1, 2)
                        StartTime = (Get-Date).AddHours(-$EventHours)
                    }
                    ErrorAction     = 'Stop'
                }
                if (-not $isLocal) {
                    $eventArgs.ComputerName = $computer
                }
                $logEntries = @(Get-WinEvent @eventArgs)
                $errorEvents = $logEntries.Count
                $topSources = @($logEntries |
                        Group-Object -Property ProviderName |
                        Sort-Object -Property Count -Descending |
                        Select-Object -First 5 |
                        ForEach-Object { "$($_.Name) ($($_.Count))" })
            }
            catch {
                if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') {
                    $errorEvents = 0
                }
                else {
                    Write-Verbose "${computer}: event log unavailable ($($_.Exception.Message))"
                }
            }

            $evaluation = @{
                CpuLoadPercent    = $cpuLoad
                MemoryUsedPercent = $memoryUsed
                Disk              = $disks
                StoppedService    = $stopped
                PendingReboot     = $pendingReboot
                ErrorEventCount   = $errorEvents
                CpuThreshold      = $CpuLoadPercent
                MemoryThreshold   = $MemoryUsedPercent
                DiskFreeThreshold = $DiskFreePercent
            }
            $findings = @(Get-HealthFinding @evaluation)

            [pscustomobject]@{
                PSTypeName          = 'PlatformOps.ServerHealth'
                ComputerName        = $computer
                Status              = if ($findings.Count -gt 0) { 'WARNING' } else { 'OK' }
                Findings            = $findings
                UptimeDays          = $uptimeDays
                LastBootUtc         = $os.LastBootUpTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                CpuLoadPercent      = $cpuLoad
                MemoryUsedPercent   = $memoryUsed
                Disks               = $disks
                StoppedAutoServices = $stopped
                PendingReboot       = $pendingReboot
                ErrorEventCount     = $errorEvents
                TopEventSources     = $topSources
                CollectedAtUtc      = $collectedAt
            }
        }
    }
}
