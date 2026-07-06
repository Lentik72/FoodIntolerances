import Foundation
import ZIPFoundation

public enum ExportArchiveError: Error, Equatable {
    case exportXMLNotFound
}

public enum ExportArchive {
    /// Extracts `export.xml` from an Apple Health `export.zip` into a unique
    /// temp directory and returns its URL. The caller owns cleanup of the
    /// returned file's parent directory.
    public static func extractExportXML(from zipURL: URL) throws -> URL {
        let archive = try Archive(url: zipURL, accessMode: .read)
        guard let entry = archive.first(where: { $0.path.hasSuffix("export.xml") }) else {
            throw ExportArchiveError.exportXMLNotFound
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = dir.appendingPathComponent("export.xml")
        _ = try archive.extract(entry, to: destination)
        return destination
    }
}
