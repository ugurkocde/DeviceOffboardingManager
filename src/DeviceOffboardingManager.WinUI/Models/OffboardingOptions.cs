namespace DeviceOffboardingManager.WinUI.Models;

public sealed record OffboardingOptions
{
    public bool DeleteEntra { get; init; }

    public bool DisableEntra { get; init; }

    public bool DeleteIntune { get; init; }

    public bool DeleteAutopilot { get; init; }

    public bool OffboardDefender { get; init; }

    public DevicePreAction PreAction { get; init; }
}
