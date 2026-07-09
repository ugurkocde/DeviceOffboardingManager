using System.Diagnostics;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services;
using DeviceOffboardingManager.WinUI.Services.Contracts;
using DeviceOffboardingManager.WinUI.Utilities;

namespace DeviceOffboardingManager.WinUI.ViewModels;

public sealed partial class SettingsViewModel : AppViewModelBase
{
    private readonly IAuthenticationService _authenticationService;
    private readonly ISettingsService _settingsService;
    private readonly IStatusService _statusService;
    private readonly IAuditLogService _auditLogService;
    private readonly ConnectionState _connectionState;
    private readonly WindowHandleProvider _windowHandleProvider;

    public SettingsViewModel(
        IAuthenticationService authenticationService,
        ISettingsService settingsService,
        IStatusService statusService,
        IAuditLogService auditLogService,
        ConnectionState connectionState,
        WindowHandleProvider windowHandleProvider)
        : base(statusService, auditLogService)
    {
        _authenticationService = authenticationService;
        _settingsService = settingsService;
        _statusService = statusService;
        _auditLogService = auditLogService;
        _connectionState = connectionState;
        _windowHandleProvider = windowHandleProvider;

        PermissionsText = string.Join(Environment.NewLine, RequiredPermissions.Select(p => $"{p.Permission} - {p.Reason}"));
        RefreshConnectionState();
        _connectionState.Changed += RefreshConnectionState;
        _ = LoadSettingsAsync();
    }

    public string PermissionsText { get; }

    public string AuditLogPath => _auditLogService.LogFilePath;

    public bool IsDisconnected => !IsConnected;

    [ObservableProperty]
    public partial int AuthMethodIndex { get; set; }

    [ObservableProperty]
    public partial string TenantId { get; set; } = string.Empty;

    [ObservableProperty]
    public partial string ClientId { get; set; } = string.Empty;

    [ObservableProperty]
    public partial string CertificateThumbprint { get; set; } = string.Empty;

    [ObservableProperty]
    public partial string ClientSecret { get; set; } = string.Empty;

    [ObservableProperty]
    public partial string ConfigPath { get; set; } = string.Empty;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsDisconnected))]
    public partial bool IsConnected { get; set; }

    [ObservableProperty]
    public partial bool DefenderIntegrationEnabled { get; set; }

    [ObservableProperty]
    public partial string DashboardReadinessText { get; set; } = AppResources.Get(
        "DashboardReadinessDisconnected",
        "Connect to Microsoft Graph to refresh dashboard statistics. Defender remains optional and disabled until enabled in Settings.");

    public AuthenticationRequest BuildAuthenticationRequest()
    {
        return new AuthenticationRequest
        {
            Method = AuthMethodIndex switch
            {
                1 => AuthenticationMethod.DeviceCode,
                2 => AuthenticationMethod.Certificate,
                3 => AuthenticationMethod.ClientSecret,
                _ => AuthenticationMethod.Interactive
            },
            TenantId = EmptyToNull(TenantId),
            ClientId = EmptyToNull(ClientId),
            CertificateThumbprint = EmptyToNull(CertificateThumbprint),
            ClientSecret = EmptyToNull(ClientSecret),
            ParentWindowHandle = _windowHandleProvider.MainWindowHandle,
            StatusMessageCallback = message => _statusService.Report(
                AppResources.Get("DeviceCodeSignInTitle", "Device code sign-in"),
                message,
                StatusSeverity.Warning)
        };
    }

    public async Task ConnectWithCurrentSettingsAsync()
    {
        var request = BuildAuthenticationRequest();
        try
        {
            await _authenticationService.ConnectAsync(request);
            _connectionState.SetConnected(true);
            _statusService.Report(
                AppResources.Get("ConnectedTitle", "Connected"),
                _authenticationService.AccountDisplayName ?? AppResources.Get("ConnectedFallback", "Connected to Microsoft Graph."),
                StatusSeverity.Success);
        }
        finally
        {
            ClientSecret = string.Empty;
        }
    }

    [RelayCommand(CanExecute = nameof(CanConnect))]
    private async Task ConnectAsync()
    {
        await RunAsync(AppResources.Get("Connecting", "Connecting"), ConnectWithCurrentSettingsAsync);
    }

    [RelayCommand(CanExecute = nameof(CanDisconnect))]
    private async Task DisconnectAsync()
    {
        await RunAsync(AppResources.Get("Disconnecting", "Disconnecting"), async () =>
        {
            await _authenticationService.DisconnectAsync();
            _connectionState.SetConnected(false);
            _statusService.Report(
                AppResources.Get("DisconnectedTitle", "Disconnected"),
                AppResources.Get("DisconnectedMessage", "The Graph session has been cleared."),
                StatusSeverity.Informational);
        });
    }

    [RelayCommand]
    private async Task ImportConfigAsync()
    {
        await RunAsync(AppResources.Get("ImportingConfig", "Importing config"), async () =>
        {
            var settings = await _settingsService.ImportAppRegistrationConfigAsync(ConfigPath);
            ApplySettings(settings);
            _statusService.Report(
                AppResources.Get("ConfigImportedTitle", "Config imported"),
                AppResources.Get("ConfigImportedMessage", "The app registration settings were imported."),
                StatusSeverity.Success);
        });
    }

    [RelayCommand]
    private async Task SaveSettingsAsync()
    {
        await RunAsync(AppResources.Get("SavingSettings", "Saving settings"), async () =>
        {
            await _settingsService.SaveAsync(new DeviceOffboardingSettings
            {
                TenantId = EmptyToNull(TenantId),
                ClientId = EmptyToNull(ClientId),
                CertificateThumbprint = EmptyToNull(CertificateThumbprint),
                DefenderIntegrationEnabled = DefenderIntegrationEnabled
            });
            DashboardReadinessText = DefenderIntegrationEnabled
                ? AppResources.Get(
                    "DefenderEnabledReadiness",
                    "Defender for Endpoint integration is enabled. Defender tokens are requested only when Defender actions are used.")
                : AppResources.Get(
                    "DefenderDisabledReadiness",
                    "Defender for Endpoint integration is disabled. Defender controls remain gated for tenants without Defender.");
            _statusService.Report(
                AppResources.Get("SettingsSavedTitle", "Settings saved"),
                AppResources.Get("SettingsSavedMessage", "Defender visibility and app registration settings were saved."),
                StatusSeverity.Success);
        });
    }

    [RelayCommand]
    private async Task OpenAuditLogAsync()
    {
        await RunAsync(AppResources.Get("OpeningAuditLog", "Opening audit log"), async () =>
        {
            var directory = Path.GetDirectoryName(_auditLogService.LogFilePath);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            if (!File.Exists(_auditLogService.LogFilePath))
            {
                await File.WriteAllTextAsync(_auditLogService.LogFilePath, string.Empty);
            }

            Process.Start(new ProcessStartInfo(_auditLogService.LogFilePath) { UseShellExecute = true });
        });
    }

    private async Task LoadSettingsAsync()
    {
        try
        {
            var settings = await _settingsService.LoadAsync();
            ApplySettings(settings);
            _statusService.Report(
                AppResources.Get("SettingsLoadedTitle", "Settings loaded"),
                AppResources.Format("AuditLogPathFormat", "Audit log: {0}", _auditLogService.LogFilePath),
                StatusSeverity.Informational);
        }
        catch (Exception ex)
        {
            await ReportExceptionAsync(AppResources.Get("CouldNotLoadSettings", "Could not load settings"), ex);
        }
    }

    private void ApplySettings(DeviceOffboardingSettings settings)
    {
        TenantId = settings.TenantId ?? string.Empty;
        ClientId = settings.ClientId ?? string.Empty;
        CertificateThumbprint = settings.CertificateThumbprint ?? string.Empty;
        DefenderIntegrationEnabled = settings.DefenderIntegrationEnabled;
        DashboardReadinessText = settings.DefenderIntegrationEnabled
            ? AppResources.Get(
                "DefenderEnabledReadinessLoaded",
                "Defender for Endpoint integration is enabled. Defender tokens are still requested only when Defender actions are used.")
            : AppResources.Get(
                "DefenderDisabledReadinessLoaded",
                "Defender for Endpoint integration is disabled. Tenants without Defender can use Graph-only workflows.");
    }

    private void RefreshConnectionState()
    {
        IsConnected = _authenticationService.IsConnected || _connectionState.IsConnected;
    }

    partial void OnIsConnectedChanged(bool value)
    {
        OnPropertyChanged(nameof(IsDisconnected));
        ConnectCommand.NotifyCanExecuteChanged();
        DisconnectCommand.NotifyCanExecuteChanged();
    }

    private bool CanConnect()
    {
        return !IsConnected;
    }

    private bool CanDisconnect()
    {
        return IsConnected;
    }

    private static string? EmptyToNull(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    }

    private static IReadOnlyList<PermissionRequirement> RequiredPermissions { get; } =
        new[]
        {
            new PermissionRequirement("User.Read.All", AppResources.Get("PermissionUserRead", "Required to read user profile information and group memberships.")),
            new PermissionRequirement("Group.Read.All", AppResources.Get("PermissionGroupRead", "Needed to read group information and memberships.")),
            new PermissionRequirement("DeviceManagementConfiguration.Read.All", AppResources.Get("PermissionConfigurationRead", "Allows reading Intune device configuration policies and assignments.")),
            new PermissionRequirement("DeviceManagementApps.Read.All", AppResources.Get("PermissionAppsRead", "Necessary to read mobile app management policies and app configurations.")),
            new PermissionRequirement("DeviceManagementManagedDevices.ReadWrite.All", AppResources.Get("PermissionManagedDevices", "Required to read and modify managed device information.")),
            new PermissionRequirement("Device.ReadWrite.All", AppResources.Get("PermissionDeviceReadWrite", "Needed to read, disable, and delete Entra ID device objects.")),
            new PermissionRequirement("DeviceManagementServiceConfig.ReadWrite.All", AppResources.Get("PermissionServiceConfig", "Required for Autopilot configuration and management.")),
            new PermissionRequirement("BitlockerKey.Read.All", AppResources.Get("PermissionBitLocker", "Required to read BitLocker recovery key metadata during offboarding.")),
            new PermissionRequirement("DeviceLocalCredential.Read.All", AppResources.Get("PermissionLaps", "Required to read LAPS passwords during offboarding.")),
            new PermissionRequirement("WindowsDefenderATP Machine.ReadWrite.All / Machine.Offboard", AppResources.Get("PermissionDefender", "Optional Defender for Endpoint offboarding permissions."))
        };
}
