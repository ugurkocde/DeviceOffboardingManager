using System.Collections.ObjectModel;
using System.Text;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services;
using DeviceOffboardingManager.WinUI.Services.Contracts;

namespace DeviceOffboardingManager.WinUI.ViewModels;

public sealed partial class PlaybooksViewModel : AppViewModelBase
{
    private readonly IAuthenticationService _authenticationService;
    private readonly IPlaybookService _playbookService;
    private readonly IStatusService _statusService;
    private readonly DeviceListState _deviceListState;

    public PlaybooksViewModel(
        IAuthenticationService authenticationService,
        IPlaybookService playbookService,
        IStatusService statusService,
        IAuditLogService auditLogService,
        DeviceListState deviceListState)
        : base(statusService, auditLogService)
    {
        _authenticationService = authenticationService;
        _playbookService = playbookService;
        _statusService = statusService;
        _deviceListState = deviceListState;
        PlaybookNames = _playbookService.Definitions.Select(playbook => playbook.Name).ToArray();
    }

    public IReadOnlyList<string> PlaybookNames { get; }

    public ObservableCollection<TextRow> PlaybookRows { get; } = new();

    [ObservableProperty]
    private int selectedPlaybookIndex;

    [ObservableProperty]
    private string playbookParameter = string.Empty;

    [ObservableProperty]
    private string playbookStatusText = "Run a playbook to export a CSV report to the desktop.";

    [RelayCommand]
    private async Task RunPlaybookAsync()
    {
        await RunAsync("Running playbook", async () =>
        {
            EnsureConnected();
            if (_playbookService.Definitions.Count == 0)
            {
                throw new InvalidOperationException("No playbooks are available.");
            }

            var selectedIndex = SelectedPlaybookIndex < 0 || SelectedPlaybookIndex >= _playbookService.Definitions.Count
                ? 0
                : SelectedPlaybookIndex;
            var definition = _playbookService.Definitions[selectedIndex];
            var result = await _playbookService.RunAsync(definition.Id, PlaybookParameter);
            _deviceListState.LastPlaybookResult = result;
            PopulatePlaybookRows(result);
            PlaybookStatusText = $"{result.Definition.Name} completed with {result.Rows.Count:n0} row(s).";
            _statusService.Report("Playbook complete", PlaybookStatusText, StatusSeverity.Success);
        });
    }

    [RelayCommand]
    private async Task ExportLastPlaybookAsync()
    {
        await RunAsync("Exporting playbook", async () =>
        {
            if (_deviceListState.LastPlaybookResult is null)
            {
                throw new InvalidOperationException("Run a playbook before exporting.");
            }

            var path = await ExportPlaybookRowsAsync(_deviceListState.LastPlaybookResult);
            _statusService.Report("Playbook exported", path, StatusSeverity.Success);
        });
    }

    private void PopulatePlaybookRows(PlaybookRunResult result)
    {
        PlaybookRows.Clear();
        if (result.Rows.Count == 0)
        {
            PlaybookRows.Add(new TextRow("No rows returned."));
            return;
        }

        foreach (var row in result.Rows.Take(500))
        {
            PlaybookRows.Add(new TextRow(string.Join(" | ", row.Select(item => $"{item.Key}: {item.Value}"))));
        }

        if (result.Rows.Count > PlaybookRows.Count)
        {
            PlaybookRows.Add(new TextRow($"Showing first {PlaybookRows.Count:n0} of {result.Rows.Count:n0} row(s). Export the CSV for the full result."));
        }
    }

    private void EnsureConnected()
    {
        if (!_authenticationService.IsConnected)
        {
            throw new InvalidOperationException("Connect to Microsoft Graph first.");
        }
    }

    private static async Task<string> ExportPlaybookRowsAsync(PlaybookRunResult result)
    {
        var path = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
            $"DOM_Playbook_{result.Definition.Id}_{DateTime.Now:yyyyMMdd_HHmmss}.csv");

        var columns = result.Rows.SelectMany(row => row.Keys).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        var builder = new StringBuilder();
        builder.AppendLine(string.Join(",", columns.Select(Csv)));
        foreach (var row in result.Rows)
        {
            builder.AppendLine(string.Join(",", columns.Select(column => Csv(row.TryGetValue(column, out var value) ? value : null))));
        }

        await File.WriteAllTextAsync(path, builder.ToString());
        return path;
    }

    private static string Csv(string? value)
    {
        return '"' + (value ?? string.Empty).Replace("\"", "\"\"", StringComparison.Ordinal) + '"';
    }
}
