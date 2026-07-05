using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services.Contracts;

namespace DeviceOffboardingManager.WinUI.Services;

public sealed class StatusService : IStatusService
{
    public event Action<StatusReport>? StatusReported;

    public void Report(string title, string message, StatusSeverity severity)
    {
        StatusReported?.Invoke(new StatusReport(title, message, severity));
    }
}
