namespace DeviceOffboardingManager.WinUI.Models;

public sealed record OffboardingSummary
{
    public IReadOnlyList<DeviceOffboardingResult> Results { get; init; } = Array.Empty<DeviceOffboardingResult>();

    public int TotalDevices => Results.Count;

    public int SuccessfulDevices => Results.Count(r => GetServiceResults(r).Any(s => s.Found) && GetServiceResults(r).Where(s => s.Found).All(s => s.Success));

    public int FailedDevices => Results.Count(r => GetServiceResults(r).Any(s => s.Found && !s.Success));

    private static IEnumerable<ServiceOperationResult> GetServiceResults(DeviceOffboardingResult result)
    {
        yield return result.PreAction;
        yield return result.Entra;
        yield return result.Intune;
        yield return result.Autopilot;
        yield return result.Defender;
    }
}
