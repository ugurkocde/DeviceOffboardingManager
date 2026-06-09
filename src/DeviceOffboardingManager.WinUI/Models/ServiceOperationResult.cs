namespace DeviceOffboardingManager.WinUI.Models;

public sealed record ServiceOperationResult
{
    public bool Found { get; init; }

    public bool Success { get; init; }

    public string? Action { get; init; }

    public string? Error { get; init; }
}
