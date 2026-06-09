using DeviceOffboardingManager.WinUI.Services.Contracts;

namespace DeviceOffboardingManager.WinUI.Services.Placeholders;

public sealed class DeviceInventoryService : IDeviceInventoryService
{
    public Task<IReadOnlyList<object>> SearchDevicesAsync(string query, CancellationToken cancellationToken = default)
    {
        return Task.FromResult<IReadOnlyList<object>>(Array.Empty<object>());
    }
}
