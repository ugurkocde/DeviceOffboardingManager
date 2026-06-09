namespace DeviceOffboardingManager.WinUI.Services.Contracts;

public interface IAuthenticationService
{
    Task<bool> ConnectAsync(CancellationToken cancellationToken = default);

    Task DisconnectAsync(CancellationToken cancellationToken = default);
}
