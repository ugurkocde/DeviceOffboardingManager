namespace DeviceOffboardingManager.WinUI.Models;

public sealed record DeviceOffboardingSettings
{
    public bool DefenderIntegrationEnabled { get; init; }

    public string? TenantId { get; init; }

    public string? ClientId { get; init; }

    public AppDistributionChannel DistributionChannel { get; init; } = AppDistributionChannel.DeveloperBuild;
}
