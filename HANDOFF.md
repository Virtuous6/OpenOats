# OpenOats (Fork) — Handoff
**Date:** 2026-03-26
**Session:** Shipped 5 PRs (DTLN-AEC, retranscribe, notepad, intel hardening, intelligence panel), rebuilt twice

---

## TL;DR

All custom work on `main`, 315 tests pass, intelligence panel with 4 modes (off/passive/query/analyze) is built and installed. DTLN-AEC integrated. Ready for live Zoom testing.

---

## What's Done (This Session)

- **Merged `joe/live-notepad` → `main`** — fast-forward, all custom code now on `main`
- **PR #1: DTLN-AEC echo cancellation** — `Audio/EchoCanceller.swift`, wired into `TranscriptionEngine`. Neural AEC replaces force-disabled Apple AEC.
- **PR #2: Notepad fixes** — `Views/OverlayPanel.swift` — normal window level + resizable
- **PR #3: Re-transcribe button** — `App/NotesController.swift` + `Views/NotesView.swift` — wand.and.stars button, progress, transcript reload
- **PR #4: Intelligence hardening** — 6 fixes: gate before KB, 30s timeout, circuit breaker, heuristic skip, parallel embeddings, model fix
- **PR #5: Intelligence panel** — `Intelligence/IntelligenceEngine.swift` + `Views/IntelligencePanelView.swift`. 4-mode panel replaces fixed suggestions section. SuggestionEngine gated on mode == .passive.
- **Credential validation** — `hasValidCredentials` guard on query/analyze. Shows error instead of 401.
- **Raised transcript context** — 50 → 200 utterances for query/analyze (~100 min coverage)
- **18 new tests** — `Tests/OpenOatsTests/IntelligenceEngineTests.swift` covering all intelligence flows
- **Cleaned up** — all worktrees removed, all feature branches deleted, 315 tests pass
- **Built and installed twice** — `/Applications/OpenOats.app` has latest code
- **Updated memory** — `project_openoats_intelligence_vision.md` + `reference_openoats_transcripts.md` updated with all new features and future roadmap

---

## What's Next

### Priority 1: Test DTLN-AEC + dihard3 Live
**What:** Zoom call without headphones. Check `/tmp/openoats.log` for `[ENGINE-AEC]`. Compare speaker attribution.
**Files:** Logs only
**Depends on:** Joe relaunching OpenOats

### Priority 2: Test Intelligence Panel Live
**What:** Use Query and Analyze modes during a real meeting. Verify responses are useful.
**Files:** None — testing only
**Depends on:** Nothing

### Priority 3: Query + Vault Context
**What:** Wire KB search into query mode so "What did we decide about X?" searches vault + transcript, not just transcript. Reuse `KnowledgeBase.search()` from passive pipeline.
**Files:** `Intelligence/IntelligenceEngine.swift`
**Depends on:** Nothing

### Priority 4: Analyze → Persist to TaskNotes
**What:** "Save" button on analyze results that writes action items/decisions to TaskNotes API or triage board. Bridges real-time → PA routing.
**Files:** `Views/IntelligencePanelView.swift`, new persistence logic
**Depends on:** TaskNotes API running (Obsidian open)

### Priority 5: Headphone Detection
**What:** Skip AEC when headphones connected via CoreAudio transport type
**Files:** `Transcription/TranscriptionEngine.swift` or new utility
**Depends on:** Nothing

### Priority 6: Upstream Merge (1.30.2 → 1.32.2)
**What:** Audio playback, auto-stop, per-model flush intervals, download progress bar. Conflicts in `SessionRepository.swift` + `LiveNotePadView.swift`.
**Depends on:** Nothing, but test DTLN-AEC first

### Priority 7: Fix Passive Triggers + Prompts
**What:** Loosen hardcoded phrase matching (LLM-based or periodic). Rewrite all 4 prompts with examples, schemas, score anchoring.
**Files:** `Intelligence/SuggestionEngine.swift` (triggers + 3 prompts), `Intelligence/NoteMergeEngine.swift` (1 prompt)
**Depends on:** Nothing

### Priority 8: Contact-Aware Prompts + Prior Meeting Context
**What:** Inject attendee contact cards into analyze prompts. Search prior sessions by attendee/topic.
**Files:** `Intelligence/IntelligenceEngine.swift`
**Depends on:** Contact cards exist, calendar integration

---

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| Intelligence panel replaces suggestions, not alongside | One surface, multiple modes — simpler UX than two panels |
| Default mode is Off | Zero LLM cost until user opts in. Transcript still records. |
| IntelligenceEngine separate from SuggestionEngine | Different paradigms: on-demand vs auto-pipeline. Shared OpenRouterClient but independent state. |
| SuggestionEngine gated via weak ref to IntelligenceEngine | Avoids circular dependency. Gate check is one line. |
| 200-utterance transcript window | ~100 min coverage. On-demand queries control cost. Can layer running summary later. |
| Credential check is synchronous, before Task | Immediate user feedback, no wasted HTTP request |
| Responses accumulate per session, no auto-clear | User sees history of queries/analyses. `clearResponses()` exists if needed. |

## Tech Debt

- **Mode doesn't persist across restart** — defaults to Off. Could store in UserDefaults if desired.
- **Responses not persisted** — lost on app restart. Fine for now (meeting-length lifecycle).
- **Speaker labels in transcript context** — diarized speakers show as "remote_0" not real names. Functional but ugly for LLM context.
- **Video lag during batch transcription** — WhisperKit saturates ANE/GPU
- **Magic number gate thresholds** — should be named constants
- **Dead fields** in Suggestion model — tracked but never displayed

---

## Blockers

None.

---

## Open Questions

1. Did DTLN-AEC + dihard3 improve speaker attribution on Zoom? (needs live test)
2. Is 200 utterances enough or should we add running summary for very long meetings?
3. Should passive mode work without KB? (currently requires KB hit above 0.35)
4. Upstream deleted `LiveNotePadView.swift` — why? Check before merge.
5. `joe/fix-suggestion-trigger` branch still on remote — stale? Delete?

---

## Key Files

| File | Purpose |
|------|---------|
| `Intelligence/IntelligenceEngine.swift` | NEW — query + analyze modes, credential validation, 200-utterance context |
| `Views/IntelligencePanelView.swift` | NEW — mode picker tabs + mode-specific UI (off/passive/query/analyze) |
| `Audio/EchoCanceller.swift` | NEW — DTLN-AEC wrapper with resampling |
| `Intelligence/SuggestionEngine.swift` | Gate on mode == .passive, heuristic skip, gate before KB |
| `Intelligence/OpenRouterClient.swift` | 30s timeout + circuit breaker |
| `Intelligence/KnowledgeBase.swift` | Parallel embedding batches |
| `Intelligence/TranscriptRefinementEngine.swift` | Uses user's selectedModel (was hardcoded gpt-4o-mini) |
| `Transcription/TranscriptionEngine.swift` | AEC wiring + transformedStream helper |
| `App/NotesController.swift` | Re-transcribe logic |
| `Views/NotesView.swift` | Re-transcribe button UI |
| `Views/OverlayPanel.swift` | Notepad normal level + resizable |
| `Tests/OpenOatsTests/IntelligenceEngineTests.swift` | NEW — 18 tests for intelligence flows |
| `Package.swift` | dtln-aec-coreml dependency (branch: main) |

---

## Suggested Next Session Flow

1. `/pickup` — prime on OpenOats
2. Confirm DTLN-AEC + dihard3 test results from Zoom call
3. Confirm intelligence panel UX feedback from live use
4. Wire KB search into query mode (Priority 3)
5. Add "Save" button on analyze results → TaskNotes (Priority 4)
6. Headphone detection (Priority 5)
7. Upstream merge 1.30.2 → 1.32.2 (Priority 6)
8. Fix passive triggers + rewrite prompts (Priority 7)
9. `/handoff`
