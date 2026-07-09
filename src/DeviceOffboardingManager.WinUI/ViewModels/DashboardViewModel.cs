using System.Collections.ObjectModel;
using System.ComponentModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services;
using DeviceOffboardingManager.WinUI.Services.Contracts;
using DeviceOffboardingManager.WinUI.Utilities;

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
    public partial int PlatformFilterIndex { get; set; }

    [ObservableProperty]
    public partial string IntuneCountText { get; set; } = "--";

    [ObservableProperty]
    public partial string AutopilotCountText { get; set; } = "--";

    [ObservableProperty]
    public partial string EntraCountText { get; set; } = "--";

    [ObservableProperty]
    public partial string Stale30Text { get; set; } = "--";

    [ObservableProperty]
    public partial string Stale90Text { get; set; } = "--";

    [ObservableProperty]
    public partial string Stale180Text { get; set; } = "--";

    [ObservableProperty]
    public partial string CorporateCountText { get; set; } = "--";

    [ObservableProperty]
    public partial string PersonalCountText { get; set; } = "--";

    [ObservableProperty]
    public partial string DashboardPlatformText { get; set; } = AppResources.Get("DashboardPlatformInitial", "Refresh the dashboard to show platform distribution.");

    [ObservableProperty]
    public partial string DashboardOwnershipText { get; set; } = AppResources.Get("DashboardOwnershipInitial", "Ownership distribution is not loaded.");

    [ObservableProperty]
    public partial string DashboardStaleText { get; set; } = AppResources.Get("DashboardStaleInitial", "Stale device ratios are not loaded.");

    [ObservableProperty]
    public partial string DashboardResultTitleText { get; set; } = AppResources.Get("DashboardDrilldown", "Dashboard drilldown");

    [ObservableProperty]
    public partial string DashboardResultSummaryText { get; set; } = AppResources.Get("DashboardSelectCard", "Select a dashboard card to preview matching devices.");

    [ObservableProperty]
    public partial string DashboardReadinessText { get; set; } = AppResources.Get(
        "DashboardReadinessDisconnected",
        "Connect to Microsoft Graph to refresh dashboard statistics. Defender remains optional and disabled until enabled in Settings.");

    [ObservableProperty]
    public partial double CorporateDevicesProgress { get; set; }

    [ObservableProperty]
    public partial double PersonalDevicesProgress { get; set; }

    [ObservableProperty]
    public partial double StaleDevices30Progress { get; set; }

    [ObservableProperty]
    public partial double StaleDevices90Progress { get; set; }

    [ObservableProperty]
    public partial double StaleDevices180Progress { get; set; }

    [RelayCommand]
    private async Task RefreshAsync()
    {
        await RunAsync(AppResources.Get("RefreshingDashboard", "Refreshing dashboard"), async () =>
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
            _statusService.Report(
                AppResources.Get("DashboardRefreshed", "Dashboard refreshed"),
                AppResources.Format(
                    "DashboardPlatformFilterFormat",
                    "Platform filter: {0}.",
                    GetDashboardPlatformFilter() ?? AppResources.Get("AllPlatforms", "all")),
                StatusSeverity.Success);
        });
    }

    [RelayCommand]
    private async Task LoadDashboardResultsAsync(string tag)
    {
        await RunAsync(AppResources.Get("LoadingDashboardResults", "Loading dashboard results"), async () =>
        {
            EnsureConnected();
            var devices = await _deviceInventoryService.GetDashboardDevicesAsync(GetDashboardCategory(tag), GetDashboardPlatformFilter());
            var title = GetDashboardCategoryTitle(tag);
            _deviceListState.SetDashboardResults(title, devices);
            PopulateDashboardRows(title, devices);
            _deviceListState.ReplaceDeviceList(devices);
            _statusService.Report(
                AppResources.Get("DashboardResultsLoadedTitle", "Dashboard results loaded"),
                AppResources.Format("DashboardResultsLoadedFormat", "{0:N0} device(s) loaded. Use Open in devices or Export from the drilldown panel.", devices.Count),
                StatusSeverity.Success);
        });
    }

    [RelayCommand]
    private void OpenDashboardResultsInDevices()
    {
        if (_deviceListState.LastDashboardDevices.Count == 0)
        {
            _statusService.Report(
                AppResources.Get("DashboardNoResultsTitle", "No dashboard results"),
                AppResources.Get("DashboardNoResultsMessage", "Select a dashboard card before opening results in Devices."),
                StatusSeverity.Warning);
            return;
        }

        _deviceListState.ReplaceDeviceList(_deviceListState.LastDashboardDevices);
        _navigationService.Navigate("devices");
        _statusService.Report(
            AppResources.Get("DashboardResultsOpened", "Dashboard results opened"),
            AppResources.Format(
                "DashboardResultsOpenedFormat",
                "{0:N0} device(s) are loaded in Devices.",
                _deviceListState.LastDashboardDevices.Count),
            StatusSeverity.Success);
    }

    [RelayCommand]
    private async Task ExportDashboardResultsAsync()
    {
        await RunAsync(AppResources.Get("ExportingDashboardResults", "Exporting dashboard results"), async () =>
        {
            if (_deviceListState.LastDashboardDevices.Count == 0)
            {
                throw new InvalidOperationException(AppResources.Get("SelectDashboardBeforeExport", "Select a dashboard card before exporting drilldown results."));
            }

            var path = await _reportExportService.ExportDeviceCsvAsync(_deviceListState.LastDashboardDevices);
            _statusService.Report(AppResources.Get("DashboardCsvExportedTitle", "Dashboard CSV exported"), path, StatusSeverity.Success);
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

        DashboardOwnershipText = AppResources.Format(
            "DashboardOwnershipFormat",
            "Corporate: {0:N0} ({1:N0}%); Personal: {2:N0} ({3:N0}%).",
            dashboard.CorporateDevices,
            corporatePercent,
            dashboard.PersonalDevices,
            personalPercent);
        DashboardStaleText = AppResources.Format(
            "DashboardStaleFormat",
            "Stale ratios: 30 days {0:N0}%, 90 days {1:N0}%, 180 days {2:N0}%.",
            stale30Percent,
            stale90Percent,
            stale180Percent);
        DashboardPlatformText = dashboard.PlatformCounts.Count == 0
            ? AppResources.Get("DashboardPlatformUnavailable", "Platform distribution unavailable.")
            : string.Join(" | ", dashboard.PlatformCounts.Select(item => $"{item.Key}: {item.Value:n0} ({Percent(item.Value, total):n0}%)"));
    }

    private void PopulateDashboardRows(string title, IReadOnlyList<DeviceRecord> devices)
    {
        DashboardResultTitleText = title;
        DashboardResultSummaryText = devices.Count == 0
            ? AppResources.Get("DashboardNoMatches", "No devices matched this dashboard card.")
            : AppResources.Format(
                "DashboardMatchesFormat",
                "{0:N0} device(s) matched. Showing up to 100 rows here; export the CSV for the full result.",
                devices.Count);

        DashboardRows.Clear();
        foreach (var device in devices.Take(100))
        {
            DashboardRows.Add(new TextRow(
                AppResources.Format(
                    "DashboardDeviceRowFormat",
                    "{0} | Serial: {1} | OS: {2} | User: {3}",
                    device.DeviceName ?? AppResources.Get("UnnamedFallback", "(unnamed)"),
                    device.SerialNumber ?? AppResources.Get("NoneFallback", "(none)"),
                    device.OperatingSystem ?? AppResources.Get("UnknownFallback", "(unknown)"),
                    device.PrimaryUser ?? AppResources.Get("NoneFallback", "(none)"))));
        }

        if (devices.Count > DashboardRows.Count)
        {
            DashboardRows.Add(new TextRow(AppResources.Format(
                "DashboardRowsTruncatedFormat",
                "Showing first {0:N0} of {1:N0} device(s).",
                DashboardRows.Count,
                devices.Count)));
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
            "intune" => AppResources.Get("CategoryIntuneDevices", "Intune devices"),
            "autopilot" => AppResources.Get("CategoryAutopilotDevices", "Autopilot devices"),
            "entra" => AppResources.Get("CategoryEntraDevices", "Entra ID devices"),
            "stale30" => AppResources.Get("CategoryStale30", "Stale devices - 30 days"),
            "stale90" => AppResources.Get("CategoryStale90", "Stale devices - 90 days"),
            "stale180" => AppResources.Get("CategoryStale180", "Stale devices - 180 days"),
            "corporate" => AppResources.Get("CategoryCorporateDevices", "Corporate devices"),
            "personal" => AppResources.Get("CategoryPersonalDevices", "Personal devices"),
            _ => AppResources.Get("DashboardDrilldown", "Dashboard drilldown")
        };
    }

    private void EnsureConnected()
    {
        if (!_authenticationService.IsConnected)
        {
            throw new InvalidOperationException(AppResources.Get("ConnectFirst", "Connect to Microsoft Graph first."));
        }
    }

    private static double Percent(int value, int total)
    {
        return total <= 0 ? 0 : Math.Round((double)value / total * 100);
    }
}
