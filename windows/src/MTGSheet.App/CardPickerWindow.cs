using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using MTGSheet.Core;

namespace MTGSheet.App;

/// The grid of images to choose from: a card's art variants, or the cardbacks in Settings.
public sealed class CardPickerWindow : Window
{
    private readonly Ui.WrapPanel grid = new() { ItemWidth = AppSettings.Current.TileSize };
    private readonly TextBlock header;
    private readonly Func<Task<List<MPCFill.Card>>> load;
    private readonly string? selected;
    private readonly Action<MPCFill.Card> onPick;

    public CardPickerWindow(string title, string? selected, Func<Task<List<MPCFill.Card>>> load, Action<MPCFill.Card> onPick)
    {
        this.load = load;
        this.selected = selected;
        this.onPick = onPick;
        Title = title;
        AppWindow.Resize(new Windows.Graphics.SizeInt32(900, 700));
        header = Ui.Text(title, 16, bold: true);

        var root = new Grid();
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        var bar = Ui.Row(header).With(r => r.Padding = new Thickness(12));
        var scroller = new ScrollViewer { Content = grid, Padding = new Thickness(12) };
        Grid.SetRow(bar, 0);
        Grid.SetRow(scroller, 1);
        root.Children.Add(bar);
        root.Children.Add(scroller);
        Content = root;

        _ = LoadAsync();
    }

    private async Task LoadAsync()
    {
        grid.Children.Add(new ProgressRing { IsActive = true, Width = 32, Height = 32 });
        try
        {
            var cards = await load();
            grid.Children.Clear();
            header.Text = $"{Title}   {Loc.Tr("Variants: %d", cards.Count)}";
            foreach (var card in cards) grid.Children.Add(Tile(card));
        }
        catch (Exception error)
        {
            grid.Children.Clear();
            grid.Children.Add(Ui.Text(Loc.Tr("Error: %@", error.Message)));
        }
    }

    private UIElement Tile(MPCFill.Card card)
    {
        var width = AppSettings.Current.TileSize;
        var image = new Image
        {
            Source = Ui.FromUrl(card.SmallThumbnailUrl),
            Width = width,
            Height = width * 1122 / 822,
            Stretch = Stretch.Uniform,
        };
        var button = new Button
        {
            Content = image,
            Padding = new Thickness(0),
            BorderThickness = new Thickness(card.Identifier == selected ? 3 : 0),
            BorderBrush = new SolidColorBrush(Microsoft.UI.Colors.DeepSkyBlue),
        };
        button.Click += (_, _) =>
        {
            onPick(card);
            Close();
        };
        return Ui.Column(button,
            Ui.Text(card.SourceName, 12),
            Ui.Text($"{card.Dpi} DPI · {card.Size / 1_000_000.0:0.0} MB", 11, dim: true)).With(c => c.Width = width);
    }
}
