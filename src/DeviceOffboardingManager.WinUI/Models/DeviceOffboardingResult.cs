namespace DeviceOffboardingManager.WinUI.Models;

public sealed record DeviceOffboardingResult
{
    public string? DeviceName { get; init; }

    public string? SerialNumber { get; init; }

    public ServiceOperationResult PreAction { get; init; } = new();

    public ServiceOperationResult Entra { get; init; } = new();

    public ServiceOperationResult Intune { get; init; } = new();

    public ServiceOperationResult Autopilot { get; init; } = new();

    public ServiceOperationResult Defender { get; init; } = new();
}
