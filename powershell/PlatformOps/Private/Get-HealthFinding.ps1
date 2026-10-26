function Get-HealthFinding {
    <#
    .SYNOPSIS
        Evaluate collected server metrics against thresholds.
    .DESCRIPTION
        Pure function: no I/O, so it can be unit tested on any platform.
        Returns one human-readable string per breached threshold.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Nullable[double]] $CpuLoadPercent,
        [Nullable[double]] $MemoryUsedPercent,
        [object[]] $Disk = @(),
        [string[]] $StoppedService = @(),
        [Nullable[bool]] $PendingReboot,
        [Nullable[int]] $ErrorEventCount,
        [int] $CpuThreshold = 90,
        [int] $MemoryThreshold = 90,
        [int] $DiskFreeThreshold = 15
    )

    if ($null -ne $CpuLoadPercent -and $CpuLoadPercent -ge $CpuThreshold) {
        "CPU load $CpuLoadPercent% (threshold $CpuThreshold%)"
    }
    if ($null -ne $MemoryUsedPercent -and $MemoryUsedPercent -ge $MemoryThreshold) {
        "memory used $MemoryUsedPercent% (threshold $MemoryThreshold%)"
    }
    foreach ($volume in $Disk) {
        if ($null -ne $volume.FreePercent -and $volume.FreePercent -lt $DiskFreeThreshold) {
            "disk $($volume.Drive) has $($volume.FreePercent)% free ($($volume.FreeGB) GB)"
        }
    }
    if ($StoppedService.Count -gt 0) {
        "automatic services not running: $($StoppedService -join ', ')"
    }
    if ($PendingReboot -eq $true) {
        'reboot pending'
    }
    if ($null -ne $ErrorEventCount -and $ErrorEventCount -gt 0) {
        "$ErrorEventCount critical/error events in the window"
    }
}
