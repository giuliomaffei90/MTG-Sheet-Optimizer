using System.Text;

namespace MTGSheet.Core;

/// English text is the key; the Italian table is generated from spec/strings.json.
public static class Loc
{
    public static string Language { get; set; } = "en";

    public static string Tr(string english, params object[] args)
    {
        var text = Language == "it" && Strings.Italian.TryGetValue(english, out var italian) ? italian : english;
        return args.Length == 0 ? text : Format(text, args);
    }

    /// The shared strings use printf placeholders (%d, %@) because they come from the Swift side.
    private static string Format(string text, IReadOnlyList<object> args)
    {
        var result = new StringBuilder();
        var next = 0;
        for (var i = 0; i < text.Length; i++)
        {
            if (text[i] == '%' && i + 1 < text.Length && (text[i + 1] is 'd' or '@') && next < args.Count)
            {
                result.Append(args[next++]);
                i++;
            }
            else if (text[i] == '%' && i + 1 < text.Length && text[i + 1] == '%')
            {
                result.Append('%');
                i++;
            }
            else
            {
                result.Append(text[i]);
            }
        }
        return result.ToString();
    }
}
