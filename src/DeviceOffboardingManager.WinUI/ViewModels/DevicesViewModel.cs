using System.Collections.ObjectModel;
using System.Text;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services;
using DeviceOffboardingManager.WinUI.Services.Contracts;

namespace DeviceOffboardingManager.WinUI.ViewModels;

public sealed partial class DevicesViewModel : AppViewModelBase
{
    private readonly IAuthenticationService _authenticationService;
    private readonly IDeviceInventoryService _deviceInventoryService;
    private readonly IReportExportService _reportExportService;
    private readonly IStatusService _statusService;
    private readonly DeviceListState _deviceListState;

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
    private int searchModeIndex;

    [ObservableProperty]
    private string searchText = string.Empty;

    [ObservableProperty]
    private string filterDeviceName = string.Empty;

    [ObservableProperty]
    private string filterSerial = string.Empty;

    [ObservableProperty]
    private string filterOs = string.Empty;

    [ObservableProperty]
    private string filterUser = string.Empty;

    [ObservableProperty]
    private string filterCompliance = string.Empty;

    [ObservableProperty]
    private string searchStatusText = "No devices searched yet.";

    [RelayCommand]
    private async Task SearchAsync()
    {
        await RunAsync("Searching devices", SearchCurrentTermsAsync);
    }

    [RelayCommand]
    private void ClearSearch()
    {
        SearchText = string.Empty;
        _deviceListState.ClearDeviceList();
        SearchStatusText = "No devices searched yet.";
        _statusService.Report("Device list cleared", "Search terms and results were cleared.", StatusSeverity.Informational);
    }

    [RelayCommand]
    private void ResetFilters()
    {
        FilterDeviceName = string.Empty;
        FilterSerial = string.Empty;
        FilterOs = string.Empty;
        FilterUser = string.Empty;
        FilterCompliance = string.Empty;
        ApplyFilters();
    }

    [RelayCommand]
    private async Task ExportCsvAsync()
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
    private async Task DownloadBulkTemplateAsync()
    {
        await RunAsync("Saving import template", async () =>
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
            _statusService.Report("Template saved", path, StatusSeverity.Success);
        });
    }

    public void SelectAllVisibleDevices(bool isSelected)
    {
        _deviceListState.SelectVisibleDevices(isSelected);
    }

    public async Task ImportSearchTermsAsync(IReadOnlyList<string> terms)
    {
        await RunAsync("Importing search terms", async () =>
        {
            SearchText = string.Join(Environment.NewLine, terms);
            if (_authenticationService.IsConnected)
            {
                await SearchCurrentTermsAsync();
            }
            else
            {
                _statusService.Report("Bulk terms imported", $"Imported {terms.Count:n0} search term(s). Connect before searching.", StatusSeverity.Success);
            }
        });
    }

    public async Task<(DeviceRecord Device, IReadOnlyList<GroupMembershipRecord> Groups)?> LoadSelectedGroupsForDialogAsync()
    {
        return await RunAsync("Loading group memberships", async () =>
        {
            EnsureConnected();
            var selected = _deviceListState.GetSelectedDevices();
            if (selected.Count != 1)
            {
                throw new InvalidOperationException("Select exactly one device with a resolved Entra object ID.");
            }

            var groups = await _deviceInventoryService.GetDeviceGroupMembershipsAsync(selected[0]);
            _statusService.Report("Group memberships loaded", $"{groups.Count:n0} group(s) found for {selected[0].DeviceName ?? "the selected device"}.", StatusSeverity.Success);
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
        ApplyFilters();
    }

    partial void OnFilterSerialChanged(string value)
    {
        ApplyFilters();
    }

    partial void OnFilterOsChanged(string value)
    {
        ApplyFilters();
    }

    partial void OnFilterUserChanged(string value)
    {
        ApplyFilters();
    }

    partial void OnFilterComplianceChanged(string value)
    {
        ApplyFilters();
    }

    private async Task SearchCurrentTermsAsync()
    {
        EnsureConnected();
        var terms = ParseSearchTerms(SearchText);
        if (terms.Count == 0)
        {
            throw new InvalidOperationException("Enter at least one search term.");
        }

        var result = await _deviceInventoryService.SearchDevicesAsync(terms, GetSearchOption());
        _deviceListState.ReplaceDeviceList(result.Devices);
        SearchStatusText = $"{result.Devices.Count:n0} device(s) found. Intune: {result.IntuneCount:n0}; Autopilot: {result.AutopilotCount:n0}; Entra ID: {result.EntraCount:n0}.";
        _statusService.Report("Search complete", SearchStatusText, StatusSeverity.Success);
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
            throw new InvalidOperationException("Connect to Microsoft Graph first.");
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
