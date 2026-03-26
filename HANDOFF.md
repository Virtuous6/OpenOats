# OpenOats (Fork) — Handoff
**Date:** 2026-03-26
**Session:** Merged live-notepad into main, shipped 4 feature PRs via parallel worktrees

---

## TL;DR

All custom work merged to `main`, 4 new PRs shipped (DTLN-AEC, re-transcribe button, notepad fixes, intelligence hardening), app rebuilt and installed — ready for live Zoom testing.

---

## What's Done (This Session)

- **Merged `joe/live-notepad` → `main`** — fast-forward merge, pushed to origin. All custom code (live notepad, mirror, note merge) now on `main`
- **PR #1: DTLN-AEC neural echo cancellation** — `EchoCanceller.swift` wraps dtln-aec-coreml (256-unit model), wired into `TranscriptionEngine`. System audio feeds far-end, mic audio transformed before transcription. Recording gets raw audio, transcriber gets cleaned audio
- **PR #2: Notepad panel fixes** — `OverlayPanel.swift` changed from `.nonactivatingPanel` + floating to `.resizable` + `.normal` level. No longer always-on-top, now resizable
- **PR #3: Re-transcribe button** — `NotesController.swift` + `NotesView.swift`. "Re-transcribe" button (wand.and.stars icon) in Notes toolbar. Checks audio availability on session select, runs BatchTranscriptionEngine, shows progress, reloads transcript on completion
- **PR #4: Intelligence hardening** — 6 fixes across `SuggestionEngine`, `OpenRouterClient`, `KnowledgeBase`, `TranscriptRefinementEngine`: gate before KB, 30s timeout, circuit breaker, heuristic skip, parallel embeddings, model fix
- **Cleaned up** — all 4 worktrees removed, all feature branches deleted (local + remote), `joe/fix-suggestion-trigger` still exists (pre-existing)
- **Built and installed** — `SKIP_SIGN=1 scripts/build_swift_app.sh` → `/Applications/OpenOats.app`

---

## What's Next

### Priority 1: Test DTLN-AEC Live
**What:** Do a Zoom call without headphones. Check `/tmp/openoats.log` for `[ENGINE-AEC]` entries. Compare speaker attribution before/after. Verify `dihard3` variant helps.
**Files:** Check logs only — no code changes
**Depends on:** Joe relaunching OpenOats after build

### Priority 2: Headphone Detection
**What:** Detect headphone state via CoreAudio transport type. Skip AEC when headphones connected (no echo to cancel, saves CPU).
**Files:** New utility or add to `TranscriptionEngine.swift`
**Depends on:** Nothing

### Priority 3: Upstream Merge (1.30.2 → 1.32.2)
**What:** `git fetch upstream && git merge upstream/main`. Manual conflict resolution needed in `SessionRepository.swift` (keep our mirror logic) and `LiveNotePadView.swift` (upstream deleted it, we keep it).
**Key upstream features:** Audio playback in Notes window, auto-stop when meeting app exits, per-model flush intervals (Whisper 10s, Parakeet/Qwen 5s), download progress bar
**Depends on:** Nothing, but test DTLN-AEC first to avoid compounding unknowns

### Priority 4: Rewrite LLM Prompts
**What:** All 4 intelligence prompts (state update, gate, generation, note merge) need concrete examples, schema specs, edge case handling, gate score anchoring, format matching `parseBullets()`, length constraints for headlines
**Files:** `Intelligence/SuggestionEngine.swift` (3 prompts), `Intelligence/NoteMergeEngine.swift` (1 prompt)
**Depends on:** Pipeline hardening done (P4 shipped)

### Priority 5: Fix Suggestion Trigger Detection
**What:** Loosen hardcoded phrase matching — LLM-based or periodic trigger
**Files:** `Intelligence/SuggestionEngine.swift:239-320`
**Depends on:** Clean speaker attribution (DTLN-AEC shipped, needs testing)

### Priority 6: Tests for Custom Code
**What:** EchoCanceller, UserNote, LiveNoteStore, mirror logic, re-transcribe flow, notepad panel — no coverage yet
**Files:** `Tests/OpenOatsTests/`
**Depends on:** Nothing

### Priority 7: Intelligence Vision (Future)
**What:** Transform suggestions panel from passive-only to 3-mode intelligence surface: passive (tune), active LLM query (type question mid-meeting), analytical prompts (one-click "suggest questions")
**Depends on:** Priorities 4-5 (prompts + triggers fixed first)

---

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| Merge `joe/live-notepad` → `main` before branching features | Clean baseline for PRs, avoids branching off a feature branch |
| Use git worktrees for parallel feature development | 4 independent features, dispatch agents in parallel, proper PR workflow |
| DTLN-AEC uses `branch: "main"` not semver | No stable release yet (all beta tags), `main` is latest |
| EchoCanceller outputs 16kHz buffers | StreamingTranscriber already resamples to 16kHz internally — AEC output takes the fast path, no double resampling |
| Recording taps placed before AEC | Raw audio preserved in mic.caf/sys.caf for re-transcription; transcriber gets cleaned audio |
| Gate moved before KB retrieval | Saves Voyage API calls — if gate rejects, KB search never fires |
| Circuit breaker on OpenRouterClient actor | Actor-isolated state is clean, exponential backoff prevents hammering broken endpoints |

## Tech Debt

- **Video lag during batch transcription** — WhisperKit large-v3-turbo saturates ANE/GPU via CoreML. Consider lower priority or idle detection.
- **Magic number gate thresholds** (0.72, 0.75, 0.70, 0.65) — should be named constants
- **Dead fields**: `Suggestion.summarySnapshot`, `SuggestionDecision.reason`, `Suggestion.feedback` — tracked but never used
- **No correlation IDs** on LLM calls — hard to trace a suggestion's pipeline journey
- **Crude transcript truncation** in NoteMergeEngine (head+tail, drops middle)
- **Pre-existing warnings** — `StreamingTranscriber` SendableClosureCaptures, unnecessary `nonisolated(unsafe)` on DiarizationManager, unused `noteTimestamps` in NoteMergeEngine

---

## Blockers

None.

---

## Open Questions

1. Did `dihard3` actually improve speaker attribution on Joe's Zoom calls? (needs live testing)
2. DTLN-AEC convergence ~0.3s — acceptable for first utterance?
3. System audio from process tap — always 16kHz or variable? (EchoCanceller handles resampling either way, but good to know)
4. Upstream deleted `LiveNotePadView.swift` — moved elsewhere or just removed? Check before merge.
5. `joe/fix-suggestion-trigger` branch still exists on remote — stale? Delete?

---

## Key Files

| File | Purpose |
|------|---------|
| `Sources/OpenOats/Audio/EchoCanceller.swift` | NEW — DTLN-AEC wrapper with resampling |
| `Sources/OpenOats/Transcription/TranscriptionEngine.swift` | AEC wiring: model load, system feed, mic transform |
| `Sources/OpenOats/App/NotesController.swift` | Re-transcribe logic + status tracking |
| `Sources/OpenOats/Views/NotesView.swift` | Re-transcribe button UI |
| `Sources/OpenOats/Views/OverlayPanel.swift` | Notepad panel window level + resizable fix |
| `Sources/OpenOats/Intelligence/SuggestionEngine.swift` | Gate reorder + heuristic skip |
| `Sources/OpenOats/Intelligence/OpenRouterClient.swift` | Timeout + circuit breaker |
| `Sources/OpenOats/Intelligence/KnowledgeBase.swift` | Parallel embedding batches |
| `Sources/OpenOats/Intelligence/TranscriptRefinementEngine.swift` | Model fix (reads user setting) |
| `Package.swift` | Added dtln-aec-coreml dependency |

---

## Suggested Next Session Flow

1. `/pickup` — prime on OpenOats
2. Confirm Joe tested DTLN-AEC live — did speaker attribution improve?
3. If yes: add headphone detection (skip AEC when headphones connected)
4. Upstream merge 1.30.2 → 1.32.2 (resolve SessionRepository + LiveNotePadView conflicts)
5. Rewrite LLM prompts with examples, schemas, and score anchoring
6. Fix suggestion trigger detection (LLM-based or periodic)
7. Write tests for all custom code (EchoCanceller, re-transcribe, mirror, notepad)
8. `/handoff`
