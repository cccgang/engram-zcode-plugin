# Engram ZCode plugin - PreToolUse guard for write/session-class mem_* tools.
# Forwards the hook payload to `engram hook claude-pre-tool-use`, which binds the
# host session id into updatedInput. The transformer output is already in the
# shape ZCode accepts (hookSpecificOutput.permissionDecision / updatedInput).
# Fail-open: any local failure (missing binary, invalid output, server down)
# allows the call so a broken guard can never block memory writes.
. "$PSScriptRoot\_common.ps1"

$raw = Read-HookInputRaw

if ($env:ENGRAM_ZCODE_DEBUG) {
    try {
        $logDir = Join-Path $env:TEMP 'engram-zcode'
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        Add-Content -LiteralPath (Join-Path $logDir 'pretooluse-input.log') -Encoding UTF8 -Value ("[{0}] {1}" -f (Get-Date -Format o), $raw)
    } catch { }
}

$inputObj = $null
try {
    if (-not [string]::IsNullOrWhiteSpace($raw)) { $inputObj = $raw | ConvertFrom-Json }
} catch { }

$sessionId = Get-HookSessionId -HookInput $inputObj
$toolName = $null
if ($inputObj -and $inputObj.tool_name) { $toolName = [string]$inputObj.tool_name }
if (-not $sessionId -or -not $toolName) { exit 0 }

$exe = Get-EngramExe
if (-not $exe) { exit 0 }

$cwd = $null
if ($inputObj -and $inputObj.cwd) { $cwd = [string]$inputObj.cwd } else { $cwd = (Get-Location).Path }
$toolInput = $null
if ($inputObj -and $inputObj.tool_input) { $toolInput = $inputObj.tool_input } else { $toolInput = @{} }

$payload = @{
    session_id      = $sessionId
    cwd             = $cwd
    hook_event_name = 'PreToolUse'
    tool_name       = $toolName
    tool_input      = $toolInput
} | ConvertTo-Json -Depth 8 -Compress

$out = $null
try {
    $out = $payload | & $exe hook claude-pre-tool-use 2>$null
} catch { exit 0 }
if (-not $out) { exit 0 }
$text = ($out -join "`n")
if ([string]::IsNullOrWhiteSpace($text)) { exit 0 }

$parsed = $null
try { $parsed = $text | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }

# Honor an explicit deny only while the local server is healthy; a deny caused by
# server/registration trouble must not block writes (fail-open).
$decision = $null
if ($parsed.hookSpecificOutput -and $parsed.hookSpecificOutput.permissionDecision) {
    $decision = [string]$parsed.hookSpecificOutput.permissionDecision
}
if ($decision -eq 'deny') {
    $base = Get-EngramBaseUrl
    if (-not (Test-EngramServer -BaseUrl $base -TimeoutSec 1)) { exit 0 }
}

Write-Utf8Output -Text $text
exit 0
