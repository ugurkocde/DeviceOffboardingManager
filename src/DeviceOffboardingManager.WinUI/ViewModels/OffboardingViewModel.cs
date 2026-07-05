using System.ComponentModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services;
using DeviceOffboardingManager.WinUI.Services.Contracts;

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
    private string selectedDeviceCountText = "No devices selected.";

    [ObservableProperty]
    private string offboardingStatusText = "Select devices before running actions.";

    [ObservableProperty]
    private bool deleteEntra = true;

    [ObservableProperty]
    private bool disableEntra;

    [ObservableProperty]
    private bool deleteIntune = true;

    [ObservableProperty]
    private bool deleteAutopilot = true;

    [ObservableProperty]
    private bool offboardDefender;

    [ObservableProperty]
    private bool isDefenderControlEnabled;

    [ObservableProperty]
    private int preActionIndex;

    [ObservableProperty]
    private string groupTag = string.Empty;

    [RelayCommand]
    private async Task ExportSelectedAsync()
    {
        await RunAsync("Exporting CSV", async () =>
        {
            var devices = _deviceListState.GetSelectedOrVisibleDevices();
            if (devices.Count == 0)
            {
                throw new InvalidOperationException("No devices are available to export.");
            }

            var path = await _reportExportService.ExportDeviceCsvAsync(devices);
            _statusService.Report("CSV exported", path, StatusSeverity.Success);
        });
    }

    [RelayCommand]
    private async Task SetGroupTagAsync()
    {
        await RunAsync("Setting group tag", async () =>
        {
            EnsureConnected();
            var selected = _deviceListState.GetSelectedDevices();
            if (selected.Count == 0)
            {
                throw new InvalidOperationException("Select at least one device.");
            }

            var result = await _deviceInventoryService.SetAutopilotGroupTagAsync(selected, GroupTag);
            _statusService.Report("Group tag update complete", $"Updated: {result.Updated:n0}; Failed: {result.Failed:n0}.", result.Failed == 0 ? StatusSeverity.Success : StatusSeverity.Warning);
        });
    }

    [RelayCommand]
    private async Task ExportReportAsync()
    {
        await RunAsync("Exporting report", async () =>
        {
            if (_deviceListState.LastOffboardingSummary is null)
            {
                throw new InvalidOperationException("Run an offboarding operation before exporting the HTML report.");
            }

            var path = await _reportExportService.ExportOffboardingHtmlAsync(_deviceListState.LastOffboardingSummary);
            _statusService.Report("Report exported", path, StatusSeverity.Success);
        });
    }

    public IReadOnlyList<DeviceRecord> GetSelectedDevices()
    {
        return _deviceListState.GetSelectedDevices();
    }

    public async Task<IReadOnlyList<RecoveryKeyRecord>?> FetchRecoveryKeysForDialogAsync()
    {
        return await RunAsync("Fetching recovery keys", async () =>
        {
            EnsureConnected();
            var selected = _deviceListState.GetSelectedDevices();
            if (selected.Count == 0)
            {
                throw new InvalidOperationException("Select at least one device.");
            }

            var keys = await _recoveryKeyService.GetRecoveryKeysAsync(selected);
            var found = keys.Count(key => !string.IsNullOrWhiteSpace(key.KeyValue));
            OffboardingStatusText = $"Recovery key lookup complete. Records: {keys.Count:n0}; values found: {found:n0}. Values are shown once and are not written to logs.";
            _statusService.Report("Recovery key lookup complete", OffboardingStatusText, found > 0 ? StatusSeverity.Success : StatusSeverity.Informational);
            return keys;
        });
    }

    public async Task<OffboardingSummary?> RunConfirmedOffboardingAsync()
    {
        return await RunAsync("Running offboarding", async () =>
        {
            EnsureConnected();
            var selected = _deviceListState.GetSelectedDevices();
            if (selected.Count == 0)
            {
                throw new InvalidOperationException("Select at least one device.");
            }

            var summary = await _offboardingService.OffboardAsync(selected, BuildOffboardingOptions());
            _deviceListState.LastOffboardingSummary = summary;
            OffboardingStatusText = $"Offboarding complete. Devices: {summary.TotalDevices:n0}; successful: {summary.SuccessfulDevices:n0}; failed/partial: {summary.FailedDevices:n0}.";
            _statusService.Report("Offboarding complete", OffboardingStatusText, summary.FailedDevices == 0 ? StatusSeverity.Success : StatusSeverity.Warning);
            return summary;
        });
    }

    public async Task ExportSummaryAsync(OffboardingSummary summary)
    {
        await RunAsync("Exporting report", async () =>
        {
            var path = await _reportExportService.ExportOffboardingHtmlAsync(summary);
            _statusService.Report("Report exported", path, StatusSeverity.Success);
        });
    }

    public void ReportOffboardingCanceled()
    {
        _statusService.Report("Offboarding canceled", "No changes were made.", StatusSeverity.Informational);
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
            throw new InvalidOperationException("Connect to Microsoft Graph first.");
        }
    }
}
