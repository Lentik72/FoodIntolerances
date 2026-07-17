import SwiftUI
import HealthGraphCore

/// Evidence drill-down reached from an `InsightCardView` tap ("All evidence →").
/// Loads the `Relationship` + its `RelationshipEvidence`, then renders the
/// itemized exposure→outcome rows (incl. misses), a confounder callout when
/// applicable, and the raw numbers behind the confidence badge.
struct InsightDetailView: View {
    let relationshipID: UUID
    /// Defaults to the app's shared Health Graph DB; overridable so previews
    /// (and future tests) can point at a seeded in-memory database instead —
    /// same pattern as `InsightsViewModel.init(database:)`.
    private let database: AppDatabase

    @State private var relationship: Relationship?
    @State private var evidence: RelationshipEvidence?
    @State private var pushedEvent: HealthEvent?
    @State private var loadAttempted = false

    init(relationshipID: UUID, database: AppDatabase = HealthGraphProvider.shared) {
        self.relationshipID = relationshipID
        self.database = database
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let evidence {
                    exposureList(evidence.exposures)
                    if !evidence.confounders.isEmpty { confounderCallout }
                    if let relationship { rawNumbersCard(relationship) }
                } else if loadAttempted {
                    Text("This insight is no longer available.")
                        .font(.subheadline)
                        .foregroundStyle(HealthTheme.inkSecondary)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .background(HealthTheme.paper)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let relStore = GRDBRelationshipStore(database: database)
            relationship = try? await relStore.relationship(id: relationshipID)
            if let r = relationship {
                evidence = try? await EvidenceEngine(database: database).evidence(for: r, asOf: Date())
            }
            loadAttempted = true
        }
        .navigationDestination(item: $pushedEvent) { event in
            EventDetailView(event: event, viewModel: TimelineViewModel(store: GRDBEventStore(database: database)))
        }
    }

    private var navigationTitle: String {
        if let subtype = relationship?.toSubtype, !subtype.isEmpty { return "Evidence: \(subtype.capitalized)" }
        return "Evidence"
    }

    // MARK: exposure rows

    private func exposureList(_ pairs: [ExposurePairDetail]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exposures")
                .font(HealthTheme.sectionHeader())
                .foregroundStyle(HealthTheme.ink)
            if pairs.isEmpty {
                Text("No exposures recorded yet.")
                    .font(.subheadline)
                    .foregroundStyle(HealthTheme.inkSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(pairs.indices, id: \.self) { index in
                        exposureRow(pairs[index])
                        if index < pairs.count - 1 {
                            Divider().overlay(HealthTheme.cardBorder)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .hgCard()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func exposureRow(_ pair: ExposurePairDetail) -> some View {
        Button {
            Task {
                let store = GRDBEventStore(database: database)
                pushedEvent = try? await store.event(id: pair.outcomeEventID ?? pair.exposureEventID)
            }
        } label: {
            HStack(spacing: 10) {
                // Filled (amber) = outcome followed, hollow (dotMiss) = it didn't —
                // matches EvidenceDotsView's styling so the vocabulary is consistent
                // between the card's recent-dots strip and this itemized list.
                Circle()
                    .fill(pair.outcomeFollowed ? HealthTheme.amber : HealthTheme.dotMiss)
                    .frame(width: 9, height: 9)
                Text(pair.exposureTime.formatted(.dateTime.month().day().hour().minute()))
                    .font(.subheadline)
                    .foregroundStyle(HealthTheme.ink)
                Spacer()
                if let value = pair.outcomeValue {
                    Text(value.formatted(.number.precision(.fractionLength(1))))
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(HealthTheme.inkSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(HealthTheme.inkMuted)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibilityLabel(pair))
        .accessibilityHint("Opens the linked event")
    }

    private func rowAccessibilityLabel(_ pair: ExposurePairDetail) -> String {
        var parts = [pair.exposureTime.formatted(.dateTime.month().day().hour().minute())]
        parts.append(pair.outcomeFollowed ? "outcome followed" : "no outcome")
        if let value = pair.outcomeValue {
            parts.append("value \(value.formatted(.number.precision(.fractionLength(1))))")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: confounder callout

    private var confounderCallout: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(HealthTheme.amber)
            Text("Another exposure was often present on these days — can't tell them apart yet; try one without the other.")
                .font(.subheadline)
                .foregroundStyle(HealthTheme.ink)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hgCard()
        .accessibilityElement(children: .combine)
    }

    // MARK: raw numbers

    private func rawNumbersCard(_ r: Relationship) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Raw numbers")
                .font(HealthTheme.sectionHeader())
                .foregroundStyle(HealthTheme.ink)
            numberRow("Confidence", r.confidence.formatted(.percent.precision(.fractionLength(0))))
            numberRow("Evidence / contradictions", "\(r.evidenceCount) / \(r.contradictionCount)")
            if let lag = r.lagHours {
                numberRow("Median lag", "\(lag.formatted(.number.precision(.fractionLength(1)))) h")
            }
            if let strength = r.strength {
                numberRow("Avg effect", strength.formatted(.number.precision(.fractionLength(2))))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hgCard()
    }

    private func numberRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(HealthTheme.inkSecondary)
            Spacer()
            Text(value)
                .foregroundStyle(HealthTheme.ink)
        }
        .font(.system(.footnote, design: .monospaced))
        .accessibilityElement(children: .combine)
    }
}

#Preview("Insight Detail — light") {
    NavigationStack { InsightDetailPreviewHost() }
}

#Preview("Insight Detail — dark") {
    NavigationStack { InsightDetailPreviewHost() }
        .preferredColorScheme(.dark)
}

/// Seeds a small mined in-memory DB (dairy → bloating, planted pattern over 90
/// days) so the preview renders real rows, a confidence readout, and — since
/// the synthetic generator also sprinkles noise foods — exercises the same
/// evidence(for:) path Task 8 will drive live. `#Preview` bodies can't `await`
/// directly, so this host seeds in `.task` and shows a spinner until a
/// relationship id is ready.
private struct InsightDetailPreviewHost: View {
    @State private var seeded: (db: AppDatabase, id: UUID)?

    var body: some View {
        Group {
            if let seeded {
                InsightDetailView(relationshipID: seeded.id, database: seeded.db)
            } else {
                ProgressView().tint(HealthTheme.accent)
            }
        }
        .task {
            seeded = try? await Self.seed()
        }
    }

    private static func seed() async throws -> (db: AppDatabase, id: UUID) {
        let db = try AppDatabase.inMemory()
        let now = Date()
        let config = SyntheticConfig(
            startDate: now.addingTimeInterval(-90 * 86_400), days: 90, seed: 7,
            patterns: [PlantedPattern(exposureName: "dairy", exposureCategory: .food,
                                      outcomeSubtype: "bloating", lagHours: 8, lagJitterHours: 3,
                                      followProbability: 0.7, exposureProbabilityPerDay: 0.5)],
            outcomeBaseRatePerDay: 0.05, noiseFoodsPerDay: 1...2)
        try await SyntheticDataGenerator.generate(config: config).insert(into: db)
        _ = try await EvidenceEngine(database: db).recompute(asOf: now)
        let active = try await GRDBRelationshipStore(database: db).relationships(status: .active)
        guard let dairy = active.first(where: { $0.toSubtype == "bloating" }) else {
            throw PreviewSeedError.noRelationship
        }
        return (db, dairy.id)
    }

    private enum PreviewSeedError: Error { case noRelationship }
}
