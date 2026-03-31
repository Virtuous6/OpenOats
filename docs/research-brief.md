# Research Brief: OpenOats Participant Identity + Speaker Naming

**Date:** 2026-03-27
**Verdict:** PROCEED

---

## Scope

Goal: get better meeting participant identity in OpenOats, then line diarized speakers up with real names and emails, with minimal product friction and minimal risk to current live transcription.

---

## Current Repo State

- OpenOats already has a good stub for meeting identity: [`CalendarEvent` + `Participant` in `MeetingTypes.swift`](/Users/josephsanchez/Documents/repos/openoats/OpenOats/Sources/OpenOats/Domain/MeetingTypes.swift).
- Live transcription already supports remote diarized labels via `Speaker.remote(n)` and `DiarizationManager`, but those labels currently surface as `Speaker 1`, `Speaker 2`, etc. in the UI/export path. See [`Utterance.swift`](/Users/josephsanchez/Documents/repos/openoats/OpenOats/Sources/OpenOats/Domain/Utterance.swift), [`DiarizationManager.swift`](/Users/josephsanchez/Documents/repos/openoats/OpenOats/Sources/OpenOats/Transcription/DiarizationManager.swift), [`MarkdownMeetingWriter.swift`](/Users/josephsanchez/Documents/repos/openoats/OpenOats/Sources/OpenOats/Intelligence/MarkdownMeetingWriter.swift).
- `MeetingMetadata` already carries `calendarEvent`, but `MeetingDetectionController` currently constructs accepted sessions with `calendarEvent: nil`. See [`MeetingDetectionController.swift`](/Users/josephsanchez/Documents/repos/openoats/OpenOats/Sources/OpenOats/App/MeetingDetectionController.swift).
- `LiveSessionController.startTranscription(...)` receives `MeetingMetadata`, but current finalization persists only title/app/language/engine, not participant identity. See [`LiveSessionController.swift`](/Users/josephsanchez/Documents/repos/openoats/OpenOats/Sources/OpenOats/App/LiveSessionController.swift).
- The meeting format spec already anticipated this exact future state: keep `participants` as flat names, keep richer identity in `x_` extension fields. See [`docs/meeting-format-spec.md`](/Users/josephsanchez/Documents/repos/openoats/docs/meeting-format-spec.md).

Implication: this is mostly an ingestion + mapping feature. It does not require replacing the transcription pipeline.

---

## Best Options, Ranked

### 1. Calendar + Contacts enrichment, then manual bind of diarized speakers

**Fit:** best baseline. Lowest invasiveness. Highest leverage.

What it gives:
- likely meeting title
- organizer
- invited participants
- names and, often, emails
- zero audio sent off-device
- cross-provider coverage if user syncs calendars into Apple Calendar

Why it fits OpenOats:
- Apple EventKit exposes event attendees on `EKCalendarItem.attendees`.
- `EKParticipant` exposes `name`, `isCurrentUser`, and `contactPredicate`.
- `contactPredicate` can be resolved through `CNContactStore`, which exposes `emailAddresses`, names, org, etc.

What this should drive in product:
- pre-fill a candidate roster before the meeting starts
- mark current user from calendar/contact data
- if there is exactly one remote attendee, auto-map `Them` / `remote_1` to that person
- if there are multiple remote attendees, keep diarization generic until user confirms mapping

What not to overclaim:
- calendar invitees are not the same as actual attendees
- no reliable speaker-to-person mapping comes from calendar alone
- some calendars expose only partial metadata unless synced locally

Recommendation:
- make this Phase 1
- keep it passive by default
- ask for Calendar/Contacts permission only when user opts in to “Name participants”

### 2. Lightweight manual assignment UI on top of current diarization

**Fit:** best accuracy/effort tradeoff for live naming.

What it gives:
- user can assign `Speaker 1 -> Alice Chen`
- works immediately with current `remote_n` diarization output
- no vendor OAuth
- no cloud dependency
- easy recovery when diarization or roster is imperfect

Recommended behavior:
- only surface assignment UI after a remote diarized speaker has enough speech
- show candidate roster from calendar first
- one-click assign, rename, clear
- keep confidence/source on mapping: `calendar+manual`, `voiceprint`, `api`

Why this matters:
- identity is a human-trust feature
- bad auto-labels are worse than generic labels

Recommendation:
- make this Phase 1 with calendar enrichment
- do not block transcription if user ignores it

### 3. Optional voiceprints for recurring contacts

**Fit:** strong optional upgrade. Not baseline.

What it gives:
- actual speaker identification, not just diarization
- better mapping across repeated meetings
- useful for recurring 1:1s and small recurring teams

Good implementation styles:
- local voice embeddings + local matching
- or external voiceprint service behind explicit opt-in

Evidence:
- pyannote’s official docs distinguish diarization from identification and support voiceprint-based identification in the premium path.
- SpeechBrain provides pretrained speaker embedding / verification models that can be used to compute embeddings and compare voices.

Why this is Phase 2, not Phase 1:
- needs enrollment
- needs threshold tuning
- needs UX for low-confidence matches
- can false-positive if the candidate set is too broad

Recommendation:
- only enable for known frequent contacts
- require explicit enrollment or approved prior samples
- default to “suggested match”, not silent relabel

### 4. Provider-specific meeting APIs as optional power-ups

**Fit:** useful later. Not the base architecture.

Google Meet:
- Google Meet REST API can return participant details for past conferences and active conferences.
- participant sessions include join/leave timestamps.
- signed-in users expose a Google user ID interoperable with People API / Admin SDK.
- Google Meet Media API is still Developer Preview and requires the project, OAuth principal, and all participants to be enrolled. That is too much friction for baseline OpenOats.

Microsoft Teams:
- Microsoft Graph attendance records expose email, display name, role, and join/leave intervals.
- good for enterprise users who already have Graph auth
- more auth/admin friction than EventKit

Recommendation:
- treat provider APIs as add-on connectors
- use them to improve roster truth and attendance after the baseline local flow exists
- do not make live speaker naming depend on them

### 5. UI scraping / Accessibility scraping participant panels

**Fit:** bad.

Why not:
- brittle across Zoom/Meet/Teams UI changes
- locale-dependent
- likely to break on every vendor redesign
- hard to test
- awkward privacy story

Recommendation:
- avoid

### 6. Bot-based meeting joiners / cloud meeting-recording infra

**Fit:** bad for OpenOats’ current product shape.

Why not:
- changes the product from “local sidecar app” to “network participant”
- adds visible meeting friction
- weakens privacy/offline story
- adds provider coupling and ops cost

Recommendation:
- avoid for core product

---

## Recommended Architecture

### Phase 1: local, low-risk, high-value

1. Add a `CalendarIdentityService`
- use EventKit only when user opts in
- fetch events around `detectedAt`
- prefer events whose URL/title/app match the detected meeting app
- populate `MeetingMetadata.calendarEvent`

2. Add a `ParticipantResolver`
- for each `EKParticipant`, resolve `name`
- use `contactPredicate` with `CNContactStore` to enrich with emails/org when available
- mark current user with `isCurrentUser`

3. Persist rich participant metadata separately from transcript speaker keys
- keep raw transcript storage as `you` / `them` / `remote_n`
- add session-scoped participant identity map
- export full names in markdown presentation layer
- store rich details in `x_` fields, not in core `participants`

4. Add a minimal assignment UI
- map diarized remote speakers to candidate participants
- zero blocking
- one-click confirm

5. Use confidence rules
- if 1 remote diarized speaker + 1 non-user attendee: auto-suggest
- if many attendees: suggest only, never silently assign
- if user overrides: persist override as highest-priority truth

### Phase 2: optional identity automation

1. Add recurring-contact voiceprints
- local-first if possible
- otherwise explicit opt-in cloud path

2. Add provider connectors selectively
- Google Meet for Workspace-heavy users
- Microsoft Graph for Teams-heavy orgs

### Phase 3: intelligence layer

Once names are stable:
- inject named participants into prompts
- write names into transcript/export instead of `Speaker 1`
- enrich notes with `[owner:: Alice Chen]`
- use emails for CRM/contact-card linking

---

## Minimal Code Surface

Best low-churn seams:

- add new services rather than rewrite transcription
- keep `Speaker` storage enum intact for now
- add display-name overrides at render/export layer first
- thread participant identity through `MeetingMetadata` and session sidecars
- extend markdown writer with:
  - `participants` = resolved names
  - `x_openoats_participants` or similar = richer detail including email/source/confidence

This is lower risk than changing every place that assumes `Speaker` is enum-backed.

---

## Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Calendar invitees differ from real attendees | High | treat calendar as candidate roster, not truth |
| Bad auto-labels erode trust | High | default to suggestion/manual confirm unless confidence is very high |
| Contacts permission feels intrusive | Medium | separate opt-in, clear value prop, work without it |
| Voiceprints create privacy sensitivity | Medium | explicit enrollment, local-first, clear delete controls |
| Provider APIs add auth/admin friction | Medium | keep them optional add-ons |
| Changing transcript storage too early causes regressions | Medium | keep raw speaker keys, add identity map beside them |

---

## Non-Fit Calls

- Do not start with Zoom/Meet/Teams UI scraping.
- Do not start with meeting bots.
- Do not replace the current diarization/transcription engine.
- Do not silently relabel multi-party meetings from calendar data alone.

---

## Concrete Recommendation

Build this in order:

1. EventKit roster ingest
2. Contacts enrichment via `contactPredicate`
3. Session-level participant identity map
4. Manual diarized-speaker assignment UI
5. Markdown export with names + `x_` rich metadata
6. Optional voiceprints for recurring contacts
7. Optional Google Meet / Teams connectors for users who want them

This path preserves OpenOats’ local/offline posture, avoids brittle app-specific hacks, and gives meaningful user value after the first increment.

---

## Source Notes

Apple / local SDK:
- EventKit `EKCalendarItem.attendees`, `EKParticipant.name`, `EKParticipant.isCurrentUser`, `EKParticipant.contactPredicate`, `EKEventStore.requestFullAccessToEventsWithCompletion` from Xcode 26.2 macOS SDK headers inspected locally.
- Contacts `CNContactStore.requestAccessForEntityType`, `unifiedContactsMatchingPredicate`, `CNContact.emailAddresses` from Xcode 26.2 macOS SDK headers inspected locally.

Official web sources:
- Google Meet participants guide: <https://developers.google.com/workspace/meet/api/guides/participants>
- Google Meet participant sessions reference: <https://developers.google.com/workspace/meet/api/reference/rest/v2/conferenceRecords.participants.participantSessions>
- Google Meet Media API participant reference: <https://developers.google.com/workspace/meet/media-api/reference/dc/media_api.baseparticipant>
- Microsoft Graph attendance records: <https://learn.microsoft.com/graph/api/attendancerecord-list>
- pyannote models: <https://docs.pyannote.ai/models>
- pyannote voiceprints tutorial: <https://docs.pyannote.ai/tutorials/identification-with-voiceprints>
- SpeechBrain speaker verification model card: <https://huggingface.co/speechbrain/spkrec-resnet-voxceleb>
