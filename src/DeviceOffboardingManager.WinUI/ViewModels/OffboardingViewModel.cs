using System.ComponentModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services;
using DeviceOffboardingManager.WinUI.Services.Contracts;
using DeviceOffboardingManager.WinUI.Utilities;

namespace DeviceOffboardingManager.WinUI.ViewModels;

public sealed partial class OffboardingViewModel : AppViewModelBase
{
    private readonly IAuthenticationService _authenticationService;
    private readonly IDeviceInventoryService _deviceInventoryService;
    private readonly IOffboardingService _offboardingService;
    private readonly IRecoveryKeyService _recoveryKeyService;
    private readonly IReportExportService _reportExportService;
    private readonly IStatusService _statusService;
    private readonly DeviceListState _deviceListState;
    private readonly SettingsViewModel _settingsViewModel;

    public OffboardingViewModel(
        IAuthenticationService authenticationService,
        IDeviceInventoryService deviceInventoryService,
        IOffboardingService offboardingService,
        IRecoveryKeyService recoveryKeyService,
        IReportExportService reportExportService,
        IStatusService statusService,
        IAuditLogService auditLogService,
        DeviceListState deviceListState,
        SettingsViewModel settingsViewModel)
        : base(statusService, auditLogService)
    {
        _authenticationService = authenticationService;
        _deviceInventoryService = deviceInventoryService;
        _offboardingService = offboardingService;
        _recoveryKeyService = recoveryKeyService;
        _reportExportService = reportExportService;
        _statusService = statusService;
        _deviceListState = deviceListState;
        _settingsViewModel = settingsViewModel;

        IsDefenderControlEnabled = _settingsViewModel.DefenderIntegrationEnabled;
        RefreshSelectedSummary();
        _deviceListState.SelectionChanged += RefreshSelectedSummary;
        _settingsViewModel.PropertyChanged += SettingsViewModel_PropertyChanged;
    }

    [ObservableProperty]
    public partial string SelectedDeviceCountText { get; set; } = AppResources.Get("NoDevicesSelectedShort", "No devices selected.");

    [ObservableProperty]
    public partial string OffboardingStatusText { get; set; } = AppResources.Get("SelectDevicesBeforeActions", "Select devices before running actions.");

    [ObservableProperty]
    public partial bool DeleteEntra { get; set; } = true;

    [ObservableProperty]
    public partial bool DisableEntra { get; set; }

    [ObservableProperty]
    public partial bool DeleteIntune { get; set; } = true;

    [ObservableProperty]
    public partial bool DeleteAutopilot { get; set; } = true;

    [ObservableProperty]
    public partial bool OffboardDefender { get; set; }

    [ObservableProperty]
    public partial bool IsDefenderControlEnabled { get; set; }

    [ObservableProperty]
    public partial int PreActionIndex { get; set; }

    [ObservableProperty]
    public partial string GroupTag { get; set; } = string.Empty;

    [RelayCommand]
    private async Task ExportSelectedAsync()
    {
        await RunAsync(AppResources.Get("ExportingCsv", "Exporting CSV"), async () =>
        {
            var devices = _deviceListState.GetSelectedOrVisibleDevices();
            if (devices.Count == 0)
            {
                throw new InvalidOperationException(AppResources.Get("NoDevicesAvailable", "No devices are available to export."));
            }

            var path = await _reportExportService.ExportDeviceCsvAsync(devices);
            _statusService.Report(AppResources.Get("CsvExportedTitle", "CSV exported"), path, StatusSeverity.Success);
        });
    }

    [RelayCommand]
    private async Task SetGroupTagAsync()
    {
        await RunAsync(AppResources.Get("SettingGroupTag", "Setting group tag"), async () =>
        {
            EnsureConnected();
            var selected = _deviceListState.GetSelectedDevices();
            if (selected.Count == 0)
            {
                throw new InvalidOperationException(AppResources.Get("SelectOneDevice", "Select at least one device."));
            }

            var result = await _deviceInventoryService.SetAutopilotGroupTagAsync(selected, GroupTag);
            _statusService.Report(
                AppResources.Get("GroupTagComplete", "Group tag update complete"),
                AppResources.Format("GroupTagCompleteFormat", "Updated: {0:N0}; Failed: {1:N0}.", result.Updated, result.Failed),
                result.Failed == 0 ? StatusSeverity.Success : StatusSeverity.Warning);
        });
    }

    [RelayCommand]
    private async Task ExportReportAsync()
    {
        await RunAsync(AppResources.Get("ExportingReport", "Exporting report"), async () =>
        {
            if (_deviceListState.LastOffboardingSummary is null)
            {
                throw new InvalidOperationException(AppResources.Get("RunOffboardingBeforeExport", "Run an offboarding operation before exporting the HTML report."));
            }

            var path = await _reportExportService.ExportOffboardingHtmlAsync(_deviceListState.LastOffboardingSummary);
            _statusService.Report(AppResources.Get("ReportExportedTitle", "Report exported"), path, StatusSeverity.Success);
        });
    }

    public IReadOnlyList<DeviceRecord> GetSelectedDevices()
    {
        return _deviceListState.GetSelectedDevices();
    }

    public async Task<IReadOnlyList<RecoveryKeyRecord>?> FetchRecoveryKeysForDialogAsync()
    {
        return await RunAsync(AppResources.Get("FetchingRecoveryKeys", "Fetching recovery keys"), async () =>
        {
            EnsureConnected();
            var selected = _deviceListState.GetSelectedDevices();
            if (selected.Count == 0)
            {
                throw new InvalidOperationException(AppResources.Get("SelectOneDevice", "Select at least one device."));
            }

            var keys = await _recoveryKeyService.GetRecoveryKeysAsync(selected);
            var found = keys.Count(key => !string.IsNullOrWhiteSpace(key.KeyValue));
            OffboardingStatusText = AppResources.Format(
                "RecoveryLookupCompleteFormat",
                "Recovery key lookup complete. Records: {0:N0}; values found: {1:N0}. Values are shown once and are not written to logs.",
                keys.Count,
                found);
            _statusService.Report(
                AppResources.Get("RecoveryLookupComplete", "Recovery key lookup complete"),
                OffboardingStatusText,
                found > 0 ? StatusSeverity.Success : StatusSeverity.Informational);
            return keys;
        });
    }

    public async Task<OffboardingSummary?> RunConfirmedOffboardingAsync()
    {
        return await RunAsync(AppResources.Get("RunningOffboarding", "Running offboarding"), async () =>
        {
            EnsureConnected();
            var selected = _deviceListState.GetSelectedDevices();
            if (selected.Count == 0)
            {
                throw new InvalidOperationException(AppResources.Get("SelectOneDevice", "Select at least one device."));
            }

            var summary = await _offboardingService.OffboardAsync(selected, BuildOffboardingOptions());
            _deviceListState.LastOffboardingSummary = summary;
            OffboardingStatusText = AppResources.Format(
                "OffboardingCompleteFormat",
                "Offboarding complete. Devices: {0:N0}; successful: {1:N0}; failed/partial: {2:N0}.",
                summary.TotalDevices,
                summary.SuccessfulDevices,
                summary.FailedDevices);
            _statusService.Report(
                AppResources.Get("OffboardingComplete", "Offboarding complete"),
                OffboardingStatusText,
                summary.FailedDevices == 0 ? StatusSeverity.Success : StatusSeverity.Warning);
            return summary;
        });
    }

    public async Task ExportSummaryAsync(OffboardingSummary summary)
    {
        await RunAsync(AppResources.Get("ExportingReport", "Exporting report"), async () =>
        {
            var path = await _reportExportService.ExportOffboardingHtmlAsync(summary);
            _statusService.Report(AppResources.Get("ReportExportedTitle", "Report exported"), path, StatusSeverity.Success);
        });
    }

    public void ReportOffboardingCanceled()
    {
        _statusService.Report(
            AppResources.Get("OffboardingCanceledTitle", "Offboarding canceled"),
            AppResources.Get("OffboardingCanceledMessage", "No changes were made."),
            StatusSeverity.Informational);
    }

    private OffboardingOptions BuildOffboardingOptions()
    {
        var disableEntra = DisableEntra;
        return new OffboardingOptions
        {
            DisableEntra = disableEntra,
            DeleteEntra = !disableEntra && DeleteEntra,
            DeleteIntune = DeleteIntune,
            DeleteAutopilot = DeleteAutopilot,
            OffboardDefender = _settingsViewModel.DefenderIntegrationEnabled && OffboardDefender,
            PreAction = PreActionIndex switch
            {
                1 => DevicePreAction.Retire,
                2 => DevicePreAction.Wipe,
                _ => DevicePreAction.None
            }
        };
    }

    private void RefreshSelectedSummary()
    {
        SelectedDeviceCountText = _deviceListState.GetSelectedSummaryText();
        OffboardingStatusText = _deviceListState.GetOffboardingStatusText();
    }

    private void SettingsViewModel_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(SettingsViewModel.DefenderIntegrationEnabled))
        {
            IsDefenderControlEnabled = _settingsViewModel.DefenderIntegrationEnabled;
            if (!IsDefenderControlEnabled)
            {
                OffboardDefender = false;
            }
        }
    }

    private void EnsureConnected()
    {
        if (!_authenticationService.IsConnected)
        {
            throw new InvalidOperationException(AppResources.Get("ConnectFirst", "Connect to Microsoft Graph first."));
        }
    }
}
