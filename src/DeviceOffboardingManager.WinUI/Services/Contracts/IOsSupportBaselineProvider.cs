namespace DeviceOffboardingManager.WinUI.Services.Contracts;

public interface IOsSupportBaselineProvider
{
    bool IsOutdated(string? operatingSystem, string? version);

    bool IsEndOfLife(string? operatingSystem, string? version);
}
