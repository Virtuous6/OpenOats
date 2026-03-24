# OpenOats (Fork) — Handoff
**Date:** 2026-03-24
**Session:** Forked OpenOats, fixed suggestions, built live notepad backend

---

## TL;DR

Fork at `Virtuous6/OpenOats` with suggestion fix on main and live notepad backend on `joe/live-notepad` — frontend view integration is the only remaining work.

---

## What's Done (This Session)

- Forked `yazinsai/OpenOats` → `Virtuous6/OpenOats` (origin=fork, upstream=original)
- Fixed suggestion engine: removed `isRemote` gate so suggestions fire on all utterances (merged to main)
- Built live notepad feature backend (branch `joe/live-notepad`, pushed):
  - `UserNote.swift` — immutable timestamped note model with elapsed label
  - `LiveNoteStore.swift` — @Observable in-memory store (start/append/stop/clear)
  - `NoteMergeEngine.swift` — LLM merge engine (user notes + transcript → enriched markdown, ±30s window correlation)
  - `LiveNotePadView.swift` — SwiftUI floating panel (note list + text input + save)
  - `SessionRepository.swift` — added `appendUserNote`/`loadUserNotes`/`hasUserNotes` (persists to `user-notes.jsonl`)
  - `AppCoordinator.swift` — added `liveNoteStore` property
  - `LiveSessionController.swift` — added `saveQuickNote()`, lifecycle wiring (start/stop/discard), `userNotes`/`hasUserNotes` in state projection
- 289 tests pass, zero new failures
- Built + installed to `/Applications/OpenOats.app`
- Created HTML mockup at `docs/mockup-live-notepad.html`

---

## What's Next

### Priority 1: Mount LiveNotePadView in ContentView
**What:** Add Cmd+N global hotkey to toggle floating `LiveNotePadView` as an overlay/panel during recording. Wire `saveQuickNote()` from the view through to the controller.
**Files:** `Views/ContentView.swift`, possibly `Views/OverlayPanel.swift` (reuse existing floating panel pattern)
**Depends on:** Nothing — backend is complete
**Skills:** `swiftui-patterns`, `swift-concurrency-6-2`

### Priority 2: Add "Enhance Notes" button to NotesView
**What:** When `hasUserNotes` is true for a session, show "Enhance Notes" button alongside existing "Generate Notes". Wire to `NoteMergeEngine.merge()`. Output replaces notes.md same as existing generation.
**Files:** `Views/NotesView.swift`, `App/NotesController.swift`
**Depends on:** Priority 1 (need notes to exist to test)

### Priority 3: Add Cmd+3 Notepad tab (v2)
**What:** Third tab in session view showing saved notes as a review surface. Lower priority — floating input is the capture surface.
**Files:** `Views/ContentView.swift` (tab bar)
**Depends on:** Priority 1

### Priority 4: Write tests for new code
**What:** Unit tests for UserNote, LiveNoteStore, SessionRepository user notes persistence. Integration test for NoteMergeEngine prompt construction.
**Files:** `Tests/OpenOatsTests/UserNoteTests.swift`, `Tests/OpenOatsTests/LiveNoteStoreTests.swift`
**Skills:** `swift-protocol-di-testing`, `tdd-workflow`

---

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| Fork instead of PR upstream | Need isRemote fix + notepad is a divergent feature, not on upstream roadmap |
| Floating input over tab for v1 | Pre-mortem: tab requires switching away from Zoom. Cmd+N floating panel captures without context switch |
| Immediate flush on note save | Crash safety — notes are tiny, no reason to buffer like transcript records |
| ±30s window for transcript correlation | Point-in-time matching fails due to transcription latency |
| Manual "Enhance" button, not auto | Saves LLM cost, user controls when enrichment happens |
| Keep existing "Generate Notes" alongside | Two separate features — merge later if UX proves confusing |

---

## Blockers

None.

---

## Open Questions

1. Cmd+N as global hotkey — does OpenOats already register global hotkeys? May need `NSEvent.addGlobalMonitorForEvents` or the existing hotkey system
2. Should the floating panel be an `NSPanel` (stays above other windows) or a SwiftUI overlay within the app window?
3. Upstream architecture rewrite (11 phases) may create merge conflicts if we rebase — monitor but don't block on it

---

## Key Files

| File | Purpose |
|------|---------|
| `OpenOats/Sources/OpenOats/Models/UserNote.swift` | Immutable timestamped note model |
| `OpenOats/Sources/OpenOats/Models/LiveNoteStore.swift` | In-memory note store with @Observable |
| `OpenOats/Sources/OpenOats/Intelligence/NoteMergeEngine.swift` | LLM merge: notes + transcript → enriched output |
| `OpenOats/Sources/OpenOats/Views/LiveNotePadView.swift` | SwiftUI floating panel (not yet mounted) |
| `OpenOats/Sources/OpenOats/Storage/SessionRepository.swift` | Added user-notes.jsonl persistence |
| `OpenOats/Sources/OpenOats/App/AppCoordinator.swift` | Added liveNoteStore property |
| `OpenOats/Sources/OpenOats/App/LiveSessionController.swift` | Lifecycle wiring + saveQuickNote() |
| `OpenOats/Sources/OpenOats/Views/ContentView.swift` | **NEXT: mount floating panel here** |
| `OpenOats/Sources/OpenOats/Views/NotesView.swift` | **NEXT: add Enhance Notes button** |
| `docs/mockup-live-notepad.html` | Visual mockup of the feature |

---

## Suggested Next Session Flow

1. `/pickup` — prime on this project
2. Invoke `swiftui-patterns` skill for SwiftUI panel/overlay best practices
3. Read `ContentView.swift` and `OverlayPanel.swift` to understand existing floating panel pattern
4. Mount `LiveNotePadView` as Cmd+N toggled overlay during recording
5. Wire `saveQuickNote()` from view → controller → repository
6. Build + install + test with a real recording session
7. Read `NotesView.swift` and `NotesController.swift`
8. Add "Enhance Notes" button that calls `NoteMergeEngine.merge()`
9. Test merge with a real session that has user notes
10. Write unit tests (invoke `swift-protocol-di-testing` skill)
11. Commit, push, rebuild app
