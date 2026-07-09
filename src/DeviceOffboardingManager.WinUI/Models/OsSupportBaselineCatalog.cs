namespace DeviceOffboardingManager.WinUI.Models;

public sealed record OsSupportBaselineCatalog
{
    public int SchemaVersion { get; init; }

    public DateTimeOffset UpdatedUtc { get; init; }

    public IReadOnlyDictionary<string, OsSupportBaseline> Platforms { get; init; } =
        new Dictionary<string, OsSupportBaseline>(StringComparer.OrdinalIgnoreCase);
}
