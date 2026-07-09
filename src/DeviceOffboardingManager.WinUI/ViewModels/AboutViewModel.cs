using System.Diagnostics;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services.Contracts;
using DeviceOffboardingManager.WinUI.Utilities;

namespace DeviceOffboardingManager.WinUI.ViewModels;

public sealed partial class AboutViewModel : AppViewModelBase
{
    private readonly HttpClient _httpClient;
    private readonly IStatusService _statusService;

    public AboutViewModel(HttpClient httpClient, IStatusService statusService, IAuditLogService auditLogService)
        : base(statusService, auditLogService)
    {
        _httpClient = httpClient;
        _statusService = statusService;
        AboutVersionText = AppResources.Format("AboutVersionFormat", "Version {0} native Windows app track", AppInfo.Version);
    }

    [ObservableProperty]
    public partial string AboutVersionText { get; set; }

    [RelayCommand]
    private async Task OpenRepositoryAsync()
    {
        await RunAsync(AppResources.Get("OpeningRepository", "Opening repository"), () =>
        {
            OpenUrl("https://github.com/ugurkocde/DeviceOffboardingManager");
            return Task.CompletedTask;
        });
    }

    public async Task<string?> LoadChangelogForDialogAsync()
    {
        return await RunAsync(AppResources.Get("OpeningChangelog", "Opening changelog"), async () =>
        {
            var candidates = new[]
            {
                Path.Combine(AppContext.BaseDirectory, "Changelog.md"),
                Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Changelog.md"))
            };
            var changelogPath = candidates.FirstOrDefault(File.Exists);
            if (changelogPath is null)
            {
                _statusService.Report(
                    AppResources.Get("ChangelogUnavailable", "Changelog unavailable"),
                    AppResources.Get("ChangelogNotFound", "Changelog.md was not found in the app output or repository root."),
                    StatusSeverity.Warning);
                return null;
            }

            return await File.ReadAllTextAsync(changelogPath);
        });
    }

    public async Task<UpdateCheckResult?> CheckForUpdatesForDialogAsync()
    {
        return await RunAsync(AppResources.Get("CheckingForUpdates", "Checking for updates"), async () =>
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, "https://api.github.com/repos/ugurkocde/DeviceOffboardingManager/releases/latest");
            using var response = await _httpClient.SendAsync(request);
            var responseText = await response.Content.ReadAsStringAsync();
            if (!response.IsSuccessStatusCode)
            {
                throw new InvalidOperationException(AppResources.Format(
                    "UpdateCheckHttpFailureFormat",
                    "GitHub update check failed with HTTP {0}: {1}",
                    (int)response.StatusCode,
                    responseText));
            }

            var latestTag = JsonNode.Parse(responseText)?["tag_name"]?.GetValue<string>();
            var latestVersion = TryParseVersion(latestTag);
            var currentVersion = TryParseVersion(AppInfo.Version);
            if (latestVersion is null || currentVersion is null)
            {
                var fallbackMessage = AppResources.Format(
                    "UpdateCheckFallbackFormat",
                    "Latest release tag: {0}. Current app: {1}.",
                    latestTag ?? AppResources.Get("UnknownFallback", "(unknown)"),
                    AppInfo.Version);
                _statusService.Report(AppResources.Get("UpdateCheckComplete", "Update check complete"), fallbackMessage, StatusSeverity.Informational);
                return new UpdateCheckResult(fallbackMessage, false);
            }

            var updateAvailable = latestVersion.CompareTo(currentVersion) > 0;
            var message = updateAvailable
                ? AppResources.Format("UpdateAvailableFormat", "A newer release is available: {0}. Current app: {1}.", latestTag, AppInfo.Version)
                : AppResources.Format("UpdateCurrentFormat", "You are on the current or newer app track. Latest release: {0}; current app: {1}.", latestTag, AppInfo.Version);

            _statusService.Report(AppResources.Get("UpdateCheckComplete", "Update check complete"), message, updateAvailable ? StatusSeverity.Warning : StatusSeverity.Success);
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
