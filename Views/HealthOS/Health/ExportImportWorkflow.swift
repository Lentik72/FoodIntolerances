import Foundation
import UIKit
import HealthGraphCore

/// Parses an Apple Health `export.zip` / `export.xml` into the graph.
///
/// A seam because the ORCHESTRATION around it — holding the screen awake,
/// clearing progress, turning a throw into copy — carries obligations that must
/// hold on every path, while the file work itself (security-scoped access, the
/// temp copy, archive extraction, the detached parse) is untestable plumbing.
/// Production does the plumbing; tests script success, throw and progress.
@MainActor
protocol ExportFileImporting {
    /// `progress` is `@Sendable` because the parser reports from a detached
    /// parse — the caller is responsible for hopping to the main actor.
    func importExport(at url: URL, progress: @escaping @Sendable (Int) -> Void) async throws
}

enum ExportImportError: Error {
    /// The picked file could not be opened for reading. Distinct from a parse
    /// failure because it has its own remedy and its own copy.
    case noPermission
}

/// Keeps the device awake across a multi-minute parse. A seam so "released even
/// when the parse throws" is a testable fact rather than a UIKit global nobody
/// can observe.
@MainActor
protocol ScreenWakeHolding: AnyObject {
    func hold()
    func release()
}

final class SystemScreenWake: ScreenWakeHolding {
    nonisolated init() {}
    func hold() { UIApplication.shared.isIdleTimerDisabled = true }
    func release() { UIApplication.shared.isIdleTimerDisabled = false }
}

/// Ported from HealthGraphDebugView.importExport — same security-scoped copy,
/// same detached parse. The graph write is identical; only the surface is new.
struct AppleHealthExportFileImporter: ExportFileImporting {
    nonisolated init() {}

    func importExport(at url: URL, progress: @escaping @Sendable (Int) -> Void) async throws {
        guard url.startAccessingSecurityScopedResource() else { throw ExportImportError.noPermission }
        defer { url.stopAccessingSecurityScopedResource() }
        let local = FileManager.default.temporaryDirectory
            .appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: local)
        try FileManager.default.copyItem(at: url, to: local)
        let xmlURL = url.pathExtension.lowercased() == "zip"
            ? try ExportArchive.extractExportXML(from: local)
            : local
        let database = HealthGraphProvider.shared
        // AppleHealthExportParser.flushBuffer() calls progress once per
        // IngestPipeline.batchSize (500) buffered events — already a sane UI
        // cadence, so no extra throttle here.
        _ = try await Task.detached(priority: .userInitiated) {
            try AppleHealthExportParser(database: database).parse(xmlAt: xmlURL, progress: progress)
        }.value
    }
}
