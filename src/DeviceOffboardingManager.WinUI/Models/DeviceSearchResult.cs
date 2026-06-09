namespace DeviceOffboardingManager.WinUI.Models;

public sealed record DeviceSearchResult
{
    public IReadOnlyList<DeviceRecord> Devices { get; init; } = Array.Empty<DeviceRecord>();

    public int EntraCount { get; init; }

    public int IntuneCount { get; init; }

    public int AutopilotCount { get; init; }
}
