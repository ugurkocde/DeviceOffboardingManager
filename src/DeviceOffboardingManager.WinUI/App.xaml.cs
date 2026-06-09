using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;

namespace DeviceOffboardingManager.WinUI;

public partial class App : Application
{
    private Window? _window;

    public App()
    {
        Services = ConfigureServices();
        InitializeComponent();
    }

    public static IServiceProvider Services { get; private set; } = default!;

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new MainWindow();
        _window.Activate();
    }

    private static IServiceProvider ConfigureServices()
    {
        var services = new ServiceCollection();

        services.AddSingleton<Services.Contracts.ISettingsService, Services.Placeholders.SettingsService>();
        services.AddSingleton<Services.Contracts.IAuthenticationService, Services.Placeholders.AuthenticationService>();
        services.AddSingleton<Services.Contracts.IDeviceInventoryService, Services.Placeholders.DeviceInventoryService>();
        services.AddSingleton<Services.Contracts.IOffboardingService, Services.Placeholders.OffboardingService>();

        return services.BuildServiceProvider();
    }
}
