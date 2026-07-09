using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services;
using DeviceOffboardingManager.WinUI.Services.Contracts;
using DeviceOffboardingManager.WinUI.ViewModels;

namespace DeviceOffboardingManager.WinUI.Tests;

public sealed class SettingsViewModelTests
{
    [Fact]
    public async Task ClientSecretIsClearedAfterConnectionAttempt()
    {
        var authentication = new CapturingAuthenticationService();
        var viewModel = new SettingsViewModel(
            authentication,
            new FakeSettingsService(),
            new StatusService(),
            new FakeAuditLogService(),
            new ConnectionState(),
            new WindowHandleProvider())
        {
            ClientId = "client-id",
            AuthMethodIndex = 3,
            ClientSecret = "session-secret"
        };

        await viewModel.ConnectWithCurrentSettingsAsync();

        Assert.Equal("session-secret", authentication.LastRequest?.ClientSecret);
        Assert.Equal(string.Empty, viewModel.ClientSecret);
    }

    [Fact]
    public async Task ClientSecretIsClearedAfterFailedConnectionAttempt()
    {
        var authentication = new CapturingAuthenticationService { ConnectException = new InvalidOperationException("test failure") };
        var viewModel = new SettingsViewModel(
            authentication,
            new FakeSettingsService(),
            new StatusService(),
            new FakeAuditLogService(),
            new ConnectionState(),
            new WindowHandleProvider())
        {
            ClientId = "client-id",
            AuthMethodIndex = 3,
            ClientSecret = "session-secret"
        };

        await Assert.ThrowsAsync<InvalidOperationException>(viewModel.ConnectWithCurrentSettingsAsync);

        Assert.Equal(string.Empty, viewModel.ClientSecret);
    }

    private sealed class CapturingAuthenticationService : IAuthenticationService
    {
        public bool IsConnected { get; private set; }

        public string? AccountDisplayName => "test";

        public AuthenticationRequest? LastRequest { get; private set; }

        public Exception? ConnectException { get; init; }

        public Task<bool> ConnectAsync(AuthenticationRequest request, CancellationToken cancellationToken = default)
        {
            LastRequest = request;
            if (ConnectException is not null)
            {
                throw ConnectException;
            }
            IsConnected = true;
            return Task.FromResult(true);
        }

        public Task DisconnectAsync(CancellationToken cancellationToken = default)
        {
            IsConnected = false;
            return Task.CompletedTask;
        }

        public Task<string> GetGraphAccessTokenAsync(CancellationToken cancellationToken = default) => Task.FromResult("token");

        public Task<string> GetDefenderAccessTokenAsync(CancellationToken cancellationToken = default) => Task.FromResult("token");
    }

    private sealed class FakeSettingsService : ISettingsService
    {
        public Task<DeviceOffboardingSettings> LoadAsync(CancellationToken cancellationToken = default) =>
            Task.FromResult(new DeviceOffboardingSettings());

        public Task SaveAsync(DeviceOffboardingSettings settings, CancellationToken cancellationToken = default) => Task.CompletedTask;

        public Task<DeviceOffboardingSettings> ImportAppRegistrationConfigAsync(string path, CancellationToken cancellationToken = default) =>
            Task.FromResult(new DeviceOffboardingSettings());
    }

    private sealed class FakeAuditLogService : IAuditLogService
    {
        public string LogFilePath => "test.log";

        public Task WriteAsync(string message, string severity = "INFO", CancellationToken cancellationToken = default) => Task.CompletedTask;
    }
}
