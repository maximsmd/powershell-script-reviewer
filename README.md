# PowerShell Script Reviewer Skill

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/Version-1.2.2-green.svg)](CHANGELOG.md)
[![Platform](https://img.shields.io/badge/Platform-Windows%20|%20PowerShell%205.1%2F7+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Skill-blueviolet.svg)](https://claude.ai/code)

A Claude Code skill for reviewing PowerShell scripts across the Microsoft 365 and Windows admin surface — with the judgment of a senior PowerShell engineer or script manager who's accountable for what ships to production, not a syntax linter.

This is a **reviewer**. It doesn't write scripts from scratch — it reads a script someone else (or another Claude skill) already wrote and tells you, plainly, whether you should be comfortable letting it run unattended at scale.

## Features

- **Enterprise-scale review mindset** — the governing question is "what happens when this runs unattended, at scale, with no one watching, and who cleans up if it's wrong."
- **Full Microsoft 365 surface** — Intune/endpoint (Platform scripts, Remediations, Win32 apps, ConfigMgr), Exchange Online, SharePoint Online (PnP), Microsoft Teams, Microsoft Graph/Entra ID, and general unattended automation.
- **Module and authentication currency checks** — flags scripts still depending on retired modules (MSOnline, AzureAD) or a legacy auth path (Exchange Online Basic Auth) before the rest of the review even starts, since these make a script non-functional regardless of code quality.
- **Grounded in live sources, not just training data** — fetches current Microsoft Learn documentation and runs Microsoft's own PSScriptAnalyzer when the environment allows, rather than reciting cached facts that may have changed.
- **Fixed, actionable output format** — verdict, severity-rated findings with operational consequences (not just rule citations), a corrected script, a scorecard, and a pre-deployment checklist.

## Installation

Copy the skill folder to your Claude Code skills directory:

```bash
cp -r powershell-script-reviewer ~/.claude/skills/
```

Or unzip the packaged skill:

Download the packaged skill from the
[latest release](../../releases/latest), then:

```bash
unzip powershell-script-reviewer.skill -d ~/.claude/skills/
```

## Usage

The skill activates automatically when you ask Claude to:

- Review, audit, or sanity-check a PowerShell script before deployment
- Explain why a script failed on some devices, mailboxes, or sites
- Assess whether a script is safe to run unattended or at scale
- Check whether a script relies on a deprecated or retired Microsoft 365 module

### Example Prompts

```
"Review this Intune remediation script before I deploy it fleet-wide"
"Is this Exchange Online script safe to run as a scheduled task?"
"Why does this SharePoint provisioning script fail intermittently?"
"Check this script for any modules Microsoft has since deprecated"
"Would you sign off on this for production?"
```

### Grounding in live sources

The skill treats "sounds right" and "verified right now" as different things, and it verifies rather than assumes wherever the finding's severity depends on a specific current fact:

| Check | Source |
|-------|--------|
| Static analysis (unapproved verbs, plaintext passwords, `Invoke-Expression`, etc.) | Microsoft's official PSScriptAnalyzer, run directly if `pwsh` is available |
| Module currency (is this module deprecated or fully retired?) | Known-status table plus a live PowerShell Gallery lookup |
| Exit-code contracts, size limits, timeouts | Live Microsoft Learn documentation, fetched when the finding depends on the exact figure |
| Throttling, pagination, auth patterns for Graph/Exchange/SharePoint | `references/m365-service-modules.md`, sourced from Microsoft Learn and the relevant module's own documentation |

If live verification isn't available in a given environment (no `pwsh`, no web access), the skill says so explicitly and falls back to its bundled reference files rather than silently guessing.

## Skill Contents

```
powershell-script-reviewer/
├── SKILL.md                              # Core review procedure and output format
├── references/
│   ├── microsoft-sources.md              # Canonical source URLs by topic
│   ├── m365-service-modules.md           # Exchange/SharePoint/Teams/Graph patterns
│   ├── intune-and-endpoint.md            # Intune/ConfigMgr exit codes, templates
│   ├── idiomatic-powershell-checklist.md # Platform-independent code-quality checklist
│   └── failure-catalogue.md              # Real-world failure modes by symptom
└── scripts/
    ├── run_script_analyzer.sh            # Runs Microsoft's PSScriptAnalyzer if available
    └── Test-ModuleCurrency.ps1           # Module retirement/deprecation + live Gallery check
```

## Documentation Sources

- [PowerShell Docs](https://learn.microsoft.com/en-us/powershell/)
- [PSScriptAnalyzer rules](https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/rules/readme)
- [Intune Remediations](https://learn.microsoft.com/en-us/intune/device-management/tools/deploy-remediations)
- [Intune Platform scripts](https://learn.microsoft.com/en-us/intune/device-management/tools/run-powershell-scripts-windows)
- [Exchange Online PowerShell V3](https://learn.microsoft.com/en-us/powershell/exchange/exchange-online-powershell-v2)
- [PnP PowerShell](https://pnp.github.io/powershell/)
- [Microsoft Graph paging](https://learn.microsoft.com/en-us/graph/paging)
- [MSOnline/AzureAD retirement](https://techcommunity.microsoft.com/blog/microsoft-entra-blog/action-required-msonline-and-azuread-powershell-retirement---2025-info-and-resou/4364991)

See `references/microsoft-sources.md` inside the skill for the full, categorized list.

## Related

A `powershell-expert`-style **writer** skill (templates, module recommendations, GUI scaffolding) is intentionally a separate, later project. This skill is what a script gets run past before it ships — it doesn't generate scripts from scratch.

## License

MIT
