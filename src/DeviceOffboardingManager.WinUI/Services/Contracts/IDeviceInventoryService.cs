using DeviceOffboardingManager.WinUI.Models;

namespace DeviceOffboardingManager.WinUI.Services.Contracts;

public interface IDeviceInventoryService
{
    Task<DeviceSearchResult> SearchDevicesAsync(
        IReadOnlyCollection<string> searchTerms,
        DeviceSearchOption searchOption,
        CancellationToken cancellationToken = default);

    Task<DashboardSummary> GetDashboardSummaryAsync(CancellationToken cancellationToken = default);

    Task<GroupTagUpdateResult> SetAutopilotGroupTagAsync(
        IReadOnlyCollection<DeviceRecord> devices,
        string groupTag,
        CancellationToken cancellationToken = default);
}
