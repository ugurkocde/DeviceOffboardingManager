using DeviceOffboardingManager.WinUI.Models;

namespace DeviceOffboardingManager.WinUI.Services.Contracts;

public interface IAuthenticationService
{
    bool IsConnected { get; }

    string? AccountDisplayName { get; }

    Task<bool> ConnectAsync(AuthenticationRequest request, CancellationToken cancellationToken = default);

    Task DisconnectAsync(CancellationToken cancellationToken = default);

    Task<string> GetGraphAccessTokenAsync(CancellationToken cancellationToken = default);

    Task<string> GetDefenderAccessTokenAsync(CancellationToken cancellationToken = default);
}
