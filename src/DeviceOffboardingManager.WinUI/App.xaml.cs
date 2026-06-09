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

        services.AddSingleton<Services.Contracts.IAuditLogService, Services.AuditLogService>();
        services.AddSingleton<Services.Contracts.ISettingsService, Services.SettingsService>();
        services.AddSingleton<Services.Contracts.IAuthenticationService, Services.AuthenticationService>();
        services.AddSingleton<Services.Graph.GraphApiClient>();
        services.AddSingleton<Services.Defender.DefenderApiClient>();
        services.AddSingleton<Services.Contracts.IDeviceInventoryService, Services.DeviceInventoryService>();
        services.AddSingleton<Services.Contracts.IOffboardingService, Services.OffboardingService>();
        services.AddSingleton<Services.Contracts.IRecoveryKeyService, Services.RecoveryKeyService>();
        services.AddSingleton<Services.Contracts.IPlaybookService, Services.PlaybookService>();
        services.AddSingleton<Services.Contracts.IReportExportService, Services.ReportExportService>();

        return services.BuildServiceProvider();
    }
}
