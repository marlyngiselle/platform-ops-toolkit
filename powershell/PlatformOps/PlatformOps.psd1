@{
    RootModule        = 'PlatformOps.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '4aa783a2-7775-4042-91a5-cbcac4a8b50b'
    Author            = 'Giselle Da Costa'
    Copyright         = '(c) 2026 Giselle Da Costa. MIT License.'
    Description       = 'Day-to-day operations tooling: Windows server health, IIS site reporting and Azure tag compliance.'
    PowerShellVersion = '7.2'
    FunctionsToExport = @(
        'Get-ServerHealthSnapshot'
        'Get-IisSiteReport'
        'Test-AzTagCompliance'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags = @('Operations', 'Windows', 'IIS', 'Azure', 'Governance')
        }
    }
}
