namespace DeviceOffboardingManager.WinUI.Models;

public sealed record OffboardingSummary
{
    public IReadOnlyList<DeviceOffboardingResult> Results { get; init; } = Array.Empty<DeviceOffboardingResult>();

    public int TotalDevices => Results.Count;

    public int SuccessfulDevices => Results.Count(result =>
    {
        var requested = GetServiceResults(result).Where(operation => operation.WasRequested).ToArray();
        return requested.Length > 0 && requested.All(operation => operation.State == ServiceOperationState.Succeeded);
    });

    public int FailedDevices => Results.Count(result =>
        GetServiceResults(result).Any(operation => operation.State is ServiceOperationState.MissingTarget or ServiceOperationState.Failed));

    private static IEnumerable<ServiceOperationResult> GetServiceResults(DeviceOffboardingResult result)
    {
        yield return result.PreAction;
        yield return result.Entra;
        yield return result.Intune;
        yield return result.Autopilot;
        yield return result.Defender;
    }
}
