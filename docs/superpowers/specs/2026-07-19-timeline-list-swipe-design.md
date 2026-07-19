# Timeline → List (native swipe) — Design

**Date:** 2026-07-19
**Status:** Approved (decisions made interactively with Leo)
**Scope:** Convert the Timeline feed from a hand-built `ScrollView { LazyVStack }` to a **sectioned SwiftUI `List`**, to get native **swipe-to-Delete / swipe-to-Edit** on event rows — the best long-term foundation. Adds **sticky day headers** (the natural List-section structure) while preserving the current look and every existing behavior.

**Not touched:** `TimelineViewModel`'s data/query/undo logic, `TimelineDayBuilder`, `EventDisplay`, the sessionization core, search/filter logic, the crisis/red-flag or capture flows. `delete(_:)` (with undo) and `EventEditView` already exist and are reused unchanged.

---

## 1. Problem

The Timeline feed is a custom `ScrollView { LazyVStack { … } }` (`TimelineView.feed`). SwiftUI's native swipe-to-delete (`.swipeActions`) exists **only on `List` rows**, so today there is no swipe affordance at all — deleting or editing an event requires tap → `EventDetailView` → button. Leo wants swipe, done the best long-term way. Because the feed is not a `List`, the fix is a real (if contained) refactor of that one computed property, not a one-line modifier.

## 2. Decisions (Leo, 2026-07-19)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Foundation | Convert the feed to a **`List`** (native `.swipeActions`, native feel + a11y, uniform across row types) — not a custom drag gesture. |
| 2 | Swipe actions | **Delete + Edit** on event rows. Delete is the trailing `role: .destructive` full-swipe action (reuses the existing `delete(_:)` + undo toast); Edit opens the editor sheet directly (a shortcut past the detail screen). |
| 3 | Sleep-session rows | **Not swipeable.** A session is an aggregate of many HealthKit sleep segments — there is no single event to delete/edit, and the records re-sync. Sessions keep tap-to-expand only. |
| 4 | Day headers | **Sticky** (List `Section` headers). A day *is* a section, so this is the natural List structure; the always-visible date is a real win in a dense log. Costs a styling pass to tame the pinned-header chrome (see §5). |

## 3. Architecture

The change is confined to **`TimelineView.feed`** (the computed property) plus a small amount of swipe/sheet wiring in `TimelineView.body`. The row views stay presentational.

**`feed` — a sectioned List:**

```
List {
    ForEach(viewModel.days) { day in
        Section {
            ForEach(day.items) { item in
                switch item {
                case .event(let event):
                    TimelineEventRow(event: event) { path.append($0) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { Task { await viewModel.delete(event) } } label: { Label("Delete", systemImage: "trash") }
                            Button { editingEvent = event } label: { Label("Edit", systemImage: "pencil") }.tint(HealthTheme.accent)
                        }
                case .sleepSession(let session):
                    SleepSessionRow(session: session, isExpanded: …) { toggle }
                }
                // per-row list styling (insets/background/separator) applied here
            }
        } header: {
            TimelineDayHeader(day: day)   // sticky
        }
    }
    // infinite-scroll sentinel + empty state (see §4)
}
.listStyle(.plain)
.scrollContentBackground(.hidden)
.background(HealthTheme.paper)
.refreshable { await viewModel.refresh() }
.scrollDismissesKeyboard(.immediately)
```

- **Delete** → `viewModel.delete(event)` — the existing method that soft-deletes, rebuilds the day slice, and arms `pendingUndo` (the "Event deleted · Undo" overlay in `body` is unchanged). Full-swipe triggers it.
- **Edit** → sets a new `@State private var editingEvent: HealthEvent?`; `body` gains `.sheet(item: $editingEvent) { EventEditView(event: $0, viewModel: viewModel) }` — the **same sheet** `EventDetailView` presents (`EventDetailView.swift:44`), so swipe-Edit jumps straight to the editor.
- **Sessions** carry no `.swipeActions`.
- **Tap** still navigates: `TimelineEventRow`'s `Button`/`onTap` → `path.append(event)` → `EventDetailView`. Swipe and tap coexist natively on a List row.

**Row views unchanged.** `TimelineEventRow` and `SleepSessionRow` bodies are not modified — `.swipeActions` attaches to the row *in `feed`*, where `viewModel`/`path`/`editingEvent` are in scope. This keeps the rows dumb and the wiring in one place.

## 4. Preserved behaviors (the contract)

Every one of these must behave as it does today after the conversion:

- **Day segmentation** — one `Section` per `TimelineDay` (was: `TimelineDayHeader` + rows inline). Newest day first, same ordering.
- **Sleep session expand/collapse** — `expandedSessions: Set<String>` in `TimelineView`, toggled by `SleepSessionRow`'s callback, unchanged.
- **Infinite scroll** — the `hasMore && !days.isEmpty && !isSearchActive` sentinel (`ProgressView().onAppear { await viewModel.loadMore() }`) becomes a **trailing row after the sections** (a plain, header-less row); `.onAppear` still fires `loadMore()`.
- **Pull-to-refresh** — `.refreshable { await viewModel.refresh() }` (native on List).
- **Search / filter** — driven by `viewModel.days` / `searchText` / the filter bar; the List renders whatever `days` holds, so search and filter are unaffected. (Search days hold raw event rows only — no sessions — which the switch handles.)
- **Empty state** — when `viewModel.days.isEmpty && !isLoading`, show the existing empty-state view (as a plain row or an `.overlay` on the List — implementer picks whichever renders cleanly with no stray separators/insets).
- **Undo toast** — the `pendingUndo` overlay in `body` (unchanged); Delete arms it via `delete(_:)`.
- **Tap → detail** — `navigationDestination(for: HealthEvent.self)` → `EventDetailView`, unchanged.
- **Scene/capture refresh** — the `scenePhase`/`lastCaptureAt` `onChange` refreshers in `body`, unchanged.

## 5. Styling — matching the current look on a List

List brings default chrome that must be overridden so the feed looks identical (apart from the sticky headers):

- `.listStyle(.plain)` — enables sticky section headers.
- `.listRowSeparator(.hidden)` — no separators (the design uses spine/gutter, not dividers).
- `.listRowInsets(EdgeInsets())` (then re-apply the current per-row padding, e.g. `.padding(.leading, 16)` on event rows, `.padding(.trailing, 16)` inside the row) so spacing matches `LazyVStack(spacing: 0)` + the existing paddings.
- `.listRowBackground(Color.clear)` + `.scrollContentBackground(.hidden)` + `.background(HealthTheme.paper)` — so the paper palette shows through, not List's default grouped background.
- **Sticky-header background (the fiddly part, its own task):** a pinned section header otherwise shows iOS's translucent gray/blur chrome behind it. Override so the pinned `TimelineDayHeader` sits on `HealthTheme.paper` and the **severity sparkline renders crisp** in the pinned bar (light + dark). Likely `.listRowInsets` on the header + an opaque `HealthTheme.paper` background on `TimelineDayHeader` (or `.headerProminence`/section-header background modifiers) — the implementer settles the exact combination in previews + device.

## 6. Testing

This is a SwiftUI view refactor with **no new unit-testable logic** — `delete(_:)`/`undoDelete()` and the day rebuild are already covered by `TimelineViewModelTests`, and the swipe/sheet wiring is pure view. Verification:

- **Automated:** the app builds; existing `TimelineViewModelTests` stay green (they exercise the VM, which is untouched); the full app suite stays green (`-parallel-testing-enabled NO`; the known `SwiftDataMigratorTests` teardown crash is the only expected `** TEST FAILED **`).
- **Device (the real gate):** trailing swipe on an event row shows **Delete + Edit**; full-swipe deletes and the **Undo** toast restores it; **Edit** opens the editor sheet directly; **sleep-session rows are not swipeable** (swipe does nothing, expand still works); **day headers stick** to the top while scrolling with the sparkline rendering cleanly; **infinite scroll**, **pull-to-refresh**, **search**, **filter**, **empty state**, and **tap→detail** all still work; correct in **light + dark** and at **XXL Dynamic Type**.

## 7. Out of scope

- Swipe actions on sleep-session rows (Decision 3).
- Any change to `TimelineViewModel`, `TimelineDayBuilder`, `EventDisplay`, or the sessionization/search logic.
- A leading-edge swipe / additional actions beyond Delete + Edit.
- The `"what lifts your mood"` mining round (separate, still the committed next feature).
