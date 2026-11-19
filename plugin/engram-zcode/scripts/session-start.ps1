# Engram ZCode plugin - SessionStart hook (startup | resume | clear).
# Injects the Engram memory protocol and, when the local server is reachable,
# the project's recent memory context.
# Fail-open: every failure path exits 0 so a hook can never block a session.
. "$PSScriptRoot\_common.ps1"

$hookInput = Read-HookInput
$sections = @()

try {
    $protocolPath = Join-Path $PSScriptRoot '..\protocol.md'
    if (Test-Path -LiteralPath $protocolPath) {
        $protocol = Get-Content -LiteralPath $protocolPath -Raw -Encoding UTF8
        if ($protocol) { $sections += $protocol.TrimEnd() }
    }
} catch { }

try {
    $context = Get-EngramContextText -HookInput $hookInput
    if ($context) {
        $sections += "## Recent project memory context`n`n$($context.TrimEnd())"
    }
} catch { }

if ($sections.Count -gt 0) {
    Write-HookResult -EventName 'SessionStart' -AdditionalContext ($sections -join "`n`n")
}

exit 0
