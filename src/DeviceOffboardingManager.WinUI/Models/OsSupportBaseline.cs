namespace DeviceOffboardingManager.WinUI.Models;

public sealed record OsSupportBaseline
{
    public IReadOnlyList<string> CurrentVersionPrefixes { get; init; } = Array.Empty<string>();

    public IReadOnlyList<string> EndOfLifeVersionPrefixes { get; init; } = Array.Empty<string>();
}
