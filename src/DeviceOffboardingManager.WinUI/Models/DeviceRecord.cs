using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace DeviceOffboardingManager.WinUI.Models;

public sealed class DeviceRecord : INotifyPropertyChanged
{
    private bool _isSelected;

    public bool IsSelected
    {
        get => _isSelected;
        set
        {
            if (_isSelected == value)
            {
                return;
            }

            _isSelected = value;
            OnPropertyChanged();
        }
    }

    public string? DeviceName { get; init; }

    public string? SerialNumber { get; init; }

    public string? OperatingSystem { get; init; }

    public string? PrimaryUser { get; init; }

    public DateTimeOffset? AzureAdLastContact { get; init; }

    public DateTimeOffset? IntuneLastContact { get; init; }

    public DateTimeOffset? AutopilotLastContact { get; init; }

    public string? EntraDeviceId { get; init; }

    public string? EntraDeviceObjectId { get; init; }

    public string? IntuneDeviceId { get; init; }

    public string? AutopilotIdentityId { get; init; }

    public string? EntraAccountEnabled { get; init; }

    public string? ComplianceState { get; init; }

    public string? MdeDeviceId { get; set; }

    public string? ManagementAgent { get; init; }

    public string ServiceSummary
    {
        get
        {
            var services = new List<string>();
            if (!string.IsNullOrWhiteSpace(EntraDeviceId))
            {
                services.Add("Entra");
            }

            if (!string.IsNullOrWhiteSpace(IntuneDeviceId))
            {
                services.Add("Intune");
            }

            if (!string.IsNullOrWhiteSpace(AutopilotIdentityId))
            {
                services.Add("Autopilot");
            }

            if (!string.IsNullOrWhiteSpace(MdeDeviceId))
            {
                services.Add("Defender");
            }

            return services.Count == 0 ? "Not resolved" : string.Join(", ", services);
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
