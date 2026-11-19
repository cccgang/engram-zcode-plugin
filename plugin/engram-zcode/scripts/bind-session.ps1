# Engram ZCode plugin - SessionStart session binding.
# Registers the host session with the local Engram server so write tools are
# attributed to this session (see `engram hook claude-bind-session`).
# Fail-open: silently exits 0 on any failure.
. "$PSScriptRoot\_common.ps1"

$hookInput = Read-HookInput
$sessionId = Get-HookSessionId -HookInput $hookInput
if (-not $sessionId) { exit 0 }

$exe = Get-EngramExe
if (-not $exe) { exit 0 }

$cwd = $null
if ($hookInput -and $hookInput.cwd) { $cwd = [string]$hookInput.cwd } else { $cwd = (Get-Location).Path }

$payload = @{
    session_id      = $sessionId
    cwd             = $cwd
    hook_event_name = 'SessionStart'
    source          = 'startup'
} | ConvertTo-Json -Depth 6 -Compress

try {
    $out = $payload | & $exe hook claude-bind-session 2>$null
    if ($out) { Write-Utf8Output -Text ($out -join "`n") }
} catch { }

exit 0
