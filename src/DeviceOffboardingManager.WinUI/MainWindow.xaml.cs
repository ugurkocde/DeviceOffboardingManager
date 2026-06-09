using System.Collections.ObjectModel;
using System.Text;
using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services.Contracts;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace DeviceOffboardingManager.WinUI;

public sealed partial class MainWindow : Window
{
    private readonly IAuthenticationService _authenticationService;
    private readonly ISettingsService _settingsService;
    private readonly IDeviceInventoryService _deviceInventoryService;
    private readonly IOffboardingService _offboardingService;
    private readonly IRecoveryKeyService _recoveryKeyService;
    private readonly IPlaybookService _playbookService;
    private readonly IReportExportService _reportExportService;
    private readonly IAuditLogService _auditLogService;
    private readonly ObservableCollection<DeviceRecord> _devices = new();
    private OffboardingSummary? _lastOffboardingSummary;

    public MainWindow()
    {
        _authenticationService = App.Services.GetRequiredService<IAuthenticationService>();
        _settingsService = App.Services.GetRequiredService<ISettingsService>();
        _deviceInventoryService = App.Services.GetRequiredService<IDeviceInventoryService>();
        _offboardingService = App.Services.GetRequiredService<IOffboardingService>();
        _recoveryKeyService = App.Services.GetRequiredService<IRecoveryKeyService>();
        _playbookService = App.Services.GetRequiredService<IPlaybookService>();
        _reportExportService = App.Services.GetRequiredService<IReportExportService>();
        _auditLogService = App.Services.GetRequiredService<IAuditLogService>();

        InitializeComponent();
        DeviceListView.ItemsSource = _devices;
        foreach (var playbook in _playbookService.Definitions)
        {
            PlaybookBox.Items.Add(playbook.Name);
        }

        PlaybookBox.SelectedIndex = 0;
        PermissionsText.Text = string.Join(Environment.NewLine, RequiredPermissions.Select(p => $"{p.Permission} - {p.Reason}"));
        _ = LoadSettingsAsync();
    }

    private static IReadOnlyList<PermissionRequirement> RequiredPermissions { get; } =
    new[]
    {
        new PermissionRequirement("User.Read.All", "Required to read user profile information and group memberships."),
        new PermissionRequirement("Group.Read.All", "Needed to read group information and memberships."),
        new PermissionRequirement("DeviceManagementConfiguration.Read.All", "Allows reading Intune device configuration policies and assignments."),
        new PermissionRequirement("DeviceManagementApps.Read.All", "Necessary to read mobile app management policies and app configurations."),
        new PermissionRequirement("DeviceManagementManagedDevices.ReadWrite.All", "Required to read and modify managed device information."),
        new PermissionRequirement("Device.ReadWrite.All", "Needed to read, disable, and delete Entra ID device objects."),
        new PermissionRequirement("DeviceManagementServiceConfig.ReadWrite.All", "Required for Autopilot configuration and management."),
        new PermissionRequirement("BitlockerKey.Read.All", "Required to read BitLocker recovery key metadata during offboarding."),
        new PermissionRequirement("DeviceLocalCredential.Read.All", "Required to read LAPS passwords during offboarding."),
        new PermissionRequirement("WindowsDefenderATP Machine.ReadWrite.All / Machine.Offboard", "Optional Defender for Endpoint offboarding permissions.")
    };

    private async Task LoadSettingsAsync()
    {
        try
        {
            var settings = await _settingsService.LoadAsync();
            TenantIdBox.Text = settings.TenantId ?? string.Empty;
            ClientIdBox.Text = settings.ClientId ?? string.Empty;
            CertificateThumbprintBox.Text = settings.CertificateThumbprint ?? string.Empty;
            DefenderToggle.IsOn = settings.DefenderIntegrationEnabled;
            OffboardDefenderBox.IsEnabled = settings.DefenderIntegrationEnabled;
            SetStatus("Settings loaded", $"Audit log: {_auditLogService.LogFilePath}", InfoBarSeverity.Informational);
        }
        catch (Exception ex)
        {
            SetStatus("Could not load settings", ex.Message, InfoBarSeverity.Error);
        }
    }

    private async void Connect_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("Connecting", async () =>
        {
            var request = BuildAuthenticationRequest();
            await _authenticationService.ConnectAsync(request);
            ConnectButton.IsEnabled = false;
            DisconnectButton.IsEnabled = true;
            SetStatus("Connected", _authenticationService.AccountDisplayName ?? "Connected to Microsoft Graph.", InfoBarSeverity.Success);
        });
    }

    private async void Disconnect_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("Disconnecting", async () =>
        {
            await _authenticationService.DisconnectAsync();
            ConnectButton.IsEnabled = true;
            DisconnectButton.IsEnabled = false;
            SetStatus("Disconnected", "The Graph session has been cleared.", InfoBarSeverity.Informational);
        });
    }

    private async void ImportConfig_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("Importing config", async () =>
        {
            var settings = await _settingsService.ImportAppRegistrationConfigAsync(ConfigPathBox.Text);
            TenantIdBox.Text = settings.TenantId ?? string.Empty;
            ClientIdBox.Text = settings.ClientId ?? string.Empty;
            CertificateThumbprintBox.Text = settings.CertificateThumbprint ?? string.Empty;
            DefenderToggle.IsOn = settings.DefenderIntegrationEnabled;
            SetStatus("Config imported", "The app registration settings were imported.", InfoBarSeverity.Success);
        });
    }

    private async void SaveSettings_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("Saving settings", async () =>
        {
            await _settingsService.SaveAsync(new DeviceOffboardingSettings
            {
                TenantId = EmptyToNull(TenantIdBox.Text),
                ClientId = EmptyToNull(ClientIdBox.Text),
                CertificateThumbprint = EmptyToNull(CertificateThumbprintBox.Text),
                DefenderIntegrationEnabled = DefenderToggle.IsOn
            });
            OffboardDefenderBox.IsEnabled = DefenderToggle.IsOn;
            SetStatus("Settings saved", "Defender visibility and app registration settings were saved.", InfoBarSeverity.Success);
        });
    }

    private async void RefreshDashboard_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("Refreshing dashboard", async () =>
        {
            EnsureConnected();
            var dashboard = await _deviceInventoryService.GetDashboardSummaryAsync();
            IntuneCountText.Text = dashboard.IntuneDevices.ToString("n0");
            AutopilotCountText.Text = dashboard.AutopilotDevices.ToString("n0");
            EntraCountText.Text = dashboard.EntraDevices.ToString("n0");
            Stale90Text.Text = dashboard.StaleDevices90Days.ToString("n0");
            SetStatus("Dashboard refreshed", $"30d stale: {dashboard.StaleDevices30Days:n0}; 180d stale: {dashboard.StaleDevices180Days:n0}.", InfoBarSeverity.Success);
        });
    }

    private async void Search_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("Searching devices", async () =>
        {
            EnsureConnected();
            var terms = ParseSearchTerms(SearchTextBox.Text);
            if (terms.Count == 0)
            {
                throw new InvalidOperationException("Enter at least one search term.");
            }

            var result = await _deviceInventoryService.SearchDevicesAsync(terms, GetSearchOption());
            _devices.Clear();
            foreach (var device in result.Devices)
            {
                _devices.Add(device);
            }

            SearchStatusText.Text = $"{result.Devices.Count:n0} device(s) found. Intune: {result.IntuneCount:n0}; Autopilot: {result.AutopilotCount:n0}; Entra ID: {result.EntraCount:n0}.";
            SetStatus("Search complete", SearchStatusText.Text, InfoBarSeverity.Success);
        });
    }

    private async void ImportBulkPath_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("Importing search terms", async () =>
        {
            var path = SearchTextBox.Text.Trim();
            if (!File.Exists(path))
            {
                throw new FileNotFoundException("Bulk import file was not found. Paste the CSV/TXT path into Search terms first.", path);
            }

            var lines = await File.ReadAllLinesAsync(path);
            SearchTextBox.Text = string.Join(Environment.NewLine, lines.SelectMany(ParseSearchTerms));
            SetStatus("Bulk terms imported", $"Imported search terms from {path}.", InfoBarSeverity.Success);
        });
    }

    private async void ExportCsv_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("Exporting CSV", async () =>
        {
            var devices = GetSelectedOrAllDevices();
            if (devices.Count == 0)
            {
                throw new InvalidOperationException("No devices are available to export.");
            }

            var path = await _reportExportService.ExportDeviceCsvAsync(devices);
            SetStatus("CSV exported", path, InfoBarSeverity.Success);
        });
    }

    private async void SetGroupTag_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("Setting group tag", async () =>
        {
            EnsureConnected();
            var selected = GetSelectedDevices();
            if (selected.Count == 0)
            {
                throw new InvalidOperationException("Select at least one device.");
            }

            var result = await _deviceInventoryService.SetAutopilotGroupTagAsync(selected, GroupTagBox.Text);
            SetStatus("Group tag update complete", $"Updated: {result.Updated:n0}; Failed: {result.Failed:n0}.", result.Failed == 0 ? InfoBarSeverity.Success : InfoBarSeverity.Warning);
        });
    }

    private async void RunOffboarding_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("Running offboarding", async () =>
        {
            EnsureConnected();
            var selected = GetSelectedDevices();
            if (selected.Count == 0)
            {
                throw new InvalidOperationException("Select at least one device.");
            }

            var dialog = new ContentDialog
            {
                Title = "Confirm offboarding",
                Content = $"Run selected actions for {selected.Count} device(s)? Review Graph IDs in the device list before continuing.",
                PrimaryButtonText = "Run",
                CloseButtonText = "Cancel",
                DefaultButton = ContentDialogButton.Close,
                XamlRoot = this.Content.XamlRoot
            };

            if (await dialog.ShowAsync() != ContentDialogResult.Primary)
            {
                return;
            }

            _lastOffboardingSummary = await _offboardingService.OffboardAsync(selected, BuildOffboardingOptions());
            OffboardingStatusText.Text = $"Offboarding complete. Devices: {_lastOffboardingSummary.TotalDevices:n0}; successful: {_lastOffboardingSummary.SuccessfulDevices:n0}; failed/partial: {_lastOffboardingSummary.FailedDevices:n0}.";
            SetStatus("Offboarding complete", OffboardingStatusText.Text, _lastOffboardingSummary.FailedDevices == 0 ? InfoBarSeverity.Success : InfoBarSeverity.Warning);
        });
    }

    private async void FetchRecoveryKeys_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("Fetching recovery keys", async () =>
        {
            EnsureConnected();
            var selected = GetSelectedDevices();
            if (selected.Count == 0)
            {
                throw new InvalidOperationException("Select at least one device.");
            }

            var keys = await _recoveryKeyService.GetRecoveryKeysAsync(selected);
            var found = keys.Count(key => !string.IsNullOrWhiteSpace(key.KeyValue));
            OffboardingStatusText.Text = $"Recovery key lookup complete. Records: {keys.Count:n0}; values found: {found:n0}. Sensitive values were written to the audit log: {_auditLogService.LogFilePath}";
            SetStatus("Recovery key lookup complete", OffboardingStatusText.Text, found > 0 ? InfoBarSeverity.Warning : InfoBarSeverity.Informational);
        });
    }

    private async void ExportReport_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("Exporting report", async () =>
        {
            if (_lastOffboardingSummary is null)
            {
                throw new InvalidOperationException("Run an offboarding operation before exporting the HTML report.");
            }

            var path = await _reportExportService.ExportOffboardingHtmlAsync(_lastOffboardingSummary);
            SetStatus("Report exported", path, InfoBarSeverity.Success);
        });
    }

    private async void RunPlaybook_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("Running playbook", async () =>
        {
            EnsureConnected();
            var selectedIndex = PlaybookBox.SelectedIndex < 0 ? 0 : PlaybookBox.SelectedIndex;
            var definition = _playbookService.Definitions[selectedIndex];
            var result = await _playbookService.RunAsync(definition.Id, PlaybookParameterBox.Text);
            var path = await ExportPlaybookRowsAsync(result);
            PlaybookStatusText.Text = $"{result.Definition.Name} completed with {result.Rows.Count:n0} row(s). CSV exported to {path}";
            SetStatus("Playbook complete", PlaybookStatusText.Text, InfoBarSeverity.Success);
        });
    }

    private AuthenticationRequest BuildAuthenticationRequest()
    {
        return new AuthenticationRequest
        {
            Method = AuthMethodBox.SelectedIndex switch
            {
                1 => AuthenticationMethod.DeviceCode,
                2 => AuthenticationMethod.Certificate,
                3 => AuthenticationMethod.ClientSecret,
                _ => AuthenticationMethod.Interactive
            },
            TenantId = EmptyToNull(TenantIdBox.Text),
            ClientId = EmptyToNull(ClientIdBox.Text),
            CertificateThumbprint = EmptyToNull(CertificateThumbprintBox.Text),
            ClientSecret = EmptyToNull(ClientSecretBox.Password)
        };
    }

    private OffboardingOptions BuildOffboardingOptions()
    {
        var disableEntra = DisableEntraBox.IsChecked == true;
        return new OffboardingOptions
        {
            DisableEntra = disableEntra,
            DeleteEntra = !disableEntra && DeleteEntraBox.IsChecked == true,
            DeleteIntune = DeleteIntuneBox.IsChecked == true,
            DeleteAutopilot = DeleteAutopilotBox.IsChecked == true,
            OffboardDefender = DefenderToggle.IsOn && OffboardDefenderBox.IsChecked == true,
            PreAction = PreActionBox.SelectedIndex switch
            {
                1 => DevicePreAction.Retire,
                2 => DevicePreAction.Wipe,
                _ => DevicePreAction.None
            }
        };
    }

    private DeviceSearchOption GetSearchOption()
    {
        return SearchModeBox.SelectedIndex switch
        {
            1 => DeviceSearchOption.SerialNumber,
            2 => DeviceSearchOption.DeviceId,
            3 => DeviceSearchOption.Contains,
            _ => DeviceSearchOption.DeviceName
        };
    }

    private IReadOnlyList<DeviceRecord> GetSelectedDevices()
    {
        return _devices.Where(device => device.IsSelected).ToArray();
    }

    private IReadOnlyList<DeviceRecord> GetSelectedOrAllDevices()
    {
        var selected = GetSelectedDevices();
        return selected.Count > 0 ? selected : _devices.ToArray();
    }

    private void EnsureConnected()
    {
        if (!_authenticationService.IsConnected)
        {
            throw new InvalidOperationException("Connect to Microsoft Graph first.");
        }
    }

    private async Task RunUiActionAsync(string title, Func<Task> action)
    {
        try
        {
            SetStatus(title, "Working...", InfoBarSeverity.Informational);
            await action();
        }
        catch (Exception ex)
        {
            SetStatus(title, ex.Message, InfoBarSeverity.Error);
            await _auditLogService.WriteAsync($"{title} failed: {ex}", "ERROR");
        }
    }

    private void SetStatus(string title, string message, InfoBarSeverity severity)
    {
        StatusInfoBar.Title = title;
        StatusInfoBar.Message = message;
        StatusInfoBar.Severity = severity;
        StatusInfoBar.IsOpen = true;
    }

    private static IReadOnlyList<string> ParseSearchTerms(string? text)
    {
        return (text ?? string.Empty)
            .Split(new[] { ',', '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(term => !string.IsNullOrWhiteSpace(term))
            .ToArray();
    }

    private static string? EmptyToNull(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    }

    private static async Task<string> ExportPlaybookRowsAsync(PlaybookRunResult result)
    {
        var path = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
            $"DOM_Playbook_{result.Definition.Id}_{DateTime.Now:yyyyMMdd_HHmmss}.csv");

        var columns = result.Rows.SelectMany(row => row.Keys).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        var builder = new StringBuilder();
        builder.AppendLine(string.Join(",", columns.Select(Csv)));
        foreach (var row in result.Rows)
        {
            builder.AppendLine(string.Join(",", columns.Select(column => Csv(row.TryGetValue(column, out var value) ? value : null))));
        }

        await File.WriteAllTextAsync(path, builder.ToString());
        return path;
    }

    private static string Csv(string? value)
    {
        return '"' + (value ?? string.Empty).Replace("\"", "\"\"", StringComparison.Ordinal) + '"';
    }
}
