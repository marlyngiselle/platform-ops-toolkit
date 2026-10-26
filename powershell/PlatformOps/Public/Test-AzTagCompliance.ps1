function Test-AzTagCompliance {
    <#
    .SYNOPSIS
        Check Azure resources against a tagging standard, and optionally add
        default values for missing tags.

    .DESCRIPTION
        Evaluates each resource for required tags (missing or empty values) and,
        when -AllowedValue is given, for values outside the allowed list. Tag
        names are compared case-insensitively, as Azure does.

        By default only non-compliant resources are returned. With
        -DefaultValue, missing tags that have a default are merged onto the
        resource with Update-AzTag. Existing tags are never overwritten or
        removed. This step honours -WhatIf and -Confirm.

    .PARAMETER RequiredTag
        Tag names every resource must carry with a non-empty value.

    .PARAMETER AllowedValue
        Hashtable of tag name to allowed values, for example
        @{ environment = 'dev', 'test', 'prod' }.

    .PARAMETER ResourceGroupName
        Limit the check to one resource group. Ignored when resources are piped in.

    .PARAMETER InputObject
        Resources to check, typically from Get-AzResource. When omitted, the
        function calls Get-AzResource itself.

    .PARAMETER DefaultValue
        Hashtable of tag name to value applied when that tag is missing.

    .PARAMETER IncludeCompliant
        Also return resources that pass every check.

    .EXAMPLE
        Test-AzTagCompliance -RequiredTag owner, environment, cost-center

        List every resource in the current subscription missing one of the tags.

    .EXAMPLE
        Test-AzTagCompliance -RequiredTag environment -AllowedValue @{ environment = 'dev', 'test', 'prod' } |
            Export-Csv -Path .\tag-gaps.csv -NoTypeInformation

    .EXAMPLE
        Get-AzResource -ResourceGroupName rg-lab |
            Test-AzTagCompliance -RequiredTag owner -DefaultValue @{ owner = 'unassigned' } -WhatIf

        Preview which resources would receive owner=unassigned, without changing anything.

    .OUTPUTS
        PlatformOps.TagCompliance

    .NOTES
        Requires the Az.Resources module and a signed-in context (Connect-AzAccount).
        Reporting needs Reader. -DefaultValue needs Microsoft.Resources/tags/write,
        granted for example by the "Tag Contributor" role, which cannot change
        anything else on the resource.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('PlatformOps.TagCompliance')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $RequiredTag,

        [hashtable] $AllowedValue = @{},

        [string] $ResourceGroupName,

        [Parameter(ValueFromPipeline)]
        [object[]] $InputObject,

        [hashtable] $DefaultValue = @{},

        [switch] $IncludeCompliant
    )

    begin {
        $resources = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($item in $InputObject) {
            if ($null -ne $item) {
                $resources.Add($item)
            }
        }
    }

    end {
        if ($resources.Count -eq 0) {
            if (-not (Get-Command -Name 'Get-AzResource' -ErrorAction SilentlyContinue)) {
                throw 'Get-AzResource is not available. Install Az.Resources and run Connect-AzAccount.'
            }
            $query = @{ ErrorAction = 'Stop' }
            if ($ResourceGroupName) {
                $query.ResourceGroupName = $ResourceGroupName
            }
            foreach ($item in @(Get-AzResource @query)) {
                $resources.Add($item)
            }
        }

        foreach ($resource in $resources) {
            $tags = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
            if ($resource.Tags) {
                foreach ($key in $resource.Tags.Keys) {
                    $tags[$key] = $resource.Tags[$key]
                }
            }

            $missing = @($RequiredTag | Where-Object {
                    -not $tags.ContainsKey($_) -or [string]::IsNullOrWhiteSpace([string] $tags[$_])
                })

            $invalid = @(foreach ($key in $AllowedValue.Keys) {
                    if ($tags.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace([string] $tags[$key]) -and
                        $tags[$key] -notin @($AllowedValue[$key])) {
                        "$key=$($tags[$key])"
                    }
                })

            $toAdd = @{}
            foreach ($tagName in $missing) {
                if ($DefaultValue.ContainsKey($tagName)) {
                    $toAdd[$tagName] = $DefaultValue[$tagName]
                }
            }

            $remediated = @()
            if ($toAdd.Count -gt 0) {
                $summary = ($toAdd.Keys | Sort-Object | ForEach-Object { "$_=$($toAdd[$_])" }) -join ', '
                if ($PSCmdlet.ShouldProcess($resource.ResourceId, "Merge tags $summary")) {
                    try {
                        $null = Update-AzTag -ResourceId $resource.ResourceId -Tag $toAdd -Operation Merge -ErrorAction Stop
                        $remediated = @($toAdd.Keys | Sort-Object)
                    }
                    catch {
                        Write-Error "Failed to tag $($resource.ResourceId): $($_.Exception.Message)"
                    }
                }
            }

            $stillMissing = @($missing | Where-Object { $_ -notin $remediated })
            $compliant = ($stillMissing.Count -eq 0 -and $invalid.Count -eq 0)
            if ($compliant -and -not $IncludeCompliant -and $remediated.Count -eq 0) {
                continue
            }

            [pscustomobject]@{
                PSTypeName        = 'PlatformOps.TagCompliance'
                Name              = $resource.Name
                ResourceGroupName = $resource.ResourceGroupName
                ResourceType      = $resource.ResourceType
                Compliant         = $compliant
                MissingTags       = $stillMissing
                InvalidTags       = $invalid
                RemediatedTags    = $remediated
                ResourceId        = $resource.ResourceId
            }
        }
    }
}
