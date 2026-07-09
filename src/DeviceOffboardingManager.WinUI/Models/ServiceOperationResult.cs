namespace DeviceOffboardingManager.WinUI.Models;

public sealed record ServiceOperationResult
{
    public ServiceOperationState State { get; init; } = ServiceOperationState.Skipped;

    public string? Action { get; init; }

    public string? Error { get; init; }

    public bool WasRequested => State != ServiceOperationState.Skipped;

    public bool Success => State == ServiceOperationState.Succeeded;

    public static ServiceOperationResult Skipped() => new();

    public static ServiceOperationResult MissingTarget(string action, string error) => new()
    {
        State = ServiceOperationState.MissingTarget,
        Action = action,
        Error = error
    };

    public static ServiceOperationResult Succeeded(string action) => new()
    {
        State = ServiceOperationState.Succeeded,
        Action = action
    };

    public static ServiceOperationResult Failed(string action, string error) => new()
    {
        State = ServiceOperationState.Failed,
        Action = action,
        Error = error
    };
}
