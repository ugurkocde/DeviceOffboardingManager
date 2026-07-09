using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services.Contracts;
using DeviceOffboardingManager.WinUI.Utilities;
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
                _statusService.Report(
                    AppResources.Get("NoDevicesSelectedTitle", "No devices selected"),
                    AppResources.Get("NoDevicesSelectedMessage", "Select at least one device before reviewing IDs."),
                    StatusSeverity.Warning);
                return;
            }

            var content = new TextBlock
            {
                Text = string.Join(
                    Environment.NewLine + Environment.NewLine,
                    selected.Select(device =>
                        AppResources.Format(
                            "ResolvedDeviceIdsFormat",
                            "{0}{6}Serial: {1}{6}Entra object: {2}{6}Entra deviceId: {3}{6}Intune: {4}{6}Autopilot: {5}",
                            device.DeviceName ?? AppResources.Get("UnnamedFallback", "(unnamed)"),
                            device.SerialNumber ?? AppResources.Get("NoneFallback", "(none)"),
                            device.EntraDeviceId ?? AppResources.Get("NoneFallback", "(none)"),
                            device.EntraDeviceObjectId ?? AppResources.Get("NoneFallback", "(none)"),
                            device.IntuneDeviceId ?? AppResources.Get("NoneFallback", "(none)"),
                            device.AutopilotIdentityId ?? AppResources.Get("NoneFallback", "(none)"),
                            Environment.NewLine))),
                TextWrapping = TextWrapping.Wrap
            };

            var dialog = new ContentDialog
            {
                Title = AppResources.Get("ResolvedDeviceIdsTitle", "Resolved device IDs"),
                Content = new ScrollViewer { Content = content, MaxHeight = 520 },
                CloseButtonText = AppResources.Get("CloseButton", "Close"),
                XamlRoot = XamlRoot
            };
            await dialog.ShowAsync();
        }
        catch (Exception ex)
        {
            await ViewModel.ReportExceptionAsync(AppResources.Get("ReviewingSelectedIds", "Reviewing selected IDs"), ex);
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
                Title = AppResources.Get("ConfirmOffboardingTitle", "Confirm offboarding"),
                Content = AppResources.Format(
                    "ConfirmOffboardingBodyFormat",
                    "Run selected actions for {0:N0} device(s)? Review Graph IDs before continuing. Offboarding operations may be permanent.",
                    selected.Count),
                PrimaryButtonText = AppResources.Get("RunButton", "Run"),
                CloseButtonText = AppResources.Get("CancelButton", "Cancel"),
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
            await ViewModel.ReportExceptionAsync(AppResources.Get("RunningOffboarding", "Running offboarding"), ex);
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
            await ViewModel.ReportExceptionAsync(AppResources.Get("FetchingRecoveryKeys", "Fetching recovery keys"), ex);
        }
    }

    private async Task ShowRecoveryKeysDialogAsync(IReadOnlyList<RecoveryKeyRecord> records)
    {
        var found = records.Where(record => !string.IsNullOrWhiteSpace(record.KeyValue)).ToArray();
        var rows = records.Select(record =>
        {
            var parts = new List<string>
            {
                record.DeviceName ?? AppResources.Get("UnnamedFallback", "(unnamed)"),
                record.KeyType ?? AppResources.Get("KeyFallback", "Key")
            };

            if (!string.IsNullOrWhiteSpace(record.AccountName))
            {
                parts.Add(AppResources.Format("AccountFormat", "Account: {0}", record.AccountName));
            }

            parts.Add(!string.IsNullOrWhiteSpace(record.KeyValue)
                ? record.KeyValue
                : record.Status ?? AppResources.Get("NotFound", "Not found"));

            return string.Join(" | ", parts);
        }).ToArray();

        var content = new StackPanel { Spacing = 12 };
        content.Children.Add(new TextBlock
        {
            Text = AppResources.Format("RecoveryRecordsFormat", "Records: {0:N0}; values found: {1:N0}.", records.Count, found.Length),
            TextWrapping = TextWrapping.Wrap
        });
        content.Children.Add(new ListView
        {
            ItemsSource = rows,
            MaxHeight = 480
        });

        var dialog = new ContentDialog
        {
            Title = AppResources.Get("RecoveryKeysTitle", "Recovery keys"),
            Content = content,
            PrimaryButtonText = AppResources.Get("CopyAllButton", "Copy all"),
            CloseButtonText = AppResources.Get("CloseButton", "Close"),
            IsPrimaryButtonEnabled = found.Length > 0,
            XamlRoot = XamlRoot
        };

        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            var text = string.Join(Environment.NewLine, found.Select(record => AppResources.Format(
                "RecoveryClipboardRowFormat",
                "{0} | {1} | {2}",
                record.DeviceName ?? AppResources.Get("UnnamedFallback", "(unnamed)"),
                record.KeyType ?? AppResources.Get("KeyFallback", "Key"),
                record.KeyValue)));
            var package = new DataPackage();
            package.SetText(text);
            Clipboard.SetContent(package);
        }
    }

    private async Task ShowOffboardingSummaryDialogAsync(OffboardingSummary summary)
    {
        var rows = summary.Results.Select(result => AppResources.Format(
            "OffboardingSummaryRowFormat",
            "{0} | Serial: {1} | Pre: {2} | Entra: {3} | Intune: {4} | Autopilot: {5} | Defender: {6}",
            result.DeviceName ?? AppResources.Get("UnnamedFallback", "(unnamed)"),
            result.SerialNumber ?? AppResources.Get("NoneFallback", "(none)"),
            DescribeOperation(result.PreAction),
            DescribeOperation(result.Entra),
            DescribeOperation(result.Intune),
            DescribeOperation(result.Autopilot),
            DescribeOperation(result.Defender))).ToArray();

        var content = new StackPanel { Spacing = 12 };
        content.Children.Add(new TextBlock
        {
            Text = AppResources.Format(
                "OffboardingSummaryCountFormat",
                "Devices: {0:N0}; successful: {1:N0}; failed/partial: {2:N0}.",
                summary.TotalDevices,
                summary.SuccessfulDevices,
                summary.FailedDevices),
            TextWrapping = TextWrapping.Wrap
        });
        content.Children.Add(new ListView
        {
            ItemsSource = rows,
            MaxHeight = 480
        });

        var dialog = new ContentDialog
        {
            Title = AppResources.Get("OffboardingSummaryTitle", "Offboarding summary"),
            Content = content,
            PrimaryButtonText = AppResources.Get("ExportHtmlButton", "Export HTML report"),
            CloseButtonText = AppResources.Get("CloseButton", "Close"),
            XamlRoot = XamlRoot
        };

        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            await ViewModel.ExportSummaryAsync(summary);
        }
    }

    private static string DescribeOperation(ServiceOperationResult result)
    {
        if (result.State == ServiceOperationState.Skipped)
        {
            return AppResources.Get("OperationSkipped", "Skipped");
        }

        if (result.State == ServiceOperationState.MissingTarget)
        {
            return AppResources.Format("OperationMissingTargetFormat", "Missing target: {0}", result.Error);
        }

        return result.State == ServiceOperationState.Succeeded
            ? result.Action ?? AppResources.Get("OperationSuccess", "Success")
            : AppResources.Format("OperationFailedFormat", "Failed: {0}", result.Error);
    }
}
