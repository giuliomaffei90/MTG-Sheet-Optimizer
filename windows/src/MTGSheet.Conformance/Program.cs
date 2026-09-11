using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using MTGSheet.Core;
using SkiaSharp;

// Runs the shared cases in spec/ and prints what this implementation produced, so it can be compared with
// the macOS run (see spec/spec.md):
//     dotnet run --project src/MTGSheet.Conformance -- ../spec out/windows.json

/// What this build implements, checked against spec/features.json by scripts/conformance-diff.py.
string[] features = ["decklist-parse", "mpcfill-search", "sheet-plan", "render-300dpi"];

if (args.Length == 0)
{
    Console.Error.WriteLine("usage: conformance <specDir> [out.json]");
    return 2;
}

var spec = args[0];
using var masker = new Masker(Path.Combine(spec, "Resources", "mask.png"));
var fixtures = Path.Combine(spec, "fixtures");
string Fixture(string id) => Path.Combine(fixtures, $"{id}.png");

var cases = new JsonObject();
var failures = 0;

foreach (var file in Directory.GetFiles(Path.Combine(spec, "cases"), "*.json").OrderBy(f => Path.GetFileName(f), StringComparer.Ordinal))
{
    var c = JsonNode.Parse(File.ReadAllText(file))!.AsObject();
    var name = (string)c["name"]!;
    var width = (double)c["pageWidth"]!;
    var height = (double)c["pageHeight"]!;
    var slots = c["slots"]!.AsArray()
        .Select(s => new Slot((double)s![0]!, (double)s[1]!, (double)s[2]!)).ToList();
    var cards = c["cards"]!.AsArray().Select(card =>
    {
        var faces = card!.AsArray();
        return new PrintCard(Fixture((string)faces[0]!), faces.Count > 1 ? Fixture((string)faces[1]!) : null);
    }).ToList();

    var plan = Sheets.PlanSheets(cards, slots, width,
        Enum.Parse<PageKind>((string)c["kind"]!),
        Enum.Parse<ExtraCards>((string)c["extra"]!, ignoreCase: true),
        Enum.Parse<DoubleSidedMode>((string)c["doubleSided"]!, ignoreCase: true),
        (bool)c["backPage"]!);

    var result = new JsonObject { ["plan"] = PlanJson(plan) };
    var expected = c["expected"]?.AsObject() ?? [];

    if ((bool?)c["render"] == true)
    {
        var geometry = new JsonObject();
        byte[]? firstPage = null;
        foreach (var page in plan.Pages)
        {
            var boxes = new JsonArray();
            foreach (var (item, slot) in page.Items)
            {
                using var card = masker.Card(item.Path ?? Fixture("back"));
                using var sheet = Imaging.RenderPage((int)width, (int)height, masker.CardSize, [(card, slot)]);
                boxes.Add(Box(sheet));
                firstPage ??= Encode(sheet);
            }
            geometry[page.Name] = boxes;
        }
        result["geometry"] = geometry;
        result["dpi"] = firstPage is null ? null : Imaging.DpiOf(firstPage);

        if (expected["geometry"] is JsonObject want && want.Count > 0)
            foreach (var page in want)
                if (!CloseEnough(geometry[page.Key]?.AsArray(), page.Value?.AsArray()))
                {
                    Console.WriteLine($"✘ {name}: geometry differs on {page.Key}");
                    failures++;
                }
    }

    if (expected["pages"] is JsonArray pages && pages.Count > 0)
    {
        var want = new JsonObject
        {
            ["pages"] = pages.DeepClone(),
            ["singles"] = (expected["singles"] ?? new JsonArray()).DeepClone(),
            ["doubleSided"] = (expected["doubleSided"] ?? new JsonArray()).DeepClone(),
        };
        if (!Same(result["plan"], want))
        {
            Console.WriteLine($"✘ {name}: plan differs from spec");
            failures++;
        }
    }

    cases[name] = result;
}

var document = new JsonObject
{
    ["implementation"] = "windows-csharp",
    ["features"] = new JsonArray(features.Select(f => (JsonNode)f!).ToArray()),
    ["cases"] = cases,
};
var json = document.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
if (args.Length > 1)
{
    Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(args[1]))!);
    File.WriteAllText(args[1], json);
}
else
{
    Console.WriteLine(json);
}
Console.WriteLine(failures == 0 ? $"✔ {cases.Count} cases match the spec" : $"✘ {failures} mismatches");
return failures == 0 ? 0 : 1;

static JsonObject PlanJson(SheetPlan plan)
{
    static double R(double v) => Math.Round(v, 4, MidpointRounding.AwayFromZero);
    static string Id(PageItem item) => item.Path is null ? "$back" : Path.GetFileNameWithoutExtension(item.Path);

    var pages = new JsonArray();
    foreach (var page in plan.Pages)
    {
        var items = new JsonArray();
        foreach (var (item, slot) in page.Items)
            items.Add(new JsonArray(Id(item), R(slot.Cx), R(slot.Cy), R(slot.Rot)));
        pages.Add(new JsonObject { ["name"] = page.Name, ["isBack"] = page.IsBack, ["items"] = items });
    }
    return new JsonObject
    {
        ["pages"] = pages,
        ["singles"] = new JsonArray(plan.Singles.Select(s => (JsonNode)Path.GetFileNameWithoutExtension(s)!).ToArray()),
        ["doubleSided"] = new JsonArray(plan.DoubleSided.Select(s => (JsonNode)Path.GetFileNameWithoutExtension(s)!).ToArray()),
    };
}

/// Alpha bounding box of a page holding one card only: the geometry two graphics engines can agree on.
static JsonArray Box(SKBitmap page)
{
    var pixels = page.GetPixelSpan();
    int minX = page.Width, minY = page.Height, maxX = -1, maxY = -1;
    for (var y = 0; y < page.Height; y++)
        for (var x = 0; x < page.Width; x++)
            if (pixels[y * page.RowBytes + x * 4 + 3] > 8)
            {
                if (x < minX) minX = x;
                if (x > maxX) maxX = x;
                if (y < minY) minY = y;
                if (y > maxY) maxY = y;
            }
    return maxX < 0 ? new JsonArray(0, 0, 0, 0) : new JsonArray(minX, minY, maxX - minX + 1, maxY - minY + 1);
}

static byte[] Encode(SKBitmap page)
{
    using var image = SKImage.FromBitmap(page);
    using var data = image.Encode(SKEncodedImageFormat.Png, 100);
    return Imaging.WithDpi(data.ToArray(), Imaging.OutputDpi);
}

/// Two graphics engines never place a pixel identically; 2 px is the agreed tolerance.
static bool CloseEnough(JsonArray? a, JsonArray? b)
{
    if (a is null || b is null || a.Count != b.Count) return false;
    for (var i = 0; i < a.Count; i++)
    {
        var (box, want) = (a[i]!.AsArray(), b[i]!.AsArray());
        if (box.Count != want.Count) return false;
        for (var k = 0; k < box.Count; k++)
            if (Math.Abs(Number(box[k]) - Number(want[k])) > 2) return false;
    }
    return true;
}

/// JSON read from a file and JSON built here store numbers differently; compare them as doubles.
static double Number(JsonNode? node) =>
    node is null ? double.NaN : double.Parse(node.ToJsonString(), CultureInfo.InvariantCulture);

static bool Same(JsonNode? a, JsonNode? b)
{
    switch (a, b)
    {
        case (JsonObject x, JsonObject y):
            return x.Count == y.Count && x.All(p => y.ContainsKey(p.Key) && Same(p.Value, y[p.Key]));
        case (JsonArray x, JsonArray y):
            return x.Count == y.Count && x.Select((item, i) => Same(item, y[i])).All(same => same);
        case (JsonValue x, JsonValue y):
            if (x.GetValueKind() == JsonValueKind.Number && y.GetValueKind() == JsonValueKind.Number)
                return Math.Abs(Number(x) - Number(y)) < 1e-9;
            return x.ToJsonString() == y.ToJsonString();
        default:
            return a is null && b is null;
    }
}
