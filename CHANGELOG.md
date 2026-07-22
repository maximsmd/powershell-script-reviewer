# Changelog

All notable changes to the powershell-script-reviewer skill are documented in this file.

## [1.2.2] - 2026-07-22

### Added
- New check in SKILL.md Step 4 (Correctness and reliability): **computed-but-unused values**. Found via a stress test that ran a deliberately bugged script through the full review procedure — a script queried Graph to build a "stale profiles" list, then deleted everything under a target path unconditionally without ever consulting that list. Nothing in the prior 9-step procedure explicitly asked whether a computed value is actually consumed by the logic that follows, so this class of bug (script's real behavior silently diverging from what its own code claims to do) could slip past a review that otherwise caught every other planted defect.

## [1.2.1] - 2026-07-22

Verification pass: PowerShell 7.6.4 was installed in the authoring environment so every
helper script, documentation code sample, and cited URL could be genuinely executed and
checked rather than reviewed by eye. Everything below is a defect that pass found.

### Fixed
- **`Test-ModuleCurrency.ps1` — `GalleryVersion` returned a `System.Version` object rather than a string**, so it serialised as `{"Major":3,"Minor":10,...}` in JSON and broke any downstream string comparison. Now cast to `[string]` (verified: returns `"3.10.0"` for ExchangeOnlineManagement).
- **`Test-ModuleCurrency.ps1` — a module that simply doesn't exist reported as `"Gallery lookup failed: ..."`**, implying a connectivity problem and sending an engineer to debug the wrong thing. Non-existent modules now report `"Not found in PSGallery"`, distinct from genuine lookup failures.
- **`Test-ModuleCurrency.ps1` — `Write-Host` in the `end` block** violated `PSAvoidUsingWriteHost`, which this skill's own checklist flags. Because the helper is invoked programmatically by the reviewer, unsuppressable host output would pollute the caller's output stream. Replaced with `Write-Verbose`. The script now returns **zero PSScriptAnalyzer findings**.
- **Multi-result handling in `Test-ModuleCurrency.ps1`** hardened via `@($found)[0]` rather than an `-is [System.Array]` check, which misses single-item collections that aren't arrays.
- **Non-ASCII characters (em-dashes) in both helper scripts saved as UTF-8 without BOM.** PSScriptAnalyzer flagged this via `PSUseBOMForUnicodeEncodedFile`; Windows PowerShell 5.1 renders such characters as mojibake, and Intune Remediations specifically require UTF-8 without BOM, making pure ASCII the safest choice. Both scripts are now 100% ASCII.
- **Four broken cross-references to `intune-patterns.md`**, a file renamed to `intune-and-endpoint.md` in 1.2.0 — in `failure-catalogue.md` (×2) and `microsoft-sources.md` (×2). Section numbers cited (§5, §6) were separately verified as correct.
- **A fabricated documentation URL returning HTTP 404** (`.../msi/msiexec-exe-and-instmsi-exe-error-messages`), which had been constructed rather than verified. Replaced with two confirmed-200 Microsoft Learn URLs. All 29 cited URLs were checked; the rest resolve (two Tech Community links return 403 to automated requests but are valid in a browser).
- **A code sample in `idiomatic-powershell-checklist.md` defined a function named `Set-ItemProperty`**, shadowing a real built-in cmdlet — precisely the kind of thing this skill tells reviewers to flag. Renamed to `Set-DeviceSetting`, and the sample's undefined `$item` variable was given a definition.

### Added
- Three Microsoft-documented Intune failure modes to `failure-catalogue.md` §2, discovered while verifying platform facts against Microsoft Learn and previously absent: **system clock skew** preventing scripts from running at all; **Entra *registered* vs *joined*** devices silently never receiving scripts (plus the workplace-joined user-targeting caveat); and **antivirus sandboxing of `AgentExecutor`** causing false success reports, including Microsoft's own forced-fail diagnostic for confirming it.

### Verified (no change required)
- All 26 PowerShell code samples across `SKILL.md` and the reference files parse cleanly under the real PowerShell parser.
- The detection-script template executes and honours the documented exit-code contract (exit 1 with one STDOUT line when non-compliant).
- The `Write-Log` template works, including its size-based rotation path.
- The analyzer wrapper correctly detects `Invoke-Expression`, plaintext passwords, and unapproved verbs, and degrades gracefully (`{"available": false, ...}`) on a missing file, a missing argument, or an environment with no `pwsh`.
- Intune Platform script facts re-confirmed directly against Microsoft Learn: **200 KB (ASCII)** size limit, **30 minute** timeout, and retry **three times across the next three consecutive IME check-ins**.

## [1.2.0] - 2026-07-22

### Changed
- Broadened scope from Intune/endpoint-only to the full Microsoft 365 PowerShell surface: Exchange Online, SharePoint Online (PnP), Microsoft Teams, and Microsoft Graph/Entra ID, alongside the existing Intune/ConfigMgr coverage.
- Reviewer persona sharpened to explicit "Senior PowerShell Script Engineer / PowerShell Script Manager" framing — accountable-for-production judgment, not just technical correctness.
- `intune-patterns.md` renamed to `intune-and-endpoint.md` to reflect its place as one of several service-domain reference files rather than the only one.
- Repository restructured to match standard community skill conventions: top-level `README.md`, `CHANGELOG.md`, `CLAUDE.md`, `.gitignore`, packaged `.skill` file alongside the skill folder.
- Scorecard in the required output format gained a "Module & auth currency" category.

### Added
- New review step: **Module and authentication currency** (SKILL.md Step 2) — checks every module/cmdlet against known-retired and known-deprecated Microsoft 365 modules before the rest of the review proceeds, since a script calling a retired service (MSOnline, AzureAD) is non-functional regardless of how well-written it otherwise is.
- `references/m365-service-modules.md` — module status table, identity (Graph/Entra), Exchange Online, SharePoint/PnP, Teams, unattended-auth patterns, and throttling/pagination/bulk-operation guidance.
- `references/idiomatic-powershell-checklist.md` — platform-independent code-quality checklist (naming, parameter design, pipeline support, error handling, output patterns, code style) with concrete good/bad pairs.
- `scripts/Test-ModuleCurrency.ps1` — checks named modules against a hardcoded known-retired/deprecated table plus a live PowerShell Gallery lookup (PSResourceGet-first, legacy `Find-Module` fallback); runnable standalone, not just by Claude.
- Live-verified sourcing added to `microsoft-sources.md` for MSOnline/AzureAD retirement timelines, Exchange Online V3/Basic Auth retirement, and PnP PowerShell migration.
- GUI-script review addendum (event-handler exception safety, disposal, UI-thread blocking) for the cases where a reviewed script includes a Windows Forms/WPF interface.

### Fixed
- Corrected several Intune platform facts that didn't match live Microsoft Learn documentation at the time of writing: Platform script timeout is 30 minutes (not ~60), the documented size limit is 200 KB ASCII with no separately documented signed-script limit, and "Proactive Remediations" is now named "Remediations" in the admin center.

## [1.1.0] - 2026-07-22

### Added
- Step 0 in the review procedure: grounding review findings in live Microsoft Learn documentation and Microsoft's own PSScriptAnalyzer tool rather than relying on cached knowledge alone.
- `references/microsoft-sources.md` — canonical Microsoft Learn URL index by topic.
- `scripts/run_script_analyzer.sh` — runs PSScriptAnalyzer via `pwsh` if available, with a graceful "unavailable" fallback.

## [1.0.0] - 2026-07-22

### Added
- Initial skill: SKILL.md with an 8-part review procedure (intent/blast radius, security, correctness, idempotency, Intune/deployment compatibility, logging, maintainability, performance), fixed output format (verdict, findings, corrected script, scorecard, pre-deployment checklist).
- `references/intune-patterns.md` — Intune exit-code contracts, detection/remediation templates, SYSTEM-context patterns.
- `references/failure-catalogue.md` — real-world failure modes indexed by symptom.
