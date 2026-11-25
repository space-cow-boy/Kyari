# H3: data-sharing data model (CloudKit + Swift)

Owner: hrishabh. Spec: `Team R/07_Project_Memory/Kyari_data_sharing_optin.md` (24 Nov 2026). Code: `KyariSharing.swift`, test `Tests/KyariSharingSelfTest.swift`. **Status: draft, needs review by sandeep.**

## 1. Where data lives
| Data | Where | Leaves the phone? |
|---|---|---|
| `SharingConsent` (switch, adult yes/no, installID, Wi-Fi only) | UserDefaults (JSON), this phone only | never |
| Queue of `SharedSample` + photo `<id>.jpg` | `Application Support/SharingQueue/` (JSON + JPEG) | only via upload below |
| Record type `SharedSample` | CloudKit **public** DB, Kyari container | yes, if allowed |

The consent is **not** synced through the private iCloud store, on purpose: a new phone starts with sharing off and asks again.

## 2. CloudKit record type `SharedSample`
recordName = sample UUID (random). Created only by the app.

| Field | CloudKit type | Example | Index | Spec §3 row |
|---|---|---|---|---|
| schemaVersion | Int64 | 1 | – | – |
| installID | String | UUID | **Queryable** | install id |
| kind | String | `plantID` / `leafProblem` | Queryable | kind |
| photo | Asset | JPEG ≤ 1024 px, no EXIF/XMP/IPTC | – | photo |
| photoLongSidePx | Int64 | 1024 | – | photo |
| userPlantID | Int64 | 905 (dataset `plant_id`) | – | plant picked by user |
| catalogVersion | String | `215-2026-11-25` | – | – |
| plantTopIDs / plantTopScores | Int64 list / Double list | [905, 12, 40] / [0.90, 0.05, 0.02] | – | model answers (top-3) |
| leafScores | Double list (14) | order = `SharingSchema.leafClassOrder` | – | model answers (14 classes) |
| plantModelVersion / leafModelVersion | String | `KyariPlantID 1.0` / `KyariLeafProblem B` | – | model versions |
| feedback | String | `none` / `right` / `wrong` | Queryable | user feedback |
| correctedPlantID / correctedLeafClass | Int64 / String | 905 / `Yellowing` | – | the right answer they picked |
| space | String | `balcony`, `terrace`, `outdoorGround`, `windowSill`, `indoor`, `unknown` | – | space type |
| month | String | `2026-11` | **Queryable, Sortable** | month |
| appVersion / osVersion / deviceFamily | String | `1.0` / `iOS 18.0` / `iPhone 13` | – | app, iOS, phone family |

Also enable **Queryable on recordName** and **Sortable on createdTimestamp** (dashboard export + 3-year cleanup).
Class names are the training names (`Not a leaf or unclear`, `Scorch and dry leaf`, ...), not the app's enum raw values; `LeafClassName.fromAppRaw` maps them.

## 3. Security roles (CloudKit dashboard → Schema → Security Roles)
| Role | SharedSample |
|---|---|
| World | none |
| Authenticated (`_icloud`) | **Create only** (remove the default Read) |
| Creator | Read + Write (needed for "Delete what I shared") |
| Team (dashboard / Mac export script) | via the developer account |

## 4. Upload rules (`UploadPolicy.decide`, run in a BackgroundTask)
1. Consent is re-read **at upload time**: switch off or not confirmed adult → sample dropped (local copy deleted).
2. Per-photo "Don't share this one" → dropped. Sample from an older install id → dropped.
3. Invalid sample (wrong score count, photo > 1024 px, unknown class name, full date) → dropped.
4. Wi-Fi only (default) and on mobile data → wait.
5. Upload when the user tapped Right/Wrong, or 24 h after the report without feedback.
6. Before saving: `JPEGMetadata.isClean(photo)` must be true; the photo is re-encoded from pixels (drops all metadata) and checked again.

## 5. Delete
- Switch off → queue emptied, no new uploads.
- "Delete what I shared" → `SharedSampleCloud.deleteAll(installID:knownIDs:)`: query by installID + record ids remembered locally, delete in one batch.
- Team deletes records with `month` older than 3 years.

## 6. Points for the reviewer (differences from the spec / open questions)
1. **creatorUserRecordID**: CloudKit stores a creator id on every public record, and saving to the public DB needs an iCloud sign-in. That id is per-container and opaque (not the Apple ID or email), but the team can see it in the dashboard, so "not linked to identity" in App Privacy needs a check by whoever fills App Store Connect.
2. **Space list**: spec has 4 values (balcony / window sill / indoor / terrace); the app's `SpaceType` has 7. Mapping: bedroom/livingRoom/kitchen → `indoor`, frontYard → `outdoorGround` (new value), plus `unknown`.
3. **"from our 158"** in the spec is outdated: dataset has 215 plants; ids are stored with `catalogVersion`.
4. **Reinstall**: a new installID means the user can no longer delete older records from the app; the privacy policy should give the team email for that.
5. Records are uploaded once (after feedback or 24 h); feedback given later is not sent. Simpler than updating records.

## 7. How it was checked (2026-11-25, Windows 11, Swift 6.4)
- `KyariSharing.swift` + self-test compiled with `swiftc`; **31/31 checks pass**: consent off by default, under-18 blocked, month only, validation (6 kinds), upload policy (8 cases), EXIF/XMP/IPTC found in test JPEG bytes and clean JFIF passes, only spec fields in the uploaded field map, app→training class names (14/14), JSON queue round trip.
- **Not checked**: the `#if canImport(CloudKit)` part (CKRecord, upload, delete) is not compiled (no CloudKit on Windows); build in Xcode on a Mac. Security roles and indexes must be set in the dashboard by hand.
