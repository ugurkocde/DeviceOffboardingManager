namespace DeviceOffboardingManager.WinUI.Models;

public sealed record PlaybookRunResult
{
    public PlaybookDefinition Definition { get; init; } = new("unknown", "Unknown", "Unknown");

    public IReadOnlyList<IReadOnlyDictionary<string, string?>> Rows { get; init; } = Array.Empty<IReadOnlyDictionary<string, string?>>();
}
