namespace DeviceOffboardingManager.WinUI.Models;

public sealed record GroupMembershipRecord
{
    public string? Id { get; init; }

    public string DisplayName { get; init; } = string.Empty;

    public string Type { get; init; } = string.Empty;

    public bool MailEnabled { get; init; }

    public bool SecurityEnabled { get; init; }
}
