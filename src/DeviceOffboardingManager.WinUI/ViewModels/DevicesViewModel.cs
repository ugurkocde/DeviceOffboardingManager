using System.Collections.ObjectModel;
using System.Text;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services;
using DeviceOffboardingManager.WinUI.Services.Contracts;
using DeviceOffboardingManager.WinUI.Utilities;

namespace DeviceOffboardingManager.WinUI.ViewModels;

public sealed partial class DevicesViewModel : AppViewModelBase
{
    private readonly IAuthenticationService _authenticationService;
    private readonly IDeviceInventoryService _deviceInventoryService;
    private readonly IReportExportService _reportExportService;
    private readonly IStatusService _statusService;
    private readonly DeviceListState _deviceListState;
    private CancellationTokenSource? _filterDebounce;
    private bool _suppressFilterDebounce;

    public DevicesViewModel(
        IAuthenticationService authenticationService,
        IDeviceInventoryService deviceInventoryService,
        IReportExportService reportExportService,
        IStatusService statusService,
        IAuditLogService auditLogService,
        DeviceListState deviceListState)
        : base(statusService, auditLogService)
    {
        _authenticationService = authenticationService;
        _deviceInventoryService = deviceInventoryService;
        _reportExportService = reportExportService;
        _statusService = statusService;
        _deviceListState = deviceListState;
        _deviceListState.DeviceListChanged += RefreshSearchStatusFromState;
        RefreshSearchStatusFromState();
    }

    public ObservableCollection<DeviceRecord> VisibleDevices => _deviceListState.VisibleDevices;

    [ObservableProperty]
    public partial int SearchModeIndex { get; set; }

    [ObservableProperty]
    public partial string SearchText { get; set; } = string.Empty;

    [ObservableProperty]
    public partial string FilterDeviceName { get; set; } = string.Empty;

    [ObservableProperty]
    public partial string FilterSerial { get; set; } = string.Empty;

    [ObservableProperty]
    public partial string FilterOs { get; set; } = string.Empty;

    [ObservableProperty]
    public partial string FilterUser { get; set; } = string.Empty;

    [ObservableProperty]
    public partial string FilterCompliance { get; set; } = string.Empty;

    [ObservableProperty]
    public partial string SearchStatusText { get; set; } = AppResources.Get("NoDevicesSearched", "No devices searched yet.");

    [RelayCommand]
    private async Task SearchAsync()
    {
        await RunAsync(AppResources.Get("SearchingDevices", "Searching devices"), SearchCurrentTermsAsync);
    }

    [RelayCommand]
    private void ClearSearch()
    {
        SearchText = string.Empty;
        _deviceListState.ClearDeviceList();
        SearchStatusText = AppResources.Get("NoDevicesSearched", "No devices searched yet.");
        _statusService.Report(
            AppResources.Get("DeviceListClearedTitle", "Device list cleared"),
            AppResources.Get("DeviceListClearedMessage", "Search terms and results were cleared."),
            StatusSeverity.Informational);
    }

    [RelayCommand]
    private void ResetFilters()
    {
        _suppressFilterDebounce = true;
        try
        {
            FilterDeviceName = string.Empty;
            FilterSerial = string.Empty;
            FilterOs = string.Empty;
            FilterUser = string.Empty;
            FilterCompliance = string.Empty;
        }
        finally
        {
            _suppressFilterDebounce = false;
        }

        ApplyFiltersImmediately();
    }

    [RelayCommand]
    private async Task ExportCsvAsync()
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
    private async Task DownloadBulkTemplateAsync()
    {
        await RunAsync(AppResources.Get("SavingImportTemplate", "Saving import template"), async () =>
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
            _statusService.Report(AppResources.Get("TemplateSavedTitle", "Template saved"), path, StatusSeverity.Success);
        });
    }

    public void SelectAllVisibleDevices(bool isSelected)
    {
        _deviceListState.SelectVisibleDevices(isSelected);
    }

    public async Task ImportSearchTermsAsync(IReadOnlyList<string> terms)
    {
        await RunAsync(AppResources.Get("ImportingSearchTerms", "Importing search terms"), async () =>
        {
            SearchText = string.Join(Environment.NewLine, terms);
            if (_authenticationService.IsConnected)
            {
                await SearchCurrentTermsAsync();
            }
            else
            {
                _statusService.Report(
                    AppResources.Get("BulkTermsImportedTitle", "Bulk terms imported"),
                    AppResources.Format("BulkImportImportedFormat", "Imported {0:N0} search term(s). Connect before searching.", terms.Count),
                    StatusSeverity.Success);
            }
        });
    }

    public async Task<(DeviceRecord Device, IReadOnlyList<GroupMembershipRecord> Groups)?> LoadSelectedGroupsForDialogAsync()
    {
        return await RunAsync(AppResources.Get("LoadingGroupMemberships", "Loading group memberships"), async () =>
        {
            EnsureConnected();
            var selected = _deviceListState.GetSelectedDevices();
            if (selected.Count != 1)
            {
                throw new InvalidOperationException(AppResources.Get("SelectExactlyOneDevice", "Select exactly one device with a resolved Entra object ID."));
            }

            var groups = await _deviceInventoryService.GetDeviceGroupMembershipsAsync(selected[0]);
            _statusService.Report(
                AppResources.Get("GroupMembershipsLoaded", "Group memberships loaded"),
                AppResources.Format(
                    "GroupMembershipsLoadedFormat",
                    "{0:N0} group(s) found for {1}.",
                    groups.Count,
                    selected[0].DeviceName ?? AppResources.Get("SelectedDeviceFallback", "the selected device")),
                StatusSeverity.Success);
            return (selected[0], groups);
        });
    }

    public IReadOnlyList<DeviceRecord> GetSelectedDevices()
    {
        return _deviceListState.GetSelectedDevices();
    }

    public static async Task<IReadOnlyList<string>> ParseBulkImportFileAsync(string path)
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

    partial void OnFilterDeviceNameChanged(string value)
    {
        QueueFilterUpdate();
    }

    partial void OnFilterSerialChanged(string value)
    {
        QueueFilterUpdate();
    }

    partial void OnFilterOsChanged(string value)
    {
        QueueFilterUpdate();
    }

    partial void OnFilterUserChanged(string value)
    {
        QueueFilterUpdate();
    }

    partial void OnFilterComplianceChanged(string value)
    {
        QueueFilterUpdate();
    }

    private async Task SearchCurrentTermsAsync()
    {
        EnsureConnected();
        var terms = ParseSearchTerms(SearchText);
        if (terms.Count == 0)
        {
            throw new InvalidOperationException(AppResources.Get("SearchTermsRequired", "Enter at least one search term."));
        }

        var result = await _deviceInventoryService.SearchDevicesAsync(terms, GetSearchOption());
        _deviceListState.ReplaceDeviceList(result.Devices);
        SearchStatusText = AppResources.Format(
            "SearchCompleteFormat",
            "{0:N0} device(s) found. Intune: {1:N0}; Autopilot: {2:N0}; Entra ID: {3:N0}.",
            result.Devices.Count,
            result.IntuneCount,
            result.AutopilotCount,
            result.EntraCount);
        _statusService.Report(AppResources.Get("SearchComplete", "Search complete"), SearchStatusText, StatusSeverity.Success);
    }

    private void ApplyFilters()
    {
        _deviceListState.ApplyDeviceFilters(
            FilterDeviceName,
            FilterSerial,
            FilterOs,
            FilterUser,
            FilterCompliance);
    }

    private void ApplyFiltersImmediately()
    {
        _filterDebounce?.Cancel();
        _filterDebounce?.Dispose();
        _filterDebounce = null;
        ApplyFilters();
    }

    private void QueueFilterUpdate()
    {
        if (_suppressFilterDebounce)
        {
            return;
        }

        _filterDebounce?.Cancel();
        _filterDebounce?.Dispose();
        _filterDebounce = new CancellationTokenSource();
        _ = ApplyFiltersAfterDelayAsync(_filterDebounce.Token);
    }

    private async Task ApplyFiltersAfterDelayAsync(CancellationToken cancellationToken)
    {
        try
        {
            await Task.Delay(200, cancellationToken);
            ApplyFilters();
        }
        catch (OperationCanceledException)
        {
            // A newer filter value superseded this update.
        }
    }

    private void RefreshSearchStatusFromState()
    {
        if (_deviceListState.AllDevices.Count > 0)
        {
            SearchStatusText = _deviceListState.GetSearchStatusText();
        }
    }

    private DeviceSearchOption GetSearchOption()
    {
        return SearchModeIndex switch
        {
            1 => DeviceSearchOption.SerialNumber,
            2 => DeviceSearchOption.DeviceId,
            3 => DeviceSearchOption.Contains,
            _ => DeviceSearchOption.DeviceName
        };
    }

    private void EnsureConnected()
    {
        if (!_authenticationService.IsConnected)
        {
            throw new InvalidOperationException(AppResources.Get("ConnectFirst", "Connect to Microsoft Graph first."));
        }
    }

    private static IReadOnlyList<string> ParseSearchTerms(string? text)
    {
        return (text ?? string.Empty)
            .Split(new[] { ',', '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(term => !string.IsNullOrWhiteSpace(term))
            .ToArray();
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
}
