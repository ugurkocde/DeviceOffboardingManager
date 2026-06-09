namespace DeviceOffboardingManager.WinUI.Models;

public sealed record GroupTagUpdateResult
{
    public int Updated { get; init; }

    public int Failed { get; init; }
}
