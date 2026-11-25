//
//  KyariSharingSelfTest.swift — self-test for KyariSharing.swift (task H3)
//
//  Purpose  check the pure parts without Xcode: validation, upload policy, month string,
//           JPEG metadata scan, field map (what leaves the phone), app-type mapping.
//  Inputs   none (builds its own samples and tiny JPEG byte strings).
//  Output   one line per check, "PASS n/n" at the end; exit 1 on any failure.
//  How to run (any OS with Swift 5.9+):
//    cp "Data Model/Tests/KyariSharingSelfTest.swift" /tmp/main.swift   (top-level code must be main.swift)
//    swiftc "Data Model/KyariSharing.swift" /tmp/main.swift -o sharing_test
//    ./sharing_test
//

import Foundation

var passed = 0, failed = 0
func check(_ name: String, _ ok: Bool) {
    if ok { passed += 1 } else { failed += 1 }
    print(ok ? "ok   " : "FAIL ", name)
}

let install = UUID()
let t0 = Date(timeIntervalSince1970: 1_795_000_000)   // Nov 2026
func sample(_ kind: SampleKind = .leafProblem) -> SharedSample {
    var s = SharedSample(installID: install, kind: kind, photoFileName: "x.jpg", photoLongSidePx: 1024,
                         catalogVersion: "215-2026-11-25", plantModelVersion: "KyariPlantID 1.0",
                         month: ShareMonth.string(from: t0, timeZone: TimeZone(identifier: "Asia/Kolkata")!),
                         appVersion: "1.0", osVersion: "iOS 18.0", deviceFamily: "iPhone 13")
    s.createdAt = t0
    if kind == .leafProblem {
        s.leafModelVersion = "KyariLeafProblem B"
        s.leafScores = Array(repeating: 1.0 / 14, count: 14)
    } else {
        s.plantTop = [PlantGuess(speciesID: 905, score: 0.9), PlantGuess(speciesID: 12, score: 0.05)]
    }
    return s
}
var consentOn = SharingConsent(); consentOn.installID = install
consentOn.set(on: true); consentOn.isAdultConfirmed = true

// Consent defaults (spec §1: box starts unticked)
check("consent starts off", SharingConsent().isOn == false && SharingConsent().allowsUpload == false)
var minor = consentOn; minor.isAdultConfirmed = false
check("under-18 cannot upload", minor.allowsUpload == false)

// Month
check("month string 2026-11", sample().month == "2026-11")
check("month rejects full date", ShareMonth.isValid("2026-11-25") == false)

// Validation
check("valid leaf sample", sample().validate().isEmpty)
check("valid plant sample", sample(.plantID).validate().isEmpty)
var s = sample(); s.leafScores = [0.5, 0.5]
check("2 of 14 leaf scores rejected", s.validate().contains(.leafScoresWrongCount(2)))
s = sample(); s.photoLongSidePx = 4032
check("full-size photo rejected", s.validate().contains(.photoTooLarge(4032)))
s = sample(); s.feedback = .wrong; s.correctedLeafClass = "Yellow leaves"
check("unknown class name rejected", s.validate().contains(.unknownCorrectedClass("Yellow leaves")))
s = sample(); s.correctedLeafClass = "Yellowing"
check("correction needs feedback=wrong", s.validate().contains(.correctionWithoutWrong))
s = sample(.plantID); s.plantTop = []
check("plant sample needs a result", s.validate().contains(.kindNeedsResult(.plantID)))

// Upload policy
let later = t0.addingTimeInterval(SharingSchema.feedbackWait + 1)
check("consent off → drop", UploadPolicy.decide(sample(), consent: SharingConsent(), onWiFi: true, now: later) == .drop)
s = sample(); s.skippedByUser = true
check("per-photo skip → drop", UploadPolicy.decide(s, consent: consentOn, onWiFi: true, now: later) == .drop)
check("no feedback, < 24 h → wait", UploadPolicy.decide(sample(), consent: consentOn, onWiFi: true, now: t0) == .wait)
check("no feedback, > 24 h → upload", UploadPolicy.decide(sample(), consent: consentOn, onWiFi: true, now: later) == .upload)
s = sample(); s.feedback = .right
check("feedback given → upload now", UploadPolicy.decide(s, consent: consentOn, onWiFi: true, now: t0) == .upload)
check("Wi-Fi only, on mobile data → wait", UploadPolicy.decide(s, consent: consentOn, onWiFi: false, now: t0) == .wait)
s = sample(); s.installID = UUID(); s.feedback = .right
check("old install id → drop", UploadPolicy.decide(s, consent: consentOn, onWiFi: true, now: t0) == .drop)
s = sample(); s.feedback = .right; s.leafScores = [1]
check("invalid sample → drop", UploadPolicy.decide(s, consent: consentOn, onWiFi: true, now: t0) == .drop)

// JPEG metadata scan: SOI, APPn segment, SOS
func jpeg(_ segments: [(UInt8, [UInt8])]) -> Data {
    var b: [UInt8] = [0xFF, 0xD8]
    for (marker, payload) in segments {
        let len = payload.count + 2
        b += [0xFF, marker, UInt8(len >> 8), UInt8(len & 0xFF)] + payload
    }
    b += [0xFF, 0xDA, 0x00, 0x02, 0x11, 0x22, 0xFF, 0xD9]
    return Data(b)
}
let jfif = (UInt8(0xE0), Array("JFIF\0".utf8) + [1, 1, 0, 0, 1, 0, 1, 0, 0])
check("clean JFIF passes", JPEGMetadata.isClean(jpeg([jfif])))
check("EXIF found", JPEGMetadata.findSegments(in: jpeg([jfif, (0xE1, Array("Exif\0\0MM".utf8))])) == ["Exif"])
check("XMP found", JPEGMetadata.findSegments(in: jpeg([(0xE1, Array("http://ns.adobe.com/xap/1.0/\0".utf8))])) == ["XMP"])
check("IPTC found", JPEGMetadata.findSegments(in: jpeg([(0xED, Array("Photoshop 3.0\0".utf8))])) == ["IPTC"])
check("PNG bytes rejected", JPEGMetadata.isClean(Data([0x89, 0x50, 0x4E, 0x47])) == false)

// Field map = exactly what leaves the phone
let fields = sample().cloudFields()
let allowed = Set(["schemaVersion", "installID", "kind", "photo", "photoLongSidePx", "userPlantID",
                   "catalogVersion", "plantTopIDs", "plantTopScores", "leafScores", "plantModelVersion",
                   "leafModelVersion", "feedback", "correctedPlantID", "correctedLeafClass", "space",
                   "month", "appVersion", "osVersion", "deviceFamily"])
check("only spec fields leave the phone", Set(fields.keys).isSubset(of: allowed))
check("no local-only fields uploaded",
      fields.keys.allSatisfy { !["createdAt", "skippedByUser", "uploadedAt"].contains($0) })
check("month is the only time field", fields["month"] == .string("2026-11"))

// Mapping from app types
check("kitchen → indoor", SharedSpace(appSpaceTypeRaw: "kitchen") == .indoor)
check("frontYard → outdoorGround", SharedSpace(appSpaceTypeRaw: "frontYard") == .outdoorGround)
check("all 14 app classes map to training names",
      Set(LeafClassName.fromAppRaw.values) == Set(SharingSchema.leafClassOrder))

// Codable round trip (local queue is JSON)
let data = try! JSONEncoder().encode(sample())
check("queue JSON round trip", try! JSONDecoder().decode(SharedSample.self, from: data) == sample().withID(of: data))

print("PASS \(passed)/\(passed + failed)")
exit(failed == 0 ? 0 : 1)

extension SharedSample {
    /// sample() makes a new random id each call; compare with the encoded one's id.
    func withID(of data: Data) -> SharedSample {
        var c = self; c.id = (try! JSONDecoder().decode(SharedSample.self, from: data)).id; return c
    }
}
