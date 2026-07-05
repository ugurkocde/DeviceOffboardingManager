using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services;
using DeviceOffboardingManager.WinUI.Services.Contracts;
using DeviceOffboardingManager.WinUI.ViewModels;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace DeviceOffboardingManager.WinUI.Views;

public sealed partial class SettingsPage : Page
{
    private readonly IStatusService _statusService;
    private readonly WindowHandleProvider _windowHandleProvider;

    public SettingsPage()
    {
        ViewModel = App.Services.GetRequiredService<SettingsViewModel>();
        _statusService = App.Services.GetRequiredService<IStatusService>();
        _windowHandleProvider = App.Services.GetRequiredService<WindowHandleProvider>();
        InitializeComponent();
    }

    public SettingsViewModel ViewModel { get; }

    private async void BrowseConfig_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var path = await PickFilePathAsync(".json");
            if (!string.IsNullOrWhiteSpace(path))
            {
                ViewModel.ConfigPath = path;
                _statusService.Report("Config selected", path, StatusSeverity.Informational);
            }
        }
        catch (Exception ex)
        {
            await ViewModel.ReportExceptionAsync("Selecting config", ex);
        }
    }

    private async Task<string?> PickFilePathAsync(params string[] extensions)
    {
        var picker = new FileOpenPicker();
        foreach (var extension in extensions)
        {
            picker.FileTypeFilter.Add(extension);
        }

        InitializeWithWindow.Initialize(picker, _windowHandleProvider.MainWindowHandle);
        var file = await picker.PickSingleFileAsync();
        return file?.Path;
    }
}
