#Requires -Version 7.2
<#
.SYNOPSIS
    Lint and test the PlatformOps PowerShell module.

.DESCRIPTION
    Runs PSScriptAnalyzer over the module and Pester over powershell/tests.
    Installs the pinned versions of both modules for the current user when
    they are missing. Exits non-zero on any analyzer finding or failed test.

.PARAMETER Task
    Lint, Test or All (default).

.EXAMPLE
    pwsh -NoProfile -File powershell/Invoke-Checks.ps1

.EXAMPLE
    pwsh -NoProfile -File powershell/Invoke-Checks.ps1 -Task Test
#>
[CmdletBinding()]
param(
    [ValidateSet('Lint', 'Test', 'All')]
    [string] $Task = 'All'
)

$ErrorActionPreference = 'Stop'

$requirements = @{
    PSScriptAnalyzer = '1.23.0'
    Pester           = '5.6.1'
}

foreach ($name in $requirements.Keys) {
    $version = $requirements[$name]
    if (-not (Get-Module -ListAvailable -Name $name | Where-Object { $_.Version -eq [version] $version })) {
        Write-Host "Installing $name $version for the current user"
        Install-Module -Name $name -RequiredVersion $version -Scope CurrentUser -Force -SkipPublisherCheck
    }
    Import-Module -Name $name -RequiredVersion $version -Force
}

$root = $PSScriptRoot
$failed = $false

if ($Task -in 'Lint', 'All') {
    $settings = Join-Path $root 'PSScriptAnalyzerSettings.psd1'
    $findings = @(Invoke-ScriptAnalyzer -Path (Join-Path $root 'PlatformOps') -Recurse -Settings $settings)
    if ($findings.Count -gt 0) {
        $findings | Format-Table -AutoSize RuleName, Severity, ScriptName, Line, Message | Out-String | Write-Host
        $failed = $true
    }
    else {
        Write-Host 'PSScriptAnalyzer: no findings'
    }
}

if ($Task -in 'Test', 'All') {
    $config = New-PesterConfiguration
    $config.Run.Path = Join-Path $root 'tests'
    $config.Run.PassThru = $true
    $config.Output.Verbosity = 'Detailed'
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputPath = Join-Path $root 'testResults.xml'
    $result = Invoke-Pester -Configuration $config
    if ($result.FailedCount -gt 0) {
        $failed = $true
    }
}

if ($failed) {
    exit 1
}
