import SwiftUI
import HealthGraphCore

struct CaptureSheet: View {
    @EnvironmentObject private var coordinator: CaptureCoordinator
    @EnvironmentObject private var redFlagPresenter: RedFlagPresenter
    @State private var type: CaptureType = .symptom
    @State private var timestamp = Date()
    @State private var lastLogged: HealthEvent?
    @State private var toastTask: Task<Void, Never>?
    private let store = GRDBEventStore(database: HealthGraphProvider.shared)

    var body: some View {
        VStack(spacing: 16) {
            Capsule().fill(HealthTheme.cardBorder).frame(width: 36, height: 5).padding(.top, 8)
            Text("Capture")
                .font(HealthTheme.sectionHeader())
                .foregroundStyle(HealthTheme.ink)

            Picker("Type", selection: $type) {
                ForEach(CaptureType.allCases) { t in
                    Label(t.label, systemImage: t.icon).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            DatePicker("When", selection: $timestamp, in: ...Date())
                .datePickerStyle(.compact)
                .padding(.horizontal, 16)

            Group {
                switch type {
                case .symptom: SymptomCaptureView(timestamp: $timestamp, onLogged: logged)
                case .meal: MealCaptureView(timestamp: $timestamp, onLogged: logged)
                case .dose: DoseCaptureView(timestamp: $timestamp, onLogged: logged)
                case .note: NoteCaptureView(timestamp: $timestamp, onLogged: logged)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Spacer(minLength: 0)
        }
        .background(HealthTheme.paper)
        .overlay(alignment: .bottom) { if let lastLogged { toast(lastLogged) } }
        .animation(.easeOut(duration: 0.2), value: lastLogged)
    }

    /// Called by every subview after a successful write: refresh the tabs + arm the undo toast.
    private func logged(_ event: HealthEvent) {
        coordinator.saveCompleted()
        redFlagPresenter.consider(event)     // fires the takeover iff a red-flag symptom
        lastLogged = event
        toastTask?.cancel()
        toastTask = Task { try? await Task.sleep(for: .seconds(4)); guard !Task.isCancelled else { return }; lastLogged = nil }
    }

    private func undo(_ event: HealthEvent) {
        toastTask?.cancel()
        lastLogged = nil
        Task { try? await store.softDelete(id: event.id); coordinator.saveCompleted() }
    }

    private func toast(_ event: HealthEvent) -> some View {
        HStack(spacing: 12) {
            Text("Logged \(EventDisplay.title(for: event))")
                .font(.subheadline).foregroundStyle(HealthTheme.ink).lineLimit(1)
            Button("Undo") { undo(event) }
                .font(.subheadline.weight(.semibold)).foregroundStyle(HealthTheme.accent)
                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .padding(.horizontal, 20).padding(.vertical, 8).hgCard().padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Logged \(EventDisplay.title(for: event))")
        .accessibilityAction(named: "Undo") { undo(event) }
        .id(event.id)
    }
}
