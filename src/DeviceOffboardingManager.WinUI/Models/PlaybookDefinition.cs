namespace DeviceOffboardingManager.WinUI.Models;

public sealed record PlaybookDefinition(
    string Id,
    string Name,
    string Description,
    bool RequiresParameter = false,
    string? ParameterHint = null);
