using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services.Contracts;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.UI.Text;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace DeviceOffboardingManager.WinUI;

public sealed partial class MainWindow : Window
{
    private const string AppVersion = "0.4.0";
    private static readonly HttpClient UpdateHttpClient = new();

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
    private readonly ObservableCollection<string> _dashboardRows = new();
    private readonly ObservableCollection<string> _playbookRows = new();
    private IReadOnlyList<DeviceRecord> _lastDashboardDevices = Array.Empty<DeviceRecord>();
    private string _lastDashboardTitle = "Dashboard drilldown";
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
        Title = $"Device Offboarding Manager {AppVersion}";
        DeviceListView.ItemsSource = _visibleDevices;
        DashboardResultListView.ItemsSource = _dashboardRows;
        PlaybookResultListView.ItemsSource = _playbookRows;
        AboutVersionText.Text = $"Version {AppVersion} native Windows app track";

        if (!UpdateHttpClient.DefaultRequestHeaders.UserAgent.Any())
        {
            UpdateHttpClient.DefaultRequestHeaders.UserAgent.ParseAdd($"DeviceOffboardingManager-WinUI/{AppVersion}");
        }

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

    private async void BrowseConfig_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("Selecting config", async () =>
        {
            var path = await PickFilePathAsync(".json");
            if (!string.IsNullOrWhiteSpace(path))
            {
                ConfigPathBox.Text = path;
                SetStatus("Config selected", path, InfoBarSeverity.Informational);
            }
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
            UpdateDashboardVisuals(dashboard);
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
            _lastDashboardDevices = devices;
            _lastDashboardTitle = GetDashboardCategoryTitle(tag);
            PopulateDashboardRows(_lastDashboardTitle, devices);
            ReplaceDeviceList(devices);
            SetStatus("Dashboard results loaded", $"{devices.Count:n0} device(s) loaded. Use Open in devices or Export from the drilldown panel.", InfoBarSeverity.Success);
        });
    }

    private async void Search_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("Searching devices", SearchCurrentTermsAsync);
    }

    private async void ImportBulkFile_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("Importing search terms", async () =>
        {
            var path = await PickFilePathAsync(".csv", ".txt");
            if (string.IsNullOrWhiteSpace(path))
            {
                SetStatus("Import canceled", "No file was selected.", InfoBarSeverity.Informational);
                return;
            }

            var terms = await ParseBulkImportFileAsync(path);
            if (terms.Count == 0)
            {
                throw new InvalidOperationException("The selected file did not contain device identifiers.");
            }

            if (!await ConfirmBulkImportAsync(path, terms))
            {
                SetStatus("Import canceled", "No search terms were changed.", InfoBarSeverity.Informational);
                return;
            }

            SearchTextBox.Text = string.Join(Environment.NewLine, terms);
            if (_authenticationService.IsConnected)
            {
                await SearchCurrentTermsAsync();
            }
            else
            {
                SetStatus("Bulk terms imported", $"Imported {terms.Count:n0} search term(s). Connect before searching.", InfoBarSeverity.Success);
            }
        });
    }

    private async void DownloadBulkTemplate_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("Saving import template", async () =>
        {
            var path = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
                "device_import_template.csv");
            var template = string.Join(Environment.NewLine, new[]
            {
                "DeviceIdentifier",
                "DESKTOP-ABC123",
                "LAPTOP-XYZ789",
                "1234567890",
                "0987654321"
            });

            await File.WriteAllTextAsync(path, template, Encoding.UTF8);
            SetStatus("Template saved", path, InfoBarSeverity.Success);
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

    private async void ExportDashboardResults_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("Exporting dashboard results", async () =>
        {
            if (_lastDashboardDevices.Count == 0)
            {
                throw new InvalidOperationException("Select a dashboard card before exporting drilldown results.");
            }

            var path = await _reportExportService.ExportDeviceCsvAsync(_lastDashboardDevices);
            SetStatus("Dashboard CSV exported", path, InfoBarSeverity.Success);
        });
    }

    private void OpenDashboardResultsInDevices_Click(object sender, RoutedEventArgs e)
    {
        if (_lastDashboardDevices.Count == 0)
        {
            SetStatus("No dashboard results", "Select a dashboard card before opening results in Devices.", InfoBarSeverity.Warning);
            return;
        }

        ReplaceDeviceList(_lastDashboardDevices);
        RootNavigation.SelectedItem = NavDevices;
        ShowPage("devices");
        SetStatus("Dashboard results opened", $"{_lastDashboardDevices.Count:n0} device(s) are loaded in Devices.", InfoBarSeverity.Success);
    }

    private async void ViewSelectedGroups_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("Loading group memberships", async () =>
        {
            EnsureConnected();
            var selected = GetSelectedDevices();
            if (selected.Count != 1)
            {
                throw new InvalidOperationException("Select exactly one device with a resolved Entra object ID.");
            }

            var groups = await _deviceInventoryService.GetDeviceGroupMembershipsAsync(selected[0]);
            await ShowGroupMembershipDialogAsync(selected[0], groups);
            SetStatus("Group memberships loaded", $"{groups.Count:n0} group(s) found for {selected[0].DeviceName ?? "the selected device"}.", InfoBarSeverity.Success);
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
            await ShowOffboardingSummaryDialogAsync(_lastOffboardingSummary);
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

    private async void OpenChangelog_Click(object sender, RoutedEventArgs e)
    {
        var candidates = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "Changelog.md"),
            Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Changelog.md"))
        };
        var changelogPath = candidates.FirstOrDefault(File.Exists);
        if (changelogPath is null)
        {
            SetStatus("Changelog unavailable", "Changelog.md was not found in the app output or repository root.", InfoBarSeverity.Warning);
            return;
        }

        var text = await File.ReadAllTextAsync(changelogPath);
        var dialog = new ContentDialog
        {
            Title = "Changelog",
            Content = new ScrollViewer { Content = CreateChangelogContent(text), MaxHeight = 560 },
            CloseButtonText = "Close",
            XamlRoot = this.Content.XamlRoot
        };
        await dialog.ShowAsync();
    }

    private async void CheckForUpdates_Click(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync("Checking for updates", async () =>
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, "https://api.github.com/repos/ugurkocde/DeviceOffboardingManager/releases/latest");
            using var response = await UpdateHttpClient.SendAsync(request);
            var responseText = await response.Content.ReadAsStringAsync();
            if (!response.IsSuccessStatusCode)
            {
                throw new InvalidOperationException($"GitHub update check failed with HTTP {(int)response.StatusCode}: {responseText}");
            }

            var latestTag = JsonNode.Parse(responseText)?["tag_name"]?.GetValue<string>();
            var latestVersion = TryParseVersion(latestTag);
            var currentVersion = TryParseVersion(AppVersion);
            if (latestVersion is null || currentVersion is null)
            {
                SetStatus("Update check complete", $"Latest release tag: {latestTag ?? "(unknown)"}. Current app: {AppVersion}.", InfoBarSeverity.Informational);
                return;
            }

            var updateAvailable = latestVersion.CompareTo(currentVersion) > 0;
            var message = updateAvailable
                ? $"A newer release is available: {latestTag}. Current app: {AppVersion}."
                : $"You are on the current or newer app track. Latest release: {latestTag}; current app: {AppVersion}.";

            SetStatus("Update check complete", message, updateAvailable ? InfoBarSeverity.Warning : InfoBarSeverity.Success);
            var dialog = updateAvailable
                ? new ContentDialog
                {
                    Title = "Update check",
                    Content = new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap },
                    PrimaryButtonText = "Open releases",
                    CloseButtonText = "Close",
                    XamlRoot = this.Content.XamlRoot
                }
                : new ContentDialog
                {
                    Title = "Update check",
                    Content = new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap },
                    CloseButtonText = "Close",
                    XamlRoot = this.Content.XamlRoot
                };

            if (await dialog.ShowAsync() == ContentDialogResult.Primary)
            {
                OpenUrl("https://github.com/ugurkocde/DeviceOffboardingManager/releases");
            }
        });
    }

    private void OpenRepository_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            OpenUrl("https://github.com/ugurkocde/DeviceOffboardingManager");
        }
        catch (Exception ex)
        {
            SetStatus("Could not open repository", ex.Message, InfoBarSeverity.Error);
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

    private async Task SearchCurrentTermsAsync()
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
    }

    private async Task<bool> ConfirmBulkImportAsync(string path, IReadOnlyList<string> terms)
    {
        var previewRows = terms
            .Take(20)
            .Select((term, index) => $"{index + 1:n0}. {term}")
            .ToArray();

        var content = new StackPanel { Spacing = 12 };
        content.Children.Add(new TextBlock
        {
            Text = $"{Path.GetFileName(path)} contains {terms.Count:n0} unique device identifier(s).",
            TextWrapping = TextWrapping.Wrap
        });
        content.Children.Add(new ListView
        {
            ItemsSource = previewRows,
            MaxHeight = 300
        });
        if (terms.Count > previewRows.Length)
        {
            content.Children.Add(new TextBlock
            {
                Text = $"Showing first {previewRows.Length:n0} identifiers. Import will use all {terms.Count:n0}.",
                TextWrapping = TextWrapping.Wrap
            });
        }

        var dialog = new ContentDialog
        {
            Title = "Import devices",
            Content = content,
            PrimaryButtonText = "Import",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
            XamlRoot = this.Content.XamlRoot
        };

        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }

    private static async Task<IReadOnlyList<string>> ParseBulkImportFileAsync(string path)
    {
        var lines = await File.ReadAllLinesAsync(path);
        var identifiers = new List<string>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        for (var lineIndex = 0; lineIndex < lines.Length; lineIndex++)
        {
            var line = lines[lineIndex].Trim();
            if (string.IsNullOrWhiteSpace(line) || line.StartsWith('#'))
            {
                continue;
            }

            foreach (var value in SplitDelimitedLine(line))
            {
                var identifier = value.Trim();
                if (lineIndex == 0 && IsBulkImportHeader(identifier))
                {
                    continue;
                }

                if (string.IsNullOrWhiteSpace(identifier) || !seen.Add(identifier))
                {
                    continue;
                }

                identifiers.Add(identifier);
            }
        }

        return identifiers;
    }

    private static IReadOnlyList<string> SplitDelimitedLine(string line)
    {
        var values = new List<string>();
        var current = new StringBuilder();
        var inQuotes = false;

        for (var i = 0; i < line.Length; i++)
        {
            var character = line[i];
            if (character == '"')
            {
                if (inQuotes && i + 1 < line.Length && line[i + 1] == '"')
                {
                    current.Append('"');
                    i++;
                    continue;
                }

                inQuotes = !inQuotes;
                continue;
            }

            if (!inQuotes && (character == ',' || character == ';' || character == '\t'))
            {
                values.Add(current.ToString());
                current.Clear();
                continue;
            }

            current.Append(character);
        }

        values.Add(current.ToString());
        return values;
    }

    private static bool IsBulkImportHeader(string value)
    {
        return value.Equals("DeviceIdentifier", StringComparison.OrdinalIgnoreCase)
            || value.Equals("DeviceName", StringComparison.OrdinalIgnoreCase)
            || value.Equals("Device", StringComparison.OrdinalIgnoreCase)
            || value.Equals("SerialNumber", StringComparison.OrdinalIgnoreCase)
            || value.Equals("Serial", StringComparison.OrdinalIgnoreCase);
    }

    private void UpdateDashboardVisuals(DashboardSummary dashboard)
    {
        var total = Math.Max(dashboard.IntuneDevices, 0);
        var corporatePercent = Percent(dashboard.CorporateDevices, total);
        var personalPercent = Percent(dashboard.PersonalDevices, total);
        var stale30Percent = Percent(dashboard.StaleDevices30Days, total);
        var stale90Percent = Percent(dashboard.StaleDevices90Days, total);
        var stale180Percent = Percent(dashboard.StaleDevices180Days, total);

        CorporateDevicesProgress.Value = corporatePercent;
        PersonalDevicesProgress.Value = personalPercent;
        StaleDevices30Progress.Value = stale30Percent;
        StaleDevices90Progress.Value = stale90Percent;
        StaleDevices180Progress.Value = stale180Percent;

        DashboardOwnershipText.Text =
            $"Corporate: {dashboard.CorporateDevices:n0} ({corporatePercent:n0}%); Personal: {dashboard.PersonalDevices:n0} ({personalPercent:n0}%).";
        DashboardStaleText.Text =
            $"Stale ratios: 30 days {stale30Percent:n0}%, 90 days {stale90Percent:n0}%, 180 days {stale180Percent:n0}%.";
        DashboardPlatformText.Text = dashboard.PlatformCounts.Count == 0
            ? "Platform distribution unavailable."
            : string.Join(" | ", dashboard.PlatformCounts.Select(item => $"{item.Key}: {item.Value:n0} ({Percent(item.Value, total):n0}%)"));
    }

    private void PopulateDashboardRows(string title, IReadOnlyList<DeviceRecord> devices)
    {
        DashboardResultTitleText.Text = title;
        DashboardResultSummaryText.Text = devices.Count == 0
            ? "No devices matched this dashboard card."
            : $"{devices.Count:n0} device(s) matched. Showing up to 100 rows here; export the CSV for the full result.";

        _dashboardRows.Clear();
        foreach (var device in devices.Take(100))
        {
            _dashboardRows.Add(
                $"{device.DeviceName ?? "(unnamed)"} | Serial: {device.SerialNumber ?? "(none)"} | OS: {device.OperatingSystem ?? "(unknown)"} | User: {device.PrimaryUser ?? "(none)"}");
        }

        if (devices.Count > _dashboardRows.Count)
        {
            _dashboardRows.Add($"Showing first {_dashboardRows.Count:n0} of {devices.Count:n0} device(s).");
        }
    }

    private async Task ShowGroupMembershipDialogAsync(DeviceRecord device, IReadOnlyList<GroupMembershipRecord> groups)
    {
        var rows = groups.Count == 0
            ? new[] { "No group memberships found." }
            : groups.Select(group =>
                $"{group.DisplayName} | {group.Type} | Mail: {YesNo(group.MailEnabled)} | Security: {YesNo(group.SecurityEnabled)}").ToArray();

        var dialog = new ContentDialog
        {
            Title = $"Group memberships - {device.DeviceName ?? "Device"}",
            Content = new ListView
            {
                ItemsSource = rows,
                MaxHeight = 480
            },
            CloseButtonText = "Close",
            XamlRoot = this.Content.XamlRoot
        };

        await dialog.ShowAsync();
    }

    private async Task ShowOffboardingSummaryDialogAsync(OffboardingSummary summary)
    {
        var rows = summary.Results.Select(result =>
            $"{result.DeviceName ?? "(unnamed)"} | Serial: {result.SerialNumber ?? "(none)"} | Pre: {DescribeOperation(result.PreAction)} | Entra: {DescribeOperation(result.Entra)} | Intune: {DescribeOperation(result.Intune)} | Autopilot: {DescribeOperation(result.Autopilot)} | Defender: {DescribeOperation(result.Defender)}").ToArray();

        var content = new StackPanel { Spacing = 12 };
        content.Children.Add(new TextBlock
        {
            Text = $"Devices: {summary.TotalDevices:n0}; successful: {summary.SuccessfulDevices:n0}; failed/partial: {summary.FailedDevices:n0}.",
            TextWrapping = TextWrapping.Wrap
        });
        content.Children.Add(new ListView
        {
            ItemsSource = rows,
            MaxHeight = 480
        });

        var dialog = new ContentDialog
        {
            Title = "Offboarding summary",
            Content = content,
            PrimaryButtonText = "Export HTML report",
            CloseButtonText = "Close",
            XamlRoot = this.Content.XamlRoot
        };

        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            var path = await _reportExportService.ExportOffboardingHtmlAsync(summary);
            SetStatus("Report exported", path, InfoBarSeverity.Success);
        }
    }

    private static StackPanel CreateChangelogContent(string markdown)
    {
        var panel = new StackPanel { Spacing = 8 };
        foreach (var rawLine in markdown.Split(new[] { "\r\n", "\n" }, StringSplitOptions.None))
        {
            var line = rawLine.TrimEnd();
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            var block = new TextBlock
            {
                TextWrapping = TextWrapping.Wrap
            };

            if (line.StartsWith("## ", StringComparison.Ordinal))
            {
                block.Text = StripMarkdownInline(line[3..]);
                block.FontWeight = FontWeights.SemiBold;
            }
            else if (line.StartsWith("- ", StringComparison.Ordinal))
            {
                block.Text = "• " + StripMarkdownInline(line[2..]);
                block.Margin = new Thickness(16, 0, 0, 0);
            }
            else if (line.StartsWith("  - ", StringComparison.Ordinal))
            {
                block.Text = "• " + StripMarkdownInline(line[4..]);
                block.Margin = new Thickness(32, 0, 0, 0);
            }
            else
            {
                block.Text = StripMarkdownInline(line.TrimStart('#', ' '));
            }

            panel.Children.Add(block);
        }

        return panel;
    }

    private static string StripMarkdownInline(string text)
    {
        return text
            .Replace("**", string.Empty, StringComparison.Ordinal)
            .Replace("`", string.Empty, StringComparison.Ordinal);
    }

    private static Version? TryParseVersion(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return null;
        }

        var match = Regex.Match(text, @"\d+(\.\d+){0,3}");
        return match.Success && Version.TryParse(match.Value, out var version) ? version : null;
    }

    private static string DescribeOperation(ServiceOperationResult result)
    {
        if (!result.Found && string.IsNullOrWhiteSpace(result.Error))
        {
            return "Skipped";
        }

        if (!result.Found)
        {
            return $"Not found: {result.Error}";
        }

        return result.Success ? result.Action ?? "Success" : $"Failed: {result.Error}";
    }

    private static string YesNo(bool value)
    {
        return value ? "yes" : "no";
    }

    private static double Percent(int value, int total)
    {
        return total <= 0 ? 0 : Math.Round((double)value / total * 100);
    }

    private static void OpenUrl(string url)
    {
        Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
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

    private static string GetDashboardCategoryTitle(string tag)
    {
        return tag switch
        {
            "intune" => "Intune devices",
            "autopilot" => "Autopilot devices",
            "entra" => "Entra ID devices",
            "stale30" => "Stale devices - 30 days",
            "stale90" => "Stale devices - 90 days",
            "stale180" => "Stale devices - 180 days",
            "corporate" => "Corporate devices",
            "personal" => "Personal devices",
            _ => "Dashboard drilldown"
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

    private async Task<string?> PickFilePathAsync(params string[] extensions)
    {
        var picker = new FileOpenPicker();
        foreach (var extension in extensions)
        {
            picker.FileTypeFilter.Add(extension);
        }

        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
        var file = await picker.PickSingleFileAsync();
        return file?.Path;
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
