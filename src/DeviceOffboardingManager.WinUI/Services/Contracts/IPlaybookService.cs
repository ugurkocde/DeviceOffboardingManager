using DeviceOffboardingManager.WinUI.Models;

namespace DeviceOffboardingManager.WinUI.Services.Contracts;

public interface IPlaybookService
{
    IReadOnlyList<PlaybookDefinition> Definitions { get; }

    Task<PlaybookRunResult> RunAsync(string playbookId, string? parameter = null, CancellationToken cancellationToken = default);
}
