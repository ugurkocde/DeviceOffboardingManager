$script:DeviceOffboardingManagerModuleRoot = $PSScriptRoot
$script:DeviceOffboardingManagerVersion = '0.3.0'
$script:DeviceOffboardingManagerPlaybookRoot = Join-Path $script:DeviceOffboardingManagerModuleRoot 'Playbooks'

. (Join-Path $script:DeviceOffboardingManagerModuleRoot 'Public/Start-DeviceOffboardingManager.ps1')

Export-ModuleMember -Function Start-DeviceOffboardingManager
