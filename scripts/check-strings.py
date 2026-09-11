#!/usr/bin/env python3
"""Every interface text must live in spec/strings.json, on both platforms: a string added on one side only
is exactly the kind of drift this repository is set up to catch."""
import json, pathlib, re, sys

root = pathlib.Path(__file__).resolve().parent.parent
strings = json.load(open(root / "spec/strings.json", encoding="utf-8"))

def keys(pattern, files):
    found = set()
    for path in files:
        for match in re.findall(pattern, path.read_text(encoding="utf-8")):
            found.add(match.replace('\\"', '"').replace("\\\\", "\\"))
    return found

swift = keys(r'\btr\("((?:[^"\\]|\\.)*)"', root.glob("Sources/**/*.swift"))
csharp = keys(r'Loc\.Tr\("((?:[^"\\]|\\.)*)"', root.glob("windows/src/**/*.cs"))

problems = []
for platform, used in (("macOS", swift), ("Windows", csharp)):
    for missing in sorted(used - set(strings)):
        problems.append(f"{platform} uses a text that is not in spec/strings.json: {missing!r}")
for unused in sorted(set(strings) - swift - csharp):
    problems.append(f"spec/strings.json has a text neither app uses: {unused!r}")
for key, value in strings.items():
    if set(re.findall(r"%[@d]", key)) != set(re.findall(r"%[@d]", value["it"])):
        problems.append(f"the Italian text has different placeholders: {key!r}")

for problem in problems:
    print("  -", problem)
print(f"{'✘' if problems else '✔'} {len(strings)} texts, macOS uses {len(swift)}, Windows uses {len(csharp)}")
sys.exit(1 if problems else 0)
