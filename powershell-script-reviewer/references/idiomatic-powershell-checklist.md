# Idiomatic PowerShell Checklist

Concrete good/bad pairs for the "would a senior engineer sign off on this craftsmanship" layer of a review — independent of which platform the script deploys to. Use this alongside the platform-specific reference files (`intune-and-endpoint.md`, `m365-service-modules.md`); this one is about the code itself, not where it runs.

## Contents

1. Naming conventions
2. Parameter design
3. Pipeline support
4. Error handling
5. Output patterns
6. Code style

---

## 1. Naming conventions

**Functions: Verb-Noun, approved verb, singular noun, Pascal Case.**

```powershell
# Flag
function CheckStuff { }
function Get-Servers { }        # plural noun
function get-sqlserver { }      # wrong case

# Good
function Get-ServerStatus { }
function New-DeviceReport { }
```

Check the verb against `Get-Verb` if it's unfamiliar — an unapproved verb generates an `Import-Module` warning and signals the author didn't check.

**Parameters: Pascal Case, singular unless always an array, standard names with aliases where a convention exists.**

```powershell
param(
    [Parameter(Mandatory)]
    [string]$Name,

    [Alias('ComputerName', 'CN')]
    [string]$Server,

    [string[]]$Tags   # plural is correct here — genuinely accepts an array
)
```

---

## 2. Parameter design

**Strong typing and validation over untyped params and manual checks inside the body:**

```powershell
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Name,

    [ValidateRange(1, 100)]
    [int]$Count = 10,

    [ValidateSet('Debug', 'Info', 'Warning', 'Error')]
    [string]$LogLevel = 'Info',

    [switch]$Force
)
```

If the script instead does `if ($Name -eq $null -or $Name -eq '') { throw ... }` inside the body, that's a sign the author didn't reach for the validation attributes — flag as a Low maintainability note, not a functional bug.

**Parameter sets for mutually exclusive input shapes**, rather than a pile of optional parameters and runtime `if` logic to figure out which combination was passed:

```powershell
[CmdletBinding(DefaultParameterSetName = 'ByName')]
param(
    [Parameter(ParameterSetName = 'ByName', Position = 0)]
    [string]$Name,

    [Parameter(ParameterSetName = 'ByID')]
    [int]$ID,

    [Parameter(ParameterSetName = 'ByObject', ValueFromPipeline)]
    [PSObject]$InputObject
)
```

**Common parameters worth checking for, by scenario:**

| Parameter | When it should be there |
|---|---|
| `-WhatIf` / `-Confirm` (via `SupportsShouldProcess`) | Any state-changing operation, especially destructive ones |
| `-Force` | Any operation that would otherwise prompt or refuse to overwrite |
| `-PassThru` | Functions that change state but might need to hand back the changed object |
| `-Verbose` | Anything with meaningful intermediate steps worth surfacing on demand |

**Path parameters**, if the script deals in paths, should distinguish wildcard-supporting input from literal paths:

```powershell
param(
    [Parameter(ParameterSetName = 'Path')]
    [SupportsWildcards()]
    [string[]]$Path,

    [Parameter(ParameterSetName = 'LiteralPath')]
    [Alias('PSPath')]
    [string[]]$LiteralPath
)
```

---

## 3. Pipeline support

**Accept pipeline input where it's a natural fit, and stream output rather than buffering:**

```powershell
# Flag — buffers everything before returning anything
$results = @()
foreach ($item in $collection) {
    $results += Process-Item $item
}
$results

# Good — streams each result as it's produced
foreach ($item in $collection) {
    Process-Item $item
}
```

The buffered version isn't just a style issue — on a large collection it means nothing is visible to the caller (or to a progress indicator, or to a consuming pipeline stage) until the entire operation finishes, and `+=` on an array reallocates the whole array every iteration (see the Performance section of `SKILL.md`).

```powershell
param(
    [Parameter(ValueFromPipeline)]
    [string[]]$Name,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('FullName')]
    [string]$Path
)

process {
    foreach ($item in $Name) {
        # process each item as it arrives
    }
}
```

---

## 4. Error handling

**Catch specific exception types where the response actually differs, generic as a last resort:**

```powershell
try {
    $result = Get-Content -Path $Path -ErrorAction Stop
}
catch [System.IO.FileNotFoundException] {
    Write-Error "File not found: $Path"
    return
}
catch [System.UnauthorizedAccessException] {
    Write-Error "Access denied: $Path"
    return
}
catch {
    Write-Error "Unexpected error: $_"
    throw
}
```

**Terminating vs. non-terminating, and why it matters for review:** `throw` and `$PSCmdlet.ThrowTerminatingError()` stop execution; `Write-Error` alone does not unless `-ErrorAction Stop` is in effect or `$ErrorActionPreference = 'Stop'` is set. A script that calls `Write-Error` expecting the script to halt, without either of those, will silently continue past the "error" — this is one of the more common review findings and worth explaining plainly rather than just citing the rule.

**The right feedback stream for the right purpose:**

```powershell
Write-Warning "File will be overwritten"                    # potential unintended consequence
Write-Verbose "Processing file: $Path"                      # detail, opt-in via -Verbose
Write-Debug "Variable state: $($var | ConvertTo-Json)"       # troubleshooting, opt-in via -Debug
Write-Progress -Activity "Processing" -Status "Item $i of $total" -PercentComplete (($i / $total) * 100)
```

`Write-Host` for anything other than genuinely host-only presentation is a Low finding — it can't be captured, redirected, or suppressed the way the other streams can, which matters when this same script eventually gets wrapped by an orchestrator.

---

## 5. Output patterns

**Typed custom objects over ad-hoc hashtables or strings, when the output will be consumed programmatically:**

```powershell
[PSCustomObject]@{
    PSTypeName = 'MyModule.ServerInfo'
    Name       = $server.Name
    Status     = $server.Status
    IPAddress  = $server.IP
}
```

**`-PassThru` pattern** for functions that change state but sometimes need to hand back the result:

```powershell
# Note the name: don't shadow a built-in cmdlet (Set-ItemProperty is real) --
# a same-named function silently overrides the real one for the rest of the session.
function Set-DeviceSetting {
    [CmdletBinding()]
    param([string]$Name, [string]$Value, [switch]$PassThru)

    $item = Get-DeviceSetting -Name $Name
    $item.Value = $Value

    if ($PassThru) { Write-Output $item }
}
```

**`ShouldProcess` pattern** for anything destructive or state-changing — this is also what makes `-WhatIf`/`-Confirm` actually function rather than being decorative:

```powershell
function Remove-StaleReport {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([string]$Path)

    if ($PSCmdlet.ShouldProcess($Path, 'Delete')) {
        Remove-Item -Path $Path -Force
    }
}
```

A function with `[CmdletBinding(SupportsShouldProcess)]` declared but no actual `$PSCmdlet.ShouldProcess()` call anywhere in the body is worse than not declaring it at all — it advertises safety it doesn't provide. Flag this specifically if you see it.

---

## 6. Code style

**Avoid aliases in production scripts** — they read fine to the author in the moment and poorly to everyone else under pressure six months later:

```powershell
# Flag
gci | ? { $_.Length -gt 1MB } | % { $_.Name }

# Good
Get-ChildItem | Where-Object { $_.Length -gt 1MB } | ForEach-Object { $_.Name }
```

**Explicit parameter names over positional arguments**, especially past the first one or two parameters:

```powershell
# Flag
Get-Process 'notepad' 'Server01'

# Good
Get-Process -Name 'notepad' -ComputerName 'Server01'
```

**Splatting for calls with several parameters**, which also makes diffing changes in source control far more readable:

```powershell
$params = @{
    Path        = $sourcePath
    Destination = $destPath
    Recurse     = $true
    Force       = $true
    ErrorAction = 'Stop'
}
Copy-Item @params
```

**Natural line breaks after pipeline operators, not backtick continuation:**

```powershell
# Good
Get-Process |
    Where-Object { $_.CPU -gt 100 } |
    Sort-Object CPU -Descending |
    Select-Object -First 10
```

**Comment-based help** on anything another engineer will inherit:

```powershell
function Get-ServerStatus {
    <#
    .SYNOPSIS
        Gets the status of specified servers.
    .DESCRIPTION
        Retrieves operational status including CPU, memory, and network
        information from remote servers.
    .PARAMETER Name
        The server name(s) to query.
    .EXAMPLE
        Get-ServerStatus -Name 'Server01'
    .EXAMPLE
        'Server01', 'Server02' | Get-ServerStatus
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]]$Name
    )
    # implementation
}
```

Missing comment-based help is a Low finding on its own — but on a function with several parameters and non-obvious behavior, it compounds with the maintainability concerns in `SKILL.md` §8 and is worth naming explicitly rather than lumping into a generic "add documentation" note.
