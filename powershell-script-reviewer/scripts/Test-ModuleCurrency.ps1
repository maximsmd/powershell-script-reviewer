<#
.SYNOPSIS
    Checks whether PowerShell modules referenced in a script are current, deprecated, or retired.

.DESCRIPTION
    Enterprise Microsoft 365 and Windows admin scripts often keep using modules long
    after Microsoft has deprecated or fully retired them -- MSOnline and AzureAD are the
    starkest recent example, having gone from "deprecated" to genuinely non-functional.

    This script checks a list of module names against:
      1. A hardcoded table of known-retired/deprecated Microsoft modules (no network needed,
         always available, and the fastest way to catch the highest-severity findings).
      2. Live PowerShell Gallery metadata, when available, for current version and last-updated
         date on modules not already in the hardcoded table.

    Used by the powershell-script-reviewer skill's module-currency check (see SKILL.md Step 2),
    and equally usable standalone by an engineer auditing their own script inventory.

.PARAMETER Name
    One or more module names to check -- e.g. pulled from an Import-Module, #Requires -Modules,
    or Connect-* line found in the script under review.

.PARAMETER SkipLiveCheck
    Skip the PowerShell Gallery lookup and only check against the known-status table. Useful
    with no network access, or when only the retirement-table check is needed.

.EXAMPLE
    .\Test-ModuleCurrency.ps1 -Name 'AzureAD','ExchangeOnlineManagement'

    Checks two named modules; AzureAD will come back flagged as retired.

.EXAMPLE
    Select-String -Path .\script.ps1 -Pattern 'Import-Module\s+([\w.]+)' |
        ForEach-Object { $_.Matches[0].Groups[1].Value } |
        Sort-Object -Unique |
        .\Test-ModuleCurrency.ps1

    Extracts module names actually imported by a script and checks all of them in one pass.

.NOTES
    The known-status table below reflects Microsoft's published retirement schedule as of
    when this script was last updated (mid-2026). Microsoft has revised these schedules
    before -- if a finding here matters for a Critical/High severity call, cross-check against
    references/microsoft-sources.md and the live retirement announcement rather than trusting
    this table alone for anything time-sensitive.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
    [string[]]$Name,

    [switch]$SkipLiveCheck
)

begin {
    $KnownStatus = @{
        'MSOnline'                      = @{ Status = 'RETIRED';    Note = 'Non-functional since ~May 2025. Connect-MsolService / Get-MsolUser / all Msol* cmdlets no longer work. Migrate to Microsoft.Graph or Microsoft.Entra.' }
        'MSOnlineExtended'               = @{ Status = 'RETIRED';    Note = 'Retired alongside MSOnline.' }
        'AzureAD'                        = @{ Status = 'RETIRED';    Note = 'Non-functional since ~Aug 2025. Connect-AzureAD / Get-AzureADUser / all AzureAD* cmdlets no longer work. Migrate to Microsoft.Graph or Microsoft.Entra.' }
        'AzureADPreview'                 = @{ Status = 'RETIRED';    Note = 'Same retirement as AzureAD.' }
        'AzureRM'                        = @{ Status = 'DEPRECATED'; Note = 'Superseded by the Az module. Still installable but unsupported -- flag for migration.' }
        'SharePointPnPPowerShellOnline'  = @{ Status = 'DEPRECATED'; Note = 'Superseded by PnP.PowerShell, which uses a different (app-only/certificate) auth model.' }
        'PowerShellGet'                  = @{ Status = 'LEGACY';     Note = 'Not retired, but Microsoft.PowerShell.PSResourceGet is the current replacement (Find-PSResource/Install-PSResource). Low-severity note, not a functional break.' }
        'Microsoft.Graph'                = @{ Status = 'CURRENT';    Note = 'Current general-purpose Graph SDK.' }
        'Microsoft.Entra'                = @{ Status = 'CURRENT';    Note = 'Newer module offering an AzureAD-like cmdlet shape over Microsoft Graph -- a common migration target for AzureAD-heavy scripts.' }
        'ExchangeOnlineManagement'       = @{ Status = 'CURRENT';    Note = 'Confirm the script uses Connect-ExchangeOnline (V3, REST-backed), not the retired Connect-EXOPSSession / Basic Auth path.' }
        'PnP.PowerShell'                 = @{ Status = 'CURRENT';    Note = 'Current SharePoint module. Requires PowerShell 7 and, for unattended use, app-only/certificate auth.' }
        'MicrosoftTeams'                 = @{ Status = 'CURRENT';    Note = 'Current -- still confirm the installed version isn''t badly out of date, since cmdlet behavior has shifted across major versions.' }
        'Az'                             = @{ Status = 'CURRENT';    Note = 'Current Azure Resource Manager module, replacement for AzureRM.' }
    }
}

process {
    foreach ($moduleName in $Name) {
        $result = [ordered]@{
            Module         = $moduleName
            KnownStatus    = 'UNKNOWN'
            Note           = 'Not in the known-status table -- verify manually or check the Gallery result below.'
            GalleryVersion = $null
            GalleryUpdated = $null
            LiveCheck      = 'Not performed'
        }

        if ($KnownStatus.ContainsKey($moduleName)) {
            $result.KnownStatus = $KnownStatus[$moduleName].Status
            $result.Note        = $KnownStatus[$moduleName].Note
        }

        if (-not $SkipLiveCheck) {
            try {
                $found = $null
                if (Get-Module -ListAvailable -Name Microsoft.PowerShell.PSResourceGet -ErrorAction SilentlyContinue) {
                    $found = Find-PSResource -Name $moduleName -Repository PSGallery -ErrorAction Stop
                }
                else {
                    $found = Find-Module -Name $moduleName -Repository PSGallery -ErrorAction Stop
                }

                # Find-* can return multiple results; take the first (highest) version.
                $entry = @($found)[0]

                if ($entry) {
                    # Cast Version to string -- otherwise it serialises as a System.Version
                    # object ({Major=3; Minor=10; ...}) which breaks JSON output and any
                    # downstream string comparison.
                    $result.GalleryVersion = [string]$entry.Version

                    # PSResourceGet exposes PublishedDate; legacy PowerShellGet also exposes
                    # PublishedDate, but guard anyway so a schema change degrades gracefully
                    # rather than throwing.
                    $published = $entry.PSObject.Properties['PublishedDate']
                    $result.GalleryUpdated = if ($published -and $published.Value) {
                        [string]$published.Value
                    }
                    else {
                        'n/a'
                    }

                    $result.LiveCheck = 'OK'
                }
                else {
                    $result.LiveCheck = 'Not found in PSGallery'
                }
            }
            catch {
                # Distinguish "this module does not exist" from "the lookup itself broke".
                # Reporting a nonexistent module as a lookup failure sends an engineer
                # debugging connectivity when the real answer is that the name is wrong
                # -- which for a review is itself a finding worth surfacing accurately.
                $message = $_.Exception.Message
                $result.LiveCheck = if ($message -match 'could not be found|No match was found') {
                    'Not found in PSGallery'
                }
                else {
                    "Gallery lookup failed: $message"
                }
            }
        }
        else {
            $result.LiveCheck = 'Skipped (-SkipLiveCheck)'
        }

        [PSCustomObject]$result
    }
}

end {
    # Write-Verbose rather than Write-Host: Write-Host writes to the host and cannot be
    # captured, redirected, or suppressed by a calling script -- which matters because this
    # helper is invoked programmatically by the reviewer skill, whose output would otherwise
    # be polluted by this guidance text. (PSScriptAnalyzer: PSAvoidUsingWriteHost.)
    Write-Verbose ('Severity guide: RETIRED = script cannot function, treat as Critical. ' +
                   'DEPRECATED = flag for migration, typically High. ' +
                   'LEGACY = low-severity note. CURRENT = no finding needed.')
}
