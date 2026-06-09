namespace DeviceOffboardingManager.WinUI.Services.Contracts;

public interface IOffboardingService
{
    Task<object> OffboardAsync(IReadOnlyCollection<object> devices, CancellationToken cancellationToken = default);
}
