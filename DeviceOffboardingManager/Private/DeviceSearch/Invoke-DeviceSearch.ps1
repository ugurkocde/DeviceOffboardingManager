function Invoke-DeviceSearch {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$SearchTexts,
        [Parameter(Mandatory = $true)]
        [string]$SearchOption
    )

    try {
        $searchResults = New-Object 'System.Collections.Generic.List[DeviceObject]'
        $AADCount = 0
        $IntuneCount = 0
        $AutopilotCount = 0

        # Pre-fetch Autopilot devices once for devicename search (API doesn't support displayName filtering)
        $allAutopilotDevices = $null
        if ($SearchOption -eq "Device Name") {
            try {
                $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities"
                $allAutopilotDevices = Get-GraphPagedResults -Uri $uri
                Write-Log "Pre-fetched $($allAutopilotDevices.Count) Autopilot devices for display name matching"
            }
            catch {
                Write-Log "Error pre-fetching Autopilot devices: $_"
                $allAutopilotDevices = @()
            }
        }

        foreach ($SearchText in $SearchTexts) {
            # Trim whitespace and newlines
            $SearchText = $SearchText.Trim()

            if ([string]::IsNullOrWhiteSpace($SearchText)) {
                continue
            }

            $escapedSearchText = ConvertTo-ODataStringValue -Value $SearchText

            if ($SearchOption -eq "Device Name") {
                # Batch Entra + Intune queries together
                $batchRequests = @(
                    @{ id = "entra"; method = "GET"; url = "/devices?`$filter=displayName eq '$escapedSearchText'&`$select=id,deviceId,displayName,operatingSystem,approximateLastSignInDateTime,accountEnabled,physicalIds" }
                    @{ id = "intune"; method = "GET"; url = "/deviceManagement/managedDevices?`$filter=deviceName eq '$escapedSearchText'&`$select=id,deviceName,serialNumber,operatingSystem,userDisplayName,lastSyncDateTime,azureADDeviceId,complianceState,managementAgent" }
                )
                $batchResponses = Invoke-GraphBatchRequest -Requests $batchRequests
                $entraResp = $batchResponses | Where-Object { $_.id -eq "entra" }
                $intuneResp = $batchResponses | Where-Object { $_.id -eq "intune" }
                $AADDevices = if ($entraResp -and $entraResp.status -eq 200 -and $entraResp.body.value) { $entraResp.body.value } else { @() }
                $IntuneDevices = if ($intuneResp -and $intuneResp.status -eq 200 -and $intuneResp.body.value) { $intuneResp.body.value } else { @() }

                # Filter pre-fetched Autopilot devices by display name (exact match)
                $AutopilotDevices = @()
                if ($allAutopilotDevices) {
                    $AutopilotDevices = $allAutopilotDevices | Where-Object {
                        $_.displayName -and $_.displayName -eq $SearchText
                    }
                }
                Write-Log "Found $(@($AutopilotDevices).Count) Autopilot devices matching display name: $SearchText"

                # Process Entra ID devices
                if ($AADDevices) {
                    foreach ($AADDevice in $AADDevices) {
                        $serialFromPhysicalIds = Get-SerialNumberFromPhysicalIds -PhysicalIds $AADDevice.physicalIds
                        $matchingIntuneDevice = Select-MatchingIntuneDevice -AADDevice $AADDevice -IntuneDevices $IntuneDevices -SerialNumber $serialFromPhysicalIds -DeviceName $AADDevice.displayName
                        $matchingAutopilotDevice = Select-MatchingAutopilotDevice -AutopilotDevices $AutopilotDevices -SerialNumber ($matchingIntuneDevice?.serialNumber ?? $serialFromPhysicalIds) -DeviceName $AADDevice.displayName

                        # If no Autopilot match by displayName and we have Intune device with serial, try serial number
                        if (-not $matchingAutopilotDevice -and $matchingIntuneDevice -and $matchingIntuneDevice.serialNumber) {
                            $matchingAutopilotDevice = Get-AutopilotDeviceBySerial -SerialNumber $matchingIntuneDevice.serialNumber
                        }

                        $CombinedDevice = New-Object DeviceObject
                        $CombinedDevice.IsSelected = $false
                        $CombinedDevice.DeviceName = $AADDevice.displayName

                        # Try to get serial number from multiple sources
                        $CombinedDevice.SerialNumber = $matchingIntuneDevice?.serialNumber ?? $matchingAutopilotDevice?.serialNumber

                        # If still no serial number, try to extract from Entra ID physicalIds
                        if (-not $CombinedDevice.SerialNumber) {
                            $CombinedDevice.SerialNumber = $serialFromPhysicalIds
                        }
                        $CombinedDevice.OperatingSystem = $AADDevice.operatingSystem
                        $CombinedDevice.PrimaryUser = $matchingIntuneDevice?.userDisplayName
                        $CombinedDevice.AzureADLastContact = ConvertTo-SafeDateTime -dateString $AADDevice.approximateLastSignInDateTime
                        $CombinedDevice.IntuneLastContact = ConvertTo-SafeDateTime -dateString $matchingIntuneDevice.lastSyncDateTime
                        $CombinedDevice.AutopilotLastContact = ConvertTo-SafeDateTime -dateString $matchingAutopilotDevice.lastContactedDateTime
                        $CombinedDevice.EntraDeviceId = $AADDevice.id
                        $CombinedDevice.EntraDeviceObjectId = $AADDevice.deviceId
                        $CombinedDevice.IntuneDeviceId = $matchingIntuneDevice?.id
                        $CombinedDevice.AutopilotIdentityId = $matchingAutopilotDevice?.id
                        $CombinedDevice.EntraAccountEnabled = if ($null -ne $AADDevice.accountEnabled) { $AADDevice.accountEnabled.ToString() } else { $null }
                        $CombinedDevice.ComplianceState = $matchingIntuneDevice?.complianceState
                        $CombinedDevice.ManagementAgent = $matchingIntuneDevice?.managementAgent

                        $searchResults.Add($CombinedDevice)
                        $AADCount++
                        if ($matchingIntuneDevice) { $IntuneCount++ }
                        if ($matchingAutopilotDevice) { $AutopilotCount++ }
                    }
                }

                # Process Intune devices not in Entra ID
                if ($IntuneDevices) {
                    foreach ($IntuneDevice in $IntuneDevices) {
                        # Skip if we already added this device through Entra ID
                        if ($searchResults | Where-Object { $_.IntuneDeviceId -and $_.IntuneDeviceId -eq $IntuneDevice.id }) {
                            continue
                        }

                        # Check if device is in Autopilot
                        $matchingAutopilotDevice = Select-MatchingAutopilotDevice -AutopilotDevices $AutopilotDevices -SerialNumber $IntuneDevice.serialNumber -DeviceName $IntuneDevice.deviceName

                        # If no match by displayName and we have serial number, try serial number
                        if (-not $matchingAutopilotDevice -and $IntuneDevice.serialNumber) {
                            $matchingAutopilotDevice = Get-AutopilotDeviceBySerial -SerialNumber $IntuneDevice.serialNumber
                        }
                        $matchingAADDevice = Get-EntraDeviceForIntuneDevice -IntuneDevice $IntuneDevice

                        $CombinedDevice = New-Object DeviceObject
                        $CombinedDevice.IsSelected = $false
                        $CombinedDevice.DeviceName = $IntuneDevice.deviceName
                        $CombinedDevice.SerialNumber = $IntuneDevice.serialNumber ?? $matchingAutopilotDevice?.serialNumber
                        $CombinedDevice.OperatingSystem = $matchingAADDevice?.operatingSystem ?? $IntuneDevice.operatingSystem
                        $CombinedDevice.PrimaryUser = $IntuneDevice.userDisplayName
                        $CombinedDevice.AzureADLastContact = ConvertTo-SafeDateTime -dateString $matchingAADDevice?.approximateLastSignInDateTime
                        $CombinedDevice.IntuneLastContact = ConvertTo-SafeDateTime -dateString $IntuneDevice.lastSyncDateTime
                        $CombinedDevice.AutopilotLastContact = ConvertTo-SafeDateTime -dateString $matchingAutopilotDevice.lastContactedDateTime
                        $CombinedDevice.EntraDeviceId = $matchingAADDevice?.id
                        $CombinedDevice.EntraDeviceObjectId = $matchingAADDevice?.deviceId
                        $CombinedDevice.IntuneDeviceId = $IntuneDevice.id
                        $CombinedDevice.AutopilotIdentityId = $matchingAutopilotDevice?.id
                        $CombinedDevice.EntraAccountEnabled = if ($null -ne $matchingAADDevice -and $null -ne $matchingAADDevice.accountEnabled) { $matchingAADDevice.accountEnabled.ToString() } else { $null }
                        $CombinedDevice.ComplianceState = $IntuneDevice.complianceState
                        $CombinedDevice.ManagementAgent = $IntuneDevice.managementAgent

                        $searchResults.Add($CombinedDevice)
                        if ($matchingAADDevice) { $AADCount++ }
                        $IntuneCount++
                        if ($matchingAutopilotDevice) { $AutopilotCount++ }
                    }
                }

                # Process Autopilot devices not in Entra ID or Intune
                if ($AutopilotDevices) {
                    foreach ($AutopilotDevice in $AutopilotDevices) {
                        # Skip if we already added this device
                        if ($searchResults | Where-Object {
                                ($_.AutopilotIdentityId -and $_.AutopilotIdentityId -eq $AutopilotDevice.id) -or
                                ($_.SerialNumber -and (Test-SameIdentifier -Left $_.SerialNumber -Right $AutopilotDevice.serialNumber))
                            }) {
                            continue
                        }

                        $CombinedDevice = New-Object DeviceObject
                        $CombinedDevice.IsSelected = $false
                        $CombinedDevice.DeviceName = $AutopilotDevice.displayName
                        $CombinedDevice.SerialNumber = $AutopilotDevice.serialNumber
                        $CombinedDevice.AutopilotLastContact = ConvertTo-SafeDateTime -dateString $AutopilotDevice.lastContactedDateTime
                        $CombinedDevice.AutopilotIdentityId = $AutopilotDevice.id

                        $searchResults.Add($CombinedDevice)
                        $AutopilotCount++
                    }
                }
            }
            elseif ($SearchOption -eq "Serial Number") {
                # Batch Intune + Autopilot queries together.
                # NOTE: Intune managedDevices only supports 'eq' on serialNumber; contains()/startswith()
                # are silently ignored and return zero results. Autopilot does support contains().
                $batchRequests = @(
                    @{ id = "intune"; method = "GET"; url = "/deviceManagement/managedDevices?`$filter=serialNumber eq '$escapedSearchText'&`$select=id,deviceName,serialNumber,operatingSystem,userDisplayName,lastSyncDateTime,azureADDeviceId,complianceState,managementAgent" }
                    @{ id = "autopilot"; method = "GET"; url = "/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(serialNumber,'$escapedSearchText')" }
                )
                $batchResponses = Invoke-GraphBatchRequest -Requests $batchRequests
                $intuneResp = $batchResponses | Where-Object { $_.id -eq "intune" }
                $autopilotResp = $batchResponses | Where-Object { $_.id -eq "autopilot" }
                $IntuneDevices = if ($intuneResp -and $intuneResp.status -eq 200 -and $intuneResp.body.value) { $intuneResp.body.value } else { @() }
                $AutopilotDevices = if ($autopilotResp -and $autopilotResp.status -eq 200 -and $autopilotResp.body.value) { $autopilotResp.body.value } else { @() }

                if ($IntuneDevices -or $AutopilotDevices) {
                    # If device is in Intune
                    if ($IntuneDevices) {
                        foreach ($IntuneDevice in $IntuneDevices) {
                            # Get Entra ID Device by azureADDeviceId first; name-only fallback only when unique
                            $AADDevice = Get-EntraDeviceForIntuneDevice -IntuneDevice $IntuneDevice

                            # Get Autopilot Device
                            $matchingAutopilotDevice = Select-MatchingAutopilotDevice -AutopilotDevices $AutopilotDevices -SerialNumber $IntuneDevice.serialNumber -DeviceName $IntuneDevice.deviceName

                            $CombinedDevice = New-Object DeviceObject
                            $CombinedDevice.IsSelected = $false
                            $CombinedDevice.DeviceName = $IntuneDevice.deviceName
                            $CombinedDevice.SerialNumber = $IntuneDevice.serialNumber
                            $CombinedDevice.OperatingSystem = $AADDevice?.operatingSystem ?? $IntuneDevice.operatingSystem
                            $CombinedDevice.PrimaryUser = $IntuneDevice.userDisplayName
                            $CombinedDevice.AzureADLastContact = ConvertTo-SafeDateTime -dateString $AADDevice.approximateLastSignInDateTime
                            $CombinedDevice.IntuneLastContact = ConvertTo-SafeDateTime -dateString $IntuneDevice.lastSyncDateTime
                            $CombinedDevice.AutopilotLastContact = ConvertTo-SafeDateTime -dateString $matchingAutopilotDevice.lastContactedDateTime
                            $CombinedDevice.EntraDeviceId = $AADDevice?.id
                            $CombinedDevice.EntraDeviceObjectId = $AADDevice?.deviceId
                            $CombinedDevice.IntuneDeviceId = $IntuneDevice.id
                            $CombinedDevice.AutopilotIdentityId = $matchingAutopilotDevice?.id
                            $CombinedDevice.EntraAccountEnabled = if ($null -ne $AADDevice -and $null -ne $AADDevice.accountEnabled) { $AADDevice.accountEnabled.ToString() } else { $null }
                            $CombinedDevice.ComplianceState = $IntuneDevice.complianceState
                            $CombinedDevice.ManagementAgent = $IntuneDevice.managementAgent

                            $searchResults.Add($CombinedDevice)
                            if ($AADDevice) { $AADCount++ }
                            $IntuneCount++
                            if ($matchingAutopilotDevice) { $AutopilotCount++ }
                        }
                    }

                    # If device is in Autopilot but not in Intune
                    if ($AutopilotDevices) {
                        foreach ($AutopilotDevice in $AutopilotDevices) {
                            # Skip if we already added this device through Intune
                            if ($searchResults | Where-Object { Test-SameIdentifier -Left $_.SerialNumber -Right $AutopilotDevice.serialNumber }) {
                                continue
                            }

                            $CombinedDevice = New-Object DeviceObject
                            $CombinedDevice.IsSelected = $false
                            $CombinedDevice.DeviceName = $AutopilotDevice.displayName
                            $CombinedDevice.SerialNumber = $AutopilotDevice.serialNumber
                            $CombinedDevice.AutopilotLastContact = ConvertTo-SafeDateTime -dateString $AutopilotDevice.lastContactedDateTime
                            $CombinedDevice.AutopilotIdentityId = $AutopilotDevice.id

                            $searchResults.Add($CombinedDevice)
                            $AutopilotCount++
                        }
                    }
                }
            }
            elseif ($SearchOption -eq "Device ID") {
                # Direct lookup by Entra object ID first, then by deviceId property
                try {
                    $uri = "https://graph.microsoft.com/beta/devices/$escapedSearchText"
                    $AADDevice = Invoke-MgGraphRequest -Uri $uri -Method GET
                }
                catch {
                    try {
                        $uri = "https://graph.microsoft.com/beta/devices?`$filter=deviceId eq '$escapedSearchText'&`$select=id,deviceId,displayName,operatingSystem,approximateLastSignInDateTime,accountEnabled,physicalIds"
                        $AADDevice = @(Get-GraphPagedResults -Uri $uri) | Select-Object -First 1
                    }
                    catch {
                        Write-Log "Device ID '$SearchText' not found in Entra ID: $_"
                        $AADDevice = $null
                    }
                }

                if ($AADDevice) {
                    $AADCount++
                    # Cross-reference Intune by azureADDeviceId for accurate matching
                    $IntuneDevice = $null
                    if ($AADDevice.deviceId) {
                        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=azureADDeviceId eq '$($AADDevice.deviceId)'&`$select=id,deviceName,serialNumber,operatingSystem,userDisplayName,lastSyncDateTime,azureADDeviceId,complianceState,managementAgent"
                        $IntuneDevice = (Get-GraphPagedResults -Uri $uri) | Select-Object -First 1
                        if ($IntuneDevice) { $IntuneCount++ }
                    }

                    # Cross-reference Autopilot by serial from physicalIds
                    $AutopilotDevice = $null
                    $serialFromPhysicalIds = Get-SerialNumberFromPhysicalIds -PhysicalIds $AADDevice.physicalIds
                    $serial = $IntuneDevice?.serialNumber ?? $serialFromPhysicalIds
                    if ($serial) {
                        $AutopilotDevice = Get-AutopilotDeviceBySerial -SerialNumber $serial
                        if ($AutopilotDevice) { $AutopilotCount++ }
                    }

                    $CombinedDevice = New-Object DeviceObject
                    $CombinedDevice.IsSelected = $false
                    $CombinedDevice.DeviceName = $AADDevice.displayName
                    $CombinedDevice.SerialNumber = $serial
                    $CombinedDevice.OperatingSystem = $AADDevice.operatingSystem
                    $CombinedDevice.PrimaryUser = $IntuneDevice?.userDisplayName
                    $CombinedDevice.AzureADLastContact = ConvertTo-SafeDateTime -dateString $AADDevice.approximateLastSignInDateTime
                    $CombinedDevice.IntuneLastContact = ConvertTo-SafeDateTime -dateString $IntuneDevice?.lastSyncDateTime
                    $CombinedDevice.AutopilotLastContact = ConvertTo-SafeDateTime -dateString $AutopilotDevice?.lastContactedDateTime
                    $CombinedDevice.EntraDeviceId = $AADDevice.id
                    $CombinedDevice.EntraDeviceObjectId = $AADDevice.deviceId
                    $CombinedDevice.IntuneDeviceId = $IntuneDevice?.id
                    $CombinedDevice.AutopilotIdentityId = $AutopilotDevice?.id
                    $CombinedDevice.EntraAccountEnabled = if ($null -ne $AADDevice.accountEnabled) { $AADDevice.accountEnabled.ToString() } else { $null }
                    $CombinedDevice.ComplianceState = $IntuneDevice?.complianceState
                    $CombinedDevice.ManagementAgent = $IntuneDevice?.managementAgent

                    $searchResults.Add($CombinedDevice)
                }
                else {
                    Write-Log "No device found with ID: $SearchText"
                }
            }
            elseif ($SearchOption -eq "Contains (partial match)") {
                # Batch Entra (startsWith) + Intune (contains) queries.
                # NOTE: Intune managedDevices supports contains() on deviceName but NOT on serialNumber.
                # Combining them with 'or' makes the whole filter return zero rows (the unsupported clause
                # poisons the query), so we only filter on deviceName here. Partial serial matches are still
                # covered client-side for Autopilot below, and exact serials via the "Serial Number" search.
                $batchRequests = @(
                    @{ id = "entra"; method = "GET"; url = "/devices?`$filter=startsWith(displayName,'$escapedSearchText')&`$select=id,deviceId,displayName,operatingSystem,approximateLastSignInDateTime,accountEnabled,physicalIds&`$count=true"; headers = @{ "ConsistencyLevel" = "eventual" } }
                    @{ id = "intune"; method = "GET"; url = "/deviceManagement/managedDevices?`$filter=contains(deviceName,'$escapedSearchText')&`$select=id,deviceName,serialNumber,operatingSystem,userDisplayName,lastSyncDateTime,azureADDeviceId,complianceState,managementAgent" }
                )
                $batchResponses = Invoke-GraphBatchRequest -Requests $batchRequests
                $entraResp = $batchResponses | Where-Object { $_.id -eq "entra" }
                $intuneResp = $batchResponses | Where-Object { $_.id -eq "intune" }
                $AADDevices = if ($entraResp -and $entraResp.status -eq 200 -and $entraResp.body.value) { $entraResp.body.value } else { @() }
                $IntuneDevices = if ($intuneResp -and $intuneResp.status -eq 200 -and $intuneResp.body.value) { $intuneResp.body.value } else { @() }

                # Pre-fetch Autopilot devices for client-side filtering
                $AutopilotDevices = @()
                try {
                    $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities"
                    $allAutopilot = Get-GraphPagedResults -Uri $uri
                    $AutopilotDevices = $allAutopilot | Where-Object {
                        ($_.displayName -and $_.displayName -like "*$SearchText*") -or
                        ($_.serialNumber -and $_.serialNumber -like "*$SearchText*")
                    }
                } catch {
                    Write-Log "Error fetching Autopilot devices for partial match: $_"
                }

                # Process Entra ID devices
                if ($AADDevices) {
                    foreach ($AADDevice in $AADDevices) {
                        $serialFromPhysicalIds = Get-SerialNumberFromPhysicalIds -PhysicalIds $AADDevice.physicalIds
                        $matchingIntuneDevice = Select-MatchingIntuneDevice -AADDevice $AADDevice -IntuneDevices $IntuneDevices -SerialNumber $serialFromPhysicalIds -DeviceName $AADDevice.displayName
                        $matchingAutopilotDevice = Select-MatchingAutopilotDevice -AutopilotDevices $AutopilotDevices -SerialNumber ($matchingIntuneDevice?.serialNumber ?? $serialFromPhysicalIds) -DeviceName $AADDevice.displayName

                        if (-not $matchingAutopilotDevice -and $matchingIntuneDevice -and $matchingIntuneDevice.serialNumber) {
                            $matchingAutopilotDevice = Get-AutopilotDeviceBySerial -SerialNumber $matchingIntuneDevice.serialNumber
                        }

                        $CombinedDevice = New-Object DeviceObject
                        $CombinedDevice.IsSelected = $false
                        $CombinedDevice.DeviceName = $AADDevice.displayName
                        $CombinedDevice.SerialNumber = $matchingIntuneDevice?.serialNumber ?? $matchingAutopilotDevice?.serialNumber
                        if (-not $CombinedDevice.SerialNumber) {
                            $CombinedDevice.SerialNumber = $serialFromPhysicalIds
                        }
                        $CombinedDevice.OperatingSystem = $AADDevice.operatingSystem
                        $CombinedDevice.PrimaryUser = $matchingIntuneDevice?.userDisplayName
                        $CombinedDevice.AzureADLastContact = ConvertTo-SafeDateTime -dateString $AADDevice.approximateLastSignInDateTime
                        $CombinedDevice.IntuneLastContact = ConvertTo-SafeDateTime -dateString $matchingIntuneDevice.lastSyncDateTime
                        $CombinedDevice.AutopilotLastContact = ConvertTo-SafeDateTime -dateString $matchingAutopilotDevice.lastContactedDateTime
                        $CombinedDevice.EntraDeviceId = $AADDevice.id
                        $CombinedDevice.EntraDeviceObjectId = $AADDevice.deviceId
                        $CombinedDevice.IntuneDeviceId = $matchingIntuneDevice?.id
                        $CombinedDevice.AutopilotIdentityId = $matchingAutopilotDevice?.id
                        $CombinedDevice.EntraAccountEnabled = if ($null -ne $AADDevice.accountEnabled) { $AADDevice.accountEnabled.ToString() } else { $null }
                        $CombinedDevice.ComplianceState = $matchingIntuneDevice?.complianceState
                        $CombinedDevice.ManagementAgent = $matchingIntuneDevice?.managementAgent

                        $searchResults.Add($CombinedDevice)
                        $AADCount++
                        if ($matchingIntuneDevice) { $IntuneCount++ }
                        if ($matchingAutopilotDevice) { $AutopilotCount++ }
                    }
                }

                # Process Intune devices not in Entra ID results
                if ($IntuneDevices) {
                    foreach ($IntuneDevice in $IntuneDevices) {
                        if ($searchResults | Where-Object { $_.IntuneDeviceId -and $_.IntuneDeviceId -eq $IntuneDevice.id }) {
                            continue
                        }
                        $matchingAutopilotDevice = Select-MatchingAutopilotDevice -AutopilotDevices $AutopilotDevices -SerialNumber $IntuneDevice.serialNumber -DeviceName $IntuneDevice.deviceName
                        if (-not $matchingAutopilotDevice -and $IntuneDevice.serialNumber) {
                            $matchingAutopilotDevice = Get-AutopilotDeviceBySerial -SerialNumber $IntuneDevice.serialNumber
                        }
                        $matchingAADDevice = Get-EntraDeviceForIntuneDevice -IntuneDevice $IntuneDevice

                        $CombinedDevice = New-Object DeviceObject
                        $CombinedDevice.IsSelected = $false
                        $CombinedDevice.DeviceName = $IntuneDevice.deviceName
                        $CombinedDevice.SerialNumber = $IntuneDevice.serialNumber ?? $matchingAutopilotDevice?.serialNumber
                        $CombinedDevice.OperatingSystem = $matchingAADDevice?.operatingSystem ?? $IntuneDevice.operatingSystem
                        $CombinedDevice.PrimaryUser = $IntuneDevice.userDisplayName
                        $CombinedDevice.AzureADLastContact = ConvertTo-SafeDateTime -dateString $matchingAADDevice?.approximateLastSignInDateTime
                        $CombinedDevice.IntuneLastContact = ConvertTo-SafeDateTime -dateString $IntuneDevice.lastSyncDateTime
                        $CombinedDevice.AutopilotLastContact = ConvertTo-SafeDateTime -dateString $matchingAutopilotDevice.lastContactedDateTime
                        $CombinedDevice.EntraDeviceId = $matchingAADDevice?.id
                        $CombinedDevice.EntraDeviceObjectId = $matchingAADDevice?.deviceId
                        $CombinedDevice.IntuneDeviceId = $IntuneDevice.id
                        $CombinedDevice.AutopilotIdentityId = $matchingAutopilotDevice?.id
                        $CombinedDevice.EntraAccountEnabled = if ($null -ne $matchingAADDevice -and $null -ne $matchingAADDevice.accountEnabled) { $matchingAADDevice.accountEnabled.ToString() } else { $null }
                        $CombinedDevice.ComplianceState = $IntuneDevice.complianceState
                        $CombinedDevice.ManagementAgent = $IntuneDevice.managementAgent

                        $searchResults.Add($CombinedDevice)
                        if ($matchingAADDevice) { $AADCount++ }
                        $IntuneCount++
                        if ($matchingAutopilotDevice) { $AutopilotCount++ }
                    }
                }

                # Process Autopilot-only devices
                if ($AutopilotDevices) {
                    foreach ($AutopilotDevice in $AutopilotDevices) {
                        if ($searchResults | Where-Object {
                                ($_.AutopilotIdentityId -and $_.AutopilotIdentityId -eq $AutopilotDevice.id) -or
                                ($_.SerialNumber -and (Test-SameIdentifier -Left $_.SerialNumber -Right $AutopilotDevice.serialNumber))
                            }) {
                            continue
                        }
                        $CombinedDevice = New-Object DeviceObject
                        $CombinedDevice.IsSelected = $false
                        $CombinedDevice.DeviceName = $AutopilotDevice.displayName
                        $CombinedDevice.SerialNumber = $AutopilotDevice.serialNumber
                        $CombinedDevice.AutopilotLastContact = ConvertTo-SafeDateTime -dateString $AutopilotDevice.lastContactedDateTime
                        $CombinedDevice.AutopilotIdentityId = $AutopilotDevice.id

                        $searchResults.Add($CombinedDevice)
                        $AutopilotCount++
                    }
                }
            }
        }

        # Update UI status
        $Window.FindName('intune_status').Text = "Intune: $IntuneCount device found"
        $Window.FindName('intune_status').Foreground = if ($IntuneCount -gt 0) { '#4299E1' } else { '#FC8181' }
        $Window.FindName('autopilot_status').Text = "Autopilot: $AutopilotCount device found"
        $Window.FindName('autopilot_status').Foreground = if ($AutopilotCount -gt 0) { '#48BB78' } else { '#FC8181' }
        $Window.FindName('aad_status').Text = "Entra ID: $AADCount device found"
        $Window.FindName('aad_status').Foreground = if ($AADCount -gt 0) { '#ED64A6' } else { '#FC8181' }

        if ($searchResults.Count -gt 0) {
            $script:AllSearchResults = $searchResults
            $SearchResultsDataGrid.ItemsSource = $searchResults
            $script:LastCheckedIndex = -1
            $ResultCountText.Text = "$($searchResults.Count) device(s) found"
            $SearchEmptyState.Visibility = 'Collapsed'
            $SearchResultsDataGrid.Visibility = 'Visible'
        }
        else {
            $script:AllSearchResults = $null
            $SearchResultsDataGrid.ItemsSource = $null
            $FilterRow.Visibility = 'Collapsed'
            $ResultCountText.Text = ""
            $SearchEmptyState.Visibility = 'Visible'
            $SearchResultsDataGrid.Visibility = 'Collapsed'
            Show-Toast -Message "No devices found matching the search criteria." -Type "info"
        }

        # Ensure Offboard button and Export Selected button are disabled until selection
        $OffboardButton.IsEnabled = $false
        $ExportSelectedButton.IsEnabled = $false
        if ($SetGroupTagButton) { $SetGroupTagButton.IsEnabled = $false }
        $OffboardPanel.Visibility = 'Collapsed'
    }
    catch {
        Write-Log "Error occurred during search operation. Exception: $_"
        Show-Toast -Message "Error in search operation. Please ensure the Serial Number or Device Name is valid." -Type "error" -DurationSeconds 6
    }
}
