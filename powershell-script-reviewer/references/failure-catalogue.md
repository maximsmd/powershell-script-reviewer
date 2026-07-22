# Fleet Failure Catalogue

Recurring ways PowerShell scripts fail at scale, organised by observed symptom. Use this when diagnosing a script that behaves inconsistently across a fleet, or when reviewing preemptively and wanting to check against known patterns.

Each entry gives the symptom an admin actually reports, the underlying cause, and the fix.

## Contents

1. Silent success / false green
2. Works on my machine, fails in the fleet
3. Flapping compliance
4. Hangs and timeouts
5. Intermittent and device-specific failures
6. Damage caused by the script itself
7. Undiagnosable failures
8. Microsoft 365 / cloud-service specific failures

---

## 1. Silent success / false green

The most dangerous category: reporting says healthy, reality says otherwise. These erode trust in the whole management platform.

**Symptom:** Remediation reports 100% success but the issue persists on devices.
**Cause:** The script falls through to exit 0 after a failed operation — commonly an empty `catch {}`, or a `catch` that logs but doesn't exit non-zero.
**Fix:** Every `catch` ends with `exit 1`. Re-verify the change at the end of the remediation and throw if verification fails.

**Symptom:** Native command "succeeded" but nothing changed.
**Cause:** `msiexec`, `reg.exe`, `dism`, `sc.exe` and friends do not throw on failure — they set `$LASTEXITCODE`. `try/catch` catches nothing.
**Fix:** Check `$LASTEXITCODE` explicitly after every native call, or capture via `Start-Process -PassThru` and inspect `.ExitCode`. Remember robocopy treats 0–7 as success.

**Symptom:** Setting applied but users never see it.
**Cause:** Script wrote to `HKCU:` while running as SYSTEM, so it modified the SYSTEM account's hive.
**Fix:** Enumerate `HKEY_USERS`, or mount offline hives, or run the script in user context. See `intune-and-endpoint.md` §5.

**Symptom:** Detection reports compliant on devices that are clearly not.
**Cause:** Detection script running 32-bit sees `WOW6432Node` / `Program Files (x86)` and finds nothing where the 64-bit item lives — or finds a stale 32-bit copy.
**Fix:** Run in 64-bit host, or use explicit `RegistryView::Registry64`. See `intune-and-endpoint.md` §6.

**Symptom:** App removal script no-ops on newer devices.
**Cause:** Exact-match on an AppX package name that changed between OS builds or OEM images.
**Fix:** Wildcard match on the package family name, and log which packages were actually matched so drift is visible.

---

## 2. Works on my machine, fails in the fleet

**Symptom:** Script works when tested interactively, fails when deployed.
**Cause:** Interactive testing runs as an admin user with a full profile, mapped drives, a desktop session, and PowerShell 7 if that's what's installed. Deployment runs as SYSTEM, 32-bit, PS 5.1, no profile, no desktop.
**Fix:** Test in the real context: `psexec -s -i powershell.exe` or via the deployment channel to a pilot ring, never only from an admin console.

**Symptom:** Fails on non-English devices.
**Cause:** Parsing localised command output, or `-match` against English strings, or date/decimal parsing under a German or Swedish locale where `1,5` is one-and-a-half and dates are `dd.MM.yyyy`.
**Fix:** Use objects and properties rather than parsing text. Use `[CultureInfo]::InvariantCulture` for parsing, and compare on stable identifiers (SIDs, GUIDs, error codes) rather than display strings.

**Symptom:** Fails on a subset of devices with path errors.
**Cause:** Hardcoded `C:\`, hardcoded `C:\Program Files` on a device where software is 32-bit, or a Documents folder redirected into OneDrive.
**Fix:** `$env:SystemDrive`, `$env:ProgramFiles` / `${env:ProgramFiles(x86)}`, and resolve known folders rather than assuming.

**Symptom:** Fails on freshly imaged or newly enrolled devices only.
**Cause:** A dependency that arrives later — a module, an agent, a certificate, a registry key created by another policy. Ordering between Intune policies is not guaranteed.
**Fix:** Check for the dependency and exit gracefully with a clear message rather than erroring, so the next cycle picks it up once the dependency lands.

**Symptom:** Intune scripts never run at all on a specific device, with no error and no reported status.
**Cause:** Microsoft documents three distinct causes that all present this way, and they're easy to mistake for a script defect:
1. **System clock skew.** Scripts deployed to clients running the Intune Management Extension fail to run if the device's system clock is exceedingly out of date by months or years. Once the clock is corrected, scripts run as expected.
2. **Device is Entra *registered*, not *joined*.** Devices only registered with the organization in Microsoft Entra ID don't receive scripts at all. (For workplace-joined devices, only Entra *device* security groups work — user targeting is ignored.)
3. **Unsupported platform.** Scripts don't run on Surface Hubs or Windows in S mode.
**Fix:** Verify all three before touching the script — this is an enrolment/platform problem, not a code problem, and reviewing the script harder won't surface it.
Source: https://learn.microsoft.com/en-us/intune/device-management/tools/run-powershell-scripts-windows

**Symptom:** Intune reports the script succeeded, but the change didn't happen on the device.
**Cause:** Beyond the exit-code causes in §1, Microsoft documents a distinct one: antivirus software sandboxing `AgentExecutor`, the IME component that actually invokes PowerShell. The script never really ran, but a success is still reported.
**Fix:** Check `AgentExecutor.log` to confirm actual error output. Microsoft's own diagnostic is to deploy a deliberately-failing script (`Write-Error -Message "Forced Fail" -Category OperationStopped`) — if that reports *success*, AV sandboxing is confirmed, and the fix is an AV exclusion for the IME, not a script change.

---

## 3. Flapping compliance

**Symptom:** Devices oscillate between compliant and non-compliant on every remediation cycle, forever.
**Cause:** Non-idempotent remediation, or a remediation that fights another policy. A common variant: the remediation sets a value that a Configuration Profile or GPO resets between cycles.
**Fix:** Make the remediation idempotent and check current state before writing. Then find the competing policy — flapping usually means two things are managing the same setting, and the script is the wrong place to fix that.

**Symptom:** Device count for a remediation grows steadily and never resolves.
**Cause:** The remediation partially succeeds — it fixes condition A while detection also checks condition B, which it never addresses.
**Fix:** Ensure detection and remediation check and fix precisely the same condition set. Divergence between the pair is a design bug.

**Symptom:** Remediation re-runs on devices that were already fixed.
**Cause:** Detection keys on something that the remediation doesn't durably change, e.g. detecting a running process that restarts.
**Fix:** Detect on the durable end-state (registry value, file version, service start type), not on a transient symptom.

---

## 4. Hangs and timeouts

**Symptom:** Script never completes; devices show "in progress" indefinitely, then fail at timeout.
**Cause:** An interactive prompt under SYSTEM — `Read-Host`, `Get-Credential`, `Pause`, a cmdlet defaulting to `-Confirm`, `Out-GridView`, or an installer without a silent switch showing a dialogue no one can see.
**Fix:** Remove all interactivity. Add `-Force`/`-Confirm:$false` where appropriate. Verify installer silent switches. Set `$ConfirmPreference = 'None'` if needed.

**Symptom:** Script hangs on some devices only, usually remote/VPN ones.
**Cause:** A network call with no timeout — `Invoke-WebRequest` without `-TimeoutSec`, an SMB path that isn't reachable, a DNS lookup against an unreachable DC.
**Fix:** Set explicit timeouts on every network operation and handle the failure path. Assume the device may be offline.

**Symptom:** Script completes but takes 20+ minutes.
**Cause:** Usually `Get-ChildItem -Recurse` over a whole drive, an unfiltered `Get-ADUser -Filter *` in a large directory, or `+=` array building in a large loop.
**Fix:** Filter left, narrow the search root, and use `[System.Collections.Generic.List[T]]` for accumulation.

**Symptom:** Logoff hangs, or users get temporary profiles, starting after a script was deployed.
**Cause:** The script mounted a user hive with `reg load` and never unloaded it, leaving a handle on NTUSER.DAT.
**Fix:** Always unload in a `finally` block, with `[gc]::Collect()` first to release PowerShell's own handles. This one causes helpdesk tickets that are very hard to trace back to the script.

---

## 5. Intermittent and device-specific failures

**Symptom:** Fails maybe 5% of the time, no obvious pattern.
**Cause:** A race condition — a service still starting, a file locked by AV or another process, a `Start-Process` without `-Wait` followed immediately by reading its output.
**Fix:** Wait for the actual condition (`Wait-Process`, poll for service status with a bounded timeout), not an arbitrary `Start-Sleep`. Add bounded retry with backoff around operations that touch contended resources.

**Symptom:** Fails on devices with a particular security agent installed.
**Cause:** EDR/AV blocking script behaviour that resembles an attack — script-block logging triggers, LSASS access, or writing to a monitored path. Also common: AV holding a file lock during a copy.
**Fix:** Retry with backoff on file operations; work with the security team on an exclusion for the script path if genuinely needed rather than disabling protection in-script.

**Symptom:** Works for most users, fails for one department.
**Cause:** Permissions or group-scoped configuration difference — a folder ACL, a mapped drive, a different OU with different GPOs applied.
**Fix:** Don't assume access; test and log the failure with enough detail to identify the pattern. `Get-Acl` in the log helps here.

**Symptom:** Fails only on Windows 11 / only after a feature update.
**Cause:** A cmdlet, registry path, or AppX package that moved or was renamed between builds.
**Fix:** Branch on `[Environment]::OSVersion` or the build number where behaviour genuinely differs, and prefer wildcards over exact package names.

---

## 6. Damage caused by the script itself

These are the incidents. Treat any pattern below as Critical in review.

**Symptom:** Files deleted across the fleet unexpectedly.
**Cause:** A path variable that was empty or null combined with a wildcard — `Remove-Item "$path\*" -Recurse -Force` where `$path` resolved to nothing becomes a delete against the drive root.
**Fix:** Validate the path is non-empty, absolute, and under an expected root before any destructive call. Guard with `if ($path -and (Test-Path $path) -and $path -like 'C:\Expected\*')`. Consider `-WhatIf` in a pilot run.

**Symptom:** Devices unable to authenticate / lost management after a script ran.
**Cause:** The script deleted or reset a certificate, an Entra device registration, or an MDM enrolment key. Frequently a cleanup script that was too aggressive with a wildcard.
**Fix:** Never wildcard-delete under management-related registry paths or certificate stores. Enumerate, log, and delete only explicitly identified items.

**Symptom:** Disk full on a subset of devices.
**Cause:** A log file with no rotation, written by a script running hourly for a year. Or a transcript left running.
**Fix:** Rotate logs with a size cap. Stop transcripts in `finally`.

**Symptom:** Security posture degraded.
**Cause:** A script that added a Defender exclusion, disabled a firewall rule, or suspended BitLocker "temporarily" and never re-enabled it because it failed before the re-enable line.
**Fix:** Any security control that's disabled must be re-enabled in a `finally` block, not on the happy path. Better: don't disable it at all.

---

## 7. Undiagnosable failures

**Symptom:** Script failed months ago, nobody can determine why.
**Cause:** No persistent log, or a log that says "Error occurred" without the exception, or output that only went to STDOUT and was truncated at 2 KB in the Intune report.
**Fix:** Persistent timestamped log file with `$_.Exception.Message` and `$_.ScriptStackTrace`. Reserve STDOUT for one meaningful summary line.

**Symptom:** Nobody knows what version of the script is on which devices.
**Cause:** No version header, no logged version string, scripts edited in place in the Intune console.
**Fix:** Version in the header comment, and log it as the first line of every run. Under a CR-driven change process, the CR reference belongs there too.

**Symptom:** Can't tell what the script changed.
**Cause:** The script logged that it succeeded but not what the previous value was.
**Fix:** Log the before-value before overwriting. This is what makes a change reversible after the fact and what an auditor will ask for.

---

## 8. Microsoft 365 / cloud-service specific failures

**Symptom:** A script that ran fine for years suddenly fails completely, tenant-wide, with no code change.
**Cause:** It depends on a retired module or auth path — MSOnline, AzureAD, or Exchange Online Basic Auth/RPS. These didn't degrade gradually; they stopped working on Microsoft's retirement date. See `m365-service-modules.md` for the current status table.
**Fix:** Migrate to the current replacement (Microsoft.Graph/Microsoft.Entra, or Connect-ExchangeOnline). There's no configuration fix — the old path is gone, not misconfigured.

**Symptom:** Script works fine in testing against a handful of objects, fails with HTTP 429 errors at real scale.
**Cause:** No retry/backoff around Graph, Exchange, or SharePoint calls; the service is throttling a burst of requests.
**Fix:** Catch 429 specifically, honor the `Retry-After` header, and add exponential backoff for other transient failures. Batch requests where the API supports it (Graph's `$batch` supports up to 20 per call).

**Symptom:** A tenant-wide report or bulk operation silently only covers a fraction of the actual objects.
**Cause:** Missing `-All` on a Graph SDK cmdlet (which returns a default page — often 100 or 1000 — and nothing more unless told to keep paging), or unpaged retrieval against a large SharePoint list.
**Fix:** Add `-All`, or implement explicit `@odata.nextLink` paging if using raw `Invoke-MgGraphRequest`; use `-PageSize` and loop for large PnP list retrievals.

**Symptom:** A scheduled/unattended script works when the author runs it interactively but fails or hangs when it actually runs on schedule.
**Cause:** The interactive run used delegated auth with an already-cached token or an MFA prompt the author answered by hand; the unattended run has no one to answer a prompt and no valid non-interactive auth configured.
**Fix:** Confirm the auth path is genuinely non-interactive-capable — certificate-based app-only auth or managed identity — before the script is scheduled, not after the first silent failure.

**Symptom:** Repeated scheduled runs of an Exchange/SharePoint/Graph script slow down over time or start throwing odd session-related errors.
**Cause:** Sessions from `Connect-ExchangeOnline`, `Connect-PnPOnline`, or `Connect-MgGraph` are never explicitly disconnected, so they accumulate across runs.
**Fix:** `Disconnect-*` in a `finally` block, every time, even on the success path.
