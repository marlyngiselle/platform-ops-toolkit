BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')

    function New-TestResource {
        param([string] $Name, [hashtable] $Tags)
        [pscustomobject]@{
            Name              = $Name
            ResourceGroupName = 'rg-lab'
            ResourceType      = 'Microsoft.Storage/storageAccounts'
            ResourceId        = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-lab/providers/Microsoft.Storage/storageAccounts/$Name"
            Tags              = $Tags
        }
    }
}

Describe 'Test-AzTagCompliance' {
    BeforeEach {
        Mock -ModuleName PlatformOps Get-AzResource {
            New-TestResource -Name 'stcompliant' -Tags @{ owner = 'team-data'; environment = 'dev' }
            New-TestResource -Name 'stnotags' -Tags $null
            New-TestResource -Name 'stbadenv' -Tags @{ Owner = 'team-web'; environment = 'staging' }
            New-TestResource -Name 'stemptyowner' -Tags @{ owner = ' '; environment = 'prod' }
        }
        Mock -ModuleName PlatformOps Update-AzTag { }
    }

    It 'returns only non-compliant resources by default' {
        $result = @(Test-AzTagCompliance -RequiredTag owner, environment)
        $result.Name | Should -Not -Contain 'stcompliant'
        $result.Name | Should -Contain 'stnotags'
    }

    It 'returns compliant resources with -IncludeCompliant' {
        $result = @(Test-AzTagCompliance -RequiredTag owner -IncludeCompliant)
        ($result | Where-Object Name -eq 'stcompliant').Compliant | Should -BeTrue
    }

    It 'lists every missing tag' {
        $result = Test-AzTagCompliance -RequiredTag owner, environment | Where-Object Name -eq 'stnotags'
        $result.MissingTags -join ',' | Should -Be 'owner,environment'
    }

    It 'matches tag names case-insensitively' {
        $result = @(Test-AzTagCompliance -RequiredTag owner)
        $result.Name | Should -Not -Contain 'stbadenv'
    }

    It 'treats a blank value as missing' {
        $result = Test-AzTagCompliance -RequiredTag owner | Where-Object Name -eq 'stemptyowner'
        $result.MissingTags -join ',' | Should -Be 'owner'
    }

    It 'reports values outside the allowed list' {
        $allowed = @{ environment = 'dev', 'test', 'prod' }
        $result = Test-AzTagCompliance -RequiredTag owner -AllowedValue $allowed | Where-Object Name -eq 'stbadenv'
        $result.InvalidTags -join ',' | Should -Be 'environment=staging'
        $result.Compliant | Should -BeFalse
    }

    It 'passes -ResourceGroupName to Get-AzResource' {
        $null = Test-AzTagCompliance -RequiredTag owner -ResourceGroupName 'rg-lab'
        Should -Invoke -ModuleName PlatformOps Get-AzResource -ParameterFilter { $ResourceGroupName -eq 'rg-lab' } -Times 1 -Exactly
    }

    It 'uses piped resources without querying Azure' {
        $result = @(New-TestResource -Name 'stpiped' -Tags @{} | Test-AzTagCompliance -RequiredTag owner)
        $result.Name -join ',' | Should -Be 'stpiped'
        Should -Invoke -ModuleName PlatformOps Get-AzResource -Times 0 -Exactly
    }

    It 'changes nothing under -WhatIf' {
        $null = Test-AzTagCompliance -RequiredTag owner -DefaultValue @{ owner = 'unassigned' } -WhatIf
        Should -Invoke -ModuleName PlatformOps Update-AzTag -Times 0 -Exactly
    }

    It 'merges defaults for missing tags only and reports them' {
        $result = Test-AzTagCompliance -RequiredTag owner, environment -DefaultValue @{ owner = 'unassigned' } -Confirm:$false |
            Where-Object Name -eq 'stnotags'
        $result.RemediatedTags -join ',' | Should -Be 'owner'
        $result.MissingTags -join ',' | Should -Be 'environment'
        Should -Invoke -ModuleName PlatformOps Update-AzTag -ParameterFilter {
            $Operation -eq 'Merge' -and $Tag['owner'] -eq 'unassigned' -and $ResourceId -like '*/stnotags'
        } -Times 1 -Exactly
        Should -Invoke -ModuleName PlatformOps Update-AzTag -ParameterFilter { $ResourceId -like '*/stcompliant' } -Times 0 -Exactly
    }
}
