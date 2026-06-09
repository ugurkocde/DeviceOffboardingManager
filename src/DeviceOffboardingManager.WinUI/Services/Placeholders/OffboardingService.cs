using DeviceOffboardingManager.WinUI.Services.Contracts;

namespace DeviceOffboardingManager.WinUI.Services.Placeholders;

public sealed class OffboardingService : IOffboardingService
{
    public Task<object> OffboardAsync(IReadOnlyCollection<object> devices, CancellationToken cancellationToken = default)
    {
        return Task.FromResult<object>(new { Success = false, Message = "WinUI offboarding service is not implemented yet." });
    }
}
