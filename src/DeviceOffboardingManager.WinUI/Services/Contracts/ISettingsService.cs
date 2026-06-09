using DeviceOffboardingManager.WinUI.Models;

namespace DeviceOffboardingManager.WinUI.Services.Contracts;

public interface ISettingsService
{
    Task<DeviceOffboardingSettings> LoadAsync(CancellationToken cancellationToken = default);

    Task SaveAsync(DeviceOffboardingSettings settings, CancellationToken cancellationToken = default);

    Task<DeviceOffboardingSettings> ImportAppRegistrationConfigAsync(string path, CancellationToken cancellationToken = default);
}
