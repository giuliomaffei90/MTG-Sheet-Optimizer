using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using MTGSheet.Core;

namespace MTGSheet.App;

/// Phase 1: paste a Moxfield list, pick an art variant for every copy, download. Mirrors DeckView.swift.
public sealed class DeckView : UserControl
{
    public sealed class Face
    {
        public MPCFill.Query Query;
        public List<string> Results = [];
        public MPCFill.Card? Selected;
    }

    public sealed class Row
    {
        public required string Name;
        public int Copy = 1;
        public int Copies = 1;
        public bool Included = true;
        public required Face Front;
        public Face? Back;
        public string Title => Copies > 1 ? $"{Name} {Copy}/{Copies}" : Name;
    }

    private readonly Window window;
    private readonly Action<List<PrintCard>> onReady;
    private readonly TextBox list = new()
    {
        AcceptsReturn = true,
        TextWrapping = TextWrapping.NoWrap,
        FontFamily = new FontFamily("Consolas"),
        PlaceholderText = "1 Abrade\n11 Island",
    };
    private readonly Ui.WrapPanel grid = new();
    private readonly TextBlock status = Ui.Text("", dim: true);
    private readonly Slider tileSize = new() { Minimum = 90, Maximum = 300, Width = 120 };
    private readonly TextBlock counts = Ui.Text("");
    private readonly Button searchButton;
    private readonly Button downloadButton;

    private readonly List<Row> rows = [];
    private readonly Dictionary<string, MPCFill.Card> cardCache = [];
    private int[]? sources;
    private Dictionary<string, string>? dfcPairs;
    private bool busy;

    public DeckView(Window window, Action<List<PrintCard>> onReady)
    {
        this.window = window;
        this.onReady = onReady;

        searchButton = Ui.Button(Loc.Tr("Search MPCFill"), async (_, _) => await SearchAsync());
        downloadButton = Ui.Button(Loc.Tr("Download and lay out"), async (_, _) => await DownloadAsync());
        tileSize.Value = AppSettings.Current.TileSize;
        tileSize.ValueChanged += (_, e) =>
        {
            AppSettings.Current.TileSize = e.NewValue;
            AppSettings.Current.Save();
            grid.ItemWidth = e.NewValue;
            Rebuild();
        };
        grid.ItemWidth = tileSize.Value;

        var left = new Grid { Padding = new Thickness(10), Width = 320 };
        left.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        left.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        left.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var title = Ui.Text(Loc.Tr("Deck list"), 16, bold: true);
        Grid.SetRow(title, 0);
        Grid.SetRow(list, 1);
        Grid.SetRow(searchButton, 2);
        left.Children.Add(title);
        left.Children.Add(list);
        left.Children.Add(searchButton);

        var bottom = new Grid { Padding = new Thickness(10) };
        bottom.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        bottom.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(status, 0);
        var right = Ui.Row(tileSize, counts, downloadButton);
        Grid.SetColumn(right, 1);
        bottom.Children.Add(status);
        bottom.Children.Add(right);

        var rightSide = new Grid();
        rightSide.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        rightSide.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var scroller = new ScrollViewer { Content = grid, Padding = new Thickness(12) };
        Grid.SetRow(scroller, 0);
        Grid.SetRow(bottom, 1);
        rightSide.Children.Add(scroller);
        rightSide.Children.Add(bottom);

        var root = new Grid();
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        Grid.SetColumn(left, 0);
        Grid.SetColumn(rightSide, 1);
        root.Children.Add(left);
        root.Children.Add(rightSide);
        Content = root;

        UpdateCounts();
    }

    private void SetBusy(bool value)
    {
        busy = value;
        searchButton.IsEnabled = !value;
        downloadButton.IsEnabled = !value && rows.Any(r => r.Included && r.Front.Selected is not null);
    }

    private async Task SearchAsync()
    {
        if (busy) return;
        SetBusy(true);
        status.Text = Loc.Tr("Searching MPCFill…");
        try
        {
            sources ??= await MPCFill.SourceIdsAsync();
            dfcPairs ??= await MPCFill.DfcPairsAsync();
            var entries = MPCFill.ParseDecklist(list.Text, dfcPairs);
            var queries = entries.SelectMany(e => e.Back is { } back ? new[] { e.Front, back } : [e.Front]).ToList();
            var hits = await MPCFill.SearchAsync(queries, sources);

            rows.Clear();
            foreach (var entry in entries)
                for (var copy = 1; copy <= entry.Quantity; copy++)
                    rows.Add(new Row
                    {
                        Name = entry.Name,
                        Copy = copy,
                        Copies = entry.Quantity,
                        Front = new Face { Query = entry.Front, Results = hits.GetValueOrDefault(entry.Front, []) },
                        Back = entry.Back is { } back
                            ? new Face { Query = back, Results = hits.GetValueOrDefault(back, []) }
                            : null,
                    });

            // Best variant of every face preselected, like mpcfill.com.
            var firsts = rows.SelectMany(r => new[] { r.Front.Results.FirstOrDefault(), r.Back?.Results.FirstOrDefault() })
                             .Where(id => id is not null).Select(id => id!).Distinct().ToList();
            var details = await CardsAsync(firsts);
            foreach (var row in rows)
            {
                row.Front.Selected = Pick(row.Front, details);
                if (row.Back is not null) row.Back.Selected = Pick(row.Back, details);
                row.Included = row.Front.Selected is not null;
            }

            var missing = rows.Where(r => r.Front.Selected is null && r.Copy == 1).Select(r => r.Name).ToList();
            status.Text = missing.Count == 0
                ? Loc.Tr("Cards found: %d.", entries.Count)
                : Loc.Tr("Not found: %@", string.Join(", ", missing));
            Rebuild();
        }
        catch (Exception error)
        {
            status.Text = Loc.Tr("Error: %@", error.Message);
        }
        finally
        {
            SetBusy(false);
        }
    }

    private static MPCFill.Card? Pick(Face face, IReadOnlyDictionary<string, MPCFill.Card> details) =>
        face.Results.FirstOrDefault() is { } id && details.TryGetValue(id, out var card) ? card : null;

    private async Task<Dictionary<string, MPCFill.Card>> CardsAsync(IReadOnlyList<string> identifiers)
    {
        var missing = identifiers.Where(id => !cardCache.ContainsKey(id)).ToList();
        if (missing.Count > 0)
            foreach (var (id, card) in await MPCFill.CardsAsync(missing))
                cardCache[id] = card;
        return cardCache;
    }

    private void Rebuild()
    {
        grid.Children.Clear();
        foreach (var row in rows)
        {
            grid.Children.Add(Tile(row, back: false));
            if (row.Back is not null) grid.Children.Add(Tile(row, back: true));
        }
        UpdateCounts();
    }

    private UIElement Tile(Row row, bool back)
    {
        var face = back ? row.Back! : row.Front;
        var width = tileSize.Value;
        var image = new Image
        {
            Source = Ui.FromUrl(face.Selected?.SmallThumbnailUrl),
            Width = width,
            Height = width * 1122 / 822,
            Stretch = Stretch.Uniform,
            Opacity = row.Included ? 1 : 0.35,
        };
        var button = new Button { Content = image, Padding = new Thickness(0), IsEnabled = face.Results.Count > 0 };
        ToolTipService.SetToolTip(button, Loc.Tr("Choose the variant"));
        button.Click += (_, _) => new CardPickerWindow(
            back ? Loc.Tr("Back: %@", face.Selected?.Name ?? "") : row.Title,
            face.Selected?.Identifier,
            () => VariantsAsync(face),
            card => { face.Selected = card; Rebuild(); }).Activate();

        var tile = Ui.Column(button, Ui.Text(back ? Loc.Tr("Back: %@", face.Selected?.Name ?? "") : row.Title, 12, bold: true));
        tile.Children.Add(face.Selected is { } card
            ? Ui.Text(Loc.Tr("%@ · %d DPI · %d var.", card.SourceName, card.Dpi, face.Results.Count), 11, dim: true)
            : Ui.Text(Loc.Tr("Not found"), 11).With(t => t.Foreground = new SolidColorBrush(Microsoft.UI.Colors.IndianRed)));
        if (!back)
        {
            var include = new CheckBox { IsChecked = row.Included, IsEnabled = row.Front.Selected is not null };
            ToolTipService.SetToolTip(include, Loc.Tr("Print this card"));
            include.Checked += (_, _) => { row.Included = true; UpdateCounts(); };
            include.Unchecked += (_, _) => { row.Included = false; UpdateCounts(); };
            tile.Children.Add(include);
        }
        tile.Width = width;
        return tile;
    }

    private async Task<List<MPCFill.Card>> VariantsAsync(Face face)
    {
        var details = await CardsAsync(face.Results);
        return face.Results.Where(details.ContainsKey).Select(id => details[id]).ToList();
    }

    private void UpdateCounts()
    {
        var chosen = rows.Where(r => r.Included && r.Front.Selected is not null).ToList();
        counts.Text = Loc.Tr("Cards: %d · Double-sided: %d",
            chosen.Count(r => r.Back is null), chosen.Count(r => r.Back is not null));
        downloadButton.IsEnabled = !busy && chosen.Count > 0;
    }

    /// Downloads the chosen variants, four at a time, and hands one print card per copy to phase 2.
    private async Task DownloadAsync()
    {
        if (busy) return;
        SetBusy(true);
        var chosen = rows.Where(r => r.Included && r.Front.Selected is not null).ToList();
        var unique = chosen.SelectMany(r => new[] { r.Front.Selected, r.Back?.Selected })
                           .Where(c => c is not null).Select(c => c!).Distinct().ToList();
        var files = new Dictionary<string, string>();
        var done = 0;
        try
        {
            using var limit = new SemaphoreSlim(4);
            await Task.WhenAll(unique.Select(async card =>
            {
                await limit.WaitAsync();
                try
                {
                    var file = await MPCFill.DownloadAsync(card, Paths.Cache);
                    lock (files)
                    {
                        files[card.Identifier] = file;
                        done++;
                    }
                    status.Text = Loc.Tr("Downloading %d/%d…", done, unique.Count);
                }
                finally { limit.Release(); }
            }));

            var cards = chosen
                .Where(r => r.Front.Selected is not null && files.ContainsKey(r.Front.Selected!.Identifier))
                .Select(r => new PrintCard(files[r.Front.Selected!.Identifier],
                    r.Back?.Selected is { } back && files.TryGetValue(back.Identifier, out var path) ? path : null))
                .ToList();
            status.Text = Loc.Tr("Downloaded %d images.", unique.Count);
            onReady(cards);
        }
        catch (Exception error)
        {
            status.Text = Loc.Tr("Error: %@", error.Message);
        }
        finally
        {
            SetBusy(false);
        }
    }
}
