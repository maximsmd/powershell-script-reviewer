# Microsoft 365 Service Modules — Currency, Auth, and Review Patterns

Reference for reviewing PowerShell against Exchange Online, SharePoint Online, Microsoft Teams, and Microsoft Graph/Entra ID. Pair with `intune-and-endpoint.md` for the device-management side and `microsoft-sources.md` for the underlying citations.

**Why this file exists:** the M365 module landscape moves fast, and "deprecated" in this space has recently meant "actually stopped working," not just "discouraged." A review that treats a retired module as merely old-fashioned understates the finding badly.

## Contents

1. Module status table (current vs. deprecated vs. retired)
2. Identity: Microsoft Graph PowerShell SDK and Microsoft Entra
3. Exchange Online
4. SharePoint Online (PnP)
5. Microsoft Teams
6. Authentication patterns for unattended scripts
7. Throttling, pagination, and bulk operations

---

## 1. Module status table

| Module | Status | Note |
|---|---|---|
| `MSOnline` | **Retired** | Stopped working (~May 2025). `Connect-MsolService`, `Get-MsolUser`, and every other Msol cmdlet no longer function. Migrate to `Microsoft.Graph` or `Microsoft.Entra`. |
| `AzureAD` / `AzureADPreview` | **Retired** | Stopped working (~Aug 2025). `Connect-AzureAD`, `Get-AzureADUser`, etc. no longer function. Same migration path. |
| `AzureRM` | **Deprecated** | Long superseded by `Az`. Still installable but unsupported; flag for migration. |
| `SharePointPnPPowerShellOnline` | **Deprecated** | Superseded by `PnP.PowerShell`. Different auth model — the legacy module used stored user credentials; the current one expects app-only/certificate auth. |
| `Microsoft.Online.SharePoint.PowerShell` (SharePoint Online Management Shell) | **Current, narrower scope** | Still maintained by Microsoft; tenant-admin-level operations only (not site-content operations like PnP). Now supports certificate-based app-only auth as well. Works on Windows PowerShell 5.1, unlike PnP which needs PS7. |
| `ExchangeOnlineManagement` (V1, RPS-only, `Connect-EXOPSSession`) | **Retired** | The Basic Auth / legacy RPS-only path is gone. Any script still calling `Connect-EXOPSSession` or a bare `New-PSSession` against Exchange endpoints with Basic Auth will not connect. |
| `ExchangeOnlineManagement` (V3, current) | **Current** | Use `Connect-ExchangeOnline`. REST-backed cmdlets, supports MFA, certificate, and managed identity auth. |
| `MicrosoftTeams` | **Current** | Keep version-pinned and current; check for cmdlet-level deprecation notices on a given release rather than assuming the whole module is stable forever. |
| `Microsoft.Graph` (Graph PowerShell SDK) | **Current** | The general-purpose replacement for AzureAD/MSOnline and much of the legacy Azure AD Graph surface. |
| `Microsoft.Entra` | **Current, newer** | Released to give an AzureAD-like cmdlet experience while running on Microsoft Graph underneath — a smoother migration target for teams whose scripts leaned heavily on AzureAD's cmdlet shape. |
| `PowerShellGet` (legacy `Find-Module`/`Install-Module`) | **Legacy but functional** | Not retired, but `Microsoft.PowerShell.PSResourceGet` (`Find-PSResource`/`Install-PSResource`) is the modern replacement, faster and more reliable. Not a Critical finding on its own, but worth a Low/Medium note if a script bootstraps modules at the top.

If a script uses a module not on this table, don't assume it's fine — check `microsoft-sources.md` or run `scripts/Test-ModuleCurrency.ps1`, which checks a live PowerShell Gallery lookup in addition to a hardcoded version of this table.

**What "retired" means for a review finding:** this isn't a style preference, it's "this script cannot function as written." Rate it Critical, and always name the replacement in the fix.

---

## 2. Identity: Microsoft Graph PowerShell SDK and Microsoft Entra

- **Connection context matters.** `Connect-MgGraph` without `-Identity` or app-only parameters opens a delegated, interactive session — wrong for anything meant to run unattended. For unattended scripts, expect `Connect-MgGraph -ClientId ... -TenantId ... -CertificateThumbprint ...` (app-only, certificate) or `-Identity` (managed identity, when running in Azure).
- **Scope minimization.** Application permissions in Graph are granted tenant-wide by an admin at consent time; a script asking for (or an app registration already holding) `Directory.ReadWrite.All` to do something `User.ReadWrite.All` or a narrower scope would cover is over-privileged. Flag it — the fix isn't just in the script, it's in the app registration, and that's worth saying explicitly.
- **`-All` and pagination.** Graph SDK cmdlets return a default page size (varies by endpoint — 100 for `/users`, up to 1000 for some others) unless `-All` is specified. A script that loops over `Get-MgUser` results without `-All` and treats what it got as the complete tenant population will silently under-report or under-process at any tenant of meaningful size. This is a Correctness finding, not a nitpick.
- **Throttling.** Microsoft Graph returns HTTP 429 with a `Retry-After` header when throttled. A script issuing rapid sequential calls (especially in a tight per-object loop) without honoring that header, or without backoff, will start failing under real load even if it worked fine against a handful of test objects.
- **Batching.** Microsoft Graph supports JSON batching — up to 20 requests in a single HTTP call via `$batch`. A script doing hundreds of individual `Invoke-MgGraphRequest` calls in a loop where batching would apply is a performance and throttling-risk finding.
- **Disconnect.** `Disconnect-MgGraph` in a `finally` block. Missing this isn't usually catastrophic but is worth a Low finding, especially in scripts that run repeatedly in the same session/host.

---

## 3. Exchange Online

- **Module and connection method.** Confirm `ExchangeOnlineManagement` (current, V3) and `Connect-ExchangeOnline`. Anything referencing `Connect-EXOPSSession`, a raw `New-PSSession` to an Exchange endpoint, or Basic Auth is calling a path that's gone — Critical, with the fix being a straightforward `Connect-ExchangeOnline` rewrite.
- **Auth for unattended scripts.** Certificate-based app-only auth (`Connect-ExchangeOnline -CertificateThumbprint ... -AppId ... -Organization ...`) or managed identity. A stored password for a mailbox with delegated rights is the wrong pattern for anything scheduled.
- **Bulk operations.** For reporting or bulk reads across many mailboxes, the REST-backed `Get-EXO*` cmdlet family (`Get-EXOMailbox`, `Get-EXORecipient`, etc.) is materially faster than the older RPS-backed equivalents run in a loop. A script doing `Get-Mailbox` per-user in a large `foreach` where `Get-EXOMailbox` with proper filtering would do the same job faster is a Performance finding worth calling out by name.
- **Session cleanup.** `Disconnect-ExchangeOnline -Confirm:$false` in a `finally` block. A script that connects repeatedly without disconnecting (e.g. a scheduled task running every 15 minutes) will accumulate sessions.
- **PowerShell version.** Current ExchangeOnlineManagement versions increasingly require newer PowerShell 7.x releases due to .NET dependency changes — don't assume Windows PowerShell 5.1 compatibility without checking the specific module version against its stated requirement.

---

## 4. SharePoint Online (PnP)

- **Module.** `PnP.PowerShell`, not the retired `SharePointPnPPowerShellOnline`. Requires PowerShell 7.
- **Authentication.** Current PnP no longer accepts stored username/password via `-Credentials` in the way the legacy module did for unattended use; expect app-only authentication with a certificate (`Connect-PnPOnline -Url ... -ClientId ... -Thumbprint ... -Tenant ...`) registered via an Entra ID app registration, or `-Interactive`/device-code for ad-hoc admin sessions only.
- **Permission scoping.** `Sites.Selected` scoped to the specific site collections the script needs is the tighter and preferred pattern over `Sites.FullControl.All` tenant-wide, especially for an app registration whose certificate might end up on more machines than intended. Flag tenant-wide grants for scripts that only ever touch a handful of sites.
- **Disconnect.** `Disconnect-PnPOnline` in a `finally` block, same reasoning as Graph/Exchange.
- **Bulk operations at scale.** Large document libraries or site collections need paged retrieval (`Get-PnPListItem -PageSize`) rather than pulling everything into memory at once; watch for `Get-PnPListItem` without paging against a library that could hold hundreds of thousands of items.

---

## 5. Microsoft Teams

- **Module.** `MicrosoftTeams` is current and actively maintained — check the installed version against the gallery rather than assuming any given version is current, since cmdlet behavior has shifted across major versions (e.g., some legacy Skype-for-Business-era cmdlets have been phased out).
- **Auth for unattended governance scripts** (archiving teams, membership audits, policy assignment): same pattern as elsewhere — app-only with certificate or managed identity, not a stored interactive credential.
- **Rate limits.** Teams-related Graph endpoints are subject to the same throttling behavior as the rest of Graph; bulk membership or channel operations across many teams should batch and back off rather than looping tightly.

---

## 6. Authentication patterns for unattended scripts

This is worth stating once, plainly, because it's the single most common security finding across Exchange/SharePoint/Teams/Graph scripts alike:

**Acceptable for unattended/scheduled automation, in order of preference:**
1. **Managed identity** (when running inside Azure — Automation, Functions, VMs) — no secret to manage at all.
2. **Certificate-based app-only authentication** — the certificate can be stored in a machine cert store or Key Vault; no password ever appears in the script.
3. **A client secret retrieved from a proper secret store at runtime** (Azure Key Vault, `Microsoft.PowerShell.SecretManagement`) — acceptable but weaker than a certificate, since secrets are easier to accidentally leak into logs or version control.

**Not acceptable, and worth a Critical or High finding every time:**
- A plaintext password or client secret embedded directly in the script.
- A credential file sitting next to the script with a "don't commit this" comment and no actual access control.
- `ConvertTo-SecureString -AsPlainText -Force` fed from a literal string in the script — this doesn't protect anything, it just launders a plaintext secret through a `SecureString` object for the rest of the script's runtime.
- Global Admin or tenant-wide Owner-equivalent rights granted to a service principal that only needs a narrow, specific operation.

---

## 7. Throttling, pagination, and bulk operations — quick reference

| Symptom | Likely cause | Fix |
|---|---|---|
| Script works against a handful of test objects, fails at scale with HTTP 429 | No retry/backoff on Graph or Exchange calls | Catch 429 specifically, honor `Retry-After`, exponential backoff otherwise |
| Script reports far fewer users/devices/items than actually exist | Missing `-All` on a Graph cmdlet, or unpaged retrieval of a large SharePoint list | Add `-All` / implement proper paging (`@odata.nextLink` handling if using raw `Invoke-MgGraphRequest`) |
| Bulk mailbox reporting is extremely slow | Using RPS-backed `Get-Mailbox`/`Get-Recipient` per-user in a loop | Switch to REST-backed `Get-EXO*` cmdlets designed for bulk reads |
| Hundreds of individual Graph calls in a loop | No batching | Use Graph's `$batch` JSON batching (up to 20 requests per call) where the SDK or a raw request supports it |
