@{
    RootModule        = 'DeviceOffboardingManager.psm1'
    ModuleVersion     = '0.3.0'
    GUID              = 'a686724d-588d-472e-b927-c4840c32eed1'
    Author            = 'ugurk'
    CompanyName       = ''
    Copyright         = ''
    Description       = 'A PowerShell GUI tool for managing and offboarding devices from Microsoft Intune, Autopilot, Entra ID, and Microsoft Defender for Endpoint.'
    PowerShellVersion = '7.0'
    RequiredModules   = @('Microsoft.Graph.Authentication')

    FunctionsToExport = @('Start-DeviceOffboardingManager')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('Intune', 'PowerShell', 'Automation', 'Autopilot', 'EntraID', 'DeviceManagement')
            LicenseUri = 'https://github.com/ugurkocde/DeviceOffboardingManager/blob/main/LICENSE'
            ProjectUri = 'https://github.com/ugurkocde/DeviceOffboardingManager'
            ReleaseNotes = 'v0.3 migrates Device Offboarding Manager to a full PowerShell module and adds hardened device identity correlation, device-code authentication, Autopilot group tag management, local playbooks, and safer audit/export details.'
        }
    }
}
