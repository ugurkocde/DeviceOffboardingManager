using System.Globalization;
using Microsoft.Windows.ApplicationModel.Resources;

namespace DeviceOffboardingManager.WinUI.Utilities;

public static class AppResources
{
    private static readonly Lazy<ResourceLoader?> Loader = new(CreateLoader);

    public static string Get(string key, string fallback)
    {
        try
        {
            var value = Loader.Value?.GetString(key);
            return string.IsNullOrWhiteSpace(value) ? fallback : value;
        }
        catch
        {
            return fallback;
        }
    }

    public static string Format(string key, string fallback, params object?[] arguments)
    {
        return string.Format(CultureInfo.CurrentCulture, Get(key, fallback), arguments);
    }

    private static ResourceLoader? CreateLoader()
    {
        try
        {
            return new ResourceLoader();
        }
        catch
        {
            return null;
        }
    }
}
