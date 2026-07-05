using CommunityToolkit.Mvvm.ComponentModel;
using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services.Contracts;

namespace DeviceOffboardingManager.WinUI.ViewModels;

public abstract partial class AppViewModelBase : ObservableObject
{
    private readonly IAuditLogService _auditLogService;

    protected AppViewModelBase(IStatusService statusService, IAuditLogService auditLogService)
    {
        StatusService = statusService;
        _auditLogService = auditLogService;
    }

    protected IStatusService StatusService { get; }

    [ObservableProperty]
    private bool isBusy;

    protected async Task RunAsync(string title, Func<Task> action)
    {
        await RunAsync<object?>(title, async () =>
        {
            await action();
            return null;
        });
    }

    protected async Task<T?> RunAsync<T>(string title, Func<Task<T>> action)
    {
        if (IsBusy)
        {
            return default;
        }

        try
        {
            IsBusy = true;
            StatusService.Report(title, "Working...", StatusSeverity.Informational);
            return await action();
        }
        catch (Exception ex)
        {
            await ReportExceptionAsync(title, ex);
            return default;
        }
        finally
        {
            IsBusy = false;
        }
    }

    public async Task ReportExceptionAsync(string title, Exception exception)
    {
        StatusService.Report(title, exception.Message, StatusSeverity.Error);
        await _auditLogService.WriteAsync($"{title} failed: {exception}", "ERROR");
    }
}
