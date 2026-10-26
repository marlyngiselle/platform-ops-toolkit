function Get-IisSiteReport {
    <#
    .SYNOPSIS
        Report IIS sites with their application pool state, bindings and
        TLS certificate expiry.

    .DESCRIPTION
        For each site, returns the site state, the application pool of the root
        application with its state, runtime and identity, every binding, and the
        expiry of the certificates bound to HTTPS bindings.

        A site gets Status WARNING when any of these is true:
          - the site or its application pool is not Started
          - the application pool does not exist
          - the pool runs as LocalSystem (more privilege than a site needs)
          - a bound certificate is missing from the store, expired, or expires
            within -CertificateWarningDays

        Read-only.

    .PARAMETER Name
        Site names to include. Wildcards are supported. Defaults to all sites.

    .PARAMETER CertificateWarningDays
        Flag certificates that expire within this many days.

    .EXAMPLE
        Get-IisSiteReport | Format-Table Name, State, AppPool, AppPoolState, Status

    .EXAMPLE
        Get-IisSiteReport -Name 'shop*' -CertificateWarningDays 45 |
            Where-Object Status -eq 'WARNING' | Select-Object Name, Findings

    .EXAMPLE
        Get-IisSiteReport | Select-Object Name, Status, CertificateExpiresInDays |
            Export-Csv -Path .\iis-report.csv -NoTypeInformation

    .OUTPUTS
        PlatformOps.IisSite

    .NOTES
        Requires Windows Server with IIS and the IISAdministration module
        (Get-IISSite, Get-IISAppPool). Run elevated: reading the IIS
        configuration needs local administrator rights.
    #>
    [CmdletBinding()]
    [OutputType('PlatformOps.IisSite')]
    param(
        [Parameter(ValueFromPipeline)]
        [SupportsWildcards()]
        [string[]] $Name = @('*'),

        [ValidateRange(1, 365)]
        [int] $CertificateWarningDays = 30
    )

    begin {
        if (-not (Get-Command -Name 'Get-IISSite' -ErrorAction SilentlyContinue)) {
            throw 'Get-IISSite is not available. Install the IIS management tools (IISAdministration module) and run elevated.'
        }
        $pools = @{}
        foreach ($pool in @(Get-IISAppPool)) {
            $pools[$pool.Name] = $pool
        }
        $sites = @(Get-IISSite)
        $patterns = [System.Collections.Generic.List[string]]::new()
    }

    process {
        foreach ($pattern in $Name) {
            $patterns.Add($pattern)
        }
    }

    end {
        $now = Get-Date
        foreach ($site in $sites) {
            $siteName = $site.Name
            if (-not ($patterns | Where-Object { $siteName -like $_ })) {
                continue
            }

            $findings = [System.Collections.Generic.List[string]]::new()

            $siteState = "$($site.State)"
            if ($siteState -ne 'Started') {
                $findings.Add("site is $siteState")
            }

            $rootApp = @($site.Applications | Where-Object { $_.Path -eq '/' }) | Select-Object -First 1
            $poolName = if ($rootApp) { $rootApp.ApplicationPoolName } else { $null }
            $pool = if ($poolName) { $pools[$poolName] } else { $null }
            $poolState = $null
            $identity = $null
            $runtime = $null
            if (-not $pool) {
                $findings.Add("application pool '$poolName' not found")
            }
            else {
                $poolState = "$($pool.State)"
                $identity = "$($pool.ProcessModel.IdentityType)"
                $runtime = if ($pool.ManagedRuntimeVersion) { $pool.ManagedRuntimeVersion } else { 'No Managed Code' }
                if ($poolState -ne 'Started') {
                    $findings.Add("application pool '$poolName' is $poolState")
                }
                if ($identity -eq 'LocalSystem') {
                    $findings.Add("application pool '$poolName' runs as LocalSystem")
                }
            }

            $bindings = [System.Collections.Generic.List[string]]::new()
            $certificateDays = $null
            foreach ($binding in @($site.Bindings)) {
                $bindings.Add("$($binding.Protocol) $($binding.BindingInformation)")
                if ($binding.Protocol -ne 'https' -or -not $binding.CertificateHash) {
                    continue
                }
                $thumbprint = [System.BitConverter]::ToString([byte[]] $binding.CertificateHash).Replace('-', '')
                $store = if ($binding.CertificateStoreName) { $binding.CertificateStoreName } else { 'My' }
                $certificate = Get-BindingCertificate -Thumbprint $thumbprint -StoreName $store
                if (-not $certificate) {
                    $findings.Add("certificate $thumbprint not found in LocalMachine\$store")
                    continue
                }
                $days = [int][math]::Floor(($certificate.NotAfter - $now).TotalDays)
                if ($null -eq $certificateDays -or $days -lt $certificateDays) {
                    $certificateDays = $days
                }
                if ($days -lt 0) {
                    $findings.Add("certificate $($certificate.Subject) expired $(-$days) days ago")
                }
                elseif ($days -le $CertificateWarningDays) {
                    $findings.Add("certificate $($certificate.Subject) expires in $days days")
                }
            }

            [pscustomobject]@{
                PSTypeName               = 'PlatformOps.IisSite'
                Name                     = $siteName
                State                    = $siteState
                AppPool                  = $poolName
                AppPoolState             = $poolState
                AppPoolIdentity          = $identity
                Runtime                  = $runtime
                Bindings                 = $bindings.ToArray()
                CertificateExpiresInDays = $certificateDays
                Status                   = if ($findings.Count -gt 0) { 'WARNING' } else { 'OK' }
                Findings                 = $findings.ToArray()
            }
        }
    }
}
