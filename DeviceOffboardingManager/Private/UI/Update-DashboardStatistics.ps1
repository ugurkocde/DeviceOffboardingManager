function Update-DashboardStatistics {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Platform = "All Platforms"
    )

    try {
        Write-Log "Updating dashboard statistics (Platform: $Platform)..."
        $startTime = Get-Date

        # Build platform filter clause for $count queries
        $platformFilter = ""
        switch ($Platform) {
            "Windows" { $platformFilter = " and startswith(operatingSystem,'Windows')" }
            "macOS"   { $platformFilter = " and operatingSystem eq 'macOS'" }
            "iOS"     { $platformFilter = " and operatingSystem eq 'iOS'" }
            "Android" { $platformFilter = " and operatingSystem eq 'Android'" }
            "Linux"   { $platformFilter = " and operatingSystem eq 'Linux'" }
        }
        # For standalone filters (no preceding "and"), strip the leading " and "
        $platformFilterStandalone = if ($platformFilter) { $platformFilter.Substring(5) } else { "" }

        # Try $count batch approach first (single API call instead of fetching all devices)
        $countSuccess = $false
        try {
            $thirtyDaysAgo = (Get-Date).AddDays(-30).ToString('yyyy-MM-ddTHH:mm:ssZ')
            $ninetyDaysAgo = (Get-Date).AddDays(-90).ToString('yyyy-MM-ddTHH:mm:ssZ')
            $oneEightyDaysAgo = (Get-Date).AddDays(-180).ToString('yyyy-MM-ddTHH:mm:ssZ')

            # Build Intune/Entra count URLs with optional platform filter
            # Intune endpoints use ?$count=true&$top=1 (/$count path segment not supported in batch)
            $intuneCountUrl = if ($platformFilterStandalone) {
                "/deviceManagement/managedDevices?`$count=true&`$top=1&`$select=id&`$filter=$platformFilterStandalone"
            } else {
                "/deviceManagement/managedDevices?`$count=true&`$top=1&`$select=id"
            }
            $entraCountUrl = if ($platformFilterStandalone) {
                "/devices?`$count=true&`$top=1&`$select=id&`$filter=$platformFilterStandalone"
            } else {
                "/devices?`$count=true&`$top=1&`$select=id"
            }

            $batchBody = @{
                requests = @(
                    @{ id = "intune"; method = "GET"; url = $intuneCountUrl }
                    @{ id = "autopilot"; method = "GET"; url = "/deviceManagement/windowsAutopilotDeviceIdentities?`$count=true&`$top=1" }
                    @{ id = "entra"; method = "GET"; url = $entraCountUrl; headers = @{ "ConsistencyLevel" = "eventual" } }
                    @{ id = "stale30"; method = "GET"; url = "/deviceManagement/managedDevices?`$count=true&`$top=1&`$select=id&`$filter=lastSyncDateTime lt $thirtyDaysAgo$platformFilter" }
                    @{ id = "stale90"; method = "GET"; url = "/deviceManagement/managedDevices?`$count=true&`$top=1&`$select=id&`$filter=lastSyncDateTime lt $ninetyDaysAgo$platformFilter" }
                    @{ id = "stale180"; method = "GET"; url = "/deviceManagement/managedDevices?`$count=true&`$top=1&`$select=id&`$filter=lastSyncDateTime lt $oneEightyDaysAgo$platformFilter" }
                    @{ id = "personal"; method = "GET"; url = "/deviceManagement/managedDevices?`$count=true&`$top=1&`$select=id&`$filter=managedDeviceOwnerType eq 'personal'$platformFilter" }
                    @{ id = "corporate"; method = "GET"; url = "/deviceManagement/managedDevices?`$count=true&`$top=1&`$select=id&`$filter=managedDeviceOwnerType eq 'company'$platformFilter" }
                    @{ id = "osWindows"; method = "GET"; url = "/deviceManagement/managedDevices?`$count=true&`$top=1&`$select=id&`$filter=startswith(operatingSystem,'Windows')" }
                    @{ id = "osmacOS"; method = "GET"; url = "/deviceManagement/managedDevices?`$count=true&`$top=1&`$select=id&`$filter=operatingSystem eq 'macOS'" }
                    @{ id = "osiOS"; method = "GET"; url = "/deviceManagement/managedDevices?`$count=true&`$top=1&`$select=id&`$filter=operatingSystem eq 'iOS'" }
                    @{ id = "osAndroid"; method = "GET"; url = "/deviceManagement/managedDevices?`$count=true&`$top=1&`$select=id&`$filter=operatingSystem eq 'Android'" }
                    @{ id = "osLinux"; method = "GET"; url = "/deviceManagement/managedDevices?`$count=true&`$top=1&`$select=id&`$filter=operatingSystem eq 'Linux'" }
                )
            } | ConvertTo-Json -Depth 5

            $batchResponse = Invoke-GraphRequestWithRetry -Uri "https://graph.microsoft.com/beta/`$batch" -Method POST -Body $batchBody -ContentType "application/json"
            $batchResponses = $batchResponse.responses
            Write-Log "Dashboard batch raw statuses: $(($batchResponses | ForEach-Object { "$($_.id)=$($_.status)" }) -join ', ')"

            # Helper to extract count from batch response (handles raw int, @odata.count, and hashtable wrapper)
            $getCount = {
                param([string]$id)
                $resp = $batchResponses | Where-Object { $_.id -eq $id }
                if (-not $resp -or $resp.status -ne 200) { return $null }
                $rawBody = $resp.body
                if ($null -eq $rawBody) { return $null }
                if ($rawBody -is [int] -or $rawBody -is [long]) { return [int]$rawBody }
                # Try @odata.count (from ?$count=true queries)
                try {
                    $odataCount = $rawBody.'@odata.count'
                    if ($null -ne $odataCount) { return [int]$odataCount }
                } catch {}
                # Try .value as raw int
                try {
                    $val = $rawBody.'value'
                    if ($null -ne $val -and ($val -is [int] -or $val -is [long])) { return [int]$val }
                } catch {}
                try { return [int]$rawBody } catch { return $null }
            }

            $intuneCount = & $getCount "intune"
            $autopilotCount = & $getCount "autopilot"
            $entraCount = & $getCount "entra"
            $stale30 = & $getCount "stale30"
            $stale90 = & $getCount "stale90"
            $stale180 = & $getCount "stale180"
            $personalDevices = & $getCount "personal"
            $corporateDevices = & $getCount "corporate"
            $osWindows = & $getCount "osWindows"
            $osmacOS = & $getCount "osmacOS"
            $osiOS = & $getCount "osiOS"
            $osAndroid = & $getCount "osAndroid"
            $osLinux = & $getCount "osLinux"

            # Log which counts failed and use defaults for non-critical ones
            $failedIds = @()
            if ($null -eq $intuneCount)  { $failedIds += "intune" }
            if ($null -eq $entraCount)   { $failedIds += "entra" }
            if ($failedIds.Count -gt 0) {
                throw "Core `$count queries failed: $($failedIds -join ', ')"
            }
            # Non-critical counts — default to 0 if the filter query is unsupported
            if ($null -eq $autopilotCount) {
                # Autopilot $count not supported in batch — fetch count directly
                try {
                    $apResponse = Invoke-GraphRequestWithRetry -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities?`$top=1&`$count=true" -Method GET
                    $autopilotCount = if ($apResponse.'@odata.count') { [int]$apResponse.'@odata.count' } else { @($apResponse.value).Count }
                    Write-Log "Autopilot count fetched directly: $autopilotCount"
                } catch {
                    Write-Log "Autopilot count fetch failed, trying full list: $_" -Severity "WARN"
                    try {
                        $apAll = Get-GraphPagedResults -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities"
                        $autopilotCount = @($apAll).Count
                        Write-Log "Autopilot count from full list: $autopilotCount"
                    } catch {
                        Write-Log "Autopilot endpoint unavailable, defaulting to 0: $_" -Severity "WARN"
                        $autopilotCount = 0
                    }
                }
            }
            if ($null -eq $stale30)           { Write-Log "stale30 `$count returned null, defaulting to 0" -Severity "WARN";    $stale30 = 0 }
            if ($null -eq $stale90)           { Write-Log "stale90 `$count returned null, defaulting to 0" -Severity "WARN";    $stale90 = 0 }
            if ($null -eq $stale180)          { Write-Log "stale180 `$count returned null, defaulting to 0" -Severity "WARN";   $stale180 = 0 }
            if ($null -eq $personalDevices)   { Write-Log "personal `$count returned null, defaulting to 0" -Severity "WARN";   $personalDevices = 0 }
            if ($null -eq $corporateDevices)  { Write-Log "corporate `$count returned null, defaulting to 0" -Severity "WARN";  $corporateDevices = 0 }

            $countSuccess = $true
            $duration = (Get-Date) - $startTime
            Write-Log "Dashboard $count batch completed in $($duration.TotalSeconds) seconds"

            # Update top row counts
            $Window.FindName('IntuneDevicesCount').Text = $intuneCount
            $Window.FindName('AutopilotDevicesCount').Text = $autopilotCount
            $Window.FindName('EntraIDDevicesCount').Text = $entraCount

            Write-Log "Stale device counts - 30 days: $stale30, 90 days: $stale90, 180 days: $stale180"
            $Window.FindName('StaleDevices30Count').Text = $stale30
            $Window.FindName('StaleDevices90Count').Text = $stale90
            $Window.FindName('StaleDevices180Count').Text = $stale180

            # Update stale device progress bars
            $totalDevices = $intuneCount
            if ($totalDevices -gt 0) {
                $Window.FindName('StaleDevices30Progress').Value = [Math]::Round(($stale30 / $totalDevices) * 100)
                $Window.FindName('StaleDevices90Progress').Value = [Math]::Round(($stale90 / $totalDevices) * 100)
                $Window.FindName('StaleDevices180Progress').Value = [Math]::Round(($stale180 / $totalDevices) * 100)
            }

            # Update personal/corporate counts and progress bars
            $Window.FindName('PersonalDevicesCount').Text = $personalDevices
            $Window.FindName('CorporateDevicesCount').Text = $corporateDevices

            if ($totalDevices -gt 0) {
                $personalProgress = [Math]::Round(($personalDevices / $totalDevices) * 100)
                $corporateProgress = [Math]::Round(($corporateDevices / $totalDevices) * 100)
                $Window.FindName('PersonalDevicesProgress').Value = $personalProgress
                $Window.FindName('CorporateDevicesProgress').Value = $corporateProgress
            }

            # Build platform groups from $count results for pie chart
            # When a specific platform is selected, pie chart shows only that platform
            if ($platformFilterStandalone) {
                $platformGroups = @([PSCustomObject]@{ Name = $Platform; Count = $intuneCount })
            } else {
                if ($null -eq $osWindows) { $osWindows = 0 }
                if ($null -eq $osmacOS) { $osmacOS = 0 }
                if ($null -eq $osiOS) { $osiOS = 0 }
                if ($null -eq $osAndroid) { $osAndroid = 0 }
                if ($null -eq $osLinux) { $osLinux = 0 }
                $osOther = [Math]::Max(0, $intuneCount - ($osWindows + $osmacOS + $osiOS + $osAndroid + $osLinux))

                $platformGroups = @()
                if ($osWindows -gt 0) { $platformGroups += [PSCustomObject]@{ Name = 'Windows'; Count = $osWindows } }
                if ($osmacOS -gt 0) { $platformGroups += [PSCustomObject]@{ Name = 'macOS'; Count = $osmacOS } }
                if ($osiOS -gt 0) { $platformGroups += [PSCustomObject]@{ Name = 'iOS'; Count = $osiOS } }
                if ($osAndroid -gt 0) { $platformGroups += [PSCustomObject]@{ Name = 'Android'; Count = $osAndroid } }
                if ($osLinux -gt 0) { $platformGroups += [PSCustomObject]@{ Name = 'Linux'; Count = $osLinux } }
                if ($osOther -gt 0) { $platformGroups += [PSCustomObject]@{ Name = 'Other'; Count = $osOther } }
                $platformGroups = $platformGroups | Sort-Object Count -Descending
            }
        }
        catch {
            Write-Log "Dashboard `$count batch failed, falling back to full fetch: $_" -Severity "WARN"
        }

        # Fallback: full-fetch approach if $count batch failed
        if (-not $countSuccess) {
            $intuneDevices = @(Get-GraphPagedResults -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$select=deviceName,serialNumber,lastSyncDateTime,operatingSystem,managedDeviceOwnerType")
            $autopilotDevices = @()
            try {
                $autopilotDevices = @(Get-GraphPagedResults -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities")
            } catch {
                Write-Log "Autopilot fallback fetch failed (endpoint may be unavailable or permissions missing): $_" -Severity "WARN"
            }
            $entraDevices = @(Get-GraphPagedResults -Uri "https://graph.microsoft.com/beta/devices?`$select=displayName,operatingSystem,operatingSystemVersion")

            Write-Log "Fallback: Total devices - Intune: $($intuneDevices.Count), Autopilot: $($autopilotDevices.Count), Entra: $($entraDevices.Count)"

            $Window.FindName('IntuneDevicesCount').Text = $intuneDevices.Count
            $Window.FindName('AutopilotDevicesCount').Text = $autopilotDevices.Count
            $Window.FindName('EntraIDDevicesCount').Text = $entraDevices.Count

            # Calculate stale devices client-side
            $thirtyDaysAgo = (Get-Date).AddDays(-30)
            $ninetyDaysAgo = (Get-Date).AddDays(-90)
            $onehundredEightyDaysAgo = (Get-Date).AddDays(-180)

            $stale30 = ($intuneDevices | Where-Object {
                if ($_.lastSyncDateTime) {
                    try { $lastSync = ConvertTo-SafeDateTime -dateString $_.lastSyncDateTime; return $lastSync -and $lastSync -lt $thirtyDaysAgo }
                    catch { return $false }
                } else { return $false }
            }).Count
            $stale90 = ($intuneDevices | Where-Object {
                if ($_.lastSyncDateTime) {
                    try { $lastSync = ConvertTo-SafeDateTime -dateString $_.lastSyncDateTime; return $lastSync -and $lastSync -lt $ninetyDaysAgo }
                    catch { return $false }
                } else { return $false }
            }).Count
            $stale180 = ($intuneDevices | Where-Object {
                if ($_.lastSyncDateTime) {
                    try { $lastSync = ConvertTo-SafeDateTime -dateString $_.lastSyncDateTime; return $lastSync -and $lastSync -lt $onehundredEightyDaysAgo }
                    catch { return $false }
                } else { return $false }
            }).Count

            $Window.FindName('StaleDevices30Count').Text = $stale30
            $Window.FindName('StaleDevices90Count').Text = $stale90
            $Window.FindName('StaleDevices180Count').Text = $stale180

            $totalDevices = if ($intuneDevices) { $intuneDevices.Count } else { 0 }

            # Update stale device progress bars
            if ($totalDevices -gt 0) {
                $Window.FindName('StaleDevices30Progress').Value = [Math]::Round(($stale30 / $totalDevices) * 100)
                $Window.FindName('StaleDevices90Progress').Value = [Math]::Round(($stale90 / $totalDevices) * 100)
                $Window.FindName('StaleDevices180Progress').Value = [Math]::Round(($stale180 / $totalDevices) * 100)
            }

            $personalDevices = ($intuneDevices | Where-Object { $_.managedDeviceOwnerType -eq 'personal' }).Count
            $corporateDevices = ($intuneDevices | Where-Object { $_.managedDeviceOwnerType -eq 'company' }).Count

            $Window.FindName('PersonalDevicesCount').Text = $personalDevices
            $Window.FindName('CorporateDevicesCount').Text = $corporateDevices

            if ($totalDevices -gt 0) {
                $personalProgress = [Math]::Round(($personalDevices / $totalDevices) * 100)
                $corporateProgress = [Math]::Round(($corporateDevices / $totalDevices) * 100)
                $Window.FindName('PersonalDevicesProgress').Value = $personalProgress
                $Window.FindName('CorporateDevicesProgress').Value = $corporateProgress
            }

            # Group platform distribution client-side
            $platformGroups = $intuneDevices | Group-Object -Property {
                $os = $_.operatingSystem
                if ([string]::IsNullOrWhiteSpace($os)) { return "Unknown" }
                switch -Regex ($os.ToLower()) {
                    'windows' { "Windows" }
                    'macos|mac os' { "macOS" }
                    'linux' { "Linux" }
                    'ios' { "iOS" }
                    'android' { "Android" }
                    default { "Other" }
                }
            } | Sort-Object Count -Descending
        }

        # Draw pie chart from $platformGroups (works for both $count and fallback paths)
        $platformColors = @{
            'Windows' = '#0078D4'
            'iOS'     = '#48BB78'
            'Android' = '#9F7AEA'
            'macOS'   = '#F6AD55'
            'Linux'   = '#FC8181'
            'Other'   = '#718096'
            'Unknown' = '#718096'
        }

        $canvas = $Window.FindName('PlatformDistributionCanvas')
        $legendPanel = $Window.FindName('PlatformDistributionLegend')
        $canvas.Children.Clear()
        $legendPanel.Children.Clear()

        $total = ($platformGroups | Measure-Object Count -Sum).Sum
        if ($total -eq 0) { return }

        $centerX = 100
        $centerY = 100
        $radius = 80
        $startAngle = 0

        foreach ($platform in $platformGroups) {
            $percentage = $platform.Count / $total
            $sweepAngle = 360 * $percentage

            $startRad = $startAngle * [Math]::PI / 180
            $endRad = ($startAngle + $sweepAngle) * [Math]::PI / 180

            $startX = $centerX + $radius * [Math]::Cos($startRad)
            $startY = $centerY + $radius * [Math]::Sin($startRad)
            $endX = $centerX + $radius * [Math]::Cos($endRad)
            $endY = $centerY + $radius * [Math]::Sin($endRad)

            $path = New-Object System.Windows.Shapes.Path
            $pathGeometry = New-Object System.Windows.Media.PathGeometry
            $pathFigure = New-Object System.Windows.Media.PathFigure

            $pathFigure.StartPoint = New-Object System.Windows.Point($centerX, $centerY)

            $lineSegment = New-Object System.Windows.Media.LineSegment(
                (New-Object System.Windows.Point($startX, $startY)), $true)
            $pathFigure.Segments.Add($lineSegment)

            $arcSegment = New-Object System.Windows.Media.ArcSegment(
                (New-Object System.Windows.Point($endX, $endY)),
                (New-Object System.Windows.Size($radius, $radius)),
                0,
                ($sweepAngle -gt 180),
                [System.Windows.Media.SweepDirection]::Clockwise,
                $true)
            $pathFigure.Segments.Add($arcSegment)

            $lineSegment = New-Object System.Windows.Media.LineSegment(
                (New-Object System.Windows.Point($centerX, $centerY)), $true)
            $pathFigure.Segments.Add($lineSegment)

            $pathGeometry.Figures.Add($pathFigure)
            $path.Data = $pathGeometry

            $pName = if ($platform.Name) { $platform.Name } else { 'Unknown' }
            $color = if ($platformColors[$pName]) { $platformColors[$pName] } else { $platformColors['Unknown'] }
            $path.Fill = New-Object System.Windows.Media.SolidColorBrush(
                [System.Windows.Media.ColorConverter]::ConvertFromString($color))

            $canvas.Children.Add($path)

            $legendItem = New-Object System.Windows.Controls.StackPanel
            $legendItem.Orientation = "Horizontal"
            $legendItem.Margin = New-Object System.Windows.Thickness(0, 0, 0, 5)

            $colorBox = New-Object System.Windows.Shapes.Rectangle
            $colorBox.Width = 12
            $colorBox.Height = 12
            $colorBox.Fill = $path.Fill
            $colorBox.Margin = New-Object System.Windows.Thickness(0, 0, 5, 0)

            $label = New-Object System.Windows.Controls.TextBlock
            $label.Text = "$($platform.Name) ($([Math]::Round($percentage * 100))%)"
            $label.Foreground = "White"
            $label.VerticalAlignment = "Center"

            $legendItem.Children.Add($colorBox)
            $legendItem.Children.Add($label)
            $legendPanel.Children.Add($legendItem)

            $startAngle += $sweepAngle
        }

        Write-Log "Dashboard statistics updated successfully."
    }
    catch {
        Write-Log "Error updating dashboard statistics: $_"
        Show-Toast -Message "Error updating dashboard statistics. Please ensure you are connected to MS Graph." -Type "error" -DurationSeconds 6
    }
}
