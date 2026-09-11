using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using MTGSheet.Core;

namespace MTGSheet.App;

/// The two phases, like the segmented control in the macOS title bar: pick the cards, then lay them out.
public sealed class MainWindow : Window
{
    private readonly ToggleButton deckTab = new() { Content = Loc.Tr("1. Deck"), IsChecked = true };
    private readonly ToggleButton layoutTab = new() { Content = Loc.Tr("2. Layout") };
    private readonly ContentControl host = new() { HorizontalContentAlignment = HorizontalAlignment.Stretch,
                                                   VerticalContentAlignment = VerticalAlignment.Stretch };
    private readonly DeckView deck;
    private readonly OutputView output;

    public MainWindow()
    {
        Title = "MTG Sheet Optimizer";
        AppWindow.Resize(new Windows.Graphics.SizeInt32(1400, 900));

        output = new OutputView(this);
        deck = new DeckView(this, cards =>
        {
            output.SetCards(cards);
            Show(layout: true);
        });

        deckTab.Click += (_, _) => Show(layout: false);
        layoutTab.Click += (_, _) => Show(layout: true);

        var bar = new Grid { Padding = new Thickness(10, 8, 10, 8) };
        bar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        bar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var tabs = Ui.Row(deckTab, layoutTab).With(r => r.HorizontalAlignment = HorizontalAlignment.Center);
        Grid.SetColumn(tabs, 0);
        var settings = Ui.Button(Loc.Tr("Settings"), (_, _) => new SettingsWindow().Activate());
        Grid.SetColumn(settings, 1);
        bar.Children.Add(tabs);
        bar.Children.Add(settings);

        var root = new Grid();
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        Grid.SetRow(bar, 0);
        Grid.SetRow(host, 1);
        root.Children.Add(bar);
        root.Children.Add(host);
        Content = root;

        Show(layout: false);
    }

    private void Show(bool layout)
    {
        deckTab.IsChecked = !layout;
        layoutTab.IsChecked = layout;
        host.Content = layout ? output : deck;
        if (layout) output.Refresh();
    }
}
