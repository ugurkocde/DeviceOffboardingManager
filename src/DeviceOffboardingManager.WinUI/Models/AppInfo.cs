using System.Reflection;

namespace DeviceOffboardingManager.WinUI.Models;

public static class AppInfo
{
    public static string Version { get; } = GetVersion();

    private static string GetVersion()
    {
        var version = Assembly.GetExecutingAssembly().GetName().Version;
        return version is null ? "0.0.0" : $"{version.Major}.{version.Minor}.{version.Build}";
    }
}
