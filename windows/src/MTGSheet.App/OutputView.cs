using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using MTGSheet.Core;
using SkiaSharp;

namespace MTGSheet.App;

/// Phase 2: how to lay the cards out, a live preview of every sheet, and the export. Mirrors OutputView in App.swift.
public sealed class OutputView : UserControl
{
    private readonly Window window;
    private readonly AppSettings settings = AppSettings.Current;
    private readonly ComboBox kind = new() { ItemsSource = new[] { "A4", "A3" } };
    private readonly CheckBox backPage = new() { Content = Loc.Tr("Export back page") };
    private readonly ComboBox extra = new();
    private readonly ComboBox doubleSided = new();
    private readonly TextBlock outputPath = Ui.Text("—");
    private readonly TextBlock status = Ui.Text("", dim: true);
    private readonly TextBlock summary = Ui.Text("", dim: true);
    private readonly Ui.WrapPanel previews = new() { ItemWidth = 180 };
    private readonly Button renderButton;

    private List<PrintCard> cards = [];
    private CancellationTokenSource? previewWork;

    public OutputView(Window window)
    {
        this.window = window;

        kind.SelectedIndex = settings.PageKind == PageKind.A4 ? 0 : 1;
        backPage.IsChecked = settings.BackPage;
        extra.ItemsSource = new[] { Loc.Tr("Last page with empty slots"), Loc.Tr("As singles") };
        extra.SelectedIndex = settings.ExtraCards == ExtraCards.EmptySlots ? 0 : 1;
        doubleSided.ItemsSource = new[] { Loc.Tr("As singles"), Loc.Tr("Front/back pages") };
        doubleSided.SelectedIndex = settings.DoubleSidedMode == DoubleSidedMode.Singles ? 0 : 1;
        outputPath.Text = settings.OutputPath.Length == 0 ? "—" : settings.OutputPath;

        kind.SelectionChanged += (_, _) => Changed();
        backPage.Checked += (_, _) => Changed();
        backPage.Unchecked += (_, _) => Changed();
        extra.SelectionChanged += (_, _) => Changed();
        doubleSided.SelectionChanged += (_, _) => Changed();

        renderButton = Ui.Button("Render", async (_, _) => await RenderAsync());
        var options = Ui.Row(Ui.Text("Layout"), kind, backPage,
                             Ui.Text(Loc.Tr("Extra cards")), extra,
                             Ui.Text(Loc.Tr("Double-sided")), doubleSided);
        var output = Ui.Row(Ui.Text("Output"), outputPath,
                            Ui.Button(Loc.Tr("Choose…"), async (_, _) => await ChooseOutputAsync()),
                            Ui.Button(Loc.Tr("Open output"), (_, _) => OpenOutput()),
                            renderButton);

        var top = Ui.Column(options, output, status).With(c => c.Padding = new Thickness(10));
        var scroller = new ScrollViewer { Content = previews, Padding = new Thickness(12) };

        var root = new Grid();
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        Grid.SetRow(top, 0);
        Grid.SetRow(summary, 1);
        Grid.SetRow(scroller, 2);
        summary.Margin = new Thickness(12, 0, 12, 6);
        root.Children.Add(top);
        root.Children.Add(summary);
        root.Children.Add(scroller);
        Content = root;
    }

    public void SetCards(List<PrintCard> value)
    {
        cards = value;
        Refresh();
    }

    private PageKind Kind => kind.SelectedIndex == 1 ? PageKind.A3 : PageKind.A4;

    private SheetPlan Plan() => Sheets.PlanSheets(cards, LayoutStore.Shared.Slots(Kind),
        LayoutStore.Shared.Size(Kind).Width, Kind,
        extra.SelectedIndex == 1 ? ExtraCards.Singles : ExtraCards.EmptySlots,
        doubleSided.SelectedIndex == 1 ? DoubleSidedMode.Duplex : DoubleSidedMode.Singles,
        backPage.IsChecked == true);

    private void Changed()
    {
        settings.Kind = Kind.ToString();
        settings.BackPage = backPage.IsChecked == true;
        settings.Extra = extra.SelectedIndex == 1 ? nameof(ExtraCards.Singles) : nameof(ExtraCards.EmptySlots);
        settings.DoubleSided = doubleSided.SelectedIndex == 1 ? nameof(DoubleSidedMode.Duplex) : nameof(DoubleSidedMode.Singles);
        settings.Save();
        Refresh();
    }

    /// Redraws the preview from the same plan the export uses; a newer call cancels the previous one.
    public async void Refresh()
    {
        previewWork?.Cancel();
        var work = previewWork = new CancellationTokenSource();
        var token = work.Token;

        var plan = Plan();
        summary.Text = Loc.Tr("Sheets: %d · Back pages: %d · Singles: %d",
            plan.Pages.Count(p => !p.IsBack), plan.Pages.Count(p => p.IsBack),
            plan.Singles.Count + plan.DoubleSided.Count);
        previews.Children.Clear();
        if (cards.Count == 0)
        {
            previews.Children.Add(Ui.Text(Loc.Tr("Search and download a deck in \"1. Deck\" first."), dim: true));
            return;
        }
        if (LayoutStore.Shared.Masker is not { } masker) return;

        try
        {
            await Task.Delay(120, token);   // coalesce quick option changes
            var (width, height) = LayoutStore.Shared.Size(Kind);
            var back = plan.NeedsCardBack ? await MPCFill.DownloadAsync(settings.Back, Paths.Cache) : null;
            var scale = 520.0 / height;

            var pages = await Task.Run(() =>
            {
                var drawn = new List<(string Name, byte[] Png)>();
                var cache = new Dictionary<string, SKBitmap>();
                SKBitmap Card(string path)
                {
                    if (!cache.TryGetValue(path, out var bitmap))
                        cache[path] = bitmap = masker.Card(path, (int)(masker.Mask.Height * scale));
                    return bitmap;
                }
                foreach (var page in plan.Pages)
                {
                    token.ThrowIfCancellationRequested();
                    var placements = page.Items
                        .Select(item => (Card(item.Item.Path ?? back!), item.Slot))
                        .ToList();
                    using var sheet = Imaging.RenderPage(width, height, masker.CardSize, placements, scale);
                    using var image = SKImage.FromBitmap(sheet);
                    using var data = image.Encode(SKEncodedImageFormat.Png, 100);
                    drawn.Add((page.Name, data.ToArray()));
                }
                foreach (var bitmap in cache.Values) bitmap.Dispose();
                return drawn;
            }, token);

            previews.Children.Clear();
            foreach (var (name, png) in pages)
            {
                var source = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage();
                using (var stream = new MemoryStream(png)) await source.SetSourceAsync(stream.AsRandomAccessStream());
                previews.Children.Add(Ui.Column(
                    new Image { Source = source, Width = 170, Stretch = Stretch.Uniform,
                                Background = new SolidColorBrush(Microsoft.UI.Colors.White) },
                    Ui.Text(name, 11, dim: true)).With(c => c.Width = 170));
            }
        }
        catch (OperationCanceledException) { /* superseded by a newer refresh */ }
        catch (Exception error) { status.Text = Loc.Tr("Error: %@", error.Message); }
    }

    private async Task ChooseOutputAsync()
    {
        var picker = new Windows.Storage.Pickers.FolderPicker();
        picker.FileTypeFilter.Add("*");
        WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(window));
        if (await picker.PickSingleFolderAsync() is { } folder)
        {
            settings.OutputPath = folder.Path;
            settings.Save();
            outputPath.Text = folder.Path;
        }
    }

    private void OpenOutput()
    {
        if (Directory.Exists(settings.OutputPath))
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(settings.OutputPath) { UseShellExecute = true });
    }

    private async Task RenderAsync()
    {
        if (LayoutStore.Shared.Masker is not { } masker)
        {
            await Ui.ShowAsync(XamlRoot, Loc.Tr("Error"), Loc.Tr("Layout or mask.png missing"));
            return;
        }
        if (settings.OutputPath.Length == 0)
        {
            await Ui.ShowAsync(XamlRoot, Loc.Tr("Error"), Loc.Tr("Choose an output folder."));
            return;
        }

        var plan = Plan();
        var (width, height) = LayoutStore.Shared.Size(Kind);
        renderButton.IsEnabled = false;
        status.Text = Loc.Tr("Rendering…");
        try
        {
            var back = plan.NeedsCardBack ? await MPCFill.DownloadAsync(settings.Back, Paths.Cache) : null;
            var result = await Task.Run(() => Export.RenderPlan(plan, width, height, settings.OutputPath, masker, back,
                progress => DispatcherQueue.TryEnqueue(() => status.Text = progress)));
            status.Text = result.Summary(Kind);
        }
        catch (Exception error)
        {
            status.Text = Loc.Tr("Error.");
            await Ui.ShowAsync(XamlRoot, Loc.Tr("Error"), error.Message);
        }
        finally
        {
            renderButton.IsEnabled = true;
        }
    }
}
