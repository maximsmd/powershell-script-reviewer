# Microsoft Learn Source Index

Canonical, official documentation to fetch (via `web_fetch`) when a review depends on a specific current fact — an exit code, a size limit, a timeout, a licensing requirement, or a feature's current name. Every fact stated as a hard number in `intune-and-endpoint.md` traces back to one of these pages, verified at the time this skill was written. Docs pages get revised; treat this list as where to look, not as a permanent snapshot.

If `web_fetch` isn't available or a fetch fails, say so and fall back to the cached figures in `intune-and-endpoint.md`, flagging that they weren't re-verified live.

## PowerShell language and standards

| Topic | URL |
|---|---|
| Approved verbs (full list, by category) | https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands |
| `Get-Verb` reference | https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/get-verb |
| `try`/`catch`/`finally` semantics, terminating vs. non-terminating errors | https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_try_catch_finally |
| General error handling concepts | https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_error_handling |

## PSScriptAnalyzer (Microsoft's official static analyzer)

Prefer *running* this over reading about it — see `scripts/run_script_analyzer.sh`. Use these pages when you need to explain *why* a rule exists, or when the analyzer isn't available and you're checking manually against its rule set.

| Topic | URL |
|---|---|
| Full rule list | https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/rules/readme |
| Rules and recommendations (grouped by category, with severity) | https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/rules-recommendations |
| `Invoke-ScriptAnalyzer` reference | https://learn.microsoft.com/en-us/powershell/module/psscriptanalyzer/invoke-scriptanalyzer |
| Using PSScriptAnalyzer (config, suppression, auto-fix) | https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/using-scriptanalyzer |
| `AvoidUsingInvokeExpression` | https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/rules/avoidusinginvokeexpression |
| `AvoidUsingPlainTextForPassword` | https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/rules/avoidusingplaintextforpassword |
| `UseApprovedVerbs` (rule detail) | https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/rules/useapprovedverbs |

Other rules worth knowing exist even without individually fetching each page (check the full rule list above for current detail/severity): `AvoidUsingUsernameAndPasswordParams`, `AvoidUsingConvertToSecureStringWithPlainText`, `AvoidUsingComputerNameHardcoded`, `AvoidUsingWMICmdlet` (use `Get-CimInstance` instead), `AvoidUsingWriteHost`, `UseShouldProcessForStateChangingFunctions` (state-changing verbs like `Set`/`Remove`/`New` should support `-WhatIf`/`-Confirm`), `PossibleIncorrectComparisonWithNull`.

## Intune deployment mechanics

| Topic | URL |
|---|---|
| Platform scripts (device management scripts) — size limit, timeout, retry behavior, execution order | https://learn.microsoft.com/en-us/intune/device-management/tools/run-powershell-scripts-windows |
| Remediations (formerly Proactive Remediations) — exit code contract, output limit, package count, encoding | https://learn.microsoft.com/en-us/intune/device-management/tools/deploy-remediations |
| Win32 app deployment — detection rules, script-based detection, exit code evaluation | https://learn.microsoft.com/en-us/intune/app-management/deployment/add-win32 |
| Intune Management Extension — prerequisites, install triggers, .NET Framework requirement | https://learn.microsoft.com/en-us/intune/device-management/tools/management-extension-windows |
| Custom compliance discovery scripts — 1 MB script/output limit, 32-bit default host | https://learn.microsoft.com/en-us/intune/intune-service/protect/compliance-custom-script |

**Naming note:** Microsoft renamed *Proactive Remediations* to *Remediations* in the Intune admin center (Devices > Manage devices > Scripts and remediations). Older blog posts, community content, and even some Microsoft documentation still use the old name — they refer to the same feature.

## Windows Installer / exit codes

| Topic | URL |
|---|---|
| MsiExec.exe / InstMsi.exe returned error codes (0, 1618, 1641, 3010, etc.) | https://learn.microsoft.com/en-us/windows/win32/msi/error-codes |
| Windows Installer error messages (codes 1000+, authored/internal errors) | https://learn.microsoft.com/en-us/windows/win32/msi/windows-installer-error-messages |

Key codes worth having memorized, still worth confirming for anything unusual: `0` success, `1618` another installation in progress (retry, don't fail immediately), `3010` success — reboot required, `1641` success — reboot initiated, `1603` fatal error during installation (needs log investigation, not a generic retry).

## Microsoft 365 module currency and retirement

| Topic | URL |
|---|---|
| MSOnline/AzureAD PowerShell retirement — official Microsoft Entra blog | https://techcommunity.microsoft.com/blog/microsoft-entra-blog/action-required-msonline-and-azuread-powershell-retirement---2025-info-and-resou/4364991 |
| AzureAD PowerShell retirement notice | https://techcommunity.microsoft.com/blog/microsoft-entra-blog/important-update-azuread-powershell-retirement/4364989 |
| Exchange Online — Basic Authentication deprecation | https://learn.microsoft.com/en-us/exchange/clients-and-mobile-in-exchange-online/deprecation-of-basic-authentication-exchange-online |
| Exchange Online PowerShell V3 module — current requirements and version history | https://learn.microsoft.com/en-us/powershell/exchange/exchange-online-powershell-v2 |
| What's new in the Exchange Online PowerShell module | https://learn.microsoft.com/en-us/powershell/exchange/whats-new-in-the-exo-module |
| PnP PowerShell — upgrading from the legacy SharePointPnPPowerShellOnline module | https://pnp.github.io/powershell/articles/upgrading.html |
| Microsoft Graph — paging a collection | https://learn.microsoft.com/en-us/graph/paging |

**Note on currency:** MSOnline and AzureAD are, as of this skill's last verification, fully retired (non-functional), not merely deprecated — treat any script depending on them as broken, not just outdated. Re-check the retirement blog post above if there's any doubt, since Microsoft has revised the retirement timeline more than once historically.

## PowerShell Gallery and module management

| Topic | URL |
|---|---|
| PowerShell Gallery | https://www.powershellgallery.com |
| PSResourceGet overview (modern PowerShellGet replacement) | https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.psresourceget/ |
| Module Browser | https://learn.microsoft.com/en-us/powershell/module/ |

For a specific module's current gallery status (version, last updated, deprecation flag), the most direct check is the module's own gallery page: `https://www.powershellgallery.com/packages/{ModuleName}` — fetch this directly rather than searching when you already have the exact module name.

## Fetching strategy during a review

- If the script is plain PowerShell with no Intune/ConfigMgr angle, the language-standards table is usually enough.
- If it's a detection/remediation pair, fetch the Remediations page — the exit-code contract and output limit are exactly the kind of detail that's cheap to get wrong from memory and expensive to get wrong in production.
- If it's a Win32 app detection or requirement script, fetch the Win32 app page for the current exit-code/STDOUT evaluation behavior.
- If the script uses `MSOnline`, `AzureAD`, `SharePointPnPPowerShellOnline`, or anything that looks like an older M365 module you don't immediately recognize as current, check the module currency table above and fetch the retirement blog post if there's any doubt about whether it still functions — this is high-value because the finding severity (Critical, "this cannot run") depends entirely on getting it right.
- If it's Exchange Online, SharePoint/PnP, Teams, or Graph automation meant to run unattended, check `m365-service-modules.md` first (it's already sourced from these pages); fetch live only if the review hinges on a detail not already covered there.
- Don't fetch everything reflexively — fetch what the specific script in front of you actually depends on.
