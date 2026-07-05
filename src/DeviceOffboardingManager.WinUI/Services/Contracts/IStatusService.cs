using DeviceOffboardingManager.WinUI.Models;

namespace DeviceOffboardingManager.WinUI.Services.Contracts;

public interface IStatusService
{
    event Action<StatusReport>? StatusReported;

    void Report(string title, string message, StatusSeverity severity);
}
