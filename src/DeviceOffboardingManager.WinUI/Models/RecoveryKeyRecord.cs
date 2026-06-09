namespace DeviceOffboardingManager.WinUI.Models;

public sealed record RecoveryKeyRecord
{
    public string? DeviceName { get; init; }

    public string? KeyType { get; init; }

    public string? AccountName { get; init; }

    public string? KeyValue { get; init; }

    public string? Status { get; init; }
}
