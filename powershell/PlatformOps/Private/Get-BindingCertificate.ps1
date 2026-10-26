function Get-BindingCertificate {
    <#
    .SYNOPSIS
        Look up a certificate in the LocalMachine store by thumbprint.
    .DESCRIPTION
        Returns the certificate, or $null when it is not in the store (which is
        itself a finding: the binding points at a certificate that is gone).
    #>
    [CmdletBinding()]
    [OutputType([System.Security.Cryptography.X509Certificates.X509Certificate2])]
    param(
        [Parameter(Mandatory)] [string] $Thumbprint,
        [string] $StoreName = 'My'
    )

    $path = "Cert:\LocalMachine\$StoreName\$Thumbprint"
    if (Test-Path -LiteralPath $path) {
        return Get-Item -LiteralPath $path
    }
    return $null
}
