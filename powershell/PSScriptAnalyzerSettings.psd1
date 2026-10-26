@{
    Severity            = @('Error', 'Warning')
    IncludeDefaultRules = $true
    Rules               = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('7.2')
        }
    }
}
