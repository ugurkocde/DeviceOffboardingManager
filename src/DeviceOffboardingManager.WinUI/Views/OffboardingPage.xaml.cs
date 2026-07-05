using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services.Contracts;
using DeviceOffboardingManager.WinUI.ViewModels;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.ApplicationModel.DataTransfer;

namespace DeviceOffboardingManager.WinUI.Views;

public sealed partial class OffboardingPage : Page
{
    private readonly IStatusService _statusService;

    public OffboardingPage()
    {
        ViewModel = App.Services.GetRequiredService<OffboardingViewModel>();
        _statusService = App.Services.GetRequiredService<IStatusService>();
        InitializeComponent();
    }

    public OffboardingViewModel ViewModel { get; }

    private async void ReviewSelectedIds_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var selected = ViewModel.GetSelectedDevices();
            if (selected.Count == 0)
            {
                _statusService.Report("No devices selected", "Select at least one device before reviewing IDs.", StatusSeverity.Warning);
                return;
            }

            var content = new TextBlock
            {
                Text = string.Join(
                    Environment.NewLine + Environment.NewLine,
                    selected.Select(device =>
                        $"{device.DeviceName ?? "(unnamed)"}{Environment.NewLine}Serial: {device.SerialNumber ?? "(none)"}{Environment.NewLine}Entra object: {device.EntraDeviceId ?? "(none)"}{Environment.NewLine}Entra deviceId: {device.EntraDeviceObjectId ?? "(none)"}{Environment.NewLine}Intune: {device.IntuneDeviceId ?? "(none)"}{Environment.NewLine}Autopilot: {device.AutopilotIdentityId ?? "(none)"}")),
                TextWrapping = TextWrapping.Wrap
            };

            var dialog = new ContentDialog
            {
                Title = "Resolved device IDs",
                Content = new ScrollViewer { Content = content, MaxHeight = 520 },
                CloseButtonText = "Close",
                XamlRoot = XamlRoot
            };
            await dialog.ShowAsync();
        }
        catch (Exception ex)
        {
            await ViewModel.ReportExceptionAsync("Reviewing selected IDs", ex);
        }
    }

    private async void RunOffboarding_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var selected = ViewModel.GetSelectedDevices();
            if (selected.Count == 0)
            {
                await ViewModel.RunConfirmedOffboardingAsync();
                return;
            }

            var dialog = new ContentDialog
            {
                Title = "Confirm offboarding",
                Content = $"Run selected actions for {selected.Count:n0} device(s)? Review Graph IDs before continuing. Offboarding operations may be permanent.",
                PrimaryButtonText = "Run",
                CloseButtonText = "Cancel",
                DefaultButton = ContentDialogButton.Close,
                XamlRoot = XamlRoot
            };

            if (await dialog.ShowAsync() != ContentDialogResult.Primary)
            {
                ViewModel.ReportOffboardingCanceled();
                return;
            }

            var summary = await ViewModel.RunConfirmedOffboardingAsync();
            if (summary is not null)
            {
                await ShowOffboardingSummaryDialogAsync(summary);
            }
        }
        catch (Exception ex)
        {
            await ViewModel.ReportExceptionAsync("Running offboarding", ex);
        }
    }

    private async void FetchRecoveryKeys_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var keys = await ViewModel.FetchRecoveryKeysForDialogAsync();
            if (keys is not null)
            {
                await ShowRecoveryKeysDialogAsync(keys);
            }
        }
        catch (Exception ex)
        {
            await ViewModel.ReportExceptionAsync("Fetching recovery keys", ex);
        }
    }

    private async Task ShowRecoveryKeysDialogAsync(IReadOnlyList<RecoveryKeyRecord> records)
    {
        var found = records.Where(record => !string.IsNullOrWhiteSpace(record.KeyValue)).ToArray();
        var rows = records.Select(record =>
        {
            var parts = new List<string>
            {
                record.DeviceName ?? "(unnamed)",
                record.KeyType ?? "Key"
            };

            if (!string.IsNullOrWhiteSpace(record.AccountName))
            {
                parts.Add($"Account: {record.AccountName}");
            }

            parts.Add(!string.IsNullOrWhiteSpace(record.KeyValue)
                ? record.KeyValue
                : record.Status ?? "Not found");

            return string.Join(" | ", parts);
        }).ToArray();

        var content = new StackPanel { Spacing = 12 };
        content.Children.Add(new TextBlock
        {
            Text = $"Records: {records.Count:n0}; values found: {found.Length:n0}.",
            TextWrapping = TextWrapping.Wrap
        });
        content.Children.Add(new ListView
        {
            ItemsSource = rows,
            MaxHeight = 480
        });

        var dialog = new ContentDialog
        {
            Title = "Recovery keys",
            Content = content,
            PrimaryButtonText = "Copy all",
            CloseButtonText = "Close",
            IsPrimaryButtonEnabled = found.Length > 0,
            XamlRoot = XamlRoot
        };

        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            var text = string.Join(Environment.NewLine, found.Select(record => $"{record.DeviceName ?? "(unnamed)"} | {record.KeyType ?? "Key"} | {record.KeyValue}"));
            var package = new DataPackage();
            package.SetText(text);
            Clipboard.SetContent(package);
        }
    }

    private async Task ShowOffboardingSummaryDialogAsync(OffboardingSummary summary)
    {
        var rows = summary.Results.Select(result =>
            $"{result.DeviceName ?? "(unnamed)"} | Serial: {result.SerialNumber ?? "(none)"} | Pre: {DescribeOperation(result.PreAction)} | Entra: {DescribeOperation(result.Entra)} | Intune: {DescribeOperation(result.Intune)} | Autopilot: {DescribeOperation(result.Autopilot)} | Defender: {DescribeOperation(result.Defender)}").ToArray();

        var content = new StackPanel { Spacing = 12 };
        content.Children.Add(new TextBlock
        {
            Text = $"Devices: {summary.TotalDevices:n0}; successful: {summary.SuccessfulDevices:n0}; failed/partial: {summary.FailedDevices:n0}.",
            TextWrapping = TextWrapping.Wrap
        });
        content.Children.Add(new ListView
        {
            ItemsSource = rows,
            MaxHeight = 480
        });

        var dialog = new ContentDialog
        {
            Title = "Offboarding summary",
            Content = content,
            PrimaryButtonText = "Export HTML report",
            CloseButtonText = "Close",
            XamlRoot = XamlRoot
        };

        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            await ViewModel.ExportSummaryAsync(summary);
        }
    }

    private static string DescribeOperation(ServiceOperationResult result)
    {
        if (!result.Found && string.IsNullOrWhiteSpace(result.Error))
        {
            return "Skipped";
        }

        if (!result.Found)
        {
            return $"Not found: {result.Error}";
        }

        return result.Success ? result.Action ?? "Success" : $"Failed: {result.Error}";
    }
}
