using System.Security.Cryptography.X509Certificates;
using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services.Contracts;
using Microsoft.Identity.Client;

namespace DeviceOffboardingManager.WinUI.Services;

public sealed class AuthenticationService : IAuthenticationService
{
    private static readonly string[] DelegatedGraphScopes =
    {
        "User.Read.All",
        "Group.Read.All",
        "DeviceManagementConfiguration.Read.All",
        "DeviceManagementApps.Read.All",
        "DeviceManagementManagedDevices.ReadWrite.All",
        "Device.ReadWrite.All",
        "DeviceManagementServiceConfig.ReadWrite.All",
        "BitlockerKey.Read.All",
        "DeviceLocalCredential.Read.All"
    };

    private static readonly string[] AppGraphScopes = { "https://graph.microsoft.com/.default" };

    private static readonly string[][] DefenderScopeSets =
    {
        new[] { "https://api.securitycenter.microsoft.com/.default" },
        new[] { "https://api.security.microsoft.com/.default" },
        new[] { "https://api.securitycenter.microsoft.com/Machine.ReadWrite", "https://api.securitycenter.microsoft.com/Machine.Offboard" }
    };

    private readonly IAuditLogService _auditLog;
    private AuthenticationRequest? _currentRequest;
    private IPublicClientApplication? _publicClient;
    private IConfidentialClientApplication? _confidentialClient;
    private IAccount? _account;

    public AuthenticationService(IAuditLogService auditLog)
    {
        _auditLog = auditLog;
    }

    public bool IsConnected => _currentRequest is not null;

    public string? AccountDisplayName { get; private set; }

    public async Task<bool> ConnectAsync(AuthenticationRequest request, CancellationToken cancellationToken = default)
    {
        ValidateRequest(request);
        _currentRequest = request;
        _publicClient = null;
        _confidentialClient = null;
        _account = null;

        _ = await GetGraphAccessTokenAsync(cancellationToken);
        AccountDisplayName = request.Method is AuthenticationMethod.Certificate or AuthenticationMethod.ClientSecret
            ? $"AppId:{request.ClientId}"
            : _account?.Username ?? "Delegated session";

        await _auditLog.WriteAsync($"Connected with {request.Method} authentication as {AccountDisplayName}.", "AUDIT", cancellationToken);
        return true;
    }

    public Task DisconnectAsync(CancellationToken cancellationToken = default)
    {
        _currentRequest = null;
        _publicClient = null;
        _confidentialClient = null;
        _account = null;
        AccountDisplayName = null;
        return Task.CompletedTask;
    }

    public Task<string> GetGraphAccessTokenAsync(CancellationToken cancellationToken = default)
    {
        if (_currentRequest is null)
        {
            throw new InvalidOperationException("Connect before requesting a Graph token.");
        }

        return _currentRequest.Method is AuthenticationMethod.Certificate or AuthenticationMethod.ClientSecret
            ? AcquireConfidentialTokenAsync(AppGraphScopes, cancellationToken)
            : AcquireDelegatedTokenAsync(DelegatedGraphScopes, cancellationToken);
    }

    public async Task<string> GetDefenderAccessTokenAsync(CancellationToken cancellationToken = default)
    {
        if (_currentRequest is null)
        {
            throw new InvalidOperationException("Connect before requesting a Defender token.");
        }

        Exception? lastError = null;
        foreach (var scopes in DefenderScopeSets)
        {
            try
            {
                return _currentRequest.Method is AuthenticationMethod.Certificate or AuthenticationMethod.ClientSecret
                    ? await AcquireConfidentialTokenAsync(scopes, cancellationToken)
                    : await AcquireDelegatedTokenAsync(scopes, cancellationToken);
            }
            catch (Exception ex)
            {
                lastError = ex;
                await _auditLog.WriteAsync($"Defender token acquisition failed for {string.Join(", ", scopes)}: {ex.Message}", "WARN", cancellationToken);
            }
        }

        throw new InvalidOperationException(
            "Could not acquire Defender token. Consent WindowsDefenderATP Machine.ReadWrite.All and Machine.Offboard for app-only auth, or delegated Machine.ReadWrite and Machine.Offboard.",
            lastError);
    }

    private async Task<string> AcquireDelegatedTokenAsync(string[] scopes, CancellationToken cancellationToken)
    {
        var request = _currentRequest ?? throw new InvalidOperationException("No auth request is active.");
        _publicClient ??= PublicClientApplicationBuilder
            .Create(request.ClientId)
            .WithTenantId(NormalizeTenant(request.TenantId))
            .WithRedirectUri("http://localhost")
            .Build();

        try
        {
            var accounts = await _publicClient.GetAccountsAsync();
            _account ??= accounts.FirstOrDefault();
            if (_account is not null)
            {
                var silent = await _publicClient.AcquireTokenSilent(scopes, _account).ExecuteAsync(cancellationToken);
                _account = silent.Account;
                return silent.AccessToken;
            }
        }
        catch (MsalUiRequiredException)
        {
            // Fall through to the requested interactive mode.
        }

        AuthenticationResult result;
        if (request.Method == AuthenticationMethod.DeviceCode)
        {
            result = await _publicClient
                .AcquireTokenWithDeviceCode(scopes, code =>
                {
                    AccountDisplayName = code.Message;
                    return Task.CompletedTask;
                })
                .ExecuteAsync(cancellationToken);
        }
        else
        {
            result = await _publicClient.AcquireTokenInteractive(scopes).ExecuteAsync(cancellationToken);
        }

        _account = result.Account;
        return result.AccessToken;
    }

    private async Task<string> AcquireConfidentialTokenAsync(string[] scopes, CancellationToken cancellationToken)
    {
        _confidentialClient ??= BuildConfidentialClient();
        var result = await _confidentialClient.AcquireTokenForClient(scopes).ExecuteAsync(cancellationToken);
        return result.AccessToken;
    }

    private IConfidentialClientApplication BuildConfidentialClient()
    {
        var request = _currentRequest ?? throw new InvalidOperationException("No auth request is active.");
        var builder = ConfidentialClientApplicationBuilder
            .Create(request.ClientId)
            .WithTenantId(NormalizeTenant(request.TenantId));

        return request.Method switch
        {
            AuthenticationMethod.ClientSecret => builder.WithClientSecret(request.ClientSecret).Build(),
            AuthenticationMethod.Certificate => builder.WithCertificate(FindCertificate(request.CertificateThumbprint)).Build(),
            _ => throw new InvalidOperationException("Confidential client requires certificate or client secret authentication.")
        };
    }

    private static X509Certificate2 FindCertificate(string? thumbprint)
    {
        if (string.IsNullOrWhiteSpace(thumbprint))
        {
            throw new InvalidOperationException("Certificate thumbprint is required.");
        }

        var normalized = thumbprint.Replace(" ", string.Empty, StringComparison.OrdinalIgnoreCase);
        foreach (var location in new[] { StoreLocation.CurrentUser, StoreLocation.LocalMachine })
        {
            using var store = new X509Store(StoreName.My, location);
            store.Open(OpenFlags.ReadOnly);
            var matches = store.Certificates.Find(X509FindType.FindByThumbprint, normalized, validOnly: false);
            if (matches.Count > 0)
            {
                return matches[0];
            }
        }

        throw new InvalidOperationException($"Certificate with thumbprint {normalized} was not found.");
    }

    private static string NormalizeTenant(string? tenantId)
    {
        return string.IsNullOrWhiteSpace(tenantId) ? "organizations" : tenantId.Trim();
    }

    private static void ValidateRequest(AuthenticationRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.ClientId))
        {
            throw new InvalidOperationException("Client ID is required.");
        }

        if (request.Method == AuthenticationMethod.Certificate && string.IsNullOrWhiteSpace(request.CertificateThumbprint))
        {
            throw new InvalidOperationException("Certificate thumbprint is required.");
        }

        if (request.Method == AuthenticationMethod.ClientSecret && string.IsNullOrWhiteSpace(request.ClientSecret))
        {
            throw new InvalidOperationException("Client secret is required for this session.");
        }
    }
}
