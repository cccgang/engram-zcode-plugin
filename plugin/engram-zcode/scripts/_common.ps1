# Shared helpers for Engram ZCode plugin hooks.
# ASCII only. Every helper fails safe: callers never throw because of these.

function Get-EngramExe {
    if ($env:ENGRAM_BIN -and (Test-Path -LiteralPath $env:ENGRAM_BIN)) { return $env:ENGRAM_BIN }
    $cmd = Get-Command engram -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $fallback = 'D:\个人\agent-memory\bin\engram.exe'
    if (Test-Path -LiteralPath $fallback) { return $fallback }
    return $null
}

function Get-HookSessionId {
    param($HookInput)
    if ($HookInput -and $HookInput.session_id) { return [string]$HookInput.session_id }
    if ($env:CLAUDE_SESSION_ID) { return $env:CLAUDE_SESSION_ID }
    if ($env:ZCODE_SESSION_ID) { return $env:ZCODE_SESSION_ID }
    return $null
}

function Get-EngramBaseUrl {
    if ($env:ENGRAM_URL) { return $env:ENGRAM_URL.TrimEnd('/') }
    $port = if ($env:ENGRAM_PORT) { $env:ENGRAM_PORT } else { '7437' }
    return "http://127.0.0.1:$port"
}

function Test-EngramServer {
    param([string]$BaseUrl, [int]$TimeoutSec = 2)
    try {
        $null = Invoke-RestMethod -Uri "$BaseUrl/health" -TimeoutSec $TimeoutSec -ErrorAction Stop
        return $true
    } catch { return $false }
}

function Start-EngramServerIfNeeded {
    param([string]$BaseUrl, [int]$WaitMs = 1500)
    if (Test-EngramServer -BaseUrl $BaseUrl) { return $true }
    try {
        Start-Process -FilePath 'engram' -ArgumentList 'serve' -WindowStyle Hidden -ErrorAction Stop
    } catch { return $false }
    $deadline = (Get-Date).AddMilliseconds($WaitMs)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 250
        if (Test-EngramServer -BaseUrl $BaseUrl -TimeoutSec 1) { return $true }
    }
    return $false
}

function Read-HookInputRaw {
    # Read stdin as UTF-8 regardless of the console code page. PowerShell 5.1's
    # [Console]::In uses the console encoding (GB2312 here), which corrupts
    # non-ASCII JSON fields such as cwd or tool_input sent by the host.
    try {
        $stdin = [Console]::OpenStandardInput()
        $reader = New-Object System.IO.StreamReader($stdin, [System.Text.Encoding]::UTF8, $true)
        return $reader.ReadToEnd()
    } catch { return '' }
}

function Read-HookInput {
    try {
        $raw = Read-HookInputRaw
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json)
    } catch { return $null }
}

function Write-Utf8Output {
    # Write UTF-8 bytes directly: [Console]::Out uses the console code page and
    # would corrupt non-ASCII hook output for the host's JSON parser.
    param([string]$Text)
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $stdout = [Console]::OpenStandardOutput()
        $stdout.Write($bytes, 0, $bytes.Length)
        $stdout.Flush()
    } catch { }
}

function Get-EngramProjectName {
    param($HookInput)
    if ($env:ENGRAM_PROJECT) { return $env:ENGRAM_PROJECT }
    $cwd = $null
    if ($HookInput -and $HookInput.cwd) { $cwd = [string]$HookInput.cwd }
    if (-not $cwd) { $cwd = (Get-Location).Path }
    # Nearest .engram/config.json project_name wins, mirroring Engram's own
    # repo/subproject config resolution, so hook context lookups hit the same
    # project bucket that MCP writes use.
    try {
        $dir = Get-Item -LiteralPath $cwd -ErrorAction Stop
        for ($i = 0; $i -lt 8 -and $dir; $i++) {
            $cfgPath = Join-Path $dir.FullName '.engram\config.json'
            if (Test-Path -LiteralPath $cfgPath) {
                $cfg = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($cfg -and $cfg.project_name) { return [string]$cfg.project_name }
            }
            $dir = $dir.Parent
        }
    } catch { }
    try { return (Split-Path -Leaf ($cwd.TrimEnd('\', '/'))) } catch { return $null }
}

function Get-EngramContextText {
    param($HookInput)
    $base = Get-EngramBaseUrl
    if (-not (Start-EngramServerIfNeeded -BaseUrl $base)) { return $null }
    $project = Get-EngramProjectName -HookInput $HookInput
    if (-not $project) { return $null }
    $wc = $null
    try {
        $encoded = [Uri]::EscapeDataString($project)
        # PowerShell 5.1's Invoke-RestMethod decodes a charset-less
        # application/json response as ISO-8859-1, turning UTF-8 Chinese into
        # mojibake. Engram's /context returns UTF-8 without a charset parameter,
        # so fetch it with WebClient and decode explicitly as UTF-8.
        $wc = New-Object System.Net.WebClient
        $wc.Encoding = [System.Text.Encoding]::UTF8
        # Explicitly request the Pinned section (curated always-visible memories)
        # and cap the payload size, so passive recall does not depend on version
        # defaults and injection stays bounded. The server clamps max_bytes to
        # 65536, truncates UTF-8-safely, and silently ignores bad values.
        $json = $wc.DownloadString("$base/context?project=$encoded&pinned=10&max_bytes=65536")
        $resp = $json | ConvertFrom-Json
        if ($resp -is [string]) { return $resp }
        if ($resp.context) { return [string]$resp.context }
        if ($resp -is [System.Management.Automation.PSCustomObject]) {
            return ($resp | ConvertTo-Json -Depth 4 -Compress)
        }
        return $null
    } catch { return $null }
    finally { if ($wc) { $wc.Dispose() } }
}

function Write-HookResult {
    param([string]$EventName, [string]$AdditionalContext)
    try {
        $payload = @{
            hookSpecificOutput = @{
                hookEventName     = $EventName
                additionalContext = $AdditionalContext
            }
        }
        $json = $payload | ConvertTo-Json -Depth 4 -Compress
        Write-Utf8Output -Text $json
    } catch { }
}

# Ensure hooks target the intended local store even when the parent process
# (ZCode, a terminal) started before the user-level ENGRAM_DATA_DIR existed.
# Without this, serve auto-start and hook transformers would resolve the
# default store and either split the database or deny writes.
function Initialize-EngramEnv {
    if ($env:ENGRAM_DATA_DIR) { return }
    $fallback = 'D:\个人\agent-memory\data'
    if (Test-Path -LiteralPath $fallback) { $env:ENGRAM_DATA_DIR = $fallback }
}

Initialize-EngramEnv

