# Timeline → List (native swipe) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert `TimelineView.feed` from `ScrollView { LazyVStack }` to a sectioned SwiftUI `List` so event rows get native swipe-to-Delete/Edit, with sticky day headers, preserving the current look and every behavior.

**Architecture:** The change is confined to `Views/HealthOS/Timeline/TimelineView.swift` — the `feed` computed property becomes a `List` with one `Section` per `TimelineDay` (header = `TimelineDayHeader`, sticky), plus a swipe/edit-sheet wiring in `body`. `TimelineViewModel.delete(_:)` (with undo), `EventEditView`, `TimelineEventRow`, `SleepSessionRow`, and `TimelineDayHeader` are reused **unchanged**.

**Tech Stack:** SwiftUI (`List`, `.swipeActions`, `Section` sticky headers — iOS 17+ APIs; deployment target iOS 26.5), Swift Testing for the (unchanged) VM tests.

Design: `docs/superpowers/specs/2026-07-19-timeline-list-swipe-design.md`.

## Global Constraints

- **Only `TimelineView.swift` changes.** `TimelineViewModel`, `TimelineDayBuilder`, `EventDisplay`, `TimelineEventRow`, `SleepSessionRow`, `TimelineDayHeader`, `EventEditView`, `EventDetailView` are NOT modified. (spec §Scope)
- **Preserve every behavior (spec §4):** day segmentation (newest first), sleep-session expand/collapse (`expandedSessions`), infinite scroll (the `hasMore && !isSearchActive` `loadMore` sentinel), pull-to-refresh, search/filter (data-driven), empty state, the `pendingUndo` toast, tap→`EventDetailView`, and the `scenePhase`/`lastCaptureAt` refreshers.
- **Swipe = Delete + Edit on EVENT rows only.** Delete is the trailing `role: .destructive` full-swipe action → `viewModel.delete(event)` (already arms the undo toast). Edit → opens `EventEditView` as a sheet. **Sleep-session rows get NO swipe.** (spec §2)
- **Sticky day headers** via List `Section` headers; the pinned header must render on `HealthTheme.paper` (no system gray/blur) with the severity sparkline crisp, light + dark. (spec §2, §5)
- **Match the current look** — hidden separators, cleared List/row backgrounds so `HealthTheme.paper` shows, and the existing per-row padding re-applied over `.listRowInsets(EdgeInsets())`. (spec §5)
- **No new unit-testable logic.** This is a view refactor; the VM logic (`delete`/`undoDelete`/rebuild) is unchanged and already covered by `TimelineViewModelTests`. Per-task gates are: app builds + `TimelineViewModelTests` stays green + `#Preview`. The **on-device pass (Task 3) is the real gate.**
- **App-target tests MUST run with `-parallel-testing-enabled NO`;** the lone `SwiftDataMigratorTests` `** TEST FAILED **` is the KNOWN pre-existing teardown crash.
- **Simulator:** iPhone 17 Pro (iOS 26.5).

---

### Task 1: Convert `feed` to a sectioned List (sticky headers, no swipe yet)

**Files:**
- Modify: `Views/HealthOS/Timeline/TimelineView.swift` — replace the `feed` computed property (currently lines 99-139).

**Interfaces:**
- Consumes (unchanged): `viewModel.days: [TimelineDay]`, `viewModel.isLoading`, `viewModel.hasMore`, `viewModel.isSearchActive`, `viewModel.loadMore()`, `viewModel.refresh()`; `expandedSessions: Set<String>`; `path`; `TimelineDayHeader(day:)`, `TimelineEventRow(event:onTap:)`, `SleepSessionRow(session:isExpanded:onToggle:)`, `emptyState`.
- Produces: a `List`-based `feed`. Task 2 attaches `.swipeActions` to the event branch and adds the edit sheet.

- [ ] **Step 1: Replace the `feed` computed property** with the List version below. (This is a view refactor — there is no failing unit test to write first; correctness is verified by build + the unchanged `TimelineViewModelTests` + the preview + Task 3's device pass.)

```swift
    private var feed: some View {
        List {
            if viewModel.days.isEmpty && !viewModel.isLoading {
                emptyState
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            ForEach(viewModel.days) { day in
                Section {
                    ForEach(day.items) { item in
                        switch item {
                        case .event(let event):
                            TimelineEventRow(event: event) { tapped in
                                path.append(tapped)
                            }
                            .padding(.leading, 16)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        case .sleepSession(let session):
                            SleepSessionRow(session: session,
                                            isExpanded: expandedSessions.contains(session.id)) {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    if expandedSessions.contains(session.id) {
                                        expandedSessions.remove(session.id)
                                    } else {
                                        expandedSessions.insert(session.id)
                                    }
                                }
                            }
                            .padding(.leading, 16)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                } header: {
                    TimelineDayHeader(day: day)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(HealthTheme.paper)
                        .listRowInsets(EdgeInsets())
                        .textCase(nil)
                }
                .listSectionSeparator(.hidden)   // MUST be on the Section — inert if applied to the List
            }
            if viewModel.hasMore && !viewModel.days.isEmpty && !viewModel.isSearchActive {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .onAppear { Task { await viewModel.loadMore() } }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
        .scrollContentBackground(.hidden)
        .background(HealthTheme.paper)
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await viewModel.refresh() }
    }
```

Notes for the implementer (settle in `#Preview` + device, spec §5):
- The sticky-header background is the fiddly part. `.background(HealthTheme.paper)` + `.listRowInsets(EdgeInsets())` on the header is the starting point; if the pinned header still shows iOS's default material/separator, also try `.listRowSeparator(.hidden)` on the header and confirm `.listSectionSeparator(.hidden)` is taking effect. The goal: pinned header sits on opaque `HealthTheme.paper` with the sparkline crisp, light + dark.
- `.textCase(nil)` prevents List from uppercasing the header title.
- `.listSectionSpacing(0)` keeps days abutting (the header supplies its own top padding), matching the old `LazyVStack(spacing: 0)`.
- Do NOT modify `TimelineDayHeader.swift`, `TimelineEventRow.swift`, or `SleepSessionRow.swift` — the paper background is applied in the `header:` closure here.

- [ ] **Step 1b: Add a `#Preview` for the sticky-header styling** (there is none in the file today; the sticky-header background is the flagged-fiddly part and canvas iteration on it — light + dark, pinned vs. inline — is far faster than device rebuilds). Append to `TimelineView.swift`. Keep the synthetic-data constructors matching the real initializers (`HealthEvent(timestamp:category:subtype:value:source:)`, `TimelineDay(dayStart:items:severityPoints:)`, `SeverityPoint(time:value:)`) — adjust if the build flags a signature:

```swift
#Preview("Timeline — sticky headers") {
    func ev(_ minsAgo: Double, _ cat: EventCategory, _ sub: String, _ v: Double?) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSinceNow: -minsAgo * 60),
                    category: cat, subtype: sub, value: v, source: .manual)
    }
    let cal = Calendar.current
    let days = [
        TimelineDay(dayStart: cal.startOfDay(for: Date()),
                    items: [.event(ev(30, .symptom, "headache", 6)),
                            .event(ev(120, .mood, "mood", 2)),
                            .event(ev(200, .note, "Slept badly", nil))],
                    severityPoints: [SeverityPoint(time: Date(), value: 6)]),
        TimelineDay(dayStart: cal.startOfDay(for: Date(timeIntervalSinceNow: -86_400)),
                    items: [.event(ev(1_500, .symptom, "nausea", 3))],
                    severityPoints: []),
    ]
    return List {
        ForEach(days) { day in
            Section {
                ForEach(day.items) { item in
                    if case .event(let e) = item {
                        TimelineEventRow(event: e) { _ in }
                            .padding(.leading, 16)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
            } header: {
                TimelineDayHeader(day: day)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HealthTheme.paper)
                    .listRowInsets(EdgeInsets())
                    .textCase(nil)
            }
            .listSectionSeparator(.hidden)
        }
    }
    .listStyle(.plain)
    .listSectionSpacing(0)
    .scrollContentBackground(.hidden)
    .background(HealthTheme.paper)
}
```

Scroll the canvas to confirm the pinned header sits on opaque paper (no gray material bleed) with the sparkline crisp; toggle the canvas to dark and re-check.

- [ ] **Step 2: Build + verify the VM tests + preview.**

Run:
```
xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -8
```
Expected: `** BUILD SUCCEEDED **`.

Run:
```
xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -only-testing:"Food IntolerancesTests/TimelineViewModelTests" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 | grep -E "Test run with|✔ Test|✘ Test|TEST (SUCCEEDED|FAILED)" | tail -10
```
Expected: `** TEST SUCCEEDED **`, all pass (the VM is unchanged; this is a regression guard). Confirm the new `#Preview` (Step 1b) compiles and renders in the Xcode canvas — scroll it to check the pinned header on paper, in light + dark.

- [ ] **Step 3: Commit.**

```bash
git add "Views/HealthOS/Timeline/TimelineView.swift"
git commit -m "refactor(app): Timeline feed → sectioned List with sticky day headers (preserves look + behaviors)"
```

---

### Task 2: Swipe Delete + Edit + edit sheet

**Files:**
- Modify: `Views/HealthOS/Timeline/TimelineView.swift` — add `editingEvent` state, the `.sheet(item:)` in `body`, and `.swipeActions` on the event row in `feed`.

**Interfaces:**
- Consumes (unchanged): `viewModel.delete(_ event:) async -> Bool` (soft-deletes + arms the `pendingUndo` toast), `EventEditView(event:viewModel:)` (the same editor `EventDetailView.swift:44` presents via sheet).
- Produces: swipe-Delete (full-swipe, destructive) + swipe-Edit (opens the editor sheet) on event rows.

- [ ] **Step 1: Add the editing state + edit sheet.** In `TimelineView`, add the state property alongside the others (near `@State private var expandedSessions`):

```swift
    @State private var editingEvent: HealthEvent?
```

In `body`, add the sheet next to the existing `.navigationDestination(for: HealthEvent.self)` modifier (inside the `NavigationStack`, same modifier chain on the `VStack`):

```swift
            .sheet(item: $editingEvent) { event in
                EventEditView(event: event, viewModel: viewModel)
            }
```

(`HealthEvent` is `Identifiable` — it is already used with `navigationDestination(for: HealthEvent.self)` and `ForEach` by id, so `.sheet(item:)` works.)

- [ ] **Step 2: Attach `.swipeActions` to the event row.** In `feed`, on the `.event` branch (the `TimelineEventRow(...)` with its `.listRow…` modifiers from Task 1), add — after the `.listRowBackground(Color.clear)` line:

```swift
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await viewModel.delete(event) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                if event.source == .manual {
                                    Button {
                                        editingEvent = event
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(HealthTheme.accent)
                                }
                            }
```

Delete is declared first, so full-swipe triggers it (destructive → red), and it applies to **all** event rows (parity with the detail screen, which lets any event be deleted). **Edit is gated behind `event.source == .manual`** — mirroring `EventDetailView.swift:39`, which only offers Edit for manually-logged events (editing a HealthKit/imported/photo/voice event would diverge from or be clobbered by the next sync). `.swipeActions` is a `@ViewBuilder`, so the `if` compiles; a non-manual row simply shows Delete only. The `.sleepSession` branch gets NO `.swipeActions`.

- [ ] **Step 3: Build + verify the VM tests.**

Run the same build + `TimelineViewModelTests` commands as Task 1 Step 2.
Expected: `** BUILD SUCCEEDED **` and `** TEST SUCCEEDED **` (VM unchanged; delete/undo already covered).

- [ ] **Step 4: Commit.**

```bash
git add "Views/HealthOS/Timeline/TimelineView.swift"
git commit -m "feat(app): Timeline swipe-to-Delete/Edit on event rows (reuses delete+undo, opens editor sheet)"
```

---

### Task 3: End-to-end verification + device pass

**Files:** none (verification).

- [ ] **Step 1: Full regression.**
  - App target: `xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -only-testing:"Food IntolerancesTests" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 | grep -E "✔ Suite|✘|Test run with|\*\* TEST"` → every suite green except the known pre-existing `SwiftDataMigratorTests` teardown crash.
  - App build succeeds.

- [ ] **Step 2: On-device / simulator behavior check** (device preferred) — the real gate. Confirm:

  *Swipe actions:*
  - **Swipe** a manually-logged event row (trailing) → **Delete + Edit** appear; **full-swipe deletes** and the **"Event deleted · Undo"** toast restores it.
  - **Edit** (swipe) opens the **editor sheet** directly.
  - **A non-manual row** (e.g. a HealthKit-sourced steps/vitals row, or an imported one) → swipe shows **Delete only, no Edit** (the source gate).
  - **On device with the real DB** (not the in-memory sim), a full-swipe delete **animates away promptly** — no visible hang or snap-back before removal.
  - **Sleep-session rows are NOT swipeable** (swipe does nothing); tap-to-expand/collapse still works.

  *Preserved behaviors:*
  - **Expand a sleep session that is NOT the first visible row** (scroll a few days down first) — the list does **not jump / auto-scroll** to reposition.
  - **With an active search**, swipe-delete a result row → it disappears and **Undo restores it into the search results** (not the browse list).
  - **Infinite scroll** (scroll to load more), **pull-to-refresh**, **filter**, **empty state**, and **tap → detail** all still work; **newest day is at the top**.
  - Background then foreground the app → the feed **silently refreshes** (scenePhase); logging from Capture refreshes it too.

  *Look + a11y:*
  - **Day headers stick** to the top while scrolling, on `HealthTheme.paper` with the **severity sparkline crisp** and **no system-material bleed at the header edges**; **no stray section hairlines/separators** anywhere.
  - With **VoiceOver** on, **Delete / Edit are reachable via the actions rotor** on an event row.
  - Correct in **light + dark** and at **XXL Dynamic Type** (headers/rows don't clip).

- [ ] **Step 3: Record observed behavior** in the review notes / ledger.

---

## Definition of Done

- The Timeline feed is a sectioned `List`; event rows support native swipe-to-**Delete** (full-swipe, with the existing Undo toast) and swipe-to-**Edit** (opens the editor sheet); sleep-session rows are not swipeable and still expand/collapse.
- **Day headers are sticky**, rendering on `HealthTheme.paper` with a crisp sparkline, light + dark.
- Every prior behavior is preserved: infinite scroll, pull-to-refresh, search, filter, empty state, tap→detail, scene/capture refresh, day segmentation.
- `TimelineViewModel`, `TimelineDayBuilder`, `EventDisplay`, and the three row/header views are unchanged; `TimelineViewModelTests` and the full app suite stay green; verified on-device.
- Out of scope (unchanged): swipe on sessions, leading-edge/extra actions, and the "what lifts your mood" round.
