BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')

    function New-TestSite {
        param(
            [string] $Name,
            [string] $State = 'Started',
            [string] $Pool = 'DefaultAppPool',
            [object[]] $Bindings = @([pscustomobject]@{ Protocol = 'http'; BindingInformation = '*:80:'; CertificateHash = $null; CertificateStoreName = $null })
        )
        [pscustomobject]@{
            Name         = $Name
            State        = $State
            Bindings     = $Bindings
            Applications = @([pscustomobject]@{ Path = '/'; ApplicationPoolName = $Pool })
        }
    }

    function New-TestPool {
        param([string] $Name, [string] $State = 'Started', [string] $Identity = 'ApplicationPoolIdentity')
        [pscustomobject]@{
            Name                  = $Name
            State                 = $State
            ManagedRuntimeVersion = ''
            ProcessModel          = [pscustomobject]@{ IdentityType = $Identity }
        }
    }

    function New-HttpsBinding {
        [pscustomobject]@{
            Protocol             = 'https'
            BindingInformation   = '*:443:shop.example.test'
            CertificateHash      = [byte[]](0xAB, 0xCD, 0xEF)
            CertificateStoreName = 'My'
        }
    }
}

Describe 'Get-IisSiteReport' {
    BeforeEach {
        Mock -ModuleName PlatformOps Get-IISAppPool {
            New-TestPool -Name 'DefaultAppPool'
            New-TestPool -Name 'ShopPool'
            New-TestPool -Name 'LegacyPool' -State 'Stopped' -Identity 'LocalSystem'
        }
        Mock -ModuleName PlatformOps Get-BindingCertificate {
            [pscustomobject]@{ Subject = 'CN=shop.example.test'; NotAfter = (Get-Date).AddDays(200) }
        }
    }

    It 'reports a started site with a started pool as OK' {
        Mock -ModuleName PlatformOps Get-IISSite { New-TestSite -Name 'Default Web Site' }
        $result = Get-IisSiteReport
        $result.Status | Should -Be 'OK'
        $result.AppPool | Should -Be 'DefaultAppPool'
        $result.Runtime | Should -Be 'No Managed Code'
        $result.Bindings -join ';' | Should -Be 'http *:80:'
    }

    It 'flags a stopped site' {
        Mock -ModuleName PlatformOps Get-IISSite { New-TestSite -Name 'intranet' -State 'Stopped' }
        (Get-IisSiteReport).Findings | Should -Contain 'site is Stopped'
    }

    It 'flags a stopped pool running as LocalSystem' {
        Mock -ModuleName PlatformOps Get-IISSite { New-TestSite -Name 'legacy' -Pool 'LegacyPool' }
        $result = Get-IisSiteReport
        $result.Status | Should -Be 'WARNING'
        $result.Findings | Should -Contain "application pool 'LegacyPool' is Stopped"
        $result.Findings | Should -Contain "application pool 'LegacyPool' runs as LocalSystem"
    }

    It 'flags a site whose pool does not exist' {
        Mock -ModuleName PlatformOps Get-IISSite { New-TestSite -Name 'orphan' -Pool 'GonePool' }
        (Get-IisSiteReport).Findings | Should -Contain "application pool 'GonePool' not found"
    }

    It 'reads the certificate behind an HTTPS binding by thumbprint' {
        Mock -ModuleName PlatformOps Get-IISSite { New-TestSite -Name 'shop' -Pool 'ShopPool' -Bindings @(New-HttpsBinding) }
        $result = Get-IisSiteReport
        $result.CertificateExpiresInDays | Should -BeGreaterOrEqual 199
        $result.Status | Should -Be 'OK'
        Should -Invoke -ModuleName PlatformOps Get-BindingCertificate -ParameterFilter {
            $Thumbprint -eq 'ABCDEF' -and $StoreName -eq 'My'
        } -Times 1 -Exactly
    }

    It 'warns when a certificate expires inside the window' {
        Mock -ModuleName PlatformOps Get-IISSite { New-TestSite -Name 'shop' -Pool 'ShopPool' -Bindings @(New-HttpsBinding) }
        Mock -ModuleName PlatformOps Get-BindingCertificate {
            [pscustomobject]@{ Subject = 'CN=shop.example.test'; NotAfter = (Get-Date).AddDays(10.5) }
        }
        $result = Get-IisSiteReport -CertificateWarningDays 30
        $result.Status | Should -Be 'WARNING'
        $result.Findings | Should -Contain 'certificate CN=shop.example.test expires in 10 days'
    }

    It 'flags a binding whose certificate is missing from the store' {
        Mock -ModuleName PlatformOps Get-IISSite { New-TestSite -Name 'shop' -Pool 'ShopPool' -Bindings @(New-HttpsBinding) }
        Mock -ModuleName PlatformOps Get-BindingCertificate { $null }
        (Get-IisSiteReport).Findings | Should -Contain 'certificate ABCDEF not found in LocalMachine\My'
    }

    It 'filters sites by wildcard name' {
        Mock -ModuleName PlatformOps Get-IISSite {
            New-TestSite -Name 'shop-api'
            New-TestSite -Name 'shop-web'
            New-TestSite -Name 'intranet'
        }
        $result = @(Get-IisSiteReport -Name 'shop*')
        $result | Should -HaveCount 2
        $result.Name | Should -Not -Contain 'intranet'
    }
}
