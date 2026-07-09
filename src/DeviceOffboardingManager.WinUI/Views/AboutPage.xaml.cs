using DeviceOffboardingManager.WinUI.ViewModels;
using DeviceOffboardingManager.WinUI.Utilities;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Text;

namespace DeviceOffboardingManager.WinUI.Views;

public sealed partial class AboutPage : Page
{
    public AboutPage()
    {
        ViewModel = App.Services.GetRequiredService<AboutViewModel>();
        InitializeComponent();
    }

    public AboutViewModel ViewModel { get; }

    private async void OpenChangelog_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var text = await ViewModel.LoadChangelogForDialogAsync();
            if (text is null)
            {
                return;
            }

            var dialog = new ContentDialog
            {
                Title = AppResources.Get("ChangelogTitle", "Changelog"),
                Content = new ScrollViewer { Content = CreateChangelogContent(text), MaxHeight = 560 },
                CloseButtonText = AppResources.Get("CloseButton", "Close"),
                XamlRoot = XamlRoot
            };
            await dialog.ShowAsync();
        }
        catch (Exception ex)
        {
            await ViewModel.ReportExceptionAsync(AppResources.Get("OpeningChangelog", "Opening changelog"), ex);
        }
    }

    private async void CheckForUpdates_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var result = await ViewModel.CheckForUpdatesForDialogAsync();
            if (result is null)
            {
                return;
            }

            var dialog = result.UpdateAvailable
                ? new ContentDialog
                {
                    Title = AppResources.Get("UpdateCheckTitle", "Update check"),
                    Content = new TextBlock { Text = result.Message, TextWrapping = TextWrapping.Wrap },
                    PrimaryButtonText = AppResources.Get("OpenReleasesButton", "Open releases"),
                    CloseButtonText = AppResources.Get("CloseButton", "Close"),
                    XamlRoot = XamlRoot
                }
                : new ContentDialog
                {
                    Title = AppResources.Get("UpdateCheckTitle", "Update check"),
                    Content = new TextBlock { Text = result.Message, TextWrapping = TextWrapping.Wrap },
                    CloseButtonText = AppResources.Get("CloseButton", "Close"),
                    XamlRoot = XamlRoot
                };

            if (await dialog.ShowAsync() == ContentDialogResult.Primary)
            {
                ViewModel.OpenReleases();
            }
        }
        catch (Exception ex)
        {
            await ViewModel.ReportExceptionAsync(AppResources.Get("CheckingForUpdates", "Checking for updates"), ex);
        }
    }

    private static StackPanel CreateChangelogContent(string markdown)
    {
        var panel = new StackPanel { Spacing = 8 };
        foreach (var rawLine in markdown.Split(new[] { "\r\n", "\n" }, StringSplitOptions.None))
        {
            var line = rawLine.TrimEnd();
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            var block = new TextBlock
            {
                TextWrapping = TextWrapping.Wrap
            };

            if (line.StartsWith("## ", StringComparison.Ordinal))
            {
                block.Text = StripMarkdownInline(line[3..]);
                block.FontWeight = FontWeights.SemiBold;
            }
            else if (line.StartsWith("- ", StringComparison.Ordinal))
            {
                block.Text = "• " + StripMarkdownInline(line[2..]);
                block.Margin = new Thickness(16, 0, 0, 0);
            }
            else if (line.StartsWith("  - ", StringComparison.Ordinal))
            {
                block.Text = "• " + StripMarkdownInline(line[4..]);
                block.Margin = new Thickness(32, 0, 0, 0);
            }
            else
            {
                block.Text = StripMarkdownInline(line.TrimStart('#', ' '));
            }

            panel.Children.Add(block);
        }

        return panel;
    }

    private static string StripMarkdownInline(string text)
    {
        return text
            .Replace("**", string.Empty, StringComparison.Ordinal)
            .Replace("`", string.Empty, StringComparison.Ordinal);
    }
}
