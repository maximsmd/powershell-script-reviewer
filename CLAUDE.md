# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Claude Code skill for reviewing PowerShell scripts across the Microsoft 365 and Windows admin surface — Intune/endpoint management, Exchange Online, SharePoint Online (PnP), Microsoft Teams, and Microsoft Graph/Entra ID. It reviews with the mindset of a senior PowerShell engineer / script manager who is accountable for what ships to production, not a syntax linter.

This is a **reviewer**, not an author. A companion `powershell-expert`-style writer skill (templates, scaffolding, module recommendations) is a separate, later project — don't conflate the two when extending this one. If both are installed, the writer skill produces the script and this skill is what someone runs it past before it goes anywhere near production.

## Build Commands

```bash
# Package the skill (creates .skill zip file)
zip -r powershell-script-reviewer.skill powershell-script-reviewer -x "*.DS_Store"

# Install to Claude Code skills directory
cp -r powershell-script-reviewer ~/.claude/skills/
```

## Architecture

Standard skill structure:

- `powershell-script-reviewer/SKILL.md` — Main skill definition with frontmatter (name, description) and the full review procedure. This is what Claude loads when the skill triggers.
- `powershell-script-reviewer/references/` — Detailed documentation loaded on-demand to keep context efficient:
  - `microsoft-sources.md` — Canonical Microsoft Learn / official source URLs by topic. The grounding layer — fetch these live rather than trusting cached figures for anything time-sensitive.
  - `m365-service-modules.md` — Exchange Online, SharePoint/PnP, Teams, Graph/Entra: module currency, auth patterns, throttling.
  - `intune-and-endpoint.md` — Intune/ConfigMgr exit-code contracts, SYSTEM-context patterns, templates.
  - `idiomatic-powershell-checklist.md` — Platform-independent code-quality checklist (naming, parameters, pipeline, error handling, style).
  - `failure-catalogue.md` — Real-world failure modes indexed by symptom, for diagnosing rather than pre-reviewing.
- `powershell-script-reviewer/scripts/` — Helper scripts, executable without loading into context:
  - `run_script_analyzer.sh` — Runs Microsoft's official PSScriptAnalyzer if `pwsh` is present; fails gracefully otherwise.
  - `Test-ModuleCurrency.ps1` — Checks module names against a known-retired/deprecated table plus a live PowerShell Gallery lookup.

## Skill Design Principles

- SKILL.md should stay well under the ~500-line soft guideline; detailed content goes in `references/`.
- Reference files are loaded only when needed (progressive disclosure).
- Scripts can be executed without loading into context.
- The description in SKILL.md frontmatter determines when the skill triggers — keep it a little "pushy" about scope (explicitly listing Intune, Exchange, SharePoint, Teams, Graph) since under-triggering on a broad-scope skill is the more likely failure mode.
- **Currency is a first-class concern, not an afterthought.** The M365 module landscape changes fast enough (MSOnline/AzureAD went from deprecated to fully non-functional within about a year) that a review grounded only in training data can confidently bless a script that's already broken. Step 0 of the review procedure and the module-currency check in Step 2 exist specifically to counter that — don't remove or soften them when editing this skill.
- When updating factual claims (exit codes, size limits, retirement dates, throttling behavior), re-verify against a live source before editing `references/*.md`, and note the source inline the way the existing files do. Don't silently update a number without a citation.

## Updating this skill

If you're asked to broaden scope further (e.g. Azure/infra-as-code PowerShell, on-prem AD-only environments), follow the existing pattern: add a new `references/<domain>.md` file with a module-status table and platform-specific gotchas, then point to it from `SKILL.md`'s review procedure and reference-material list rather than inlining everything into `SKILL.md` itself.
