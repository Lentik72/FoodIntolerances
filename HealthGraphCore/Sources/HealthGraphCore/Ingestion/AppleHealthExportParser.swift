import Foundation
import GRDB

public struct ExportParseResult: Sendable {
    public let summary: IngestSummary
    public let recordsRead: Int
    public let recordsSkipped: Int
}

/// Streaming parser for Apple Health `export.xml` (spec §5.2). Synchronous by
/// design: XMLParser drives a sync delegate, and each 500-event batch flushes
/// through `IngestPipeline.process` inside a blocking `dbWriter.write` — flat
/// memory for multi-hundred-MB exports. Callers wrap in `Task.detached`.
public final class AppleHealthExportParser: NSObject, XMLParserDelegate {
    private let dbWriter: any DatabaseWriter
    private var buffer: [HealthEvent] = []
    private var summary = IngestSummary()
    private var recordsRead = 0
    private var recordsSkipped = 0
    private var progress: (@Sendable (Int) -> Void)?
    private var parseError: Error?

    // per-day accumulators for daily-stat identifiers:
    // key = "identifier|dayEpochMinute", value = (dayStart, sum, count)
    private var dailyAccumulator: [String: (dayStart: Date, sum: Double, count: Int)] = [:]

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return f
    }()

    public init(database: AppDatabase) {
        self.dbWriter = database.dbWriter
    }

    public func parse(xmlAt url: URL, progress: (@Sendable (Int) -> Void)?) throws -> ExportParseResult {
        // Reset per-call state: the same parser instance may parse repeatedly
        // (idempotent re-imports must not report cumulative counters).
        summary = IngestSummary()
        recordsRead = 0
        recordsSkipped = 0
        buffer = []
        dailyAccumulator = [:]
        parseError = nil
        self.progress = progress
        guard let stream = InputStream(url: url) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let parser = XMLParser(stream: stream)
        parser.delegate = self
        parser.parse()
        if let parseError { throw parseError }
        if let xmlError = parser.parserError { throw xmlError }
        flushDailyAccumulators()
        try flushBuffer()
        return ExportParseResult(summary: summary, recordsRead: recordsRead,
                                 recordsSkipped: recordsSkipped)
    }

    public func parser(_ parser: XMLParser, didStartElement name: String,
                       namespaceURI: String?, qualifiedName: String?,
                       attributes attrs: [String: String]) {
        do {
            switch name {
            case "Record": try handleRecord(attrs)
            case "Workout": try handleWorkout(attrs)
            default: return
            }
        } catch {
            parseError = error
            parser.abortParsing()
        }
    }

    private func handleRecord(_ attrs: [String: String]) throws {
        guard let type = attrs["type"],
              let start = attrs["startDate"].flatMap(Self.dateFormatter.date(from:)),
              let end = attrs["endDate"].flatMap(Self.dateFormatter.date(from:)) else { return }
        recordsRead += 1

        if HealthKitSampleMapper.dailyStatIdentifiers.contains(type) {
            guard let value = attrs["value"].flatMap(Double.init) else { recordsSkipped += 1; return }
            let dayStart = Calendar.current.startOfDay(for: start)
            let key = "\(type)|\(Int(dayStart.timeIntervalSince1970 / 60))"
            var acc = dailyAccumulator[key] ?? (dayStart, 0, 0)
            acc.sum += value
            acc.count += 1
            dailyAccumulator[key] = acc
            return
        }
        if HealthKitSampleMapper.perSampleQuantityIdentifiers.contains(type) {
            guard let value = attrs["value"].flatMap(Double.init), let unit = attrs["unit"] else {
                recordsSkipped += 1; return
            }
            try append(HealthKitSampleMapper.map(
                QuantitySampleData(identifier: type, start: start, end: end,
                                   value: value, unit: unit, timezoneID: nil),
                source: .healthExportFile))
            return
        }
        if HealthKitSampleMapper.categoryIdentifiers.contains(type) {
            guard let raw = attrs["value"],
                  let intValue = HealthKitSampleMapper.categoryValue(fromExportString: raw) else {
                recordsSkipped += 1; return
            }
            try append(HealthKitSampleMapper.map(
                CategorySampleData(identifier: type, start: start, end: end,
                                   value: intValue, timezoneID: nil),
                source: .healthExportFile))
            return
        }
        recordsSkipped += 1
    }

    private func handleWorkout(_ attrs: [String: String]) throws {
        guard let rawType = attrs["workoutActivityType"],
              let start = attrs["startDate"].flatMap(Self.dateFormatter.date(from:)),
              let end = attrs["endDate"].flatMap(Self.dateFormatter.date(from:)) else { return }
        recordsRead += 1
        var name = rawType.replacingOccurrences(of: "HKWorkoutActivityType", with: "")
        name = name.prefix(1).lowercased() + name.dropFirst()
        try append(HealthKitSampleMapper.map(
            WorkoutData(activityName: name, start: start, end: end,
                        kcal: attrs["totalEnergyBurned"].flatMap(Double.init),
                        distanceKm: attrs["totalDistance"].flatMap(Double.init),
                        timezoneID: nil),
            source: .healthExportFile))
    }

    private func append(_ event: HealthEvent?) throws {
        guard let event else { recordsSkipped += 1; return }
        buffer.append(event)
        if buffer.count >= IngestPipeline.batchSize {
            try flushBuffer()
        }
    }

    private func flushDailyAccumulators() {
        for (key, acc) in dailyAccumulator.sorted(by: { $0.key < $1.key }) {
            let identifier = String(key.split(separator: "|")[0])
            let value: Double
            switch HealthKitSampleMapper.dailyStatOptions(for: identifier) {
            case .sum: value = acc.sum
            case .average: value = acc.count > 0 ? acc.sum / Double(acc.count) : 0
            }
            if let event = HealthKitSampleMapper.map(
                DailyStatData(identifier: identifier, dayStart: acc.dayStart,
                              value: value, timezoneID: nil),
                source: .healthExportFile) {
                buffer.append(event)
            }
        }
        dailyAccumulator = [:]
    }

    private func flushBuffer() throws {
        guard !buffer.isEmpty else { return }
        let batch = buffer
        buffer = []
        let batchSummary = try dbWriter.write { db in
            try IngestPipeline.process(batch, db: db)
        }
        summary = summary + batchSummary
        progress?(recordsRead)
    }
}
