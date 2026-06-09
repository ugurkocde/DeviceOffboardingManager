namespace DeviceOffboardingManager.WinUI.Graph;

public sealed record GraphBatchRequest(
    string Id,
    string Method,
    string Url,
    object? Body = null,
    IReadOnlyDictionary<string, string>? Headers = null);
