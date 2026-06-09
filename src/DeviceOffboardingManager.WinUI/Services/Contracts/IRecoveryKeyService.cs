using DeviceOffboardingManager.WinUI.Models;

namespace DeviceOffboardingManager.WinUI.Services.Contracts;

public interface IRecoveryKeyService
{
    Task<IReadOnlyList<RecoveryKeyRecord>> GetRecoveryKeysAsync(
        IReadOnlyCollection<DeviceRecord> devices,
        CancellationToken cancellationToken = default);
}
