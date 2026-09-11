using System.Text.Json;
using System.Text.Json.Serialization;

namespace MTGSheet.Core;

/// The layout files in spec/Resources (same format the macOS app reads and writes; unknown keys are ignored).
public sealed class LayoutFile
{
    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public sealed class NormalizedSlot
    {
        public double Cx { get; set; }
        public double Cy { get; set; }
        public double? Rot { get; set; }
    }

    public string? LayoutKind { get; set; }
    public List<NormalizedSlot> Slots { get; set; } = [];

    public static LayoutFile Load(string path) =>
        JsonSerializer.Deserialize<LayoutFile>(File.ReadAllText(path), Options)
        ?? throw new IOException($"Can't read {Path.GetFileName(path)}");

    public static LayoutFile FromSlots(PageKind kind, IEnumerable<Slot> slots, double width, double height) => new()
    {
        LayoutKind = kind.ToString(),
        Slots = slots.Select(s => new NormalizedSlot { Cx = s.Cx / width, Cy = s.Cy / height, Rot = Sheets.SnapAngle(s.Rot) }).ToList(),
    };

    public void Save(string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        File.WriteAllText(path, JsonSerializer.Serialize(this, Options));
    }

    public Slot[] PageSlots(double width, double height) =>
        Slots.Select(s => new Slot(s.Cx * width, s.Cy * height, Sheets.SnapAngle(s.Rot ?? 0))).ToArray();
}
