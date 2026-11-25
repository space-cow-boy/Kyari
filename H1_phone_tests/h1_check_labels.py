#!/usr/bin/env python3
"""
h1_check_labels.py — check the labels of Kyari real phone test photos (task H1).

Purpose
    Catch label mistakes before the phone test set is used to score models.
    Works on both label files:
      * phone_truth.csv : folder,file,plant                     (plant ID test)
      * leaf_truth.csv  : folder,file,plant,problem,closeup,labeled_by,checked_by,notes
                                                                (leaf problem test)
    These photos are TEST ONLY. Never train on them.

Inputs
    --labels   path to phone_truth.csv or leaf_truth.csv (UTF-8, BOM allowed)
    --dataset  path to 02_Data/Kyari_plant_care_dataset.csv (plant names = column common_name)
    --photos   optional: the phone_tests/ folder; if given, every <folder>/<file> must exist
    --issues   optional: write every problem found to this CSV

Outputs
    A short summary on stdout (rows, plants, problems per class, issues by type).
    Exit code 0 = no errors (warnings allowed), 1 = errors found.

Rules checked
    * header is exactly one of the two known layouts
    * plant name is exactly a common_name in the dataset ('?' allowed in leaf_truth, as a warning)
    * problem is one of the 14 leaf classes of the leaf model (names as in training)
    * closeup is y or n
    * no duplicate folder+file
    * leaf_truth: checked_by filled and different from labeled_by = "checked" (second person)
    * photo file exists (only with --photos)

How to run
    python -I h1_check_labels.py --labels phone_truth.csv --dataset Kyari_plant_care_dataset.csv
    python -I h1_check_labels.py --labels leaf_truth.csv --dataset ... --photos <phone_tests dir> --issues issues.csv

How it was checked
    Run on the existing phone_truth.csv (92 rows) and on a leaf_truth.csv test file with one
    planted mistake per rule; see H1_phone_tests/README.md for the outputs.
Standard library only.
"""
import argparse
import csv
import sys
from collections import Counter
from pathlib import Path

# ── settings ───────────────────────────────────────────────────────────
PLANT_HEADER = ["folder", "file", "plant"]
LEAF_HEADER = ["folder", "file", "plant", "problem", "closeup",
               "labeled_by", "checked_by", "notes"]
DATASET_NAME_COLUMN = "common_name"
UNKNOWN_PLANT = "?"
CLOSEUP_VALUES = {"y", "n"}
# The 14 classes of the leaf problem model (from Kyari_colab_results/predictions.csv, 25 Nov 2026).
LEAF_CLASSES = [
    "Downy mildew", "Healthy", "Insect chewing damage", "Leaf blight", "Leaf curl",
    "Leaf spot", "Mosaic virus", "Not a leaf or unclear", "Powdery mildew",
    "Rot and wilt", "Rust", "Scorch and dry leaf", "Visible pests", "Yellowing",
]
ENCODING = "utf-8-sig"  # Excel CSVs carry a BOM (LESSONS 2026-11-24)


def read_csv(path):
    with open(path, encoding=ENCODING, newline="") as f:
        reader = csv.reader(f)
        header = [h.strip() for h in next(reader, [])]
        rows = [[c.strip() for c in r] for r in reader if any(c.strip() for c in r)]
    return header, rows


def load_plant_names(dataset_path):
    header, rows = read_csv(dataset_path)
    col = header.index(DATASET_NAME_COLUMN)
    return {r[col] for r in rows if len(r) > col}


def check_rows(header, rows, plant_names, photos_dir):
    """Return (issues, stats). issues = list of (line, level, kind, detail)."""
    issues = []
    is_leaf = header == LEAF_HEADER
    seen = set()
    for line, values in enumerate(rows, start=2):  # line 1 = header
        if len(values) < len(header):
            values = values + [""] * (len(header) - len(values))
        row = dict(zip(header, values))
        key = (row["folder"], row["file"])

        if key in seen:
            issues.append((line, "error", "duplicate", f"{key[0]}/{key[1]}"))
        seen.add(key)

        plant = row["plant"]
        if plant == UNKNOWN_PLANT and is_leaf:
            issues.append((line, "warning", "plant unknown", key[1]))
        elif plant not in plant_names:
            issues.append((line, "error", "plant not in dataset", plant))

        if photos_dir and not (photos_dir / key[0] / key[1]).is_file():
            issues.append((line, "error", "photo missing", f"{key[0]}/{key[1]}"))

        if is_leaf:
            if row["problem"] not in LEAF_CLASSES:
                issues.append((line, "error", "unknown problem", row["problem"]))
            if row["closeup"].lower() not in CLOSEUP_VALUES:
                issues.append((line, "error", "closeup not y/n", row["closeup"]))
            if not row["labeled_by"]:
                issues.append((line, "error", "labeled_by empty", key[1]))
            if not row["checked_by"]:
                issues.append((line, "warning", "not checked yet", key[1]))
            elif row["checked_by"] == row["labeled_by"]:
                issues.append((line, "error", "checked by the labeller", row["checked_by"]))
    return issues


def summarize(header, rows, issues):
    is_leaf = header == LEAF_HEADER
    idx = {h: i for i, h in enumerate(header)}
    get = lambda r, h: r[idx[h]] if len(r) > idx[h] else ""
    print(f"rows: {len(rows)}  photo folders: {len({get(r, 'folder') for r in rows})}  "
          f"plants: {len({get(r, 'plant') for r in rows})}")
    if is_leaf:
        problems = Counter(get(r, "problem") for r in rows)
        print("problems:", ", ".join(f"{k} {v}" for k, v in sorted(problems.items())))
        closeups = sum(get(r, "closeup").lower() == "y" for r in rows)
        checked = sum(bool(get(r, "checked_by")) and get(r, "checked_by") != get(r, "labeled_by")
                      for r in rows)
        print(f"close-ups: {closeups}  checked by a second person: {checked}/{len(rows)}")
    kinds = Counter((lvl, kind) for _, lvl, kind, _ in issues)
    if not kinds:
        print("issues: none")
    for (lvl, kind), n in sorted(kinds.items()):
        print(f"{lvl}: {kind} x{n}")
    for line, lvl, kind, detail in issues[:10]:
        print(f"  line {line}: {lvl} {kind}: {detail}")
    if len(issues) > 10:
        print(f"  ... {len(issues) - 10} more (use --issues)")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--labels", required=True, type=Path)
    ap.add_argument("--dataset", required=True, type=Path)
    ap.add_argument("--photos", type=Path)
    ap.add_argument("--issues", type=Path)
    args = ap.parse_args()

    header, rows = read_csv(args.labels)
    if header not in (PLANT_HEADER, LEAF_HEADER):
        print(f"error: unknown header {header}; expected {PLANT_HEADER} or {LEAF_HEADER}")
        return 1
    plant_names = load_plant_names(args.dataset)
    print(f"dataset plants: {len(plant_names)}")
    issues = check_rows(header, rows, plant_names, args.photos)
    summarize(header, rows, issues)

    if args.issues:
        with open(args.issues, "w", encoding="utf-8", newline="") as f:
            w = csv.writer(f)
            w.writerow(["line", "level", "kind", "detail"])
            w.writerows(issues)
    return 1 if any(lvl == "error" for _, lvl, _, _ in issues) else 0


if __name__ == "__main__":
    sys.exit(main())
