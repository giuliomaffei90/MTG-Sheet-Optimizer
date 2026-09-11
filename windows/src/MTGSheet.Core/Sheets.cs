namespace MTGSheet.Core;

// The sheet plan, mirroring Sources/MTGSheetOptimizer/Render.swift. The rules live in spec/spec.md and
// spec/cases/*.json checks both implementations agree.

public enum PageKind { A4, A3 }
public enum ExtraCards { EmptySlots, Singles }
public enum DoubleSidedMode { Singles, Duplex }

public static class PageKinds
{
    public static int SlotCount(this PageKind kind) => kind == PageKind.A4 ? 6 : 14;
    public static string LayoutPng(this PageKind kind) => $"Layout {kind}.png";
    public static string LayoutJson(this PageKind kind) => $"Layout{kind}.json";
}

/// Card centre in page pixels; rotation in degrees clockwise, multiple of 45.
public readonly record struct Slot(double Cx, double Cy, double Rot);

/// One card to print; Back is the other face of a double-faced card.
public readonly record struct PrintCard(string Front, string? Back = null)
{
    public IEnumerable<string> Faces => Back is null ? [Front] : [Front, Back];
}

/// What sits in a slot: a card image, or the generic card back chosen in Settings.
public readonly record struct PageItem(string? Path)
{
    public static readonly PageItem CardBack = new((string?)null);
    public bool IsCardBack => Path is null;
    public static PageItem Image(string path) => new(path);
}

public sealed record PlannedPage(string Name, bool IsBack, List<(PageItem Item, Slot Slot)> Items);

/// Every file an export writes, in print order. Rendering and the live preview both draw this.
public sealed class SheetPlan
{
    public List<PlannedPage> Pages { get; } = [];
    public List<string> Singles { get; } = [];        // → Singles/
    public List<string> DoubleSided { get; } = [];    // → Double Sided/
    public bool NeedsCardBack => Pages.Any(p => p.Items.Any(i => i.Item.IsCardBack));
}

public static class Sheets
{
    /// Swift's Double.rounded() rounds halves away from zero, so this must too.
    public static double SnapAngle(double degrees)
    {
        var r = Math.Round(degrees / 45, MidpointRounding.AwayFromZero) * 45 % 360;
        return r < 0 ? r + 360 : r;
    }

    public static SheetPlan PlanSheets(IReadOnlyList<PrintCard> cards, IReadOnlyList<Slot> slots, double pageWidth,
                                       PageKind kind, ExtraCards extra, DoubleSidedMode doubleSided, bool backPage)
    {
        var plan = new SheetPlan();
        var n = slots.Count;
        if (n == 0) return plan;

        var doubleFaced = cards.Where(c => c.Back is not null).ToList();
        var onPages = cards.Where(c => c.Back is null).ToList();
        if (doubleSided == DoubleSidedMode.Duplex)
            onPages = [.. doubleFaced, .. onPages];   // grouped first, so fewer sheets need a back page of their own
        else
            plan.DoubleSided.AddRange(doubleFaced.SelectMany(c => c.Faces));

        // The sheet flips on its long edge: x is mirrored and every back turns the opposite way (90° → 270°),
        // so it's upright when the cut card is flipped.
        Slot Behind(Slot s) => new(pageWidth - s.Cx, s.Cy, SnapAngle(-s.Rot));

        var sheetsWithoutBack = false;
        var number = 0;
        for (var start = 0; start < onPages.Count; start += n)
        {
            var chunk = onPages.Skip(start).Take(n).ToList();
            if (chunk.Count < n && extra == ExtraCards.Singles)
            {
                plan.Singles.AddRange(chunk.SelectMany(c => c.Faces));
                continue;
            }
            number++;
            var name = $"layout_{kind}_" + (chunk.Count < n ? "LAST" : number.ToString("D3"));
            plan.Pages.Add(new PlannedPage(name + ".png", false,
                chunk.Zip(slots, (card, slot) => (PageItem.Image(card.Front), slot)).ToList()));

            if (chunk.Any(c => c.Back is not null))
            {
                // Other slots get the generic back only when the back page is on.
                var backs = chunk.Zip(slots, (card, slot) => card.Back is not null
                        ? ((PageItem, Slot)?)(PageItem.Image(card.Back), Behind(slot))
                        : backPage ? (PageItem.CardBack, Behind(slot)) : null)
                    .Where(x => x is not null).Select(x => x!.Value).ToList();
                plan.Pages.Add(new PlannedPage(name + "_back.png", true, backs));
            }
            else if (backPage)
            {
                sheetsWithoutBack = true;
            }
        }

        if (sheetsWithoutBack)
        {
            // One back page serves every sheet without double-faced cards.
            plan.Pages.Insert(0, new PlannedPage($"backpage_{kind}.png", true,
                slots.Select(s => (PageItem.CardBack, Behind(s))).ToList()));
        }
        return plan;
    }

    /// Topmost slot whose card, rotated with the slot, contains the point.
    public static int? SlotAt(IReadOnlyList<Slot> slots, double px, double py, double cardWidth, double cardHeight)
    {
        for (var i = slots.Count - 1; i >= 0; i--)
        {
            var s = slots[i];
            var a = s.Rot * Math.PI / 180;
            double dx = px - s.Cx, dy = py - s.Cy;
            // Undo the slot's clockwise rotation (y points down).
            var lx = dx * Math.Cos(a) + dy * Math.Sin(a);
            var ly = -dx * Math.Sin(a) + dy * Math.Cos(a);
            if (Math.Abs(lx) <= cardWidth / 2 && Math.Abs(ly) <= cardHeight / 2) return i;
        }
        return null;
    }

    /// Spaces the cards at the given indices evenly, centre to centre, between the outermost two.
    public static void Distribute(Slot[] slots, IReadOnlyList<int> indices, bool horizontal)
    {
        double Axis(int i) => horizontal ? slots[i].Cx : slots[i].Cy;
        var sorted = indices.OrderBy(Axis).ToList();
        if (sorted.Count <= 2) return;
        var start = Axis(sorted[0]);
        var step = (Axis(sorted[^1]) - start) / (sorted.Count - 1);
        for (var k = 0; k < sorted.Count; k++)
        {
            var value = start + k * step;
            slots[sorted[k]] = horizontal ? slots[sorted[k]] with { Cx = value } : slots[sorted[k]] with { Cy = value };
        }
    }

    public static Slot[] DefaultSlots(PageKind kind, double width, double height)
    {
        int cols = kind == PageKind.A3 ? 7 : 3, rows = 2;
        double mx = width * 0.06, my = height * 0.06;
        double cw = (width - 2 * mx) / cols, ch = (height - 2 * my) / rows;
        return (from r in Enumerable.Range(0, rows)
                from c in Enumerable.Range(0, cols)
                select new Slot(mx + (c + 0.5) * cw, my + (r + 0.5) * ch, 0)).ToArray();
    }
}
