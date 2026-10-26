# PlatformOps module loader: dot-source private helpers, then public functions.

foreach ($folder in @('Private', 'Public')) {
    $path = Join-Path -Path $PSScriptRoot -ChildPath $folder
    if (Test-Path -LiteralPath $path) {
        foreach ($file in Get-ChildItem -LiteralPath $path -Filter '*.ps1') {
            . $file.FullName
        }
    }
}

$public = Get-ChildItem -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'Public') -Filter '*.ps1'
Export-ModuleMember -Function $public.BaseName
