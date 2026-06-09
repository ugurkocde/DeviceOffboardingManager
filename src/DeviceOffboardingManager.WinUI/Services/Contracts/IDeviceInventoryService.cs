namespace DeviceOffboardingManager.WinUI.Services.Contracts;

public interface IDeviceInventoryService
{
    Task<IReadOnlyList<object>> SearchDevicesAsync(string query, CancellationToken cancellationToken = default);
}
