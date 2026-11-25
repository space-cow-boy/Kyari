//
//  KyariSharing.swift
//  Kyari — opt-in photo and result sharing (task H3)
//
//  Purpose
//    Data model for the opt-in "Help improve Kyari" sharing, as specified in
//    Team R/07_Project_Memory/Kyari_data_sharing_optin.md (24 Nov 2026):
//      • SharingConsent  — the user's choice (starts OFF, adult-only), kept on the phone
//      • SharedSample    — one photo + model answers + feedback, queued on the phone
//      • CloudKit record type `SharedSample` in the PUBLIC database (write-only for users)
//      • UploadPolicy    — when a queued sample may leave the phone
//      • JPEGMetadata    — refuses photos that still carry EXIF/XMP/IPTC (location, camera)
//    Schema doc: H3_data_sharing_schema.md (same folder).
//
//  Inputs   the user's consent, a finished diagnosis/identification, a JPEG already
//           resized to long side 1024 px and re-encoded without metadata.
//  Outputs  a validated SharedSample, its CloudKit field map, a CKRecord (on Apple platforms).
//
//  Privacy rules enforced in code (not only in UI):
//    • nothing is uploaded unless consent.isOn && consent.isAdultConfirmed at UPLOAD time
//    • no name, email, Apple ID, GPS, address, exact time: only "YYYY-MM" and a coarse space
//    • per-photo skip; delete = all records of this install
//
//  How it was checked
//    Pure parts (validation, upload policy, month string, EXIF scan, field map) compiled and
//    run on Windows, Swift 6.4, with Tests/KyariSharingSelfTest.swift (see the schema doc).
//    CloudKit parts (#if canImport(CloudKit)) NOT compiled yet: build in Xcode on a Mac.
//
//  Self-contained on purpose (no dependency on KyariModels_Generic.swift), so it can be
//  tested without SwiftData; the mapping helpers to the app's types are at the end.
//

import Foundation
#if canImport(CloudKit)
import CloudKit
#endif

// MARK: - Schema constants

enum SharingSchema {
    static let recordType = "SharedSample"
    static let schemaVersion = 1
    static let photoLongSidePx = 1024
    /// Wait this long for Right/Wrong feedback before uploading without it.
    static let feedbackWait: TimeInterval = 24 * 60 * 60
    /// Records older than this are deleted by the team (spec §5).
    static let retentionYears = 3

    /// Leaf model classes in the model's output order. Names exactly as in training
    /// (Kyari_colab_results/predictions.csv). leafScores[i] belongs to leafClassOrder[i].
    static let leafClassOrder: [String] = [
        "Downy mildew", "Healthy", "Insect chewing damage", "Leaf blight", "Leaf curl",
        "Leaf spot", "Mosaic virus", "Not a leaf or unclear", "Powdery mildew",
        "Rot and wilt", "Rust", "Scorch and dry leaf", "Visible pests", "Yellowing",
    ]
    static let plantTopCount = 3

    /// CloudKit field names. Changing one = schema change in the CloudKit dashboard.
    enum Field {
        static let schemaVersion = "schemaVersion"
        static let installID = "installID"                 // QUERYABLE (delete-my-data)
        static let kind = "kind"
        static let photo = "photo"                         // CKAsset
        static let photoLongSidePx = "photoLongSidePx"
        static let userPlantID = "userPlantID"
        static let catalogVersion = "catalogVersion"
        static let plantTopIDs = "plantTopIDs"
        static let plantTopScores = "plantTopScores"
        static let leafScores = "leafScores"
        static let plantModelVersion = "plantModelVersion"
        static let leafModelVersion = "leafModelVersion"
        static let feedback = "feedback"
        static let correctedPlantID = "correctedPlantID"
        static let correctedLeafClass = "correctedLeafClass"
        static let space = "space"
        static let month = "month"                         // QUERYABLE (3-year cleanup)
        static let appVersion = "appVersion"
        static let osVersion = "osVersion"
        static let deviceFamily = "deviceFamily"
    }
}

// MARK: - Enums (stored as String raw values; never rename a case)

enum SampleKind: String, Codable, CaseIterable, Sendable {
    case plantID        // photo used for plant identification
    case leafProblem    // photo used for the leaf problem check
}

/// Coarse place only (spec §3: "balcony / window sill / indoor / terrace"). No address, no GPS.
enum SharedSpace: String, Codable, CaseIterable, Sendable {
    case balcony, terrace, outdoorGround, windowSill, indoor, unknown
}

enum SampleFeedback: String, Codable, CaseIterable, Sendable {
    case none, right, wrong
}

// MARK: - Consent (kept on the phone only, never uploaded)

struct SharingConsent: Codable, Hashable, Sendable {
    /// The checkbox / Settings switch. Starts unticked (spec §1).
    var isOn: Bool = false
    /// User said they are 18 or older. Under 18 → sharing stays off (spec §6, DPDP Act).
    var isAdultConfirmed: Bool = false
    /// Random id made at install; lets the user delete "everything from this phone".
    /// Not linked to the Apple ID. A reinstall makes a new one.
    var installID: UUID = UUID()
    var changedAt: Date? = nil
    /// Upload only on Wi-Fi by default (spec §4).
    var wifiOnly: Bool = true

    var allowsUpload: Bool { isOn && isAdultConfirmed }

    mutating func set(on: Bool, now: Date = Date()) {
        isOn = on
        changedAt = now
    }
}

// MARK: - One shared sample

struct PlantGuess: Codable, Hashable, Sendable {
    var speciesID: Int      // plant_id in Kyari_plant_care_dataset.csv
    var score: Double       // 0…1
}

struct SharedSample: Codable, Hashable, Identifiable, Sendable {
    /// Also the CloudKit recordName. Random, not linked to the Apple ID.
    var id: UUID = UUID()
    var installID: UUID
    var kind: SampleKind
    /// Local file (Application Support/SharingQueue/<id>.jpg): resized, metadata removed.
    var photoFileName: String
    var photoLongSidePx: Int

    /// Plant the user picked (dataset plant_id); nil if not picked.
    var userPlantID: Int?
    /// Version of the bundled catalogue, e.g. "215-2026-11-25", so ids stay meaningful.
    var catalogVersion: String

    var plantTop: [PlantGuess] = []          // up to 3, best first (plantID samples)
    var leafScores: [Double] = []            // 14, order = SharingSchema.leafClassOrder
    var plantModelVersion: String
    var leafModelVersion: String?

    var feedback: SampleFeedback = .none
    var correctedPlantID: Int?
    var correctedLeafClass: String?          // one of leafClassOrder

    var space: SharedSpace = .unknown
    var month: String                        // "2026-11", never a full date
    var appVersion: String
    var osVersion: String
    var deviceFamily: String                 // "iPhone 13" (family, not serial or name)

    // Local-only state (not uploaded)
    var createdAt: Date = Date()
    var skippedByUser: Bool = false          // "Don't share this one"
    var uploadedAt: Date? = nil
}

// MARK: - Validation

enum SharingIssue: Equatable, Sendable {
    case photoTooLarge(Int)
    case leafScoresWrongCount(Int)
    case leafScoreOutOfRange
    case plantTopTooMany(Int)
    case plantScoreOutOfRange
    case kindNeedsResult(SampleKind)
    case unknownCorrectedClass(String)
    case correctionWithoutWrong
    case badMonth(String)
    case emptyVersion
}

extension SharedSample {
    /// Empty = OK to queue. Checked again right before upload.
    func validate() -> [SharingIssue] {
        var issues: [SharingIssue] = []
        if photoLongSidePx > SharingSchema.photoLongSidePx { issues.append(.photoTooLarge(photoLongSidePx)) }

        switch kind {
        case .plantID where plantTop.isEmpty, .leafProblem where leafScores.isEmpty:
            issues.append(.kindNeedsResult(kind))
        default: break
        }
        if !leafScores.isEmpty {
            if leafScores.count != SharingSchema.leafClassOrder.count {
                issues.append(.leafScoresWrongCount(leafScores.count))
            }
            if leafScores.contains(where: { !(0...1).contains($0) }) { issues.append(.leafScoreOutOfRange) }
        }
        if plantTop.count > SharingSchema.plantTopCount { issues.append(.plantTopTooMany(plantTop.count)) }
        if plantTop.contains(where: { !(0...1).contains($0.score) }) { issues.append(.plantScoreOutOfRange) }

        if let cls = correctedLeafClass, !SharingSchema.leafClassOrder.contains(cls) {
            issues.append(.unknownCorrectedClass(cls))
        }
        if (correctedLeafClass != nil || correctedPlantID != nil) && feedback != .wrong {
            issues.append(.correctionWithoutWrong)
        }
        if !ShareMonth.isValid(month) { issues.append(.badMonth(month)) }
        if plantModelVersion.isEmpty || catalogVersion.isEmpty || appVersion.isEmpty {
            issues.append(.emptyVersion)
        }
        return issues
    }
}

// MARK: - Month only (no exact time)

enum ShareMonth {
    static func string(from date: Date, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    static func isValid(_ s: String) -> Bool {
        let parts = s.split(separator: "-")
        guard parts.count == 2, parts[0].count == 4, parts[1].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]) else { return false }
        return (2025...2100).contains(y) && (1...12).contains(m)
    }
}

// MARK: - Upload policy (pure, testable)

enum UploadDecision: Equatable, Sendable {
    case upload
    case wait          // try again later (no Wi-Fi, waiting for feedback)
    case drop          // never upload; delete the local copy
}

enum UploadPolicy {
    /// Consent is read at upload time, so switching it off stops queued samples too.
    static func decide(_ s: SharedSample, consent: SharingConsent,
                       onWiFi: Bool, now: Date = Date()) -> UploadDecision {
        if !consent.allowsUpload || s.skippedByUser || s.uploadedAt != nil { return .drop }
        if s.installID != consent.installID { return .drop }      // from an older install
        if !s.validate().isEmpty { return .drop }
        if consent.wifiOnly && !onWiFi { return .wait }
        let waitedEnough = now.timeIntervalSince(s.createdAt) >= SharingSchema.feedbackWait
        return (s.feedback != .none || waitedEnough) ? .upload : .wait
    }
}

// MARK: - JPEG metadata check (refuse photos that still carry EXIF/XMP/IPTC)

enum JPEGMetadata {
    /// Names of metadata segments found: "Exif", "XMP", "IPTC". Empty = clean.
    /// Returns ["not a JPEG"] if the start-of-image marker is missing.
    static func findSegments(in data: Data) -> [String] {
        let b = [UInt8](data)
        guard b.count >= 4, b[0] == 0xFF, b[1] == 0xD8 else { return ["not a JPEG"] }
        var found: [String] = []
        var i = 2
        while i + 4 <= b.count, b[i] == 0xFF {
            let marker = b[i + 1]
            if marker == 0xDA || marker == 0xD9 { break }          // image data starts / end
            let length = Int(b[i + 2]) << 8 | Int(b[i + 3])
            guard length >= 2, i + 2 + length <= b.count else { break }
            let payload = b[(i + 4)..<(i + 2 + length)]
            let head = String(decoding: payload.prefix(29), as: UTF8.self)
            if marker == 0xE1 && head.hasPrefix("Exif") { found.append("Exif") }
            if marker == 0xE1 && head.hasPrefix("http://ns.adobe.com/xap") { found.append("XMP") }
            if marker == 0xED { found.append("IPTC") }
            i += 2 + length
        }
        return found
    }

    static func isClean(_ data: Data) -> Bool { findSegments(in: data).isEmpty }
}

// MARK: - Field map (platform-neutral; CloudKit record built from this)

enum SharedFieldValue: Equatable, Sendable {
    case string(String), int(Int), intList([Int]), doubleList([Double]), asset(fileName: String)
}

extension SharedSample {
    /// Exactly what leaves the phone. Local-only state (createdAt, skippedByUser, uploadedAt)
    /// is NOT in here; createdAt is replaced by CloudKit's own creation time.
    func cloudFields() -> [String: SharedFieldValue] {
        typealias F = SharingSchema.Field
        var f: [String: SharedFieldValue] = [
            F.schemaVersion: .int(SharingSchema.schemaVersion),
            F.installID: .string(installID.uuidString),
            F.kind: .string(kind.rawValue),
            F.photo: .asset(fileName: photoFileName),
            F.photoLongSidePx: .int(photoLongSidePx),
            F.catalogVersion: .string(catalogVersion),
            F.plantModelVersion: .string(plantModelVersion),
            F.feedback: .string(feedback.rawValue),
            F.space: .string(space.rawValue),
            F.month: .string(month),
            F.appVersion: .string(appVersion),
            F.osVersion: .string(osVersion),
            F.deviceFamily: .string(deviceFamily),
        ]
        if let v = userPlantID { f[F.userPlantID] = .int(v) }
        if !plantTop.isEmpty {
            f[F.plantTopIDs] = .intList(plantTop.map(\.speciesID))
            f[F.plantTopScores] = .doubleList(plantTop.map(\.score))
        }
        if !leafScores.isEmpty { f[F.leafScores] = .doubleList(leafScores) }
        if let v = leafModelVersion { f[F.leafModelVersion] = .string(v) }
        if let v = correctedPlantID { f[F.correctedPlantID] = .int(v) }
        if let v = correctedLeafClass { f[F.correctedLeafClass] = .string(v) }
        return f
    }
}

// MARK: - CloudKit (Apple platforms only; not compiled on Windows)

#if canImport(CloudKit)
extension SharedSample {
    /// - Parameter photoDirectory: folder that holds `photoFileName` (the sharing queue).
    func makeRecord(photoDirectory: URL) -> CKRecord {
        let record = CKRecord(recordType: SharingSchema.recordType,
                              recordID: CKRecord.ID(recordName: id.uuidString))
        for (key, value) in cloudFields() {
            switch value {
            case .string(let s): record[key] = s as CKRecordValue
            case .int(let n): record[key] = NSNumber(value: n)
            case .intList(let a): record[key] = a.map { NSNumber(value: $0) } as CKRecordValue
            case .doubleList(let a): record[key] = a.map { NSNumber(value: $0) } as CKRecordValue
            case .asset(let name): record[key] = CKAsset(fileURL: photoDirectory.appendingPathComponent(name))
            }
        }
        return record
    }
}

/// Upload and delete in the public database of the Kyari container.
/// Roles in the CloudKit dashboard: World = none, Authenticated = create, Creator = read + write.
struct SharedSampleCloud {
    let database: CKDatabase   // CKContainer(identifier: "iCloud.<kyari>").publicCloudDatabase

    func upload(_ sample: SharedSample, photoDirectory: URL) async throws {
        _ = try await database.save(sample.makeRecord(photoDirectory: photoDirectory))
    }

    /// "Delete what I shared": every record with this install id (creator can read own records).
    /// Also pass ids remembered locally, so deletion works even if the query index lags.
    func deleteAll(installID: UUID, knownIDs: [UUID]) async throws {
        let predicate = NSPredicate(format: "%K == %@", SharingSchema.Field.installID, installID.uuidString)
        let query = CKQuery(recordType: SharingSchema.recordType, predicate: predicate)
        var ids = Set(knownIDs.map { CKRecord.ID(recordName: $0.uuidString) })
        var (results, cursor) = try await database.records(matching: query, desiredKeys: [])
        while true {
            ids.formUnion(results.map(\.0))
            guard let c = cursor else { break }
            (results, cursor) = try await database.records(continuingMatchFrom: c, desiredKeys: [])
        }
        guard !ids.isEmpty else { return }
        _ = try await database.modifyRecords(saving: [], deleting: Array(ids))
    }
}
#endif

// MARK: - Mapping from the app's own types (KyariModels_Generic.swift)
//
// Kept as plain functions on raw values so this file stays independent:
//   SpaceType.rawValue → SharedSpace       DiseaseClass.rawValue → training class name

extension SharedSpace {
    /// Coarsens the app's SpaceType (7 cases) to what the spec allows.
    init(appSpaceTypeRaw raw: String?) {
        switch raw {
        case "balcony": self = .balcony
        case "terrace": self = .terrace
        case "frontYard": self = .outdoorGround
        case "windowSill": self = .windowSill
        case "bedroom", "livingRoom", "kitchen": self = .indoor
        default: self = .unknown
        }
    }
}

enum LeafClassName {
    /// DiseaseClass.rawValue (app) → training class name (shared records).
    static let fromAppRaw: [String: String] = [
        "downyMildew": "Downy mildew", "healthy": "Healthy",
        "insectChewing": "Insect chewing damage", "leafBlight": "Leaf blight",
        "leafCurl": "Leaf curl", "leafSpot": "Leaf spot", "mosaicVirus": "Mosaic virus",
        "notALeaf": "Not a leaf or unclear", "powderyMildew": "Powdery mildew",
        "rotAndWilt": "Rot and wilt", "rust": "Rust", "scorchAndDry": "Scorch and dry leaf",
        "visiblePests": "Visible pests", "yellowing": "Yellowing",
    ]
}
