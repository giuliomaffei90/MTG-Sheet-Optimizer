using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using SkiaSharp;

namespace MTGSheet.App;

/// Small helpers shared by the views: the interface is built in code, not XAML.
public static class Ui
{
    public static T With<T>(this T element, Action<T> configure) where T : notnull
    {
        configure(element);
        return element;
    }

    public static TextBlock Text(string text, double size = 14, bool dim = false, bool bold = false) => new()
    {
        Text = text,
        FontSize = size,
        FontWeight = bold ? Microsoft.UI.Text.FontWeights.SemiBold : Microsoft.UI.Text.FontWeights.Normal,
        Opacity = dim ? 0.6 : 1,
        TextTrimming = TextTrimming.CharacterEllipsis,
        VerticalAlignment = VerticalAlignment.Center,
    };

    public static Button Button(string label, RoutedEventHandler click) =>
        new Button { Content = label }.With(b => b.Click += click);

    public static StackPanel Row(params UIElement[] children) =>
        new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center }
            .With(panel => { foreach (var child in children) panel.Children.Add(child); });

    public static StackPanel Column(params UIElement[] children) =>
        new StackPanel { Orientation = Orientation.Vertical, Spacing = 8 }
            .With(panel => { foreach (var child in children) panel.Children.Add(child); });

    public static async Task<BitmapImage> ToImageAsync(SKBitmap bitmap)
    {
        using var image = SKImage.FromBitmap(bitmap);
        using var data = image.Encode(SKEncodedImageFormat.Png, 100);
        using var stream = new MemoryStream(data.ToArray());
        var source = new BitmapImage();
        await source.SetSourceAsync(stream.AsRandomAccessStream());
        return source;
    }

    public static BitmapImage FromUrl(string? url) =>
        url is null ? new BitmapImage() : new BitmapImage(new Uri(url));

    public static async Task ShowAsync(XamlRoot root, string title, string message)
    {
        await new ContentDialog
        {
            XamlRoot = root,
            Title = title,
            Content = message,
            CloseButtonText = "OK",
        }.ShowAsync();
    }

    /// A wrap layout, so card tiles flow like the SwiftUI grid. WinUI has no built-in wrap panel.
    public sealed class WrapPanel : Panel
    {
        public double ItemWidth { get; set; } = 150;
        public double Spacing { get; set; } = 12;

        protected override Size MeasureOverride(Size available)
        {
            double x = 0, y = 0, lineHeight = 0;
            foreach (var child in Children)
            {
                child.Measure(new Size(ItemWidth, double.PositiveInfinity));
                var size = child.DesiredSize;
                if (x + size.Width > available.Width && x > 0)
                {
                    x = 0;
                    y += lineHeight + Spacing;
                    lineHeight = 0;
                }
                x += size.Width + Spacing;
                lineHeight = Math.Max(lineHeight, size.Height);
            }
            return new Size(available.Width, y + lineHeight);
        }

        protected override Size ArrangeOverride(Size final)
        {
            double x = 0, y = 0, lineHeight = 0;
            foreach (var child in Children)
            {
                var size = child.DesiredSize;
                if (x + size.Width > final.Width && x > 0)
                {
                    x = 0;
                    y += lineHeight + Spacing;
                    lineHeight = 0;
                }
                child.Arrange(new Rect(x, y, size.Width, size.Height));
                x += size.Width + Spacing;
                lineHeight = Math.Max(lineHeight, size.Height);
            }
            return final;
        }
    }
}
