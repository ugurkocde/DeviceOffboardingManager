using DeviceOffboardingManager.WinUI.Models;

namespace DeviceOffboardingManager.WinUI.Services.Contracts;

public interface IReportExportService
{
    Task<string> ExportDeviceCsvAsync(IReadOnlyCollection<DeviceRecord> devices, CancellationToken cancellationToken = default);

    Task<string> ExportOffboardingHtmlAsync(OffboardingSummary summary, CancellationToken cancellationToken = default);
}
