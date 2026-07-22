# Intune & Endpoint Management Patterns

Reference for reviewing scripts deployed via Intune, ConfigMgr, or similar endpoint-management channels — one of several service-domain references this skill uses (see `m365-service-modules.md` for the Exchange/SharePoint/Teams/Graph side). Contains the exit-code contracts, canonical templates, and context-handling patterns that scripts should conform to.

**Sourcing:** the specific numbers and contracts below (timeouts, size limits, exit codes) are drawn from the Microsoft Learn pages indexed in `microsoft-sources.md`, current as of when this skill was written. Microsoft has changed these before — Proactive Remediations was renamed to Remediations, for instance. For any finding where the exact figure matters, fetch the live page rather than trusting this cache; see Step 0 in `SKILL.md`.

## Contents

1. Exit code contracts
2. Detection script template
3. Remediation script template
4. Standard logging function
5. SYSTEM context: registry and user profiles
6. Architecture (32/64-bit) handling
7. Win32 app patterns
8. Running code as the logged-on user
9. Execution limits and environment facts

---

## 1. Exit code contracts

Getting these wrong is the single most common serious defect in fleet scripts, because the failure is silent — the script reports success and nobody investigates.

**Remediations (formerly "Proactive Remediations" — same feature, Microsoft renamed it in the admin center; both names are in common use) — detection script**
| Exit | Meaning | Intune behaviour |
|---|---|---|
| 0 | Compliant / healthy | No remediation runs. Reported as "Without issues". |
| 1 | Issue detected | Remediation script runs. |
| Any other | Script error / no exit code | Remediation does NOT run — a detection script must exit precisely 1 (or 0), not just "non-zero." |

Detection scripts must be read-only. A detection script that also fixes the problem will report the device as healthy on the next cycle while hiding that a change was made — and remediation success metrics become meaningless.
Source: https://learn.microsoft.com/en-us/intune/device-management/tools/deploy-remediations

**Remediations — remediation script**
| Exit | Meaning |
|---|---|
| 0 | Remediation succeeded |
| 1 | Remediation failed |

Exiting 0 unconditionally — for example by falling off the end of the script after a failed `try` — tells Intune the device is fixed. Intune stops retrying. The device stays broken and appears green. Always exit non-zero in the `catch`. Maximum output per script is 2,048 characters (per Microsoft's documentation) — anything longer than that is truncated in the Intune report, so keep the STDOUT line short and put detail in the log file instead.

**Platform scripts (device management scripts)**
Non-zero exit marks the script as failed. Per Microsoft's documentation, Intune retries the script on the next three consecutive Intune Management Extension check-ins if it fails, then stops. This makes a transient failure (offline, service starting) effectively permanent if it isn't handled, so transient conditions should be retried with backoff *inside* the script rather than allowed to bubble out as a script failure.
Source: https://learn.microsoft.com/en-us/intune/device-management/tools/run-powershell-scripts-windows

**Win32 apps**
| Exit | Meaning |
|---|---|
| 0 | Success |
| 1707 | Success |
| 3010 | Soft reboot required |
| 1641 | Hard reboot initiated |
| 1618 | Another install in progress — retry |
| Other | Failure |

Wrapper scripts must pass through the installer's real exit code rather than swallowing it, or Intune loses the reboot signal.
Full Windows Installer error code reference: https://learn.microsoft.com/en-us/windows/win32/msi/error-codes

---

## 2. Detection script template

```powershell
<#
.SYNOPSIS
    Detection: <what condition this checks for>
.NOTES
    Context: SYSTEM, 64-bit
    Exit 0 = compliant, Exit 1 = remediation required
    Version: 1.0
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    # --- Check current state. Read only. Change nothing. ---
    $target = 'HKLM:\SOFTWARE\Example\Setting'
    $expected = 1

    if (-not (Test-Path $target)) {
        Write-Output "Key not present - remediation required"
        exit 1
    }

    $actual = (Get-ItemProperty -Path $target -Name 'Value' -ErrorAction Stop).Value

    if ($actual -ne $expected) {
        Write-Output "Value is $actual, expected $expected - remediation required"
        exit 1
    }

    Write-Output "Compliant - value is $actual"
    exit 0
}
catch {
    # Distinguish "detection itself broke" from "device is non-compliant".
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}
```

Note the single-line STDOUT before each exit. That string appears in the Intune report and is frequently the only diagnostic available without remoting to the device — it should say what was found, not just "failed".

---

## 3. Remediation script template

```powershell
<#
.SYNOPSIS
    Remediation: <what this fixes>
.NOTES
    Context: SYSTEM, 64-bit
    Exit 0 = remediated successfully, Exit 1 = remediation failed
    Idempotent: safe to run repeatedly
    Version: 1.0
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$LogDir  = "$env:ProgramData\<Org>\<ScriptName>"
$LogFile = Join-Path $LogDir 'remediation.log'

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message" |
        Add-Content -Path $LogFile -Encoding UTF8
}

try {
    Write-Log "Remediation started"

    $target   = 'HKLM:\SOFTWARE\Example\Setting'
    $expected = 1

    # Idempotent: create only if absent.
    if (-not (Test-Path $target)) {
        New-Item -Path $target -Force | Out-Null
        Write-Log "Created key $target"
    }

    # Capture the previous value before overwriting - this is what makes
    # the change auditable and reversible after the fact.
    $previous = (Get-ItemProperty -Path $target -Name 'Value' -ErrorAction SilentlyContinue).Value
    Write-Log "Previous value: $previous"

    Set-ItemProperty -Path $target -Name 'Value' -Value $expected -Type DWord -Force

    # Re-verify rather than assuming the write took effect.
    $actual = (Get-ItemProperty -Path $target -Name 'Value' -ErrorAction Stop).Value
    if ($actual -ne $expected) {
        throw "Verification failed: value is $actual after write, expected $expected"
    }

    Write-Log "Remediation successful - value is $actual"
    Write-Output "Remediated: value set to $actual"
    exit 0
}
catch {
    Write-Log "Remediation failed: $($_.Exception.Message)" -Level ERROR
    Write-Log $_.ScriptStackTrace -Level ERROR
    Write-Output "Remediation failed: $($_.Exception.Message)"
    exit 1   # Critical: never fall through to 0 on failure.
}
```

---

## 4. Standard logging function

A log that survives the script is what makes fleet issues diagnosable months later. Minimum viable version, with rotation:

```powershell
function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO',
        [int]$MaxSizeMB = 5
    )

    $LogDir  = "$env:ProgramData\<Org>\<ScriptName>"
    $LogFile = Join-Path $LogDir 'script.log'

    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }

    # Rotate rather than growing without bound - an hourly script
    # will otherwise fill the disk given enough time.
    if ((Test-Path $LogFile) -and ((Get-Item $LogFile).Length / 1MB) -gt $MaxSizeMB) {
        Move-Item $LogFile "$LogFile.old" -Force
    }

    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message" |
        Add-Content -Path $LogFile -Encoding UTF8
}
```

Keep STDOUT reserved for the single Intune report line. Everything else goes to the log file.

---

## 5. SYSTEM context: registry and user profiles

Under SYSTEM, `HKCU:` resolves to the SYSTEM account's own hive — not the logged-on user's. Scripts that write user settings via `HKCU:` from a remediation appear to succeed and change nothing the user will ever see. This is one of the most common silent failures in endpoint management.

**Enumerate loaded user hives:**

```powershell
# Real user SIDs only: S-1-5-21-*, and exclude _Classes hives.
$userSIDs = Get-ChildItem 'Registry::HKEY_USERS' |
    Where-Object { $_.PSChildName -match '^S-1-5-21-\d+-\d+-\d+-\d+$' }

foreach ($sid in $userSIDs) {
    $path = "Registry::HKEY_USERS\$($sid.PSChildName)\Software\Example"
    # ...operate on $path
}
```

**Reach users who are not logged on** by mounting their offline hive — and always unmount in `finally`, because a leaked handle on NTUSER.DAT blocks profile unload and causes logoff hangs and temp-profile creation:

```powershell
$profiles = Get-ChildItem 'C:\Users' -Directory |
    Where-Object { $_.Name -notin @('Public','Default','Default User','All Users') }

foreach ($p in $profiles) {
    $hive = Join-Path $p.FullName 'NTUSER.DAT'
    if (-not (Test-Path $hive)) { continue }

    $mountPoint = "HKU\TempHive_$($p.Name)"
    $mounted = $false
    try {
        $null = reg.exe load $mountPoint $hive 2>&1
        if ($LASTEXITCODE -ne 0) { continue }   # hive in use - skip, don't fail
        $mounted = $true

        # ...operate on "Registry::$mountPoint\Software\Example"
    }
    finally {
        if ($mounted) {
            [gc]::Collect()                     # release PS handles before unload
            $null = reg.exe unload $mountPoint 2>&1
        }
    }
}
```

**Identify the currently logged-on user from SYSTEM:**

```powershell
$explorer = Get-CimInstance Win32_Process -Filter "Name = 'explorer.exe'" |
    Select-Object -First 1
$owner = Invoke-CimMethod -InputObject $explorer -MethodName GetOwner
$loggedOnUser = "$($owner.Domain)\$($owner.User)"
```

---

## 6. Architecture (32/64-bit) handling

Intune Platform scripts and remediations default to running in a **32-bit** PowerShell host unless "Run script in 64-bit PowerShell" is set. In a 32-bit host on 64-bit Windows:

- `C:\Windows\System32` silently redirects to `C:\Windows\SysWOW64`
- `HKLM:\SOFTWARE` redirects to `HKLM:\SOFTWARE\WOW6432Node`
- `$env:ProgramFiles` points to `Program Files (x86)`

So a script checking for 64-bit installed software will report it missing, and a remediation will "fix" something that was never broken.

Prefer setting the 64-bit flag in the Intune policy. Where that isn't possible, relaunch:

```powershell
if ($env:PROCESSOR_ARCHITEW6432 -eq 'AMD64' -and -not [Environment]::Is64BitProcess) {
    $sysnative = "$env:WINDIR\SysNative\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path $sysnative) {
        $proc = Start-Process -FilePath $sysnative `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
            -Wait -PassThru -WindowStyle Hidden
        exit $proc.ExitCode      # pass the real exit code through
    }
}
```

To read the 64-bit registry explicitly from a 32-bit host:

```powershell
$base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
    [Microsoft.Win32.RegistryHive]::LocalMachine,
    [Microsoft.Win32.RegistryView]::Registry64)
$key = $base.OpenSubKey('SOFTWARE\Example')
```

---

## 7. Win32 app patterns

**Handle 3010 correctly** — swallowing it loses the reboot signal and the app appears installed while sitting in a pending-reboot state:

```powershell
$proc = Start-Process msiexec.exe -ArgumentList '/i "app.msi" /qn /norestart' -Wait -PassThru
switch ($proc.ExitCode) {
    0     { Write-Output 'Install succeeded'; exit 0 }
    3010  { Write-Output 'Install succeeded - reboot required'; exit 3010 }
    1618  { Write-Output 'Another install in progress'; exit 1618 }
    default { Write-Output "Install failed with $($proc.ExitCode)"; exit $proc.ExitCode }
}
```

**Detection rules should be version-aware.** Detecting only that a folder or EXE exists means an upgrade never triggers, and a broken half-uninstall reports as installed. Prefer the uninstall registry key's `DisplayVersion`, or file version with a "greater than or equal to" operator.

**Uninstall detection** for AppX/MSIX packages should use a wildcard match on the package family name rather than an exact string, since Microsoft and OEMs change package names between builds. (This is the class of bug where a removal script silently no-ops on newer devices.)

---

## 8. Running code as the logged-on user

Toast notifications, per-user settings, and anything touching the user's session cannot be done directly from SYSTEM. Options, in order of preference:

1. **Assign the Intune script to a user group and set "Run this script using the logged on credentials" to Yes.** Simplest and most supportable.
2. **Create a scheduled task from the SYSTEM script** that runs in the interactive user's context at logon, then triggers it. Ensure the task is idempotent (delete-then-create, or check existence first) and cleans up.
3. **Write the setting into every user hive** including the Default profile (`C:\Users\Default\NTUSER.DAT`) so future users inherit it — see the hive mounting pattern above.

An HKCU write from a SYSTEM remediation is essentially always a bug.

---

## 9. Execution limits and environment facts

Useful constraints to check a script against. Figures below are sourced from the pages in `microsoft-sources.md` — re-verify live if a review outcome hinges on the exact number:

- **Default host**: Windows PowerShell 5.1, running in a 32-bit process by default (there's an explicit "run in 64-bit PowerShell host" toggle in the policy). PowerShell 7 constructs (`??`, ternary `? :`, `ForEach-Object -Parallel`) will fail on the default host unless PS7 is separately deployed and explicitly invoked.
- **Platform script size limit**: must be under 200 KB (ASCII), per Microsoft's documentation. (Signing adds overhead to the payload but Microsoft doesn't document a separate signed-script limit for Platform scripts specifically — don't assert one from memory.)
- **Platform script timeout**: 30 minutes, per Microsoft's documentation. Design for well under that; long work belongs in a scheduled task the script creates, not the inline script body.
- **Platform scripts run once** per assignment and, on failure, retry on the next three consecutive Intune Management Extension check-ins. After that they stop until the policy is reassigned or the script changes.
- **Remediations run detection/remediation as a pair** on whatever schedule the policy defines (hourly, daily, or a specific time), and remediation output is capped at 2,048 characters.
- **Output captured**: only STDOUT is surfaced in Intune's reporting UI, and it's the truncated/capped figure noted above for Remediations — write the one meaningful line there and put verbose detail in a log file instead.
- **Execution policy** is bypassed by Intune's own invocation, so scripts don't need to manage it — a script that sets it globally is changing machine state unnecessarily.
- **Network is not guaranteed.** Scripts may run pre-VPN, on metered connections, or offline. Anything reaching out over the network needs a timeout and a graceful failure path.
- **Custom compliance discovery scripts** (a related but distinct mechanism) have their own limit: up to 1 MB for the script and up to 1 MB for its output, and also default to the 32-bit host. Don't confuse these limits with Platform script or Remediation limits when reviewing a compliance discovery script.
