using System.Collections.ObjectModel;
using System.ComponentModel;
using DeviceOffboardingManager.WinUI.Models;

namespace DeviceOffboardingManager.WinUI.Services;

public sealed class DeviceListState
{
    private bool _suppressSelectionNotification;
    private string? _complianceFilter;
    private string? _deviceNameFilter;
    private string? _operatingSystemFilter;
    private string? _serialFilter;
    private string? _userFilter;

    public List<DeviceRecord> AllDevices { get; } = new();

    public ObservableCollection<DeviceRecord> VisibleDevices { get; } = new();

    public IReadOnlyList<DeviceRecord> LastDashboardDevices { get; private set; } = Array.Empty<DeviceRecord>();

    public string LastDashboardTitle { get; private set; } = "Dashboard drilldown";

    public OffboardingSummary? LastOffboardingSummary { get; set; }

    public PlaybookRunResult? LastPlaybookResult { get; set; }

    public event Action? DeviceListChanged;

    public event Action? SelectionChanged;

    public event Action? DashboardResultsChanged;

    public void ReplaceDeviceList(IReadOnlyList<DeviceRecord> devices)
    {
        foreach (var device in AllDevices)
        {
            device.PropertyChanged -= Device_PropertyChanged;
        }

        AllDevices.Clear();
        AllDevices.AddRange(devices);

        foreach (var device in AllDevices)
        {
            device.PropertyChanged += Device_PropertyChanged;
        }

        ApplyDeviceFilters(
            _deviceNameFilter,
            _serialFilter,
            _operatingSystemFilter,
            _userFilter,
            _complianceFilter);
    }

    public void ClearDeviceList()
    {
        ReplaceDeviceList(Array.Empty<DeviceRecord>());
    }

    public void ApplyDeviceFilters(
        string? deviceName,
        string? serialNumber,
        string? operatingSystem,
        string? primaryUser,
        string? complianceState)
    {
        _deviceNameFilter = deviceName;
        _serialFilter = serialNumber;
        _operatingSystemFilter = operatingSystem;
        _userFilter = primaryUser;
        _complianceFilter = complianceState;

        var filtered = AllDevices.Where(device =>
            Contains(device.DeviceName, _deviceNameFilter)
            && Contains(device.SerialNumber, _serialFilter)
            && Contains(device.OperatingSystem, _operatingSystemFilter)
            && Contains(device.PrimaryUser, _userFilter)
            && Contains(device.ComplianceState, _complianceFilter)).ToArray();

        VisibleDevices.Clear();
        foreach (var device in filtered)
        {
            VisibleDevices.Add(device);
        }

        DeviceListChanged?.Invoke();
        SelectionChanged?.Invoke();
    }

    public void SelectVisibleDevices(bool isSelected)
    {
        _suppressSelectionNotification = true;
        try
        {
            foreach (var device in VisibleDevices)
            {
                device.IsSelected = isSelected;
            }
        }
        finally
        {
            _suppressSelectionNotification = false;
        }

        SelectionChanged?.Invoke();
    }

    public IReadOnlyList<DeviceRecord> GetSelectedDevices()
    {
        return AllDevices.Where(device => device.IsSelected).ToArray();
    }

    public IReadOnlyList<DeviceRecord> GetSelectedOrVisibleDevices()
    {
        var selected = GetSelectedDevices();
        return selected.Count > 0 ? selected : VisibleDevices.ToArray();
    }

    public string GetSearchStatusText()
    {
        return $"{VisibleDevices.Count:n0} visible of {AllDevices.Count:n0} loaded device(s).";
    }

    public string GetSelectedSummaryText()
    {
        var selected = GetSelectedDevices();
        return selected.Count == 0
            ? "No devices selected."
            : $"{selected.Count:n0} selected device(s). Visible: {VisibleDevices.Count:n0}; loaded: {AllDevices.Count:n0}.";
    }

    public string GetOffboardingStatusText()
    {
        var selected = GetSelectedDevices();
        return selected.Count == 0
            ? "Select devices before running actions."
            : $"{selected.Count:n0} selected device(s) ready for offboarding review.";
    }

    public void SetDashboardResults(string title, IReadOnlyList<DeviceRecord> devices)
    {
        LastDashboardTitle = title;
        LastDashboardDevices = devices;
        DashboardResultsChanged?.Invoke();
    }

    private void Device_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (_suppressSelectionNotification || e.PropertyName != nameof(DeviceRecord.IsSelected))
        {
            return;
        }

        SelectionChanged?.Invoke();
    }

    private static bool Contains(string? value, string? filter)
    {
        return string.IsNullOrWhiteSpace(filter)
            || (value?.Contains(filter.Trim(), StringComparison.OrdinalIgnoreCase) ?? false);
    }
}
