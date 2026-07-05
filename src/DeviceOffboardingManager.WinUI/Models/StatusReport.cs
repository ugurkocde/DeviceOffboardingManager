namespace DeviceOffboardingManager.WinUI.Models;

public enum StatusSeverity
{
    Informational,
    Success,
    Warning,
    Error
}

public sealed record StatusReport(
    string Title,
    string Message,
    StatusSeverity Severity);
