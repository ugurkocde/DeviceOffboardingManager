using System.Runtime.InteropServices;
using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services;
using DeviceOffboardingManager.WinUI.Services.Contracts;
using DeviceOffboardingManager.WinUI.Views;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Graphics;
using WinRT.Interop;

namespace DeviceOffboardingManager.WinUI;

public sealed partial class MainWindow : Window
{
    private readonly IStatusService _statusService;
    private readonly ShellNavigationService _navigationService;

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr hWnd);

    public MainWindow()
    {
        _statusService = App.Services.GetRequiredService<IStatusService>();
        _navigationService = App.Services.GetRequiredService<ShellNavigationService>();

        InitializeComponent();
        SystemBackdrop = new MicaBackdrop();
        Title = $"Device Offboarding Manager {AppInfo.Version}";

        var hwnd = WindowNative.GetWindowHandle(this);
        App.Services.GetRequiredService<WindowHandleProvider>().MainWindowHandle = hwnd;

        var scale = GetDpiForWindow(hwnd) / 96.0;
        AppWindow.Resize(new SizeInt32((int)(1280 * scale), (int)(800 * scale)));

        _statusService.StatusReported += OnStatusReported;
        _navigationService.NavigationRequested += NavigateToTag;

        RootNavigation.SelectedItem = NavHome;
        NavigateToTag("home");
    }

    private void RootNavigation_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.IsSettingsSelected)
        {
            NavigateToTag("settings");
            return;
        }

        if (args.SelectedItemContainer?.Tag is string tag)
        {
            NavigateToTag(tag);
        }
    }

    private void NavigateToTag(string tag)
    {
        var pageType = tag switch
        {
            "home" => typeof(HomePage),
            "dashboard" => typeof(DashboardPage),
            "devices" => typeof(DevicesPage),
            "offboarding" => typeof(OffboardingPage),
            "playbooks" => typeof(PlaybooksPage),
            "settings" => typeof(SettingsPage),
            "about" => typeof(AboutPage),
            _ => typeof(HomePage)
        };

        RootNavigation.SelectedItem = tag switch
        {
            "home" => NavHome,
            "dashboard" => NavDashboard,
            "devices" => NavDevices,
            "offboarding" => NavOffboarding,
            "playbooks" => NavPlaybooks,
            "settings" => RootNavigation.SettingsItem,
            "about" => NavAbout,
            _ => NavHome
        };

        if (ContentFrame.CurrentSourcePageType != pageType)
        {
            ContentFrame.Navigate(pageType);
        }
    }

    private void OnStatusReported(StatusReport report)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            StatusInfoBar.Title = report.Title;
            StatusInfoBar.Message = report.Message;
            StatusInfoBar.Severity = report.Severity switch
            {
                StatusSeverity.Success => InfoBarSeverity.Success,
                StatusSeverity.Warning => InfoBarSeverity.Warning,
                StatusSeverity.Error => InfoBarSeverity.Error,
                _ => InfoBarSeverity.Informational
            };
            StatusInfoBar.IsOpen = true;
        });
    }
}
