#!/usr/bin/env python3
"""spec/strings.json is the only place interface texts live: this writes the Swift and C# tables from it.
Run after editing the JSON; CI checks the generated files are up to date."""
import json, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
strings = json.load(open(root / "spec/strings.json", encoding="utf-8"))
q = lambda s: json.dumps(s, ensure_ascii=False)

swift = ['// Generated from spec/strings.json by scripts/gen-strings.py. Do not edit.', '',
         'let italianTranslations: [String: String] = [']
swift += [f'    {q(k)}: {q(v["it"])},' for k, v in strings.items()]
swift += [']', '']
(root / "Sources/MTGSheetOptimizer/Strings.generated.swift").write_text("\n".join(swift), encoding="utf-8")

cs = ['// Generated from spec/strings.json by scripts/gen-strings.py. Do not edit.', '',
      'namespace MTGSheet.Core;', '', 'public static class Strings', '{',
      '    public static readonly IReadOnlyDictionary<string, string> Italian = new Dictionary<string, string>', '    {']
cs += [f'        [{q(k)}] = {q(v["it"])},' for k, v in strings.items()]
cs += ['    };', '}', '']
(root / "windows/src/MTGSheet.Core/Strings.generated.cs").write_text("\n".join(cs), encoding="utf-8")
print(f"generated {len(strings)} strings for Swift and C#")
