namespace DeviceOffboardingManager.WinUI.Models;

public sealed record UpdateCheckResult(
    string Message,
    bool UpdateAvailable);
