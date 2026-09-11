#!/usr/bin/env python3
"""Compares the conformance runs of the two apps and checks them against spec/features.json.

    scripts/conformance-diff.py out/macos.json out/windows.json

The plan must match exactly (it is arithmetic); drawn geometry is allowed 2 px, because two graphics
engines never place a pixel identically."""
import json, sys, pathlib

TOLERANCE = 2
root = pathlib.Path(__file__).resolve().parent.parent
problems = []


def norm(value):
    if isinstance(value, float) and value.is_integer():
        return int(value)
    if isinstance(value, list):
        return [norm(v) for v in value]
    if isinstance(value, dict):
        return {k: norm(v) for k, v in value.items()}
    return value


def compare_geometry(case, page, a, b):
    if len(a) != len(b):
        problems.append(f"{case}/{page}: {len(a)} cards drawn vs {len(b)}")
        return
    for i, (box_a, box_b) in enumerate(zip(a, b)):
        if any(abs(x - y) > TOLERANCE for x, y in zip(box_a, box_b)):
            problems.append(f"{case}/{page}: card {i + 1} at {box_a} vs {box_b} (tolerance {TOLERANCE} px)")


def main(paths):
    runs = [json.load(open(p, encoding="utf-8")) for p in paths]
    features = {f["id"]: f for f in json.load(open(root / "spec/features.json", encoding="utf-8"))["features"]}

    for run in runs:
        platform = run["implementation"].split("-")[0]
        declared = {i for i, f in features.items() if f["platforms"].get(platform)}
        reported = set(run["features"])
        for extra in sorted(reported - declared):
            problems.append(f"{platform}: implements '{extra}' but spec/features.json says it doesn't")
        for missing in sorted(declared - reported):
            problems.append(f"{platform}: spec/features.json promises '{missing}' but the app doesn't report it")
        for unknown in sorted(reported - set(features)):
            problems.append(f"{platform}: unknown feature '{unknown}'")

    a, b = runs[0]["cases"], runs[1]["cases"]
    for case in sorted(set(a) | set(b)):
        if case not in a or case not in b:
            problems.append(f"{case}: only run by {runs[0 if case in a else 1]['implementation']}")
            continue
        if norm(a[case]["plan"]) != norm(b[case]["plan"]):
            problems.append(f"{case}: sheet plans differ")
        if a[case].get("dpi") != b[case].get("dpi"):
            problems.append(f"{case}: saved at {a[case].get('dpi')} DPI vs {b[case].get('dpi')}")
        ga, gb = a[case].get("geometry", {}), b[case].get("geometry", {})
        for page in sorted(set(ga) | set(gb)):
            if page in ga and page in gb:
                compare_geometry(case, page, ga[page], gb[page])
            else:
                problems.append(f"{case}: page {page} rendered by only one implementation")

    names = " vs ".join(r["implementation"] for r in runs)
    if problems:
        print(f"✘ {names}: {len(problems)} differences")
        for p in problems:
            print("  -", p)
        return 1
    print(f"✔ {names}: same plans, same geometry, features as declared ({len(a)} cases)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:3]))
