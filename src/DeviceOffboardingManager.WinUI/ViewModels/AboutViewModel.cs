using System.Diagnostics;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services.Contracts;

namespace DeviceOffboardingManager.WinUI.ViewModels;

public sealed partial class AboutViewModel : AppViewModelBase
{
    private static readonly HttpClient UpdateHttpClient = new();
    private readonly IStatusService _statusService;

    public AboutViewModel(IStatusService statusService, IAuditLogService auditLogService)
        : base(statusService, auditLogService)
    {
        _statusService = statusService;
        AboutVersionText = $"Version {AppInfo.Version} native Windows app track";

        if (!UpdateHttpClient.DefaultRequestHeaders.UserAgent.Any())
        {
            UpdateHttpClient.DefaultRequestHeaders.UserAgent.ParseAdd($"DeviceOffboardingManager-WinUI/{AppInfo.Version}");
        }
    }

    [ObservableProperty]
    private string aboutVersionText;

    [RelayCommand]
    private async Task OpenRepositoryAsync()
    {
        await RunAsync("Opening repository", () =>
        {
            OpenUrl("https://github.com/ugurkocde/DeviceOffboardingManager");
            return Task.CompletedTask;
        });
    }

    public async Task<string?> LoadChangelogForDialogAsync()
    {
        return await RunAsync("Opening changelog", async () =>
        {
            var candidates = new[]
            {
                Path.Combine(AppContext.BaseDirectory, "Changelog.md"),
                Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Changelog.md"))
            };
            var changelogPath = candidates.FirstOrDefault(File.Exists);
            if (changelogPath is null)
            {
                _statusService.Report("Changelog unavailable", "Changelog.md was not found in the app output or repository root.", StatusSeverity.Warning);
                return null;
            }

            return await File.ReadAllTextAsync(changelogPath);
        });
    }

    public async Task<UpdateCheckResult?> CheckForUpdatesForDialogAsync()
    {
        return await RunAsync("Checking for updates", async () =>
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, "https://api.github.com/repos/ugurkocde/DeviceOffboardingManager/releases/latest");
            using var response = await UpdateHttpClient.SendAsync(request);
            var responseText = await response.Content.ReadAsStringAsync();
            if (!response.IsSuccessStatusCode)
            {
                throw new InvalidOperationException($"GitHub update check failed with HTTP {(int)response.StatusCode}: {responseText}");
            }

            var latestTag = JsonNode.Parse(responseText)?["tag_name"]?.GetValue<string>();
            var latestVersion = TryParseVersion(latestTag);
            var currentVersion = TryParseVersion(AppInfo.Version);
            if (latestVersion is null || currentVersion is null)
            {
                var fallbackMessage = $"Latest release tag: {latestTag ?? "(unknown)"}. Current app: {AppInfo.Version}.";
                _statusService.Report("Update check complete", fallbackMessage, StatusSeverity.Informational);
                return new UpdateCheckResult(fallbackMessage, false);
            }

            var updateAvailable = latestVersion.CompareTo(currentVersion) > 0;
            var message = updateAvailable
                ? $"A newer release is available: {latestTag}. Current app: {AppInfo.Version}."
                : $"You are on the current or newer app track. Latest release: {latestTag}; current app: {AppInfo.Version}.";

            _statusService.Report("Update check complete", message, updateAvailable ? StatusSeverity.Warning : StatusSeverity.Success);
            return new UpdateCheckResult(message, updateAvailable);
        });
    }

    public void OpenReleases()
    {
        OpenUrl("https://github.com/ugurkocde/DeviceOffboardingManager/releases");
    }

    private static Version? TryParseVersion(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return null;
        }

        var match = Regex.Match(text, @"\d+(\.\d+){0,3}");
        return match.Success && Version.TryParse(match.Value, out var version) ? version : null;
    }

    private static void OpenUrl(string url)
    {
        Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
    }
}
