using System.Collections.ObjectModel;
using System.Diagnostics;
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
    private readonly List<DeviceRecord> _allDevices = new();
    private readonly ObservableCollection<DeviceRecord> _visibleDevices = new();
    private readonly ObservableCollection<string> _playbookRows = new();
    private OffboardingSummary? _lastOffboardingSummary;
    private PlaybookRunResult? _lastPlaybookResult;

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
        DeviceListView.ItemsSource = _visibleDevices;
        PlaybookResultListView.ItemsSource = _playbookRows;

        foreach (var playbook in _playbookService.Definitions)
        {
            PlaybookBox.Items.Add(playbook.Name);
        }

        PlaybookBox.SelectedIndex = 0;
        PermissionsText.Text = string.Join(Environment.NewLine, RequiredPermissions.Select(p => $"{p.Permission} - {p.Reason}"));
        RootNavigation.SelectedItem = NavHome;
        ShowPage("home");
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
            DashboardReadinessText.Text = settings.DefenderIntegrationEnabled
                ? "Defender for Endpoint integration is enabled. Defender tokens are still requested only when Defender actions are used."
                : "Defender for Endpoint integration is disabled. Tenants without Defender can use Graph-only workflows.";
            SetStatus("Settings loaded", $"Audit log: {_auditLogService.LogFilePath}", InfoBarSeverity.Informational);
        }
        catch (Exception ex)
        {
            SetStatus("Could not load settings", ex.Message, InfoBarSeverity.Error);
        }
    }

    private void RootNavigation_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.IsSettingsSelected)
        {
            ShowPage("settings");
            return;
        }

        if (args.SelectedItemContainer?.Tag is string tag)
        {
            ShowPage(tag);
        }
    }

    private void NavigateButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string tag })
        {
            return;
        }

        RootNavigation.SelectedItem = tag switch
        {
            "home" => NavHome,
            "dashboard" => NavDashboard,
            "devices" => NavDevices,
            "offboarding" => NavOffboarding,
            "playbooks" => NavPlaybooks,
            "about" => NavAbout,
            _ => RootNavigation.SelectedItem
        };
        ShowPage(tag);
    }

    private void ShowPage(string page)
    {
        HomePage.Visibility = page == "home" ? Visibility.Visible : Visibility.Collapsed;
        DashboardPage.Visibility = page == "dashboard" ? Visibility.Visible : Visibility.Collapsed;
        DevicesPage.Visibility = page == "devices" ? Visibility.Visible : Visibility.Collapsed;
        OffboardingPage.Visibility = page == "offboarding" ? Visibility.Visible : Visibility.Collapsed;
        PlaybooksPage.Visibility = page == "playbooks" ? Visibility.Visible : Visibility.Collapsed;
        SettingsPage.Visibility = page == "settings" ? Visibility.Visible : Visibility.Collapsed;
        AboutPage.Visibility = page == "about" ? Visibility.Visible : Visibility.Collapsed;

        if (page == "offboarding")
        {
            RefreshSelectedSummary();
        }
    }

    private async void Connect_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("Connecting", async () =>
        {
            var request = BuildAuthenticationRequest();
            await _authenticationService.ConnectAsync(request);
            HomeConnectButton.IsEnabled = false;
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
            HomeConnectButton.IsEnabled = true;
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
            OffboardDefenderBox.IsEnabled = settings.DefenderIntegrationEnabled;
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
            DashboardReadinessText.Text = DefenderToggle.IsOn
                ? "Defender for Endpoint integration is enabled. Defender tokens are requested only when Defender actions are used."
                : "Defender for Endpoint integration is disabled. Defender controls remain gated for tenants without Defender.";
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
            Stale30Text.Text = dashboard.StaleDevices30Days.ToString("n0");
            Stale90Text.Text = dashboard.StaleDevices90Days.ToString("n0");
            Stale180Text.Text = dashboard.StaleDevices180Days.ToString("n0");
            CorporateCountText.Text = dashboard.CorporateDevices.ToString("n0");
            PersonalCountText.Text = dashboard.PersonalDevices.ToString("n0");
            SetStatus("Dashboard refreshed", $"Platform filter: {GetDashboardPlatformFilter() ?? "all"}.", InfoBarSeverity.Success);
        });
    }

    private async void DashboardCard_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string tag })
        {
            return;
        }

        await RunUiActionAsync("Loading dashboard results", async () =>
        {
            EnsureConnected();
            var devices = await _deviceInventoryService.GetDashboardDevicesAsync(GetDashboardCategory(tag), GetDashboardPlatformFilter());
            ReplaceDeviceList(devices);
            RootNavigation.SelectedItem = NavDevices;
            ShowPage("devices");
            SetStatus("Dashboard results loaded", $"{devices.Count:n0} device(s) loaded into Devices.", InfoBarSeverity.Success);
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
            ReplaceDeviceList(result.Devices);
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

    private void ClearSearch_Click(object sender, RoutedEventArgs e)
    {
        SearchTextBox.Text = string.Empty;
        _allDevices.Clear();
        _visibleDevices.Clear();
        SearchStatusText.Text = "No devices searched yet.";
        RefreshSelectedSummary();
        SetStatus("Device list cleared", "Search terms and results were cleared.", InfoBarSeverity.Informational);
    }

    private void DeviceFilter_TextChanged(object sender, TextChangedEventArgs e)
    {
        ApplyDeviceFilters();
    }

    private void ResetFilters_Click(object sender, RoutedEventArgs e)
    {
        FilterDeviceNameBox.Text = string.Empty;
        FilterSerialBox.Text = string.Empty;
        FilterOsBox.Text = string.Empty;
        FilterUserBox.Text = string.Empty;
        FilterComplianceBox.Text = string.Empty;
        ApplyDeviceFilters();
    }

    private void SelectAllDevices_Click(object sender, RoutedEventArgs e)
    {
        var isSelected = SelectAllDevicesBox.IsChecked == true;
        foreach (var device in _visibleDevices)
        {
            device.IsSelected = isSelected;
        }

        RefreshSelectedSummary();
    }

    private void DeviceSelectionChanged_Click(object sender, RoutedEventArgs e)
    {
        RefreshSelectedSummary();
    }

    private async void ExportCsv_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("Exporting CSV", async () =>
        {
            var devices = GetSelectedOrVisibleDevices();
            if (devices.Count == 0)
            {
                throw new InvalidOperationException("No devices are available to export.");
            }

            var path = await _reportExportService.ExportDeviceCsvAsync(devices);
            SetStatus("CSV exported", path, InfoBarSeverity.Success);
        });
    }

    private async void ReviewSelectedIds_Click(object sender, RoutedEventArgs e)
    {
        var selected = GetSelectedDevices();
        if (selected.Count == 0)
        {
            SetStatus("No devices selected", "Select at least one device before reviewing IDs.", InfoBarSeverity.Warning);
            return;
        }

        var content = new TextBlock
        {
            Text = string.Join(
                Environment.NewLine + Environment.NewLine,
                selected.Select(device =>
                    $"{device.DeviceName ?? "(unnamed)"}{Environment.NewLine}Serial: {device.SerialNumber ?? "(none)"}{Environment.NewLine}Entra object: {device.EntraDeviceId ?? "(none)"}{Environment.NewLine}Entra deviceId: {device.EntraDeviceObjectId ?? "(none)"}{Environment.NewLine}Intune: {device.IntuneDeviceId ?? "(none)"}{Environment.NewLine}Autopilot: {device.AutopilotIdentityId ?? "(none)"}")),
            TextWrapping = TextWrapping.Wrap
        };

        var dialog = new ContentDialog
        {
            Title = "Resolved device IDs",
            Content = new ScrollViewer { Content = content, MaxHeight = 520 },
            CloseButtonText = "Close",
            XamlRoot = this.Content.XamlRoot
        };
        await dialog.ShowAsync();
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
                Content = $"Run selected actions for {selected.Count:n0} device(s)? Review Graph IDs before continuing. Offboarding operations may be permanent.",
                PrimaryButtonText = "Run",
                CloseButtonText = "Cancel",
                DefaultButton = ContentDialogButton.Close,
                XamlRoot = this.Content.XamlRoot
            };

            if (await dialog.ShowAsync() != ContentDialogResult.Primary)
            {
                SetStatus("Offboarding canceled", "No changes were made.", InfoBarSeverity.Informational);
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
            _lastPlaybookResult = await _playbookService.RunAsync(definition.Id, PlaybookParameterBox.Text);
            PopulatePlaybookRows(_lastPlaybookResult);
            PlaybookStatusText.Text = $"{_lastPlaybookResult.Definition.Name} completed with {_lastPlaybookResult.Rows.Count:n0} row(s).";
            SetStatus("Playbook complete", PlaybookStatusText.Text, InfoBarSeverity.Success);
        });
    }

    private async void ExportLastPlaybook_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("Exporting playbook", async () =>
        {
            if (_lastPlaybookResult is null)
            {
                throw new InvalidOperationException("Run a playbook before exporting.");
            }

            var path = await ExportPlaybookRowsAsync(_lastPlaybookResult);
            SetStatus("Playbook exported", path, InfoBarSeverity.Success);
        });
    }

    private void OpenAuditLog_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var directory = Path.GetDirectoryName(_auditLogService.LogFilePath);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            if (!File.Exists(_auditLogService.LogFilePath))
            {
                File.WriteAllText(_auditLogService.LogFilePath, string.Empty);
            }

            Process.Start(new ProcessStartInfo(_auditLogService.LogFilePath) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            SetStatus("Could not open audit log", ex.Message, InfoBarSeverity.Error);
        }
    }

    private void ReplaceDeviceList(IReadOnlyList<DeviceRecord> devices)
    {
        _allDevices.Clear();
        _allDevices.AddRange(devices);
        ApplyDeviceFilters();
        RefreshSelectedSummary();
    }

    private void ApplyDeviceFilters()
    {
        var name = FilterDeviceNameBox.Text;
        var serial = FilterSerialBox.Text;
        var os = FilterOsBox.Text;
        var user = FilterUserBox.Text;
        var compliance = FilterComplianceBox.Text;

        var filtered = _allDevices.Where(device =>
            Contains(device.DeviceName, name)
            && Contains(device.SerialNumber, serial)
            && Contains(device.OperatingSystem, os)
            && Contains(device.PrimaryUser, user)
            && Contains(device.ComplianceState, compliance)).ToArray();

        _visibleDevices.Clear();
        foreach (var device in filtered)
        {
            _visibleDevices.Add(device);
        }

        SearchStatusText.Text = $"{_visibleDevices.Count:n0} visible of {_allDevices.Count:n0} loaded device(s).";
        RefreshSelectedSummary();
    }

    private void RefreshSelectedSummary()
    {
        var selected = GetSelectedDevices();
        SelectedDeviceCountText.Text = selected.Count == 0
            ? "No devices selected."
            : $"{selected.Count:n0} selected device(s). Visible: {_visibleDevices.Count:n0}; loaded: {_allDevices.Count:n0}.";

        OffboardingStatusText.Text = selected.Count == 0
            ? "Select devices before running actions."
            : $"{selected.Count:n0} selected device(s) ready for offboarding review.";
    }

    private void PopulatePlaybookRows(PlaybookRunResult result)
    {
        _playbookRows.Clear();
        if (result.Rows.Count == 0)
        {
            _playbookRows.Add("No rows returned.");
            return;
        }

        foreach (var row in result.Rows.Take(500))
        {
            _playbookRows.Add(string.Join(" | ", row.Select(item => $"{item.Key}: {item.Value}")));
        }

        if (result.Rows.Count > _playbookRows.Count)
        {
            _playbookRows.Add($"Showing first {_playbookRows.Count:n0} of {result.Rows.Count:n0} row(s). Export the CSV for the full result.");
        }
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

    private string? GetDashboardPlatformFilter()
    {
        if (DashboardPlatformFilter.SelectedItem is not ComboBoxItem item)
        {
            return null;
        }

        var platform = item.Content?.ToString();
        return string.Equals(platform, "All platforms", StringComparison.OrdinalIgnoreCase) ? null : platform;
    }

    private static DashboardDeviceCategory GetDashboardCategory(string tag)
    {
        return tag switch
        {
            "intune" => DashboardDeviceCategory.Intune,
            "autopilot" => DashboardDeviceCategory.Autopilot,
            "entra" => DashboardDeviceCategory.Entra,
            "stale30" => DashboardDeviceCategory.Stale30,
            "stale90" => DashboardDeviceCategory.Stale90,
            "stale180" => DashboardDeviceCategory.Stale180,
            "corporate" => DashboardDeviceCategory.Corporate,
            "personal" => DashboardDeviceCategory.Personal,
            _ => DashboardDeviceCategory.Intune
        };
    }

    private IReadOnlyList<DeviceRecord> GetSelectedDevices()
    {
        return _allDevices.Where(device => device.IsSelected).ToArray();
    }

    private IReadOnlyList<DeviceRecord> GetSelectedOrVisibleDevices()
    {
        var selected = GetSelectedDevices();
        return selected.Count > 0 ? selected : _visibleDevices.ToArray();
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

    private static bool Contains(string? value, string? filter)
    {
        return string.IsNullOrWhiteSpace(filter)
            || (value?.Contains(filter.Trim(), StringComparison.OrdinalIgnoreCase) ?? false);
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
