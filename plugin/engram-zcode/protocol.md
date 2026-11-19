# Engram Memory Protocol

You have persistent shared memory via Engram MCP tools (mem_*). Engram is also used by other agents (e.g. Codex) on this machine, so treat it as the shared source of truth for durable knowledge. Memory operations are internal bookkeeping: never end your turn with them, and never let them replace the user-facing answer.

## Orient first
- At the start of related work, call mem_context to recover recent history; call mem_current_project when you need to confirm the resolved project.
- Before revisiting a decision, bug, or convention, search first with focused terms: mem_search for candidates, mem_timeline for surrounding session context, and mem_get_observation before relying on full content. Search results are previews, not the complete record.

## Pinned memories
Pinned observations are injected automatically at session start (a "### Pinned" block in the memory context) — no search needed. Pin small, durable, always-useful knowledge: index/pointer memories, user profiles, standing rules. Use mem_search to find the numeric id, then mem_pin to pin (mem_unpin to remove). Keep the pinned set small (roughly 3-8 per project) — it is paid on every session. Pin state is local to this device and is not synced.

## What to save
Save only verified, durable, costly-to-reconstruct knowledge:
- completed bug fixes with root cause
- decisions with their rationale
- discoveries and key constraints
- configuration changes
- reusable patterns
- durable user preferences and constraints

**Credentials policy (user decision, overrides the upstream no-secrets default):** secrets and credentials MAY be saved. Keep them local-only — never enable Git Sync or Engram Cloud. Put credential-bearing memories in personal or global scope (not project buckets) and mark them with 【含凭据】 plus source and purpose so they can be audited later. Still do NOT save: speculation, raw tool output, routine progress, or duplicates of existing memories.

## Save format
mem_save takes:
- a short, verb-based, searchable title
- type: bugfix | decision | architecture | discovery | pattern | config | preference
- scope: project (default)
- optional topic_key for evolving topics
- content in four fields: What / Why / Where / Learned

## Evolving topics
Give an evolving subject a stable topic_key (e.g. architecture/auth-model). Before writing, search that topic; read candidates fully via mem_get_observation (previews do not count as identity evidence); update the same observation by ID, preserving still-valid facts. Use a distinct topic_key for genuinely new topics. If a lookup fails or identity is ambiguous, do not overwrite: a failed read is not evidence of absence.

## Session close and handoff
At explicit closure or handoff, save mem_session_summary with: goal, instructions, discoveries, accomplished work, next steps, and relevant files. Ordinary turn completion is not a closure.

## After compaction
If context was reset or compacted: first persist the summary with mem_session_summary, then call mem_context to recover recent history, and only then continue the task.

## Reliability
- If memory tools fail or are unavailable, say so briefly and continue the task; never fabricate memory IDs or session IDs.
- Do not invent session_id values; leave session binding to the host.
