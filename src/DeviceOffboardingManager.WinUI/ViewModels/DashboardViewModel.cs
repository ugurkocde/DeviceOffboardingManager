using System.Collections.ObjectModel;
using System.ComponentModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services;
using DeviceOffboardingManager.WinUI.Services.Contracts;

namespace DeviceOffboardingManager.WinUI.ViewModels;

public sealed partial class DashboardViewModel : AppViewModelBase
{
    private readonly IAuthenticationService _authenticationService;
    private readonly IDeviceInventoryService _deviceInventoryService;
    private readonly IReportExportService _reportExportService;
    private readonly IStatusService _statusService;
    private readonly DeviceListState _deviceListState;
    private readonly ShellNavigationService _navigationService;
    private readonly SettingsViewModel _settingsViewModel;

    public DashboardViewModel(
        IAuthenticationService authenticationService,
        IDeviceInventoryService deviceInventoryService,
        IReportExportService reportExportService,
        IStatusService statusService,
        IAuditLogService auditLogService,
        DeviceListState deviceListState,
        ShellNavigationService navigationService,
        SettingsViewModel settingsViewModel)
        : base(statusService, auditLogService)
    {
        _authenticationService = authenticationService;
        _deviceInventoryService = deviceInventoryService;
        _reportExportService = reportExportService;
        _statusService = statusService;
        _deviceListState = deviceListState;
        _navigationService = navigationService;
        _settingsViewModel = settingsViewModel;

        DashboardReadinessText = _settingsViewModel.DashboardReadinessText;
        _settingsViewModel.PropertyChanged += SettingsViewModel_PropertyChanged;
    }

    public ObservableCollection<TextRow> DashboardRows { get; } = new();

    [ObservableProperty]
    private int platformFilterIndex;

    [ObservableProperty]
    private string intuneCountText = "--";

    [ObservableProperty]
    private string autopilotCountText = "--";

    [ObservableProperty]
    private string entraCountText = "--";

    [ObservableProperty]
    private string stale30Text = "--";

    [ObservableProperty]
    private string stale90Text = "--";

    [ObservableProperty]
    private string stale180Text = "--";

    [ObservableProperty]
    private string corporateCountText = "--";

    [ObservableProperty]
    private string personalCountText = "--";

    [ObservableProperty]
    private string dashboardPlatformText = "Refresh the dashboard to show platform distribution.";

    [ObservableProperty]
    private string dashboardOwnershipText = "Ownership distribution is not loaded.";

    [ObservableProperty]
    private string dashboardStaleText = "Stale device ratios are not loaded.";

    [ObservableProperty]
    private string dashboardResultTitleText = "Dashboard drilldown";

    [ObservableProperty]
    private string dashboardResultSummaryText = "Select a dashboard card to preview matching devices.";

    [ObservableProperty]
    private string dashboardReadinessText = "Connect to Microsoft Graph to refresh dashboard statistics. Defender remains optional and disabled until enabled in Settings.";

    [ObservableProperty]
    private double corporateDevicesProgress;

    [ObservableProperty]
    private double personalDevicesProgress;

    [ObservableProperty]
    private double staleDevices30Progress;

    [ObservableProperty]
    private double staleDevices90Progress;

    [ObservableProperty]
    private double staleDevices180Progress;

    [RelayCommand]
    private async Task RefreshAsync()
    {
        await RunAsync("Refreshing dashboard", async () =>
        {
            EnsureConnected();
            var dashboard = await _deviceInventoryService.GetDashboardSummaryAsync();
            IntuneCountText = dashboard.IntuneDevices.ToString("n0");
            AutopilotCountText = dashboard.AutopilotDevices.ToString("n0");
            EntraCountText = dashboard.EntraDevices.ToString("n0");
            Stale30Text = dashboard.StaleDevices30Days.ToString("n0");
            Stale90Text = dashboard.StaleDevices90Days.ToString("n0");
            Stale180Text = dashboard.StaleDevices180Days.ToString("n0");
            CorporateCountText = dashboard.CorporateDevices.ToString("n0");
            PersonalCountText = dashboard.PersonalDevices.ToString("n0");
            UpdateDashboardVisuals(dashboard);
            _statusService.Report("Dashboard refreshed", $"Platform filter: {GetDashboardPlatformFilter() ?? "all"}.", StatusSeverity.Success);
        });
    }

    [RelayCommand]
    private async Task LoadDashboardResultsAsync(string tag)
    {
        await RunAsync("Loading dashboard results", async () =>
        {
            EnsureConnected();
            var devices = await _deviceInventoryService.GetDashboardDevicesAsync(GetDashboardCategory(tag), GetDashboardPlatformFilter());
            var title = GetDashboardCategoryTitle(tag);
            _deviceListState.SetDashboardResults(title, devices);
            PopulateDashboardRows(title, devices);
            _deviceListState.ReplaceDeviceList(devices);
            _statusService.Report("Dashboard results loaded", $"{devices.Count:n0} device(s) loaded. Use Open in devices or Export from the drilldown panel.", StatusSeverity.Success);
        });
    }

    [RelayCommand]
    private void OpenDashboardResultsInDevices()
    {
        if (_deviceListState.LastDashboardDevices.Count == 0)
        {
            _statusService.Report("No dashboard results", "Select a dashboard card before opening results in Devices.", StatusSeverity.Warning);
            return;
        }

        _deviceListState.ReplaceDeviceList(_deviceListState.LastDashboardDevices);
        _navigationService.Navigate("devices");
        _statusService.Report("Dashboard results opened", $"{_deviceListState.LastDashboardDevices.Count:n0} device(s) are loaded in Devices.", StatusSeverity.Success);
    }

    [RelayCommand]
    private async Task ExportDashboardResultsAsync()
    {
        await RunAsync("Exporting dashboard results", async () =>
        {
            if (_deviceListState.LastDashboardDevices.Count == 0)
            {
                throw new InvalidOperationException("Select a dashboard card before exporting drilldown results.");
            }

            var path = await _reportExportService.ExportDeviceCsvAsync(_deviceListState.LastDashboardDevices);
            _statusService.Report("Dashboard CSV exported", path, StatusSeverity.Success);
        });
    }

    [RelayCommand]
    private void OpenSettings()
    {
        _navigationService.Navigate("settings");
    }

    [RelayCommand]
    private void GoToDevices()
    {
        _navigationService.Navigate("devices");
    }

    private void UpdateDashboardVisuals(DashboardSummary dashboard)
    {
        var total = Math.Max(dashboard.IntuneDevices, 0);
        var corporatePercent = Percent(dashboard.CorporateDevices, total);
        var personalPercent = Percent(dashboard.PersonalDevices, total);
        var stale30Percent = Percent(dashboard.StaleDevices30Days, total);
        var stale90Percent = Percent(dashboard.StaleDevices90Days, total);
        var stale180Percent = Percent(dashboard.StaleDevices180Days, total);

        CorporateDevicesProgress = corporatePercent;
        PersonalDevicesProgress = personalPercent;
        StaleDevices30Progress = stale30Percent;
        StaleDevices90Progress = stale90Percent;
        StaleDevices180Progress = stale180Percent;

        DashboardOwnershipText =
            $"Corporate: {dashboard.CorporateDevices:n0} ({corporatePercent:n0}%); Personal: {dashboard.PersonalDevices:n0} ({personalPercent:n0}%).";
        DashboardStaleText =
            $"Stale ratios: 30 days {stale30Percent:n0}%, 90 days {stale90Percent:n0}%, 180 days {stale180Percent:n0}%.";
        DashboardPlatformText = dashboard.PlatformCounts.Count == 0
            ? "Platform distribution unavailable."
            : string.Join(" | ", dashboard.PlatformCounts.Select(item => $"{item.Key}: {item.Value:n0} ({Percent(item.Value, total):n0}%)"));
    }

    private void PopulateDashboardRows(string title, IReadOnlyList<DeviceRecord> devices)
    {
        DashboardResultTitleText = title;
        DashboardResultSummaryText = devices.Count == 0
            ? "No devices matched this dashboard card."
            : $"{devices.Count:n0} device(s) matched. Showing up to 100 rows here; export the CSV for the full result.";

        DashboardRows.Clear();
        foreach (var device in devices.Take(100))
        {
            DashboardRows.Add(new TextRow(
                $"{device.DeviceName ?? "(unnamed)"} | Serial: {device.SerialNumber ?? "(none)"} | OS: {device.OperatingSystem ?? "(unknown)"} | User: {device.PrimaryUser ?? "(none)"}"));
        }

        if (devices.Count > DashboardRows.Count)
        {
            DashboardRows.Add(new TextRow($"Showing first {DashboardRows.Count:n0} of {devices.Count:n0} device(s)."));
        }
    }

    private void SettingsViewModel_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(SettingsViewModel.DashboardReadinessText))
        {
            DashboardReadinessText = _settingsViewModel.DashboardReadinessText;
        }
    }

    private string? GetDashboardPlatformFilter()
    {
        return PlatformFilterIndex switch
        {
            1 => "Windows",
            2 => "macOS",
            3 => "iOS",
            4 => "Android",
            5 => "Linux",
            _ => null
        };
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

    private void EnsureConnected()
    {
        if (!_authenticationService.IsConnected)
        {
            throw new InvalidOperationException("Connect to Microsoft Graph first.");
        }
    }

    private static double Percent(int value, int total)
    {
        return total <= 0 ? 0 : Math.Round((double)value / total * 100);
    }
}
