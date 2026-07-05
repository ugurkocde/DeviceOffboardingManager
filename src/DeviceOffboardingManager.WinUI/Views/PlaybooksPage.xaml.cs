using DeviceOffboardingManager.WinUI.ViewModels;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml.Controls;

namespace DeviceOffboardingManager.WinUI.Views;

public sealed partial class PlaybooksPage : Page
{
    public PlaybooksPage()
    {
        ViewModel = App.Services.GetRequiredService<PlaybooksViewModel>();
        InitializeComponent();
    }

    public PlaybooksViewModel ViewModel { get; }
}
