# Shared test setup. The functions under test call Windows-only or Az
# commands. Pester can only mock commands that exist, so on Linux/macOS
# runners (and on machines without IIS or Az) we register inert stand-ins
# with the same parameters. On a machine where the real command exists the
# stand-in is skipped and Pester mocks the real one.

function Add-CommandStub {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [scriptblock] $Definition
    )
    if (-not (Get-Command -Name $Name -ErrorAction SilentlyContinue)) {
        Set-Item -Path "function:global:$Name" -Value $Definition
    }
}

Add-CommandStub -Name 'Get-CimInstance' -Definition {
    [CmdletBinding()]
    param([string] $ClassName, [string] $Filter, [string] $ComputerName, [string] $Namespace)
    throw 'Get-CimInstance stand-in: mock me'
}
Add-CommandStub -Name 'Invoke-CimMethod' -Definition {
    [CmdletBinding()]
    param([string] $Namespace, [string] $ClassName, [string] $MethodName,
        [System.Collections.IDictionary] $Arguments, [string] $ComputerName)
    throw 'Invoke-CimMethod stand-in: mock me'
}
Add-CommandStub -Name 'Get-WinEvent' -Definition {
    [CmdletBinding()]
    param([hashtable] $FilterHashtable, [string] $ComputerName, [int] $MaxEvents)
    throw 'Get-WinEvent stand-in: mock me'
}
Add-CommandStub -Name 'Get-IISSite' -Definition {
    [CmdletBinding()]
    param([string] $Name)
    throw 'Get-IISSite stand-in: mock me'
}
Add-CommandStub -Name 'Get-IISAppPool' -Definition {
    [CmdletBinding()]
    param([string] $Name)
    throw 'Get-IISAppPool stand-in: mock me'
}
Add-CommandStub -Name 'Get-AzResource' -Definition {
    [CmdletBinding()]
    param([string] $ResourceGroupName)
    throw 'Get-AzResource stand-in: mock me'
}
Add-CommandStub -Name 'Update-AzTag' -Definition {
    [CmdletBinding()]
    param([string] $ResourceId, [hashtable] $Tag, [string] $Operation)
    throw 'Update-AzTag stand-in: mock me'
}

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../PlatformOps/PlatformOps.psd1'
Import-Module -Name $modulePath -Force
