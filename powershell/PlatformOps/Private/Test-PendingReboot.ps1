function Test-PendingReboot {
    <#
    .SYNOPSIS
        Return $true when Windows reports a pending reboot.
    .DESCRIPTION
        Reads the three usual markers through the StdRegProv CIM class, so the
        same code works locally and over WinRM:
          - Component Based Servicing\RebootPending
          - WindowsUpdate\Auto Update\RebootRequired
          - Session Manager\PendingFileRenameOperations
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string] $ComputerName
    )

    $hklm = [uint32] 2147483650
    $cim = @{
        Namespace   = 'root/default'
        ClassName   = 'StdRegProv'
        ErrorAction = 'Stop'
    }
    if ($ComputerName) {
        $cim.ComputerName = $ComputerName
    }

    $markers = @(
        @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing'; Child = 'RebootPending' }
        @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update'; Child = 'RebootRequired' }
    )
    foreach ($marker in $markers) {
        $result = Invoke-CimMethod @cim -MethodName 'EnumKey' -Arguments @{
            hDefKey     = $hklm
            sSubKeyName = $marker.Path
        }
        if (@($result.sNames) -contains $marker.Child) {
            return $true
        }
    }

    $rename = Invoke-CimMethod @cim -MethodName 'GetMultiStringValue' -Arguments @{
        hDefKey     = $hklm
        sSubKeyName = 'SYSTEM\CurrentControlSet\Control\Session Manager'
        sValueName  = 'PendingFileRenameOperations'
    }
    return (@($rename.sValue | Where-Object { $_ }).Count -gt 0)
}
