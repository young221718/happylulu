using System.Drawing;
using System.Runtime.InteropServices;

namespace HappyLulu.Tray;

internal enum OwlState
{
    Regular,
    Waiting,
    MorningHalf,
    AfternoonHalf,
    LuluDay,
    AnnualLeave,
    DayOff,
    ReadyToLeave
}

internal sealed class OwlStateIcons : IDisposable
{
    private readonly Bitmap fallback;
    private readonly Dictionary<OwlState, Bitmap?> images = new();

    public OwlStateIcons(Icon fallbackIcon) => fallback = fallbackIcon.ToBitmap();

    // Images are shared by the form and remain owned by this cache.
    public Image Get(OwlState state)
    {
        if (!images.TryGetValue(state, out Bitmap? image))
        {
            image = Load(state);
            images[state] = image;
        }
        return image ?? fallback;
    }

    private static Bitmap? Load(OwlState state)
    {
        string? name = state switch
        {
            OwlState.Regular => "regular",
            OwlState.Waiting => "waiting",
            OwlState.MorningHalf => "morningHalf",
            OwlState.AfternoonHalf => "afternoonHalf",
            OwlState.LuluDay => "luluDay",
            OwlState.AnnualLeave => "annualLeave",
            OwlState.DayOff => "dayOff",
            OwlState.ReadyToLeave => "readyToLeave",
            _ => null
        };
        if (name is null) return null;
        using Stream? stream = typeof(OwlStateIcons).Assembly.GetManifestResourceStream($"HappyLulu.OwlStates.{name}.png");
        if (stream is null) return null;
        try
        {
            using Image source = Image.FromStream(stream);
            return new Bitmap(source);
        }
        catch (Exception error) when (error is ArgumentException or ExternalException or OutOfMemoryException)
        {
            return null;
        }
    }

    public void Dispose()
    {
        foreach (Bitmap? image in images.Values) image?.Dispose();
        images.Clear();
        fallback.Dispose();
    }
}
