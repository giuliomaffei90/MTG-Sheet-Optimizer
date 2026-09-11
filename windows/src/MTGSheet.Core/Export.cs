using SkiaSharp;

namespace MTGSheet.Core;

public sealed record RenderResult(int Pages, int BackPages, int Singles, int DoubleSided)
{
    public string Summary(PageKind kind)
    {
        var parts = new List<string>();
        if (Pages > 0) parts.Add(Loc.Tr("%@ pages: %d", kind, Pages));
        if (BackPages > 0) parts.Add(Loc.Tr("Back pages: %d", BackPages));
        if (Singles > 0) parts.Add(Loc.Tr("Singles in '%@': %d", Export.SinglesDir, Singles));
        if (DoubleSided > 0) parts.Add(Loc.Tr("Cut cards in '%@': %d", Export.DoubleSidedDir, DoubleSided));
        return Loc.Tr("Done: %@.", parts.Count == 0 ? Loc.Tr("nothing to do") : string.Join(", ", parts));
    }
}

public static class Export
{
    public const string SinglesDir = "Singles";
    public const string DoubleSidedDir = "Double Sided";

    /// Repeated files (several copies of a card) get " 2", " 3"… so no copy overwrites another.
    public static int ExportSingles(IReadOnlyList<string> files, string directory, Masker masker)
    {
        var seen = new Dictionary<string, int>();
        foreach (var file in files)
        {
            var stem = Path.GetFileNameWithoutExtension(file);
            seen[stem] = seen.GetValueOrDefault(stem) + 1;
            var suffix = seen[stem] > 1 ? $" {seen[stem]}" : "";
            using var card = masker.Card(file);
            Imaging.SavePng(card, Path.Combine(directory, $"{stem}{suffix}_alpha.png"));
        }
        return files.Count;
    }

    public static RenderResult RenderPlan(SheetPlan plan, int width, int height, string output, Masker masker,
                                          string? back, Action<string>? progress = null)
    {
        using var cardBack = back is null ? null : masker.Card(back);   // the same back sits on every back page
        int pages = 0, backPages = 0;
        for (var i = 0; i < plan.Pages.Count; i++)
        {
            var page = plan.Pages[i];
            progress?.Invoke($"{i + 1}/{plan.Pages.Count}");
            var placements = new List<(SKBitmap, Slot)>();
            var owned = new List<SKBitmap>();
            foreach (var (item, slot) in page.Items)
            {
                if (item.Path is { } path)
                {
                    var card = masker.Card(path);
                    owned.Add(card);
                    placements.Add((card, slot));
                }
                else if (cardBack is not null)
                {
                    placements.Add((cardBack, slot));
                }
            }
            using (var sheet = Imaging.RenderPage(width, height, masker.CardSize, placements))
                Imaging.SavePng(sheet, Path.Combine(output, page.Name));
            foreach (var bitmap in owned) bitmap.Dispose();
            if (page.IsBack) backPages++; else pages++;
        }
        return new RenderResult(pages, backPages,
            ExportSingles(plan.Singles, Path.Combine(output, SinglesDir), masker),
            ExportSingles(plan.DoubleSided, Path.Combine(output, DoubleSidedDir), masker));
    }
}
