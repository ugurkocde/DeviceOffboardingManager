using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services.Contracts;

namespace DeviceOffboardingManager.WinUI.Services.Placeholders;

public sealed class SettingsService : ISettingsService
{
    public Task<DeviceOffboardingSettings> LoadAsync(CancellationToken cancellationToken = default)
    {
        return Task.FromResult(new DeviceOffboardingSettings());
    }

    public Task SaveAsync(DeviceOffboardingSettings settings, CancellationToken cancellationToken = default)
    {
        return Task.CompletedTask;
    }
}
