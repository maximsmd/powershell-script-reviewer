#!/usr/bin/env bash
# Runs Microsoft's official PSScriptAnalyzer (the static analyzer behind the
# PowerShell extension in VS Code) against a script and prints JSON findings.
#
# Usage: run_script_analyzer.sh /path/to/script.ps1
#
# Design goal: never fail loudly. If pwsh isn't installed, or the PowerShell
# Gallery isn't reachable, print a small JSON object saying so and exit 0 --
# the reviewer should fall back to manual review, not crash.

set -u

SCRIPT_PATH="${1:-}"

if [ -z "$SCRIPT_PATH" ]; then
  echo '{"available": false, "reason": "no script path provided"}'
  exit 0
fi

if [ ! -f "$SCRIPT_PATH" ]; then
  echo "{\"available\": false, \"reason\": \"file not found: ${SCRIPT_PATH}\"}"
  exit 0
fi

if ! command -v pwsh >/dev/null 2>&1; then
  echo '{"available": false, "reason": "pwsh (PowerShell 7+) is not installed in this environment"}'
  exit 0
fi

pwsh -NoProfile -NonInteractive -Command "
    \$ErrorActionPreference = 'Stop'
    try {
        if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
            Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser -ErrorAction Stop | Out-Null
        }
        Import-Module PSScriptAnalyzer -ErrorAction Stop

        \$results = Invoke-ScriptAnalyzer -Path '$SCRIPT_PATH' -Severity Error,Warning,Information

        if (-not \$results) {
            '{\"available\": true, \"findings\": []}'
        } else {
            \$payload = @{
                available = \$true
                findings  = @(\$results | ForEach-Object {
                    @{
                        rule     = \$_.RuleName
                        severity = \$_.Severity.ToString()
                        line     = \$_.Line
                        message  = \$_.Message
                    }
                })
            }
            \$payload | ConvertTo-Json -Depth 5
        }
    }
    catch {
        @{ available = \$false; reason = \"PSScriptAnalyzer could not run: \$(\$_.Exception.Message)\" } | ConvertTo-Json
    }
"
