---
name: engram-memory
description: ALWAYS ACTIVE - persistent shared memory via Engram MCP tools (mem_*). Use at session start to recover project context; save verified durable knowledge after bugfixes, decisions, discoveries, config changes, and patterns; search before repeating prior work; close sessions with mem_session_summary; follow the recovery sequence after compaction.
---

# Engram Memory

You have access to Engram persistent shared memory through MCP tools named `mem_*` (e.g. `mem_context`, `mem_search`, `mem_save`, `mem_session_summary`). Tools may appear namespaced by the host (e.g. `mcp__engram__mem_save`); use whatever names the host exposes.

This memory is shared with other agents on this machine (Codex etc.), so saved knowledge must stay accurate and deduplicated. The same protocol is injected at every session start by this plugin's SessionStart hook.

## Operating contract (canonical copy: protocol.md)

### Orient first
- At the start of related work, call mem_context to recover recent history; call mem_current_project when you need to confirm the resolved project.
- Before revisiting a decision, bug, or convention, search first with focused terms: mem_search for candidates, mem_timeline for surrounding session context, and mem_get_observation before relying on full content. Search results are previews, not the complete record.

### Pinned memories
Pinned observations are injected automatically at session start (a "### Pinned" block in the memory context) — no search needed. Pin small, durable, always-useful knowledge (index/pointer memories, user profiles, standing rules): mem_search for the numeric id, then mem_pin (mem_unpin to remove). Keep the set small (~3-8 per project); pin state is local-only, not synced.

### What to save
Save only verified, durable, costly-to-reconstruct knowledge: completed bug fixes with root cause, decisions with rationale, discoveries and key constraints, configuration changes, reusable patterns, durable user preferences and constraints.
Credentials policy (user decision, overrides upstream): secrets/credentials MAY be saved — local-only (never enable Git Sync / Engram Cloud), in personal or global scope, marked 【含凭据】 with source and purpose. Still do NOT save: speculation, raw tool output, routine progress, or duplicates of existing memories.

### Save format
mem_save takes a short verb-based searchable title, a type (bugfix | decision | architecture | discovery | pattern | config | preference), scope (project default), optional topic_key, and content: What / Why / Where / Learned.

### Evolving topics
Give an evolving subject a stable topic_key. Before writing, search the topic; read candidates fully via mem_get_observation (previews do not count); update the same observation by ID, preserving still-valid facts. If lookup fails or identity is ambiguous, do not overwrite: a failed read is not evidence of absence.

### Session close and handoff
At explicit closure or handoff, save mem_session_summary with: goal, instructions, discoveries, accomplished work, next steps, relevant files. Ordinary turn completion is not a closure.

### After compaction
First persist the summary with mem_session_summary, then call mem_context to recover recent history, then continue.

### Reliability
If memory tools fail, say so briefly and continue the task; never fabricate memory IDs or session IDs. Leave session binding to the host.

## Tool quick reference

| Intent | Start with |
| --- | --- |
| Confirm the resolved project | mem_current_project |
| Recover recent work | mem_context |
| Find prior knowledge | mem_search, then mem_timeline, then mem_get_observation |
| Pin/unpin always-visible memory | mem_pin / mem_unpin (numeric id from mem_search) |
| Save durable knowledge | mem_save (What/Why/Where/Learned + type + optional topic_key) |
| Update an evolving topic | mem_update (with expected_project) |
| Close or hand off a session | mem_session_summary |
| Diagnose store or project state | mem_doctor |

## Delivery guarantee
Memory operations are internal bookkeeping. The final user-facing answer must be the turn's last message, with no memory tool calls after it.
