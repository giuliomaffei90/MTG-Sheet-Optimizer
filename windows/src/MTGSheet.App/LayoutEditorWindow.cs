using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using MTGSheet.Core;
using Windows.Foundation;
using Windows.System;

namespace MTGSheet.App;

/// Moves the card slots on a sheet: shift-click for several cards, arrows to nudge, align and distribute.
/// Every change is saved at once, like the macOS editor.
public sealed class LayoutEditorWindow : Window
{
    private readonly Canvas canvas = new() { Background = new SolidColorBrush(Microsoft.UI.Colors.Black) };
    private readonly Image background = new() { Stretch = Stretch.Uniform };
    private readonly ComboBox kindBox = new() { ItemsSource = new[] { "A4", "A3" }, SelectedIndex = 0 };
    private readonly List<int> selection = [];
    private readonly Dictionary<int, Slot> dragOrigins = [];

    private PageKind kind = PageKind.A4;
    private Slot[] slots = [];
    private double scale = 1, offsetX, offsetY;
    private Point dragStart;
    private bool dragging;

    public LayoutEditorWindow()
    {
        Title = Loc.Tr("Layout editor");
        AppWindow.Resize(new Windows.Graphics.SizeInt32(900, 800));
        slots = (Slot[])LayoutStore.Shared.Slots(kind).Clone();

        kindBox.SelectionChanged += (_, _) =>
        {
            kind = kindBox.SelectedIndex == 1 ? PageKind.A3 : PageKind.A4;
            slots = (Slot[])LayoutStore.Shared.Slots(kind).Clone();
            selection.Clear();
            Draw();
        };

        var rotateLeft = Ui.Button("↺ 45°", (_, _) => Edit(s => s with { Rot = Sheets.SnapAngle(s.Rot - 45) }));
        var rotateRight = Ui.Button("↻ 45°", (_, _) => Edit(s => s with { Rot = Sheets.SnapAngle(s.Rot + 45) }));
        var noRotation = Ui.Button("0°", (_, _) => Edit(s => s with { Rot = 0 }));
        var alignRow = Ui.Button("⬌", (_, _) => Align(horizontal: false));
        var alignColumn = Ui.Button("⬍", (_, _) => Align(horizontal: true));
        ToolTipService.SetToolTip(alignRow, Loc.Tr("Puts the selected cards on the same row as the first one you selected."));
        ToolTipService.SetToolTip(alignColumn, Loc.Tr("Puts the selected cards in the same column as the first one you selected."));
        var spreadRow = Ui.Button("⇔", (_, _) => Spread(horizontal: true));
        var spreadColumn = Ui.Button("⇕", (_, _) => Spread(horizontal: false));
        ToolTipService.SetToolTip(spreadRow, Loc.Tr("Spaces the selected cards evenly from left to right."));
        ToolTipService.SetToolTip(spreadColumn, Loc.Tr("Spaces the selected cards evenly from top to bottom."));

        var bar = Ui.Row(Ui.Text("Layout"), kindBox, rotateLeft, rotateRight, noRotation,
                         alignRow, alignColumn, spreadRow, spreadColumn,
                         Ui.Button(Loc.Tr("Reset slots"), (_, _) =>
                         {
                             LayoutStore.Shared.Reset(kind);
                             slots = (Slot[])LayoutStore.Shared.Slots(kind).Clone();
                             selection.Clear();
                             Draw();
                         })).With(r => r.Padding = new Thickness(10));

        canvas.PointerPressed += OnPointerPressed;
        canvas.PointerMoved += OnPointerMoved;
        canvas.PointerReleased += OnPointerReleased;
        canvas.SizeChanged += (_, _) => Draw();

        var root = new Grid { IsTabStop = true };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        Grid.SetRow(bar, 0);
        Grid.SetRow(canvas, 1);
        root.Children.Add(bar);
        root.Children.Add(canvas);
        root.KeyDown += OnKeyDown;
        root.Loaded += (_, _) => root.Focus(FocusState.Programmatic);
        Content = root;

        background.Source = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri(LayoutStore.Shared.BackgroundPath(kind)));
        Draw();
    }

    private (double Width, double Height) Page => (LayoutStore.Shared.Size(kind).Width, LayoutStore.Shared.Size(kind).Height);

    private void Save()
    {
        LayoutStore.Shared.SetSlots(kind, (Slot[])slots.Clone());
        Draw();
    }

    private void Edit(Func<Slot, Slot> change)
    {
        foreach (var i in selection) slots[i] = change(slots[i]);
        Save();
    }

    private void Align(bool horizontal)
    {
        if (selection.Count < 2) return;
        var reference = slots[selection[0]];
        Edit(s => horizontal ? s with { Cx = reference.Cx } : s with { Cy = reference.Cy });
    }

    private void Spread(bool horizontal)
    {
        if (selection.Count < 3) return;
        Sheets.Distribute(slots, selection, horizontal);
        Save();
    }

    private void OnKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (selection.Count == 0) return;
        var step = InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Shift).HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down) ? 10 : 1;
        switch (e.Key)
        {
            case VirtualKey.Left: Edit(s => s with { Cx = s.Cx - step }); break;
            case VirtualKey.Right: Edit(s => s with { Cx = s.Cx + step }); break;
            case VirtualKey.Up: Edit(s => s with { Cy = s.Cy - step }); break;
            case VirtualKey.Down: Edit(s => s with { Cy = s.Cy + step }); break;
            case VirtualKey.Escape: selection.Clear(); Draw(); break;
            default: return;
        }
        e.Handled = true;
    }

    private Point ToPage(Point p) => new((p.X - offsetX) / scale, (p.Y - offsetY) / scale);

    private void OnPointerPressed(object sender, PointerRoutedEventArgs e)
    {
        var mask = LayoutStore.Shared.Masker;
        if (mask is null) return;
        var point = ToPage(e.GetCurrentPoint(canvas).Position);
        var hit = Sheets.SlotAt(slots, point.X, point.Y, mask.CardSize.Width, mask.CardSize.Height);
        var shift = InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Shift).HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);

        if (hit is { } index)
        {
            if (shift)
            {
                if (!selection.Remove(index)) selection.Add(index);
            }
            else if (!selection.Contains(index))
            {
                selection.Clear();
                selection.Add(index);
            }
        }
        else if (!shift)
        {
            selection.Clear();
        }

        dragOrigins.Clear();
        if (hit is { } dragged && selection.Contains(dragged))
            foreach (var i in selection) dragOrigins[i] = slots[i];
        dragStart = point;
        dragging = dragOrigins.Count > 0;
        canvas.CapturePointer(e.Pointer);
        Draw();
    }

    private void OnPointerMoved(object sender, PointerRoutedEventArgs e)
    {
        if (!dragging) return;
        var point = ToPage(e.GetCurrentPoint(canvas).Position);
        var (width, height) = Page;
        foreach (var (i, origin) in dragOrigins)
            slots[i] = origin with
            {
                Cx = Math.Clamp(origin.Cx + point.X - dragStart.X, 0, width),
                Cy = Math.Clamp(origin.Cy + point.Y - dragStart.Y, 0, height),
            };
        Draw();
    }

    private void OnPointerReleased(object sender, PointerRoutedEventArgs e)
    {
        canvas.ReleasePointerCapture(e.Pointer);
        if (dragging) Save();
        dragging = false;
        dragOrigins.Clear();
    }

    private void Draw()
    {
        var (pageWidth, pageHeight) = Page;
        if (pageWidth == 0 || canvas.ActualWidth == 0) return;
        var mask = LayoutStore.Shared.Masker;
        scale = Math.Min(canvas.ActualWidth / pageWidth, canvas.ActualHeight / pageHeight);
        offsetX = (canvas.ActualWidth - pageWidth * scale) / 2;
        offsetY = (canvas.ActualHeight - pageHeight * scale) / 2;

        canvas.Children.Clear();
        background.Width = pageWidth * scale;
        background.Height = pageHeight * scale;
        Canvas.SetLeft(background, offsetX);
        Canvas.SetTop(background, offsetY);
        canvas.Children.Add(background);

        var cardWidth = (mask?.CardSize.Width ?? 822) * scale;
        var cardHeight = (mask?.CardSize.Height ?? 1122) * scale;
        for (var i = 0; i < slots.Length; i++)
        {
            var slot = slots[i];
            var isSelected = selection.Contains(i);
            var isReference = selection.Count > 1 && selection[0] == i;
            var card = new Rectangle
            {
                Width = cardWidth,
                Height = cardHeight,
                RadiusX = 14 * scale,
                RadiusY = 14 * scale,
                Fill = new SolidColorBrush(isSelected ? Microsoft.UI.Colors.Cyan : Microsoft.UI.Colors.Yellow)
                    { Opacity = isReference ? 0.85 : 0.55 },
                RenderTransformOrigin = new Point(0.5, 0.5),
                RenderTransform = new RotateTransform { Angle = slot.Rot },
            };
            Canvas.SetLeft(card, offsetX + slot.Cx * scale - cardWidth / 2);
            Canvas.SetTop(card, offsetY + slot.Cy * scale - cardHeight / 2);
            canvas.Children.Add(card);

            var number = Ui.Text((i + 1).ToString(), 18, bold: true);
            Canvas.SetLeft(number, offsetX + slot.Cx * scale - 6);
            Canvas.SetTop(number, offsetY + slot.Cy * scale - 12);
            canvas.Children.Add(number);
        }
    }
}
