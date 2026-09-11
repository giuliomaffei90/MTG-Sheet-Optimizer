using SkiaSharp;

namespace MTGSheet.Core;

/// Cuts cards out with mask.png and draws sheets, mirroring Render.swift. Output is always 300 DPI.
public static class Imaging
{
    public const int OutputDpi = 300;

    public static SKBitmap Load(string path, int? maxPixelSize = null)
    {
        var bitmap = SKBitmap.Decode(path) ?? throw new IOException($"Can't read {Path.GetFileName(path)}");
        if (maxPixelSize is not { } max || Math.Max(bitmap.Width, bitmap.Height) <= max) return bitmap;
        var scale = (float)max / Math.Max(bitmap.Width, bitmap.Height);
        var info = new SKImageInfo((int)(bitmap.Width * scale), (int)(bitmap.Height * scale),
                                   SKColorType.Rgba8888, SKAlphaType.Premul);
        var small = bitmap.Resize(info, SKFilterQuality.Medium) ?? bitmap;
        if (!ReferenceEquals(small, bitmap)) bitmap.Dispose();
        return small;
    }

    /// Slots are in full-resolution top-left page coordinates, the same system Skia uses.
    /// scale &lt; 1 draws a smaller copy of the page.
    public static SKBitmap RenderPage(int width, int height, SKSize cardSize,
                                      IReadOnlyList<(SKBitmap Image, Slot Slot)> placements, double scale = 1)
    {
        var bitmap = new SKBitmap(Math.Max(1, (int)(width * scale)), Math.Max(1, (int)(height * scale)),
                                  SKColorType.Rgba8888, SKAlphaType.Premul);
        using var canvas = new SKCanvas(bitmap);
        canvas.Clear(SKColors.Transparent);
        canvas.Scale((float)scale);
        using var paint = new SKPaint { IsAntialias = true, FilterQuality = SKFilterQuality.High };
        var rect = new SKRect(-cardSize.Width / 2, -cardSize.Height / 2, cardSize.Width / 2, cardSize.Height / 2);
        foreach (var (image, slot) in placements)
        {
            canvas.Save();
            canvas.Translate((float)Math.Round(slot.Cx, MidpointRounding.AwayFromZero),
                             (float)Math.Round(slot.Cy, MidpointRounding.AwayFromZero));
            canvas.RotateDegrees((float)slot.Rot);
            canvas.DrawBitmap(image, rect, paint);
            canvas.Restore();
        }
        return bitmap;
    }

    public static void SavePng(SKBitmap bitmap, string path)
    {
        using var image = SKImage.FromBitmap(bitmap);
        using var data = image.Encode(SKEncodedImageFormat.Png, 100);
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        File.WriteAllBytes(path, WithDpi(data.ToArray(), OutputDpi));
    }

    /// Skia doesn't write the PNG pHYs chunk, so the print resolution is inserted right after IHDR.
    public static byte[] WithDpi(byte[] png, int dpi)
    {
        var perMetre = (uint)Math.Round(dpi / 0.0254);
        var body = new List<byte>("pHYs"u8.ToArray());
        body.AddRange(BigEndian(perMetre));
        body.AddRange(BigEndian(perMetre));
        body.Add(1);   // unit: metres
        var chunk = new List<byte>(BigEndian(9));
        chunk.AddRange(body);
        chunk.AddRange(BigEndian(Crc32(body)));

        const int afterIhdr = 8 + 4 + 4 + 13 + 4;   // signature + IHDR length, type, data, crc
        var result = new byte[png.Length + chunk.Count];
        Array.Copy(png, result, afterIhdr);
        chunk.CopyTo(result, afterIhdr);
        Array.Copy(png, afterIhdr, result, afterIhdr + chunk.Count, png.Length - afterIhdr);
        return result;
    }

    /// Pixels per metre stored in a PNG, or null when the chunk is missing.
    public static uint? DpiOf(byte[] png)
    {
        for (var i = 8; i + 8 <= png.Length;)
        {
            var length = (int)BitConverter.ToUInt32([png[i + 3], png[i + 2], png[i + 1], png[i]]);
            var type = System.Text.Encoding.ASCII.GetString(png, i + 4, 4);
            if (type == "pHYs")
            {
                var perMetre = BitConverter.ToUInt32([png[i + 11], png[i + 10], png[i + 9], png[i + 8]]);
                return (uint)Math.Round(perMetre * 0.0254);
            }
            i += 12 + length;
        }
        return null;
    }

    private static byte[] BigEndian(uint value) => [(byte)(value >> 24), (byte)(value >> 16), (byte)(value >> 8), (byte)value];

    private static uint Crc32(IEnumerable<byte> bytes)
    {
        uint crc = 0xFFFFFFFF;
        foreach (var b in bytes)
        {
            crc ^= b;
            for (var k = 0; k < 8; k++) crc = (crc >> 1) ^ (0xEDB88320 & (uint)-(crc & 1));
        }
        return crc ^ 0xFFFFFFFF;
    }
}

/// mask.png: the card canvas (822x1122 px = 69.6x95 mm at 300 DPI) and the rounded card shape in its alpha.
public sealed class Masker : IDisposable
{
    public SKBitmap Mask { get; }
    public SKSize CardSize => new(Mask.Width, Mask.Height);

    public Masker(string maskPath) => Mask = Imaging.Load(maskPath);

    /// Card stretched to the card canvas, alpha taken from the mask; height makes a small copy for previews.
    public SKBitmap Card(string path, int? height = null)
    {
        var h = height ?? Mask.Height;
        var w = Mask.Width * h / Mask.Height;
        var bitmap = new SKBitmap(w, h, SKColorType.Rgba8888, SKAlphaType.Premul);
        using var canvas = new SKCanvas(bitmap);
        canvas.Clear(SKColors.Transparent);
        var rect = new SKRect(0, 0, w, h);
        using var source = Imaging.Load(path, height * 2);
        using var paint = new SKPaint { IsAntialias = true, FilterQuality = SKFilterQuality.High };
        canvas.DrawBitmap(source, rect, paint);
        paint.BlendMode = SKBlendMode.DstIn;
        canvas.DrawBitmap(Mask, rect, paint);
        return bitmap;
    }

    public void Dispose() => Mask.Dispose();
}
