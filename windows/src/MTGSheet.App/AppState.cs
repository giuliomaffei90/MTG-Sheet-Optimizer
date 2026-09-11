using System.Text.Json;
using System.Text.Json.Serialization;
using MTGSheet.Core;

namespace MTGSheet.App;

/// Where the app keeps things on Windows; the macOS app uses Application Support and Caches the same way.
public static class Paths
{
    public static readonly string Support =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "MTG Sheet Optimizer");
    public static readonly string Cache =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MTG Sheet Optimizer", "Cache");
    public static readonly string Assets = Path.Combine(AppContext.BaseDirectory, "Assets");

    /// A copy in the settings folder (an edited layout, a downloaded back) wins over the bundled one.
    public static string Resource(string name)
    {
        var user = Path.Combine(Support, name);
        return File.Exists(user) ? user : Path.Combine(Assets, name);
    }
}

/// Everything the app remembers, in %APPDATA%\MTG Sheet Optimizer\settings.json.
public sealed class AppSettings
{
    public string Language { get; set; } = "en";
    public string Kind { get; set; } = nameof(PageKind.A4);
    public bool BackPage { get; set; }
    public string Extra { get; set; } = nameof(ExtraCards.EmptySlots);
    public string DoubleSided { get; set; } = nameof(DoubleSidedMode.Singles);
    public string OutputPath { get; set; } = "";
    public double TileSize { get; set; } = 150;
    public MPCFill.Card? CardBack { get; set; }

    [JsonIgnore] public PageKind PageKind => Enum.Parse<PageKind>(Kind, true);
    [JsonIgnore] public ExtraCards ExtraCards => Enum.Parse<ExtraCards>(Extra, true);
    [JsonIgnore] public DoubleSidedMode DoubleSidedMode => Enum.Parse<DoubleSidedMode>(DoubleSided, true);

    /// ProxyBack by OffPlanetVibes until the user picks another cardback.
    public static readonly MPCFill.Card ProxyBack = new(
        "1Aa98sI-YvFUSnNYGGfJvc7NR9VtUOpNp", "ProxyBack", "OffPlanetVibes", "Google Drive", 1240, 8_986_157, "jpg",
        "https://drive.google.com/thumbnail?sz=w400-h400&id=1Aa98sI-YvFUSnNYGGfJvc7NR9VtUOpNp", null);

    [JsonIgnore] public MPCFill.Card Back => CardBack ?? ProxyBack;

    private static readonly string File_ = Path.Combine(Paths.Support, "settings.json");
    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };
    private static AppSettings? current;

    public static AppSettings Current
    {
        get
        {
            if (current is not null) return current;
            try { current = JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(File_), Options); }
            catch { /* first run, or a settings file we can't read: start fresh */ }
            current ??= new AppSettings();
            Loc.Language = current.Language;
            return current;
        }
    }

    public void Save()
    {
        Loc.Language = Language;
        Directory.CreateDirectory(Paths.Support);
        File.WriteAllText(File_, JsonSerializer.Serialize(this, Options));
    }
}

/// The two page layouts: background image size and card slots, saved on every change (see Layout.swift).
public sealed class LayoutStore
{
    public static readonly LayoutStore Shared = new();

    public Masker? Masker { get; }
    private readonly Dictionary<PageKind, Slot[]> slots = [];
    private readonly Dictionary<PageKind, (int Width, int Height)> sizes = [];

    private LayoutStore()
    {
        try { Masker = new Masker(Paths.Resource("mask.png")); } catch { Masker = null; }
        foreach (var kind in Enum.GetValues<PageKind>())
        {
            try
            {
                using var background = Imaging.Load(Paths.Resource(kind.LayoutPng()));
                sizes[kind] = (background.Width, background.Height);
            }
            catch { sizes[kind] = (0, 0); }

            var (width, height) = sizes[kind];
            Slot[]? saved = null;
            try { saved = LayoutFile.Load(Paths.Resource(kind.LayoutJson())).PageSlots(width, height); } catch { }
            slots[kind] = saved?.Length == kind.SlotCount() ? saved : Sheets.DefaultSlots(kind, width, height);
        }
    }

    public (int Width, int Height) Size(PageKind kind) => sizes[kind];
    public Slot[] Slots(PageKind kind) => slots[kind];
    public string BackgroundPath(PageKind kind) => Paths.Resource(kind.LayoutPng());

    public void SetSlots(PageKind kind, Slot[] value)
    {
        slots[kind] = value;
        var (width, height) = sizes[kind];
        LayoutFile.FromSlots(kind, value, width, height).Save(Path.Combine(Paths.Support, kind.LayoutJson()));
    }

    public void Reset(PageKind kind)
    {
        var (width, height) = sizes[kind];
        SetSlots(kind, Sheets.DefaultSlots(kind, width, height));
    }
}
