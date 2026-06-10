namespace DeviceOffboardingManager.WinUI.Models;

public sealed record DashboardSummary
{
    public int IntuneDevices { get; init; }

    public int AutopilotDevices { get; init; }

    public int EntraDevices { get; init; }

    public int StaleDevices30Days { get; init; }

    public int StaleDevices90Days { get; init; }

    public int StaleDevices180Days { get; init; }

    public int PersonalDevices { get; init; }

    public int CorporateDevices { get; init; }

    public IReadOnlyDictionary<string, int> PlatformCounts { get; init; } =
        new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
}
