using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using DeviceOffboardingManager.WinUI.Services;
using DeviceOffboardingManager.WinUI.Services.Contracts;

namespace DeviceOffboardingManager.WinUI.ViewModels;

public sealed partial class HomeViewModel : AppViewModelBase
{
    private readonly SettingsViewModel _settingsViewModel;
    private readonly ShellNavigationService _navigationService;
    private readonly ConnectionState _connectionState;

    public HomeViewModel(
        SettingsViewModel settingsViewModel,
        ShellNavigationService navigationService,
        ConnectionState connectionState,
        IStatusService statusService,
        IAuditLogService auditLogService)
        : base(statusService, auditLogService)
    {
        _settingsViewModel = settingsViewModel;
        _navigationService = navigationService;
        _connectionState = connectionState;
        RefreshConnectionState();
        _connectionState.Changed += RefreshConnectionState;
    }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsDisconnected))]
    private bool isConnected;

    public bool IsDisconnected => !IsConnected;

    [RelayCommand(CanExecute = nameof(CanConnect))]
    private async Task ConnectAsync()
    {
        await RunAsync("Connecting", _settingsViewModel.ConnectWithCurrentSettingsAsync);
    }

    [RelayCommand]
    private void GoToDevices()
    {
        _navigationService.Navigate("devices");
    }

    private void RefreshConnectionState()
    {
        IsConnected = _connectionState.IsConnected;
    }

    partial void OnIsConnectedChanged(bool value)
    {
        OnPropertyChanged(nameof(IsDisconnected));
        ConnectCommand.NotifyCanExecuteChanged();
    }

    private bool CanConnect()
    {
        return !IsConnected;
    }
}
