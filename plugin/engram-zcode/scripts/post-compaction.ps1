# Engram ZCode plugin - SessionStart(compact) hook.
# After compaction: persist the handoff first, then recover context.
# Fail-open: every failure path exits 0 so a hook can never block a session.
. "$PSScriptRoot\_common.ps1"

$hookInput = Read-HookInput
$lines = @(
    'Context was compacted. Follow the Engram recovery sequence now:',
    '1. Immediately persist the compacted handoff with mem_session_summary (goal, instructions, discoveries, accomplished work, next steps, relevant files).',
    '2. Then call mem_context to recover recent session history.',
    '3. Resume the original task; do not ask the user to repeat context that Engram can recall.'
)

try {
    $context = Get-EngramContextText -HookInput $hookInput
    if ($context) {
        $lines += ''
        $lines += '## Recent project memory context'
        $lines += ''
        $lines += $context.TrimEnd()
    }
} catch { }

Write-HookResult -EventName 'SessionStart' -AdditionalContext ($lines -join "`n")
exit 0
