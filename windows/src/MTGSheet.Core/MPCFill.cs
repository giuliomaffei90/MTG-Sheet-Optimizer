using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace MTGSheet.Core;

/// Client for the public MPC Autofill backend behind mpcfill.com, mirroring MPCFill.swift (see spec/spec.md).
/// No login needed: search goes to mpcfill.com, images come straight from Google.
public static class MPCFill
{
    public const string BaseUrl = "https://mpcfill.com/";
    /// Cloudflare in front of mpcfill.com rejects some default user agents.
    public const string UserAgent = "Mozilla/5.0 (Macintosh) MTGSheetOptimizer";
    public const int MaxQueriesPerSearch = 300;
    public const int MaxCardsPerRequest = 1000;

    public enum CardType { Card, Token, Cardback }

    public readonly record struct Query(string Text, CardType Type)
    {
        public string TypeName => Type switch
        {
            CardType.Token => "TOKEN",
            CardType.Cardback => "CARDBACK",
            _ => "CARD",
        };
    }

    public sealed record Card(
        string Identifier, string Name, string SourceName, string? SourceType, int Dpi, long Size,
        [property: JsonPropertyName("extension")] string Extension, string SmallThumbnailUrl, string? DownloadLink);

    public sealed record Entry(int Quantity, string Name, Query Front, Query? Back);

    private static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    private static readonly HttpClient Http = CreateClient();

    private static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromMinutes(2) };
        client.DefaultRequestHeaders.Add("User-Agent", UserAgent);
        return client;
    }

    /// HttpClient can reuse a keep-alive connection the server already closed: retry once.
    private static async Task<JsonElement> SendAsync(string path, object? body = null)
    {
        async Task<HttpResponseMessage> Once() => body is null
            ? await Http.GetAsync(BaseUrl + path)
            : await Http.PostAsJsonAsync(BaseUrl + path, body);

        HttpResponseMessage response;
        try { response = await Once(); }
        catch (HttpRequestException) { response = await Once(); }

        if (!response.IsSuccessStatusCode)
            throw new HttpRequestException(Loc.Tr("MPCFill answered %d to %@", (int)response.StatusCode, path));
        return JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement.Clone();
    }

    /// Every source, enabled, in the order mpcfill.com searches them by default (ascending primary key).
    public static async Task<int[]> SourceIdsAsync()
    {
        var results = (await SendAsync("2/sources/")).GetProperty("results");
        return results.EnumerateObject().Select(p => p.Value.GetProperty("pk").GetInt32()).OrderBy(pk => pk).ToArray();
    }

    /// mpcfill.com's default search settings.
    private static object SearchSettings(IEnumerable<int> sources) => new
    {
        searchTypeSettings = new { fuzzySearch = false, filterCardbacks = false },
        sourceSettings = new { sources = sources.Select(pk => new object[] { pk, true }).ToArray() },
        filterSettings = new
        {
            minimumDPI = 0, maximumDPI = 1500, maximumSize = 30,
            languages = Array.Empty<string>(), includesTags = Array.Empty<string>(), excludesTags = new[] { "NSFW" },
        },
    };

    /// Identifiers of every variant of each query, best first.
    public static async Task<Dictionary<Query, List<string>>> SearchAsync(IReadOnlyList<Query> queries, IReadOnlyList<int> sources)
    {
        var unique = queries.Distinct().ToList();
        var found = new Dictionary<Query, List<string>>();
        for (var start = 0; start < unique.Count; start += MaxQueriesPerSearch)
        {
            var chunk = unique.Skip(start).Take(MaxQueriesPerSearch).ToList();
            // v2 endpoint: the one live on mpcfill.com, kept upstream for third-party clients.
            var response = await SendAsync("2/editorSearch/", new
            {
                queries = chunk.Select(q => new { query = q.Text, cardType = q.TypeName }).ToArray(),
                searchSettings = SearchSettings(sources),
            });
            var results = response.GetProperty("results");
            foreach (var query in chunk)
            {
                var hits = new List<string>();
                if (results.TryGetProperty(query.Text, out var byType) && byType.TryGetProperty(query.TypeName, out var ids))
                    hits.AddRange(ids.EnumerateArray().Select(i => i.GetString()!));
                found[query] = hits;
            }
        }
        return found;
    }

    public static async Task<Dictionary<string, Card>> CardsAsync(IReadOnlyList<string> identifiers)
    {
        var cards = new Dictionary<string, Card>();
        for (var start = 0; start < identifiers.Count; start += MaxCardsPerRequest)
        {
            var response = await SendAsync("2/cards/",
                new { cardIdentifiers = identifiers.Skip(start).Take(MaxCardsPerRequest).ToArray() });
            foreach (var property in response.GetProperty("results").EnumerateObject())
                cards[property.Name] = property.Value.Deserialize<Card>(Json)!;
        }
        return cards;
    }

    public static async Task<string[]> CardbacksAsync(IReadOnlyList<int> sources)
    {
        var response = await SendAsync("2/cardbacks/", new { searchSettings = SearchSettings(sources) });
        return response.GetProperty("cardbacks").EnumerateArray().Select(i => i.GetString()!).ToArray();
    }

    /// Front face → back face of double-faced cards, both normalised like queries.
    public static async Task<Dictionary<string, string>> DfcPairsAsync()
    {
        var pairs = (await SendAsync("2/DFCPairs/")).GetProperty("dfcPairs");
        var map = new Dictionary<string, string>();
        foreach (var pair in pairs.EnumerateObject()) map[Normalise(pair.Name)] = Normalise(pair.Value.GetString()!);
        return map;
    }

    /// Output cards are 1122 px tall: fetch twice that so the downscale stays sharp without pulling ~9 MB originals.
    public static string? ImageUrl(Card card) =>
        card.SourceType is null or "Google Drive"
            ? $"https://lh4.googleusercontent.com/d/{card.Identifier}=h2244"
            : card.DownloadLink;

    /// Saves the card in the folder as "Name (identifier).ext", like mpcfill.com exports; reuses earlier downloads.
    public static async Task<string> DownloadAsync(Card card, string directory)
    {
        var safeName = card.Name.Replace('/', '-').Replace(':', '-');
        var file = Path.Combine(directory, $"{safeName} ({card.Identifier}).{card.Extension}");
        if (File.Exists(file)) return file;
        var url = ImageUrl(card) ?? throw new HttpRequestException(Loc.Tr("No download link for %@", card.Name));

        async Task<HttpResponseMessage> Once() => await Http.GetAsync(url);
        HttpResponseMessage response;
        try { response = await Once(); }
        catch (HttpRequestException) { response = await Once(); }
        if (!response.IsSuccessStatusCode) throw new HttpRequestException(Loc.Tr("Download failed: %@", card.Name));

        Directory.CreateDirectory(directory);
        await File.WriteAllBytesAsync(file, await response.Content.ReadAsByteArrayAsync());
        return file;
    }

    // MARK: decklist

    private const string Punctuation = "~`!@#$%^&*(){}[];:\"'’<,.>?/\\|_+=";

    /// Lowercase, drop punctuation except hyphens, collapse whitespace: what mpcfill.com searches for.
    public static string Normalise(string text)
    {
        var kept = new string(text.ToLowerInvariant().Where(c => !Punctuation.Contains(c)).ToArray());
        return string.Join(" ", kept.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
    }

    /// Parses a Moxfield / mpcfill.com list: "2 Opt", "2x Opt (XLN) 65 *F*", "t:Treasure", "Front // Back".
    public static List<Entry> ParseDecklist(string text, IReadOnlyDictionary<string, string> dfcPairs)
    {
        var entries = new List<Entry>();
        foreach (var rawLine in text.Split('\n', '\r'))
        {
            var line = rawLine.Trim();
            if (line.Length == 0 || line.EndsWith(':') || line.StartsWith('#') || line.StartsWith("//")) continue;

            var quantity = 1;
            var parts = line.Split(' ', 2);
            if (parts.Length == 2)
            {
                var token = parts[0].EndsWith('x') || parts[0].EndsWith('X') ? parts[0][..^1] : parts[0];
                if (int.TryParse(token, out var n)) { quantity = n; line = parts[1]; }
            }
            if (quantity <= 0) continue;
            line = Regex.Replace(line, @"\*[A-Z]+\*", "");

            var faces = line.Split("//").Select(ParseFace).Where(f => f is not null).Select(f => f!.Value).ToList();
            if (faces.Count == 0) continue;
            var front = faces[0];
            Query? back = faces.Count > 1
                ? faces[1].Query
                : dfcPairs.TryGetValue(front.Query.Text, out var pair) ? new Query(pair, front.Query.Type) : null;
            entries.Add(new Entry(quantity, front.Name, front.Query, back));
        }
        return entries;
    }

    private static (string Name, Query Query)? ParseFace(string raw)
    {
        var text = raw.Trim();
        var type = CardType.Card;
        if (text.StartsWith("t:", StringComparison.OrdinalIgnoreCase)) { type = CardType.Token; text = text[2..]; }
        else if (text.StartsWith("b:", StringComparison.OrdinalIgnoreCase)) { type = CardType.Cardback; text = text[2..]; }
        // Printing info "(SET) 123" and mpcfill's "@identifier" can't be searched for: keep the name only.
        var cut = text.IndexOfAny(['(', '[', '@']);
        if (cut >= 0) text = text[..cut];
        text = text.Trim();
        var query = Normalise(text);
        return query.Length == 0 ? null : (text, new Query(query, type));
    }
}
