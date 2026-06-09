function Initialize-DeviceObjectType {
    if (-not ([System.Management.Automation.PSTypeName]'DeviceObject').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;

public class DeviceObject : INotifyPropertyChanged
{
    private bool isSelected;
    public bool IsSelected
    {
        get { return isSelected; }
        set
        {
            isSelected = value;
            OnPropertyChanged("IsSelected");
        }
    }

    public string DeviceName { get; set; }
    public string SerialNumber { get; set; }
    public string OperatingSystem { get; set; }
    public string PrimaryUser { get; set; }
    public DateTime? AzureADLastContact { get; set; }
    public DateTime? IntuneLastContact { get; set; }
    public DateTime? AutopilotLastContact { get; set; }

    // Graph IDs captured at search time for safe ID-based offboarding
    public string EntraDeviceId { get; set; }
    public string EntraDeviceObjectId { get; set; }
    public string IntuneDeviceId { get; set; }
    public string AutopilotIdentityId { get; set; }
    public string EntraAccountEnabled { get; set; }
    public string ComplianceState { get; set; }
    public string MdeDeviceId { get; set; }
    public string ManagementAgent { get; set; }

    public event PropertyChangedEventHandler PropertyChanged;

    protected void OnPropertyChanged(string name)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }
}
"@
    }
}
