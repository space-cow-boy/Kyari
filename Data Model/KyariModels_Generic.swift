//
//  KyariModels.swift
//  Kyari (Meri Kyari) — data model
//
//  Three layers:
//    1. Catalogue  — read-only structs loaded from catalog.json in the app bundle
//    2. Garden     — user data, SwiftData @Model classes, synced to the user's private iCloud
//    3. Derived    — structs worked out from 1 + 2, never stored (PlantState is cached)
//
//  CloudKit rules followed everywhere in layer 2:
//    • every stored property has a default value or is optional
//    • every relationship is optional (arrays default to [])
//    • no @Attribute(.unique)
//  Enums are stored as their String raw value (`...Raw`) with a typed computed
//  property, so #Predicate filters work and new enum cases never break old data.
//
//  Target: iOS 17+ (SwiftData, Observation). Not yet compiled: build in Xcode and fix any SDK differences.
//

import Foundation
import Observation
import SwiftData

// MARK: - ─────────────────────────────────────────────────────────────
// MARK:   1. CATALOGUE (bundled, read-only)
// MARK: - ─────────────────────────────────────────────────────────────

/// How much we trust a care value. Matches the `_credibility` columns in the dataset.
enum Credibility: String, Codable, CaseIterable, Sendable {
    case high      // university or botanical source
    case medium    // category rule or scaled value
    case low       // Kyari estimate (source D1)
}

/// A care value plus where it came from. Every care number in the catalogue uses this.
/// Example: watering every 5 days, source "S12", credibility .high
struct SourcedValue<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    var value: Value
    var sourceID: String          // "S12", "D1" (Kyari rule), "G1" (general practice)
    var credibility: Credibility
}

/// A closed range such as 15...38 °C or 40...70 % humidity.
struct ValueRange: Codable, Hashable, Sendable {
    var min: Double
    var max: Double
    var isEmpty: Bool { max < min }
}

/// Watering class from the dataset (guide section 14).
enum WaterNeed: String, Codable, CaseIterable, Sendable {
    case wet           // every 2–3 days
    case moist         // 3–4
    case moderate      // 5–7
    case dryTolerant   // 7–10
    case succulent     // 10–14
}

enum LightNeed: String, Codable, CaseIterable, Sendable {
    case fullSun        // 6+ hrs direct
    case partSun        // 3–6 hrs
    case brightShade    // bright, no direct sun
    case lowLight
}

enum IndiaAvailability: String, Codable, CaseIterable, Sendable {
    case veryCommon, common, uncommon, collector
}

enum IndiaClimateFit: String, Codable, CaseIterable, Sendable {
    case easy, moderate, needsHumidityOrShade, winterOnlyPlains, coolClimateOnly
}

/// What a plant is grown for — drives "What do you want to grow?" in Find plants.
enum PlantGroup: String, Codable, CaseIterable, Sendable {
    case herb, flower, vegetable, indoorGreen, succulent, shrub, climber, fern, palm, other
}

/// One part of a soil mix: "Garden soil 40%".
struct SoilPart: Codable, Hashable, Sendable {
    var component: SoilComponent
    var percent: Int
}

enum SoilComponent: String, Codable, CaseIterable, Sendable {
    case gardenSoil, cocopeat, vermicompost, perlite, coarseSand, barkOrWoodChips, readyMix
}

/// A pest to watch for, with the Indian months it is most active (dataset "Pest warnings").
struct PestWarning: Codable, Hashable, Sendable, Identifiable {
    var id: String { pest.rawValue }
    var pest: Pest
    var activeMonths: Set<Int>     // 1 = January … 12 = December
    var trigger: String            // "Warm, dry air", "Overwatering"
    var lookFor: String            // "Fine webbing and tiny pale dots under the leaves"
    var prevent: String            // "Mist the undersides of the leaves on warm mornings"
    var sourceID: String
    var credibility: Credibility
}

enum Pest: String, Codable, CaseIterable, Sendable {
    case spiderMites, whiteflies, thrips, aphids, mealybugs, scale, fungusGnats, powderyMildew
    case citrusPsyllid, caterpillars, other
}

/// One plant species row from Kyari_plant_care_dataset.csv (158 rows).
/// Map each property to its CSV column in the build script; names here are the Swift side.
struct PlantSpecies: Codable, Hashable, Identifiable, Sendable {
    let id: Int                     // dataset id: 1…100 FloraDB, 901…958 India rows
    var name: String                // card name, exact: "Chinese Hibiscus", "Indian Holy Basil (Tulsi)"
    var shortName: String           // where space is tight: "Tulsi"
    var hindiName: String?          // "Tulsi"; nil when none (Crossandra's Tamil name is NOT Hindi)
    var scientificName: String      // "Ocimum tenuiflorum" — shown only inside profiles
    var family: String
    var group: PlantGroup
    var subCategory: String?        // "Outdoor foliage shrubs"

    // Care values (each with its source)
    var light: SourcedValue<LightNeed>
    var sunHoursPerDay: SourcedValue<ValueRange>        // 6…12 for "6+ hrs"
    var waterNeed: SourcedValue<WaterNeed>
    var wateringEveryDays: SourcedValue<Int>            // base interval, before season factor
    var waterBufferDays: SourcedValue<Int>              // grace days before "overdue" (Low, D1)
    var checkDepthCm: Int                               // "Water when the top 2 cm feels dry"
    var humidityPercent: SourcedValue<ValueRange>?      // nil for outdoor rows ("outdoor air")
    var temperatureC: SourcedValue<ValueRange>          // ideal range
    var minSurvivalTempC: SourcedValue<Double>?         // "Bring in if below 10 °C"
    var potMinDiameterCm: Int
    var potMaterials: [PotMaterial]
    var soilMix: [SoilPart]                             // best mix, sums to 100
    var feedEveryWeeks: Int?
    var plantingMonths: Set<Int>                        // "Feb Mar Apr Jul Aug"
    var pests: [PestWarning]

    // India fit
    var availability: IndiaAvailability
    var climateFit: IndiaClimateFit
}

/// A care rule that turns into a task on the care plan, per species and stage.
/// Generic rules (water, feed) are built from PlantSpecies; these cover the extras
/// seen in the frames: "Pinch off flower spikes", "Separate the 2 pups", "Thin the seedlings".
struct CareRule: Codable, Hashable, Identifiable, Sendable {
    let id: String                  // "tulsi.pinch-spikes"
    var speciesIDs: Set<Int>        // empty = all species
    var stages: Set<PlantStage>     // empty = all stages
    var milestones: Set<Milestone>  // e.g. only when .flowering
    var kind: CareTaskKind
    var title: String               // "Pinch off flower spikes"
    var detail: String              // "Keeps new leaves coming. Leave one spike if you want seeds"
    var steps: [String]             // numbered steps in the task sheet
    var repeatEveryDays: Int?       // nil = once
    var sourceID: String
}

/// The 14 classes of the disease model (final split, 22 Nov 2026).
enum DiseaseClass: String, Codable, CaseIterable, Sendable {
    case healthy, leafSpot, leafBlight, powderyMildew, downyMildew, rust, mosaicVirus
    case insectChewing, visiblePests, yellowing, scorchAndDry, rotAndWilt, leafCurl
    case notALeaf                   // "Not a leaf or unclear" → ask for a retake

    var isProblem: Bool { self != .healthy && self != .notALeaf }
}

/// One row of Kyari_causes_solutions.csv: a likely cause for a class, and what to do.
struct CauseSolution: Codable, Hashable, Identifiable, Sendable {
    let id: String                  // "leafSpot.fungal-wet-leaves"
    var diseaseClass: DiseaseClass
    var cause: String               // "Fungal leaf spot spread by wet leaves"
    var signs: [String]             // what the photo or the log would show
    var whatToCheck: [String]       // feeds the one quick question
    var contextRule: ContextRule?   // when the care log / weather makes this cause likelier
    var firstSteps: [String]
    var ifItContinues: [String]
    var whenToGetHelp: String
    var sourceIDs: [String]
}

/// A rule the cause ranker checks against PlantState and weather.
struct ContextRule: Codable, Hashable, Sendable {
    enum Signal: String, Codable, Sendable {
        case wateredMoreThanNeeded, wateredLessThanNeeded, leavesGetWet, lowHumidity, highHumidity
        case lowLight, tooMuchSun, coldNights, recentRepot, recentMove, potNoDrainage
    }
    var signal: Signal
    var weight: Double              // how much it raises this cause's rank
}

/// Everything bundled. Decoded once from catalog.json.
struct CatalogFile: Codable, Sendable {
    var version: String             // bump when the dataset changes, e.g. "2026-11-23"
    var species: [PlantSpecies]
    var careRules: [CareRule]
    var causes: [CauseSolution]
    var seasonFactorOutdoor: [Int: Double]   // month → factor (ICAR S106: Jan 2.4 … Dec 2.3)
    var sources: [String: String]            // "S12" → title + URL, for the profile's source sheet
}

// MARK: - ─────────────────────────────────────────────────────────────
// MARK:   2. GARDEN (user data, SwiftData + CloudKit)
// MARK: - ─────────────────────────────────────────────────────────────

// MARK: Shared enums

enum SpaceType: String, Codable, CaseIterable, Sendable {
    case balcony, terrace, frontYard, windowSill, bedroom, livingRoom, kitchen
    var isIndoor: Bool { [.windowSill, .bedroom, .livingRoom, .kitchen].contains(self) }
}

/// "What's in front of it?" on the Set up screen. More than one can apply.
enum Obstruction: String, Codable, CaseIterable, Sendable {
    case openSky, trees, building, roofOrShadeAbove
}

/// Indoor light reading ("Brightness by the window").
enum IndoorBrightness: String, Codable, CaseIterable, Sendable {
    case low, medium, bright, directSun
}

/// "Does this look right?" answer on the space result screen.
enum LightCorrection: String, Codable, CaseIterable, Sendable {
    case less, aboutRight, more
}

/// The four stages offered when adding a plant.
enum PlantStage: String, Codable, CaseIterable, Sendable {
    case seed          // "Seed or just sprouting"
    case seedling      // "Small seedling"
    case young         // "Young plant"
    case established   // "Established plant"
}

/// Journey milestones (the chip on the profile header and the journey dots).
enum Milestone: String, Codable, CaseIterable, Sendable {
    case sown, sprouted, trueLeaves, bushy, branching, rooted, buds, firstFlowers, flowering
    case fruiting, dormant, recovering
}

/// Where the plant sits inside its space in the My Garden scene.
/// Align the cases with Kyari_my_garden_system.md (surfaces, slots, shelves, hanging).
enum SurfaceKind: String, Codable, CaseIterable, Sendable {
    case floor, wallShelf, hangingHook, railing, windowSill, table, custom
}

enum PotSize: String, Codable, CaseIterable, Sendable {
    case small    // under 15 cm
    case medium   // 15–25 cm
    case large    // over 25 cm
    case notSure
}

enum PotMaterial: String, Codable, CaseIterable, Sendable {
    case plastic, clay, ceramic, other, waterJar   // waterJar = cutting rooting in water
}

enum TriState: String, Codable, CaseIterable, Sendable { case yes, no, notSure }

enum SoilMoisture: String, Codable, CaseIterable, Sendable { case dry, damp, wet }

/// "Last watered" buckets on the Care sheet. Saved as an estimated event.
enum LastWateredBucket: String, Codable, CaseIterable, Sendable {
    case today, yesterday, twoToThreeDays, aWeekPlus
    /// Days ago to use for the estimated event (middle of the bucket).
    var daysAgo: Int {
        switch self {
        case .today: 0
        case .yesterday: 1
        case .twoToThreeDays: 2
        case .aWeekPlus: 7
        }
    }
}

/// How the plant's name was chosen when it was added.
enum IdentificationMethod: String, Codable, Sendable {
    case photoModel      // BioCLIP 2 top-3, user confirmed
    case search          // typed "Tul" → picked Tulsi
    case manual          // "Use 'Tul' as the name" — not in the catalogue
    case fromSavedList   // "I bought it" on a saved plant
    case notYet          // seed, "name it once it sprouts"
}

// MARK: Embedded value types (stored inside a @Model as Codable)

/// Placement in the 2.5D My Garden scene. Normalised 0…1 inside the space's canvas.
struct GardenSpot: Codable, Hashable, Sendable {
    var surface: SurfaceKind = .floor
    var surfaceID: String?          // which shelf / hook when a scene has more than one
    var slotIndex: Int?             // fixed slot, if the scene uses slots
    var x: Double = 0.5
    var y: Double = 0.5
    var label: String {             // "Balcony floor", "hanging hook"
        switch surface {
        case .floor: "floor"
        case .wallShelf: "wall shelf"
        case .hangingHook: "hanging hook"
        case .railing: "railing"
        case .windowSill: "window sill"
        case .table: "table"
        case .custom: "spot"
        }
    }
}

/// Pot and soil sheet ("Helps us time watering").
struct PotSetup: Codable, Hashable, Sendable {
    var size: PotSize = .notSure
    var material: PotMaterial?
    var drainage: TriState = .notSure
    var soil: Set<SoilComponent> = []
    var soilNotSure: Bool = false
    var isComplete: Bool { size != .notSure && material != nil && drainage != .notSure && (!soil.isEmpty || soilNotSure) }
}

/// What BioCLIP suggested at onboarding (kept so wrong-name reports can be checked).
struct IdentificationCandidate: Codable, Hashable, Sendable {
    var speciesID: Int
    var score: Double
}

/// Sun estimate for a space, from compass + sky + location (Set up screens).
struct SunEstimate: Codable, Hashable, Sendable {
    var winterHours: ValueRange?          // "About 4 to 5 hrs"; nil indoors
    var summerHours: ValueRange?
    var directSunToday: DateInterval?     // "12:40 pm to 5:20 pm" (refreshed daily)
    var indoorBrightnessWinter: IndoorBrightness?
    var indoorBrightnessSummer: IndoorBrightness?
    var computedAt: Date = .now
}

// MARK: UserProfile — one per user (Account screen)

@Model
final class UserProfile {
    var id: UUID = UUID()
    var displayName: String = ""              // "Team R"
    var signInProviderRaw: String = SignInProvider.apple.rawValue
    var cityName: String = ""                 // "Dehradun, Uttarakhand"
    var latitude: Double?                     // 30.32 — used for sun paths and WeatherKit
    var longitude: Double?
    var timeZoneID: String = TimeZone.current.identifier
    var recentCities: [String] = []           // "Mussoorie", "New Delhi"
    var createdAt: Date = Date.now

    init(displayName: String = "", provider: SignInProvider = .apple) {
        self.displayName = displayName
        self.signInProviderRaw = provider.rawValue
    }

    var signInProvider: SignInProvider {
        get { SignInProvider(rawValue: signInProviderRaw) ?? .apple }
        set { signInProviderRaw = newValue.rawValue }
    }
}

enum SignInProvider: String, Codable, Sendable { case apple, google }

// MARK: Space — Balcony, Back balcony, Bedroom, Terrace, Front balcony

@Model
final class Space {
    var id: UUID = UUID()
    var name: String = ""                     // as said at home: "Front balcony"
    var typeRaw: String = SpaceType.balcony.rawValue
    var facingDegrees: Double?                // 225 = SW; nil until set up
    var obstructionsRaw: [String] = []        // Obstruction raw values
    var sun: SunEstimate?
    var correctionRaw: String?                // LightCorrection — nudges the estimate
    var sceneID: String?                      // which Blender scene renders this space
    var sortOrder: Int = 0
    var createdAt: Date = Date.now

    /// Plants here. Deleting a space must not delete plants: the UI asks to move them first.
    @Relationship(deleteRule: .nullify, inverse: \Plant.space)
    var plants: [Plant]? = []

    init(name: String, type: SpaceType, sortOrder: Int = 0) {
        self.name = name
        self.typeRaw = type.rawValue
        self.sortOrder = sortOrder
    }

    var type: SpaceType {
        get { SpaceType(rawValue: typeRaw) ?? .balcony }
        set { typeRaw = newValue.rawValue }
    }
    var obstructions: Set<Obstruction> {
        get { Set(obstructionsRaw.compactMap(Obstruction.init(rawValue:))) }
        set { obstructionsRaw = newValue.map(\.rawValue).sorted() }
    }
    var correction: LightCorrection? {
        get { correctionRaw.flatMap(LightCorrection.init(rawValue:)) }
        set { correctionRaw = newValue?.rawValue }
    }
    var isIndoor: Bool { type.isIndoor }
    var activePlants: [Plant] { (plants ?? []).filter { $0.removedAt == nil } }
}

// MARK: Plant — one real plant the user owns

@Model
final class Plant {
    var id: UUID = UUID()
    var speciesID: Int?                       // nil = not named yet (seed) or manual name
    var displayName: String = ""              // copy of the species name, or the manual name
    var nickname: String?
    var stageRaw: String = PlantStage.established.rawValue
    var milestoneRaw: String?                 // "flowering" → chip on the header
    var startedOn: Date = Date.now            // Day 1 (date added, or sowing date)
    var addedAt: Date = Date.now
    var identificationRaw: String = IdentificationMethod.photoModel.rawValue
    var identificationCandidates: [IdentificationCandidate] = []
    var spot: GardenSpot = GardenSpot()
    var pot: PotSetup = PotSetup()
    var careDetailsAddedAt: Date?             // set when the Care sheet is saved once
    var learnedWateringDays: Double?          // learned from "soil still moist" skips
    var state: PlantState?                    // cached derived state (see section 3)
    var removedAt: Date?                      // soft-remove while Undo is on screen; then hard delete

    @Attribute(.externalStorage) var avatarImage: Data?   // AI cut-out on white (Home/Garden avatar)
    @Attribute(.externalStorage) var headerImage: Data?   // profile header photo

    var space: Space?

    @Relationship(deleteRule: .cascade, inverse: \CareEvent.plant)
    var careEvents: [CareEvent]? = []

    @Relationship(deleteRule: .cascade, inverse: \JourneyEntry.plant)
    var journey: [JourneyEntry]? = []

    @Relationship(deleteRule: .cascade, inverse: \DiagnosisReport.plant)
    var reports: [DiagnosisReport]? = []

    init(speciesID: Int?, displayName: String, stage: PlantStage, space: Space?,
         startedOn: Date = .now, method: IdentificationMethod) {
        self.speciesID = speciesID
        self.displayName = displayName
        self.stageRaw = stage.rawValue
        self.space = space
        self.startedOn = startedOn
        self.identificationRaw = method.rawValue
    }

    var stage: PlantStage {
        get { PlantStage(rawValue: stageRaw) ?? .established }
        set { stageRaw = newValue.rawValue }
    }
    var milestone: Milestone? {
        get { milestoneRaw.flatMap(Milestone.init(rawValue:)) }
        set { milestoneRaw = newValue?.rawValue }
    }
    var identification: IdentificationMethod {
        IdentificationMethod(rawValue: identificationRaw) ?? .manual
    }

    /// "Day 164" on the header.
    func dayNumber(on date: Date = .now, calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: startedOn),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        return days + 1
    }

    /// "Balcony, hanging hook" on reports.
    var locationLabel: String {
        guard let space else { return "No space yet" }
        return "\(space.name), \(spot.label)"
    }

    /// The 75% ring: four Details rows (Plant, Location, Pot, Care), 25% each.
    var profileCompleteness: Double {
        var done = 0
        if speciesID != nil || !displayName.isEmpty { done += 1 }   // Plant: name, stage, photo
        if space != nil { done += 1 }                               // Location
        if pot.isComplete { done += 1 }                             // Pot
        if careDetailsAddedAt != nil { done += 1 }                  // Care
        return Double(done) / 4
    }

    /// Care log without undone entries, newest first.
    var activeEvents: [CareEvent] {
        (careEvents ?? []).filter { $0.undoneAt == nil }.sorted { $0.date > $1.date }
    }
}

// MARK: CareEvent — the care log (append-only)

enum CareEventKind: String, Codable, CaseIterable, Sendable {
    case watered, skippedSoilMoist, fed, repotted, pruned, pinched, misted
    case changedWater, pottedUp, separatedPups, turnedPot, wipedLeaves
    case pestCheckClear, pestFound
    case postponed            // "Later" / "Remind me in 3 days" / "Moved to tomorrow"
    case movedSpace, broughtIndoors, soilCheck, note, custom
}

/// Where the event was recorded — useful when checking reminder bugs.
enum EventSource: String, Codable, Sendable {
    case homeCareCard, carePlan, careSheet, report, notification, widget, journey
}

@Model
final class CareEvent {
    var id: UUID = UUID()
    var date: Date = Date.now
    var kindRaw: String = CareEventKind.watered.rawValue
    var sourceRaw: String = EventSource.homeCareCard.rawValue
    var isEstimate: Bool = false              // from the "Last watered: 2 to 3 days" bucket
    var taskID: String?                       // CareTask.id it completed / postponed
    var postponedUntil: Date?                 // for .postponed
    var pestRaw: String?                      // for pest checks
    var soilMoistureRaw: String?              // Dry / Damp / Wet on the Care sheet
    var fromSpaceID: UUID?                    // for .movedSpace
    var toSpaceID: UUID?
    var note: String?                         // "Anything you noticed"
    var undoneAt: Date?                       // Undo never deletes; it marks
    var plant: Plant?

    init(kind: CareEventKind, plant: Plant, date: Date = .now, source: EventSource,
         taskID: String? = nil, isEstimate: Bool = false) {
        self.kindRaw = kind.rawValue
        self.plant = plant
        self.date = date
        self.sourceRaw = source.rawValue
        self.taskID = taskID
        self.isEstimate = isEstimate
    }

    var kind: CareEventKind { CareEventKind(rawValue: kindRaw) ?? .custom }
    var source: EventSource { EventSource(rawValue: sourceRaw) ?? .carePlan }
    var soilMoisture: SoilMoisture? {
        get { soilMoistureRaw.flatMap(SoilMoisture.init(rawValue:)) }
        set { soilMoistureRaw = newValue?.rawValue }
    }
    var pest: Pest? {
        get { pestRaw.flatMap(Pest.init(rawValue:)) }
        set { pestRaw = newValue?.rawValue }
    }
}

// MARK: JourneyEntry — growth journey photos

@Model
final class JourneyEntry {
    var id: UUID = UUID()
    var date: Date = Date.now
    var milestoneRaw: String?                 // "trueLeaves" — nil for an ordinary weekly photo
    var note: String?
    var isStartPhoto: Bool = false            // "Added as a seed" / "Day 1 of the growth journey"
    @Attribute(.externalStorage) var image: Data?
    @Attribute(.externalStorage) var thumbnail: Data?     // 256 px, for the journey strip
    var plant: Plant?

    init(plant: Plant, date: Date = .now, milestone: Milestone? = nil, note: String? = nil, image: Data?) {
        self.plant = plant
        self.date = date
        self.milestoneRaw = milestone?.rawValue
        self.note = note
        self.image = image
    }

    var milestone: Milestone? { milestoneRaw.flatMap(Milestone.init(rawValue:)) }
}

// MARK: DiagnosisReport — one check from the Diagnosis tab

/// Where a sentence in the report came from. Enforces "honest claims".
enum Evidence: String, Codable, CaseIterable, Sendable {
    case photo          // only this may appear under "What we noticed"
    case careLog
    case weather
    case userAnswer     // the one quick question
    case plantProfile   // space, sun hours, pot
    case dataset        // species care values, causes table
}

/// Icon tone of a line: warning (yellow) or fine (green tick).
enum FindingTone: String, Codable, Sendable { case concern, fine }

struct ReportLine: Codable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    var text: String                // "Brown spots with yellow rings on this leaf"
    var evidence: Evidence
    var tone: FindingTone
    var causeID: String?            // CauseSolution.id it supports
}

struct ReportStep: Codable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    var order: Int
    var text: String                // "Cut off the spotted leaf at the stem…"
    var when: String                // "Today", "From now", "Next week"
    var createsTaskKind: CareTaskKind?   // a step can add a task to the care plan
    var dueDate: Date?
}

struct ClassScore: Codable, Hashable, Sendable {
    var diseaseClass: DiseaseClass
    var confidence: Double
}

struct QuickAnswer: Codable, Hashable, Sendable {
    var question: String            // "Do you water from above, over the leaves?"
    var answer: String
}

/// What the pipeline read before writing the report (frozen for audits and wrong-report checks).
struct ContextSnapshot: Codable, Hashable, Sendable {
    var speciesID: Int?
    var stage: PlantStage
    var spaceType: SpaceType?
    var spot: SurfaceKind?
    var sunHoursPerDay: ValueRange?
    var averageWateringDays: Double?        // from the last 14 days of events
    var lastWatered: Date?
    var lastSoilMoisture: SoilMoisture?
    var avgHumidity7d: Double?
    var tempRange7d: ValueRange?
    var catalogVersion: String
}

enum ReportStatus: String, Codable, Sendable {
    case healthy, problem, notSure      // notSure = confidence < 0.6 → "take a closer photo"
}

enum PhotoQuality: String, Codable, Sendable { case clear, blurry, tooFar, notAPlant, usedAnyway }

@Model
final class DiagnosisReport {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var statusRaw: String = ReportStatus.notSure.rawValue
    var title: String = ""                    // "Leaf spot, early stage" / "Looks healthy"
    var affectedPart: String?                 // chip: "Lower leaves", "Leaf spots"
    var topClassRaw: String = DiseaseClass.healthy.rawValue
    var scores: [ClassScore] = []             // top 3 from the model
    var photoQualityRaw: String = PhotoQuality.clear.rawValue
    var noticed: [ReportLine] = []            // evidence must be .photo
    var reasons: [ReportLine] = []            // "Why we think it happened" / "Why it's doing well"
    var steps: [ReportStep] = []              // "What to do" / "Keep it healthy"
    var answers: [QuickAnswer] = []
    var context: ContextSnapshot?
    var modelVersion: String = ""             // "kyari-disease-v1 (Create ML)"
    var isSaved: Bool = false                 // "Save report" / "Done"
    var followUpOn: Date?                     // "We will remind you to check again"
    var userSaysWrong: Bool = false           // set from Report a problem
    @Attribute(.externalStorage) var photo: Data?
    var plant: Plant?

    init(plant: Plant, photo: Data?) {
        self.plant = plant
        self.photo = photo
    }

    var status: ReportStatus {
        get { ReportStatus(rawValue: statusRaw) ?? .notSure }
        set { statusRaw = newValue.rawValue }
    }
    var topClass: DiseaseClass {
        get { DiseaseClass(rawValue: topClassRaw) ?? .healthy }
        set { topClassRaw = newValue.rawValue }
    }
    var photoQuality: PhotoQuality {
        get { PhotoQuality(rawValue: photoQualityRaw) ?? .clear }
        set { photoQualityRaw = newValue.rawValue }
    }

    /// Call before saving. Returns the lines that break the honest-claims rule.
    func honestyViolations() -> [ReportLine] {
        noticed.filter { $0.evidence != .photo }
    }
}

// MARK: WeatherDay — one day of weather for the user's city (WeatherKit)

@Model
final class WeatherDay {
    var id: UUID = UUID()
    var day: Date = Date.now                  // start of day, local time
    var latitude: Double = 0
    var longitude: Double = 0
    var tempMinC: Double = 0
    var tempMaxC: Double = 0
    var humidityPercent: Double = 0
    var rainChance: Double = 0                // 0…1
    var rainMm: Double = 0
    var conditionSymbol: String = "sun.max"   // SF Symbol from WeatherKit
    var conditionText: String = ""            // "Sunny"
    var sunrise: Date?
    var sunset: Date?
    var isForecast: Bool = true               // becomes false once the day has passed
    var fetchedAt: Date = Date.now

    init(day: Date, latitude: Double, longitude: Double) {
        self.day = day
        self.latitude = latitude
        self.longitude = longitude
    }
}

// MARK: SavedPlant — "Plants you are thinking about"

@Model
final class SavedPlant {
    var id: UUID = UUID()
    var speciesID: Int = 0
    var savedAt: Date = Date.now
    var forSpaceID: UUID?                     // the space chosen in Find plants
    var boughtAt: Date?                       // "I bought it" → starts Add a plant
    var addedPlantID: UUID?                   // the Plant made from it

    init(speciesID: Int, forSpaceID: UUID? = nil) {
        self.speciesID = speciesID
        self.forSpaceID = forSpaceID
    }
}

// MARK: SupportTicket — Report a problem / Send feedback

enum TicketKind: String, Codable, CaseIterable, Sendable {
    case wrongPlantName, wrongHealthReport, reminderIssue, appBug, somethingElse, feedback
}

enum TicketStatus: String, Codable, Sendable { case draft, sent, inProgress, resolved }

@Model
final class SupportTicket {
    var id: UUID = UUID()
    var kindRaw: String = TicketKind.somethingElse.rawValue
    var statusRaw: String = TicketStatus.draft.rawValue
    var reference: String?                    // "#MK-1042", given when sent
    var createdAt: Date = Date.now
    var message: String = ""
    var rating: String?                       // feedback: "Love it" / "It's okay" / "Not great"
    var votedIdeas: [String] = []             // "Garden widgets", "Hindi language"
    var reportID: UUID?                       // the report it is about
    var plantID: UUID?
    @Attribute(.externalStorage) var screenshot: Data?

    init(kind: TicketKind, message: String = "") {
        self.kindRaw = kind.rawValue
        self.message = message
    }

    var kind: TicketKind { TicketKind(rawValue: kindRaw) ?? .somethingElse }
    var status: TicketStatus {
        get { TicketStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }
}

// MARK: Schema

enum KyariSchema {
    static let models: [any PersistentModel.Type] = [
        UserProfile.self, Space.self, Plant.self, CareEvent.self, JourneyEntry.self,
        DiagnosisReport.self, WeatherDay.self, SavedPlant.self, SupportTicket.self
    ]

    /// App container: private iCloud database.
    static func container(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(models)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: inMemory ? ModelConfiguration.CloudKitDatabase.none
                                       : .private("iCloud.com.teamr.kyari")   // set your container id
        )
        return try ModelContainer(for: schema, configurations: config)
    }
}

// MARK: - ─────────────────────────────────────────────────────────────
// MARK:   3. DERIVED (never stored, except the PlantState cache)
// MARK: - ─────────────────────────────────────────────────────────────

/// Plant state, rebuilt after every event and once a day. Cached on Plant.state.
/// Feeds the "This week" tiles, the care plan and the diagnosis context.
struct PlantState: Codable, Hashable, Sendable {
    var computedAt: Date
    var lastWatered: Date?
    var nextWaterDue: DateInterval?           // a range: "Times are a range and shift with weather"
    var effectiveWateringDays: Double         // base × season factor, adjusted by learned value
    var wateringsThisWeek: Int                // "Watered 3x"
    var sunHoursThisWeek: Double?             // "~38 hrs"
    var avgHumidityThisWeek: Double?          // "45%, a little dry"
    var lastSoilMoisture: SoilMoisture?
    var health: ReportStatus?                 // from the latest report
    var lastReportDate: Date?
    var activePestRisks: [Pest]
    var coldNightAlert: Bool                  // tonight's low < species minimum (outdoor spaces)
}

/// Category on the Home Care card.
enum CareCategory: String, Codable, CaseIterable, Sendable { case water, soil, health }

enum CareTaskKind: String, Codable, CaseIterable, Sendable {
    case water, mist, feed, repot, pottingUp, separatePups, changeWater
    case pinch, deadhead, prune, saveSeeds, thinSeedlings, turnPot, wipeLeaves
    case pestCheck, leafCheck, bringIndoors, keepInShade, letSettle

    var category: CareCategory {
        switch self {
        case .water, .mist, .changeWater: .water
        case .feed, .repot, .pottingUp, .separatePups: .soil
        default: .health
        }
    }
}

/// When a task is due. The UI shows the label, never a fake exact time.
enum DueWindow: Hashable, Sendable {
    case tonight, today, tomorrow, inDays(Int), thisWeek, nextWeek, inWeeks(Int), anyTime
}

/// One row of the care plan / Home card. Built by CareEngine, never stored.
/// Its id is stable for the same plant, rule and due day, so CareEvent.taskID can point at it.
struct CareTask: Identifiable, Hashable, Sendable {
    var id: String                    // "\(plantID)|\(ruleID)|\(yyyy-MM-dd)"
    var plantID: UUID
    var kind: CareTaskKind
    var title: String                 // "Water deeply"
    var detail: String                // "Until it drains, then let the top dry"
    var steps: [String]
    var due: DueWindow
    var dueDate: Date
    var pest: Pest?
    var why: String?                  // "Warm, dry air (45%) is when mites spread fast"
    var category: CareCategory { kind.category }
}

/// One row of the Home Care card: Water / Soil / Health with plant avatars.
struct CareCardRow: Identifiable, Hashable, Sendable {
    var id: CareCategory { category }
    var category: CareCategory
    var tasksToday: [CareTask]
    var tasksLater: [CareTask]        // "2 today, 1 later"
    var subtitle: String?             // "Feeding (1) | Repotting (1)"
    var isDone: Bool { tasksToday.isEmpty }
}

/// How well a species suits a space (Move to, Find plants, Where does it grow?).
enum SpaceFit: Hashable, Sendable {
    case good                         // "Good fit, 5 to 6 hrs of sun"
    case okayIf(String)               // "Okay only by a sunny window"
    case tooLittleSun, tooDark, tooHot, tooCold
    case nowHere                      // "Now here"
}

/// Unsaved input of the Add a plant flow. Held in @State; a Plant is inserted only on Save,
/// so a cancelled flow leaves nothing in the store.
struct NewPlantDraft: Hashable, Sendable {
    var stage: PlantStage = .established
    var photo: Data?
    var candidates: [IdentificationCandidate] = []   // BioCLIP top 3
    var speciesID: Int?
    var manualName: String?                          // "Use 'Tul' as the name"
    var nickname: String = ""
    var method: IdentificationMethod = .photoModel
    var spaceID: UUID?
    var fromSavedPlantID: UUID?
    var canSave: Bool { spaceID != nil && (speciesID != nil || stage == .seed || !(manualName ?? "").isEmpty) }
}

// MARK: - Sample data for previews

extension KyariSchema {
    @MainActor
    static func previewContainer() throws -> ModelContainer {
        let container = try container(inMemory: true)
        let ctx = container.mainContext
        let balcony = Space(name: "Balcony", type: .balcony, sortOrder: 0)
        balcony.facingDegrees = 135
        balcony.sun = SunEstimate(winterHours: .init(min: 5, max: 6), summerHours: .init(min: 3, max: 4))
        let bedroom = Space(name: "Bedroom", type: .bedroom, sortOrder: 2)
        ctx.insert(balcony); ctx.insert(bedroom)

        // Replace 0 with Tulsi's id from Kyari_plant_care_dataset.csv.
        let tulsi = Plant(speciesID: 0, displayName: "Indian Holy Basil (Tulsi)", stage: .seed,
                          space: balcony, startedOn: .now.addingTimeInterval(-163 * 86_400),
                          method: .search)
        tulsi.milestone = .flowering
        tulsi.spot = GardenSpot(surface: .wallShelf)
        tulsi.pot = PotSetup(size: .medium, material: .clay, drainage: .yes,
                             soil: [.gardenSoil, .cocopeat, .vermicompost])
        ctx.insert(tulsi)
        ctx.insert(CareEvent(kind: .watered, plant: tulsi, date: .now.addingTimeInterval(-2 * 86_400),
                             source: .homeCareCard))
        return container
    }
}

// MARK: - ─────────────────────────────────────────────────────────────
// MARK:   4. SERVICES (owners of non-stored data; injected with .environment)
// MARK: - ─────────────────────────────────────────────────────────────
//  Behind protocols so previews and tests can use mocks (reference §9).

/// Owns the bundled catalogue. Created once in the App and injected:
/// `.environment(catalog)` → `@Environment(PlantCatalog.self) private var catalog`
@Observable
final class PlantCatalog {
    private(set) var file: CatalogFile?
    @ObservationIgnored private var byID: [Int: PlantSpecies] = [:]

    init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CatalogFile.self, from: data) else { return }
        file = decoded
        byID = Dictionary(decoded.species.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var version: String { file?.version ?? "missing" }
    var allSpecies: [PlantSpecies] { file?.species ?? [] }
    func species(_ id: Int?) -> PlantSpecies? { id.flatMap { byID[$0] } }
    func causes(for diseaseClass: DiseaseClass) -> [CauseSolution] {
        (file?.causes ?? []).filter { $0.diseaseClass == diseaseClass }
    }
    func search(_ text: String) -> [PlantSpecies] {
        guard !text.isEmpty else { return allSpecies }
        return allSpecies.filter {
            $0.name.localizedCaseInsensitiveContains(text)
            || ($0.hindiName?.localizedCaseInsensitiveContains(text) ?? false)
            || $0.scientificName.localizedCaseInsensitiveContains(text)
        }
    }
}

/// Builds tasks and plant state. Pure functions of the data → easy to unit-test.
protocol CareEngine {
    func state(for plant: Plant, species: PlantSpecies?, weather: [WeatherDay], now: Date) -> PlantState
    func tasks(for plant: Plant, species: PlantSpecies?, rules: [CareRule], state: PlantState, now: Date) -> [CareTask]
    func careCard(from tasks: [CareTask], now: Date) -> [CareCardRow]
    func fit(_ species: PlantSpecies, in space: Space, on date: Date) -> SpaceFit
}

/// WeatherKit wrapper (Apple framework, not a third-party API). Writes WeatherDay rows.
protocol WeatherProviding {
    func refresh(latitude: Double, longitude: Double, into context: ModelContext) async throws
}

/// The on-device diagnosis flow: photo checks → model → causes → report.
protocol DiagnosisPipeline {
    func checkPhoto(_ image: Data) async -> PhotoQuality
    func classify(_ image: Data) async throws -> [ClassScore]
    func quickQuestion(for scores: [ClassScore], plant: Plant) -> String?
    func makeReport(plant: Plant, photo: Data, scores: [ClassScore], answers: [QuickAnswer],
                    catalog: PlantCatalog) async throws -> DiagnosisReport
}

/// Small per-device settings (reference §8.1). Keys in one place.
enum SettingsKey {
    static let careReminders = "careRemindersOn"       // Bool, default true
    static let weatherAlerts = "weatherAlertsOn"       // Bool, default true
    static let reminderMinutes = "reminderMinutes"     // Int, minutes after midnight; 450 = 7:30 AM
    static let lastTab = "lastTab"                     // "home" | "garden" | "diagnosis"
    static let lastSpaceID = "lastSpaceID"             // which space My Garden opens on
    static let onboardingDone = "onboardingDone"       // Bool
}
