function Get-DeviceOffboardingRequiredPermissions {
    return @(
        @{
            Permission = "User.Read.All"
            Reason     = "Required to read user profile information and check group memberships"
        },
        @{
            Permission = "Group.Read.All"
            Reason     = "Needed to read group information and memberships"
        },
        @{
            Permission = "DeviceManagementConfiguration.Read.All"
            Reason     = "Allows reading Intune device configuration policies and their assignments"
        },
        @{
            Permission = "DeviceManagementApps.Read.All"
            Reason     = "Necessary to read mobile app management policies and app configurations"
        },
        @{
            Permission = "DeviceManagementManagedDevices.ReadWrite.All"
            Reason     = "Required to read and modify managed device information and compliance policies"
        },
        @{
            Permission = "Device.ReadWrite.All"
            Reason     = "Needed to read and delete device objects from Entra ID"
        },
        @{
            Permission = "DeviceManagementServiceConfig.ReadWrite.All"
            Reason     = "Required for Autopilot configuration and management"
        },
        @{
            Permission = "BitlockerKey.Read.All"
            Reason     = "Required to read BitLocker recovery keys for device offboarding"
        },
        @{
            Permission = "DeviceLocalCredential.Read.All"
            Reason     = "Required to read LAPS passwords for device offboarding"
        }
    )
}
