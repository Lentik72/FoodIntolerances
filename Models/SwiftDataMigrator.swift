import Foundation
import SwiftData
import CryptoKit
import HealthGraphCore

/// One-time SwiftData -> Health Graph migration. Reads the legacy store,
/// never writes to it. Runs behind a completion flag; DEBUG screen can force.
/// Every created event id is deterministic (UUIDv5 of the legacy row id),
/// so re-runs upsert the same rows instead of duplicating them.
struct SwiftDataMigrator {

    struct Report: Codable, Equatable {
        var logEntriesMigrated = 0
        var trackedItemsMigrated = 0
        var avoidedItemsMigrated = 0
        var cabinetItemsMigrated = 0
        var ongoingSymptomsMigrated = 0
        var checkInsMigrated = 0
        var protocolsMigrated = 0
        var eventsCreated = 0
        var objectsCreated = 0
        var attachmentsSaved = 0
        var attachmentFailures = 0
    }

    static let completedFlagKey = "hg.migration.v1.completed"

    static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedFlagKey)
    }

    @MainActor
    static func run(
        context: ModelContext,
        database: AppDatabase,
        force: Bool = false,
        attachmentsDirectory: URL? = nil
    ) async throws -> Report {
        guard force || !isCompleted else { return Report() }

        let events = GRDBEventStore(database: database)
        let objects = GRDBObjectStore(database: database)
        var report = Report()
        let tz = TimeZone.current.identifier
        let iso = ISO8601DateFormatter()

        // --- LogEntry -> events ---
        for entry in try context.fetch(FetchDescriptor<LogEntry>()) {
            let ts = combine(day: entry.date, time: entry.timeOfDay)
            let deletedAt: Date? = entry.isActive ? nil : Date()
            var meta: [String: String] = ["legacyID": entry.id.uuidString]
            if !entry.notes.isEmpty { meta["notes"] = entry.notes }
            if !entry.category.isEmpty { meta["legacyCategory"] = entry.category }
            if !entry.subcategories.isEmpty { meta["subcategories"] = entry.subcategories.joined(separator: "|") }
            if !entry.moonPhase.isEmpty { meta["moonPhase"] = entry.moonPhase }
            meta["atmosphericPressure"] = entry.atmosphericPressure
            meta["suddenChange"] = String(entry.suddenChange)
            if !entry.season.isEmpty { meta["season"] = entry.season }
            meta["isMercuryRetrograde"] = String(entry.isMercuryRetrograde)
            if !entry.additionalContext.isEmpty { meta["additionalContext"] = entry.additionalContext }
            if let v = entry.protocolID { meta["protocolID"] = v.uuidString }
            if let v = entry.protocolEffectiveness { meta["protocolEffectiveness"] = String(v) }
            if let v = entry.protocolNotes, !v.isEmpty { meta["protocolNotes"] = v }
            if let v = entry.usedProtocolID { meta["usedProtocolID"] = v.uuidString }
            if let v = entry.linkedTrackedItemID { meta["linkedTrackedItemID"] = v.uuidString }
            if let v = entry.resolutionFactor { meta["resolutionFactor"] = v.rawValue }
            if let v = entry.isOngoing { meta["isOngoing"] = String(v) }
            if let v = entry.startDate { meta["legacyStartDate"] = iso.string(from: v) }
            if let v = entry.recommendedProtocol { meta["recommendedProtocolID"] = v.id.uuidString }

            switch entry.itemType {
            case .symptom:
                var attachmentPath: String?
                if let photo = entry.symptomPhotoData {
                    do {
                        attachmentPath = try saveAttachment(photo, id: entry.id,
                                                            directory: attachmentsDirectory)
                        report.attachmentsSaved += 1
                    } catch {
                        report.attachmentFailures += 1
                    }
                }
                var seenNames = Set<String>()
                let names = (entry.symptoms.isEmpty ? [entry.itemName] : entry.symptoms)
                    .filter { seenNames.insert($0).inserted } // dup names share a v5 id; skip to keep counts honest
                for name in names {
                    var m = meta
                    if !entry.affectedAreas.isEmpty {
                        m["affectedAreas"] = entry.affectedAreas.joined(separator: "|")
                    }
                    if !entry.symptomTriggers.isEmpty {
                        m["symptomTriggers"] = entry.symptomTriggers.joined(separator: "|")
                    }
                    if !entry.contributingFactors.isEmpty {
                        m["contributingFactors"] = entry.contributingFactors.joined(separator: "|")
                    }
                    try await events.save(HealthEvent(
                        id: .deterministic("logEntry:\(entry.id.uuidString):symptom:\(name)"),
                        timestamp: ts, timezoneID: tz, endTimestamp: entry.endDate,
                        category: .symptom, subtype: name,
                        value: Double(entry.severity), source: .legacyImport,
                        metadata: encode(m), attachmentPath: attachmentPath,
                        deletedAt: deletedAt
                    ))
                    report.eventsCreated += 1
                }
            case .foodDrink:
                let foodName = entry.foodDrinkItem ?? entry.itemName
                let object = try await objects.findOrCreate(
                    name: foodName, kind: .food, metadata: nil)
                try await events.save(HealthEvent(
                    id: .deterministic("logEntry:\(entry.id.uuidString):food"),
                    timestamp: ts, timezoneID: tz, category: .food,
                    subtype: foodName, objectID: object.id,
                    source: .legacyImport, metadata: encode(meta),
                    deletedAt: deletedAt
                ))
                report.eventsCreated += 1
            }
            for (index, treatment) in entry.treatments.enumerated() {
                let isSupplement = treatment.type.lowercased().contains("supp")
                let kind: ObjectKind = isSupplement ? .supplement : .medication
                let object = try await objects.findOrCreate(
                    name: treatment.name, kind: kind, metadata: nil)
                var m: [String: String] = ["fromLogEntry": entry.id.uuidString]
                if let dosage = treatment.dosage { m["dosage"] = dosage }
                if let eff = treatment.effectiveness { m["effectiveness"] = String(eff) }
                if let notes = treatment.notes, !notes.isEmpty { m["notes"] = notes }
                try await events.save(HealthEvent(
                    id: .deterministic("logEntry:\(entry.id.uuidString):treatment:\(index)"),
                    timestamp: treatment.startDate, timezoneID: tz,
                    endTimestamp: treatment.endDate,
                    category: isSupplement ? .supplement : .medication,
                    subtype: treatment.name, objectID: object.id,
                    source: .legacyImport, metadata: encode(m)
                ))
                report.eventsCreated += 1
            }
            report.logEntriesMigrated += 1
        }

        // --- TrackedItem -> objects ---
        for item in try context.fetch(FetchDescriptor<TrackedItem>()) {
            let kind: ObjectKind
            switch item.type {
            case .supplement: kind = .supplement
            case .medication: kind = .medication
            case .food: kind = .food
            }
            var m: [String: String] = ["legacyStartDate": iso.string(from: item.startDate)]
            if let brand = item.brand { m["brand"] = brand }
            if !item.notes.isEmpty { m["notes"] = item.notes }
            let object = try await objects.findOrCreate(
                name: item.name, kind: kind, metadata: encode(m))
            if !item.isActive {
                try await objects.setArchived(id: object.id, true)
            }
            report.trackedItemsMigrated += 1
        }

        // --- AvoidedItem -> objects ---
        for item in try context.fetch(FetchDescriptor<AvoidedItem>()) {
            let kind: ObjectKind
            switch item.type {
            case .food, .drink: kind = .food
            case .supplement: kind = .supplement
            case .activity: kind = .activity
            }
            var m: [String: String] = ["avoided": "true",
                                       "isRecommended": String(item.isRecommended),
                                       "dateAdded": iso.string(from: item.dateAdded)]
            if let reason = item.reason { m["reason"] = reason }
            _ = try await objects.findOrCreate(name: item.name, kind: kind, metadata: encode(m))
            report.avoidedItemsMigrated += 1
        }

        // --- CabinetItem -> objects ---
        for item in try context.fetch(FetchDescriptor<CabinetItem>()) {
            let category = (item.category ?? "").lowercased()
            let kind: ObjectKind = category.contains("med") ? .medication
                : category.contains("device") ? .device : .supplement
            var m: [String: String] = [:]
            if let v = item.dosage { m["dosage"] = v }
            if let v = item.ingredients { m["ingredients"] = v }
            if let v = item.quantity { m["quantity"] = v }
            if let v = item.notes { m["notes"] = v }
            if let v = item.usageNotes { m["usageNotes"] = v }
            if let v = item.currentStock { m["currentStock"] = String(v) }
            if let v = item.refillThreshold { m["refillThreshold"] = String(v) }
            if let v = item.lastUsed { m["lastUsed"] = iso.string(from: v) }
            m["refillNotificationEnabled"] = String(item.refillNotificationEnabled)
            m["usageCount"] = String(item.usageCount)
            _ = try await objects.findOrCreate(name: item.name, kind: kind, metadata: encode(m))
            report.cabinetItemsMigrated += 1
        }

        // --- OngoingSymptom + SymptomCheckIn -> events ---
        var episodeNames: [UUID: String] = [:]
        for symptom in try context.fetch(FetchDescriptor<OngoingSymptom>()) {
            episodeNames[symptom.id] = symptom.name
            var m: [String: String] = ["episodeID": symptom.id.uuidString,
                                       "isOpen": String(symptom.isOpen)]
            if !symptom.notes.isEmpty { m["notes"] = symptom.notes }
            if let v = symptom.usedProtocolID { m["usedProtocolID"] = v.uuidString }
            if let v = symptom.protocolNotes, !v.isEmpty { m["protocolNotes"] = v }
            if let v = symptom.protocolEffectiveness { m["protocolEffectiveness"] = String(v) }
            if let v = symptom.protocolLastUpdated { m["protocolLastUpdated"] = iso.string(from: v) }
            try await events.save(HealthEvent(
                id: .deterministic("ongoing:\(symptom.id.uuidString)"),
                timestamp: symptom.startDate, timezoneID: tz,
                endTimestamp: symptom.endDate, category: .symptom,
                subtype: symptom.name, source: .legacyImport, metadata: encode(m)
            ))
            report.eventsCreated += 1
            report.ongoingSymptomsMigrated += 1
        }
        for checkIn in try context.fetch(FetchDescriptor<SymptomCheckIn>()) {
            var m: [String: String] = ["episodeID": checkIn.parentSymptomID.uuidString]
            if !checkIn.notes.isEmpty { m["notes"] = checkIn.notes }
            if !checkIn.protocolUsed.isEmpty { m["protocolUsed"] = checkIn.protocolUsed }
            if let v = checkIn.usedProtocolID { m["usedProtocolID"] = v.uuidString }
            if let v = checkIn.protocolEffectiveness { m["protocolEffectiveness"] = String(v) }
            if let v = checkIn.protocolNotes, !v.isEmpty { m["protocolNotes"] = v }
            try await events.save(HealthEvent(
                id: .deterministic("checkIn:\(checkIn.id.uuidString)"),
                timestamp: checkIn.date, timezoneID: tz, category: .symptom,
                subtype: episodeNames[checkIn.parentSymptomID] ?? "check-in",
                value: Double(checkIn.severity), source: .legacyImport,
                metadata: encode(m)
            ))
            report.eventsCreated += 1
            report.checkInsMigrated += 1
        }

        // --- TherapyProtocol (+ items) -> objects ---
        for proto in try context.fetch(FetchDescriptor<TherapyProtocol>()) {
            var m: [String: String] = [
                "instructions": proto.instructions,
                "category": proto.category,
                "frequency": proto.frequency,
                "timeOfDay": proto.timeOfDay,
                "duration": proto.duration,
                "status": proto.status,
                "startDate": iso.string(from: proto.startDate),
                "dateAdded": iso.string(from: proto.dateAdded),
                "isActive": String(proto.isActive),
                "isWishlist": String(proto.isWishlist),
                "enableReminder": String(proto.enableReminder)
            ]
            if let v = proto.endDate { m["endDate"] = iso.string(from: v) }
            if let v = proto.notes, !v.isEmpty { m["notes"] = v }
            if let v = proto.reminderTime { m["reminderTime"] = iso.string(from: v) }
            if let v = proto.completionDate { m["completionDate"] = iso.string(from: v) }
            if let v = proto.protocolEffectiveness { m["effectiveness"] = String(v) }
            if let symptoms = proto.symptoms, !symptoms.isEmpty {
                m["symptoms"] = symptoms.joined(separator: "|")
            }
            if let tags = proto.tags, !tags.isEmpty {
                m["tags"] = tags.joined(separator: "|")
            }
            let items = proto.items.map { item -> [String: String] in
                ["name": item.itemName,
                 "dosage": item.dosageOrQuantity ?? "",
                 "usageNotes": item.usageNotes ?? "",
                 "isCompleted": String(item.isCompleted),
                 "cabinetItemID": item.cabinetItem?.id.uuidString ?? ""]
            }
            if !items.isEmpty, let data = try? JSONEncoder().encode(items) {
                m["items"] = String(data: data, encoding: .utf8) ?? ""
            }
            _ = try await objects.findOrCreate(
                name: proto.title, kind: .careProtocol, metadata: encode(m))
            report.protocolsMigrated += 1
        }

        report.objectsCreated = try await objects.count()

        if !force {
            UserDefaults.standard.set(true, forKey: completedFlagKey)
        }
        return report
    }

    // MARK: - Helpers

    static func combine(day: Date, time: Date?) -> Date {
        guard let time else { return day }
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0,
                        second: 0, of: day) ?? day
    }

    static func encode(_ dict: [String: String]) -> Data? {
        dict.isEmpty ? nil : try? JSONEncoder().encode(dict)
    }

    /// Writes attachment data and returns the canonical relative path stored
    /// on the event. `directory` overrides the write location (tests);
    /// the stored path is unchanged — it is defined relative to
    /// Application Support regardless of where the bytes land.
    static func saveAttachment(_ data: Data, id: UUID, directory: URL?) throws -> String {
        let dir = try directory ?? HealthGraphProvider.attachmentsDirectory()
        let file = dir.appendingPathComponent("\(id.uuidString).jpg")
        try data.write(to: file)
        return "HealthGraph/attachments/\(id.uuidString).jpg"
    }
}

private extension UUID {
    /// Namespace for migration-derived ids. NEVER change this value —
    /// changing it breaks re-run idempotence against already-migrated data.
    static let hgMigrationNamespace = UUID(uuidString: "8F1E4A2C-0B7D-4E5A-9C3F-2D6B1A0E7F45")!

    /// RFC 4122 v5 (name-based, SHA-1): the same name always yields the same
    /// UUID, so migration re-runs upsert rows instead of duplicating them.
    static func deterministic(_ name: String) -> UUID {
        var data = withUnsafeBytes(of: hgMigrationNamespace.uuid) { Data($0) }
        data.append(Data(name.utf8))
        var digest = Array(Insecure.SHA1.hash(data: data))
        digest[6] = (digest[6] & 0x0F) | 0x50 // version 5
        digest[8] = (digest[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (digest[0], digest[1], digest[2], digest[3],
                           digest[4], digest[5], digest[6], digest[7],
                           digest[8], digest[9], digest[10], digest[11],
                           digest[12], digest[13], digest[14], digest[15]))
    }
}
