using DeviceOffboardingManager.WinUI.Models;
using DeviceOffboardingManager.WinUI.Services;
using DeviceOffboardingManager.WinUI.Services.Contracts;
using DeviceOffboardingManager.WinUI.Utilities;
using DeviceOffboardingManager.WinUI.ViewModels;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace DeviceOffboardingManager.WinUI.Views;

public sealed partial class DevicesPage : Page
{
    private readonly IStatusService _statusService;
    private readonly WindowHandleProvider _windowHandleProvider;

    public DevicesPage()
    {
        ViewModel = App.Services.GetRequiredService<DevicesViewModel>();
        _statusService = App.Services.GetRequiredService<IStatusService>();
        _windowHandleProvider = App.Services.GetRequiredService<WindowHandleProvider>();
        InitializeComponent();
    }

    public DevicesViewModel ViewModel { get; }

    private void SelectAllDevices_Click(object sender, RoutedEventArgs e)
    {
        ViewModel.SelectAllVisibleDevices(SelectAllDevicesBox.IsChecked == true);
    }

    private async void ImportBulkFile_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var path = await PickFilePathAsync(".csv", ".txt");
            if (string.IsNullOrWhiteSpace(path))
            {
                _statusService.Report(
                    AppResources.Get("ImportCanceledTitle", "Import canceled"),
                    AppResources.Get("ImportCanceledNoFile", "No file was selected."),
                    StatusSeverity.Informational);
                return;
            }

            var terms = await DevicesViewModel.ParseBulkImportFileAsync(path);
            if (terms.Count == 0)
            {
                throw new InvalidOperationException(AppResources.Get("BulkImportEmpty", "The selected file did not contain device identifiers."));
            }

            if (!await ConfirmBulkImportAsync(path, terms))
            {
                _statusService.Report(
                    AppResources.Get("ImportCanceledTitle", "Import canceled"),
                    AppResources.Get("ImportCanceledNoChanges", "No search terms were changed."),
                    StatusSeverity.Informational);
                return;
            }

            await ViewModel.ImportSearchTermsAsync(terms);
        }
        catch (Exception ex)
        {
            await ViewModel.ReportExceptionAsync(AppResources.Get("ImportingSearchTerms", "Importing search terms"), ex);
        }
    }

    private async void ViewSelectedGroups_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var result = await ViewModel.LoadSelectedGroupsForDialogAsync();
            if (result is null)
            {
                return;
            }

            await ShowGroupMembershipDialogAsync(result.Value.Device, result.Value.Groups);
        }
        catch (Exception ex)
        {
            await ViewModel.ReportExceptionAsync(AppResources.Get("LoadingGroupMemberships", "Loading group memberships"), ex);
        }
    }

    private async Task<bool> ConfirmBulkImportAsync(string path, IReadOnlyList<string> terms)
    {
        var previewRows = terms
            .Take(20)
            .Select((term, index) => $"{index + 1:n0}. {term}")
            .ToArray();

        var content = new StackPanel { Spacing = 12 };
        content.Children.Add(new TextBlock
        {
            Text = AppResources.Format("BulkImportCountFormat", "{0} contains {1:N0} unique device identifier(s).", Path.GetFileName(path), terms.Count),
            TextWrapping = TextWrapping.Wrap
        });
        content.Children.Add(new ListView
        {
            ItemsSource = previewRows,
            MaxHeight = 300
        });
        if (terms.Count > previewRows.Length)
        {
            content.Children.Add(new TextBlock
            {
                Text = AppResources.Format("BulkImportPreviewFormat", "Showing first {0:N0} identifiers. Import will use all {1:N0}.", previewRows.Length, terms.Count),
                TextWrapping = TextWrapping.Wrap
            });
        }

        var dialog = new ContentDialog
        {
            Title = AppResources.Get("ImportDevicesTitle", "Import devices"),
            Content = content,
            PrimaryButtonText = AppResources.Get("ImportButton", "Import"),
            CloseButtonText = AppResources.Get("CancelButton", "Cancel"),
            DefaultButton = ContentDialogButton.Primary,
            XamlRoot = XamlRoot
        };

        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }

    private async Task ShowGroupMembershipDialogAsync(DeviceRecord device, IReadOnlyList<GroupMembershipRecord> groups)
    {
        var rows = groups.Count == 0
            ? new[] { AppResources.Get("NoGroupMemberships", "No group memberships found.") }
            : groups.Select(group =>
                AppResources.Format(
                    "GroupMembershipRowFormat",
                    "{0} | {1} | Mail: {2} | Security: {3}",
                    group.DisplayName,
                    group.Type,
                    YesNo(group.MailEnabled),
                    YesNo(group.SecurityEnabled))).ToArray();

        var dialog = new ContentDialog
        {
            Title = AppResources.Format(
                "GroupMembershipsTitleFormat",
                "Group memberships - {0}",
                device.DeviceName ?? AppResources.Get("DeviceFallback", "Device")),
            Content = new ListView
            {
                ItemsSource = rows,
                MaxHeight = 480
            },
            CloseButtonText = AppResources.Get("CloseButton", "Close"),
            XamlRoot = XamlRoot
        };

        await dialog.ShowAsync();
    }

    private async Task<string?> PickFilePathAsync(params string[] extensions)
    {
        var picker = new FileOpenPicker();
        foreach (var extension in extensions)
        {
            picker.FileTypeFilter.Add(extension);
        }

        InitializeWithWindow.Initialize(picker, _windowHandleProvider.MainWindowHandle);
        var file = await picker.PickSingleFileAsync();
        return file?.Path;
    }

    private static string YesNo(bool value)
    {
        return value
            ? AppResources.Get("YesLowercase", "yes")
            : AppResources.Get("NoLowercase", "no");
    }
}
