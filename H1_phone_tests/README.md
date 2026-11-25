# H1: real phone test photos (owner: hrishabh)

Goal: 92 → 300+ real phone photos, incl. **close-ups of damaged leaves** from teammates' homes. **Test only, never train on them.**

## Taking photos (send to hrishabh)
- One leaf fills most of the frame, in focus, daylight, no flash. Damaged leaves first, **yellowing especially** (model B: Yellowing 12-14% outside).
- Per plant: 1 close-up of the damaged leaf + 1 whole-plant photo (for plant ID).
- Write the plant name next to the photo if you know it; unknown is fine (`?`).
- Original files (no WhatsApp: it shrinks them). Location in EXIF is removed before upload.

## Files
| File | What |
|---|---|
| `phone_tests/<date>/` | photos, one folder per batch (as in phone_truth.csv) |
| `phone_truth.csv` | `folder,file,plant` (plant ID test; existing 92 rows) |
| `leaf_truth.csv` | `folder,file,plant,problem,closeup,labeled_by,checked_by,notes` (start from `leaf_truth_template.csv`) |
| `h1_check_labels.py` | label checker (stdlib) |

- `plant` = exactly `common_name` in `02_Data/Kyari_plant_care_dataset.csv` (`?` allowed in leaf_truth).
- `problem` = one of the 14 model classes: Downy mildew, Healthy, Insect chewing damage, Leaf blight, Leaf curl, Leaf spot, Mosaic virus, Not a leaf or unclear, Powdery mildew, Rot and wilt, Rust, Scorch and dry leaf, Visible pests, Yellowing.
- `closeup` = y/n. `checked_by` = a second person, not the labeller.

## Check
```
python -I h1_check_labels.py --labels leaf_truth.csv --dataset <Team R>/02_Data/Kyari_plant_care_dataset.csv --photos <phone_tests dir> --issues issues.csv
```
Exit 0 = no errors.

## How the checker was checked (2026-11-25, Windows, Python 3)
- `phone_truth.csv` (Drive copy, 92 rows, 3 folders, 25 plants) vs dataset (215 plants): no issues, exit 0.
- Test leaf file with one planted mistake per rule (duplicate, plant "Roses", class "Yellow leaves", closeup "maybe", empty labeller, self-check, `?` plant, unchecked): all 8 caught (6 errors, 2 warnings), exit 1.
- Empty template: exit 0.
- Not tested yet: `--photos` (phone_tests not synced on this PC).
