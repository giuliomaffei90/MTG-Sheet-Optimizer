using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using MTGSheet.Core;

namespace MTGSheet.App;

/// Language, the layout editor and the card back — the same three settings the macOS app offers.
public sealed class SettingsWindow : Window
{
    private readonly AppSettings settings = AppSettings.Current;
    private readonly Image backThumbnail = new() { Width = 44, Stretch = Stretch.Uniform };
    private readonly TextBlock backName = Ui.Text("");
    private readonly TextBlock backSource = Ui.Text("", 11, dim: true);

    public SettingsWindow()
    {
        Title = Loc.Tr("Settings");
        AppWindow.Resize(new Windows.Graphics.SizeInt32(560, 380));

        var english = new RadioButton { Content = "English", IsChecked = settings.Language == "en", GroupName = "lang" };
        var italian = new RadioButton { Content = "Italiano", IsChecked = settings.Language == "it", GroupName = "lang" };
        english.Checked += (_, _) => SetLanguage("en");
        italian.Checked += (_, _) => SetLanguage("it");

        ShowBack();
        var back = Ui.Row(backThumbnail, Ui.Column(backName, backSource),
            Ui.Button(Loc.Tr("Choose…"), (_, _) => new CardPickerWindow(
                Loc.Tr("Card back"), settings.Back.Identifier, CardbacksAsync,
                card => { settings.CardBack = card; settings.Save(); ShowBack(); }).Activate()));

        Content = new ScrollViewer
        {
            Content = Ui.Column(
                Ui.Text(Loc.Tr("Language"), 16, bold: true), english, italian,
                Ui.Text("Layout", 16, bold: true),
                Ui.Button(Loc.Tr("Edit layout…"), (_, _) => new LayoutEditorWindow().Activate()),
                Ui.Text(Loc.Tr("Card back"), 16, bold: true), back,
                Ui.Text(Loc.Tr("The language applies to windows opened from now on."), 11, dim: true)
            ).With(c => c.Padding = new Thickness(20)),
        };
    }

    private static async Task<List<MPCFill.Card>> CardbacksAsync()
    {
        var sources = await MPCFill.SourceIdsAsync();
        var identifiers = await MPCFill.CardbacksAsync(sources);
        var details = await MPCFill.CardsAsync(identifiers);
        return identifiers.Where(details.ContainsKey).Select(id => details[id]).ToList();
    }

    private void SetLanguage(string language)
    {
        settings.Language = language;
        settings.Save();
    }

    private void ShowBack()
    {
        backThumbnail.Source = Ui.FromUrl(settings.Back.SmallThumbnailUrl);
        backName.Text = settings.Back.Name;
        backSource.Text = $"{settings.Back.SourceName} · {settings.Back.Dpi} DPI";
    }
}
