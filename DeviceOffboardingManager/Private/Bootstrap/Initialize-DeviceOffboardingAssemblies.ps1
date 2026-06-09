function Initialize-DeviceOffboardingAssemblies {
    if (-not $IsWindows) {
        throw 'Device Offboarding Manager requires Windows because the UI is built with WPF desktop assemblies.'
    }

    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName PresentationCore -ErrorAction Stop
        Add-Type -AssemblyName WindowsBase -ErrorAction Stop
    }
    catch {
        throw "Failed to load required .NET desktop assemblies. Device Offboarding Manager requires Windows PowerShell desktop UI assemblies. Error: $_"
    }
}
