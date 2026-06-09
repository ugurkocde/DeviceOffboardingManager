function Export-OffboardingReport {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Results,
        [Parameter(Mandatory = $false)]
        [string]$DefaultFileName = "OffboardingReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    )

    try {
        $saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
        $saveFileDialog.Filter = "HTML Files (*.html)|*.html"
        $saveFileDialog.DefaultExt = "html"
        $saveFileDialog.FileName = $DefaultFileName
        $saveFileDialog.Title = "Export Offboarding Report"

        if ($saveFileDialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $false }

        $exportPath = $saveFileDialog.FileName
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $adminUPN = [System.Web.HttpUtility]::HtmlEncode($(if ($script:AdminUPN) { $script:AdminUPN } else { "N/A" }))
        $version = Get-ScriptVersion

        # Calculate summary stats
        $total = $Results.Count
        $successCount = 0
        $partialCount = 0
        $failedCount = 0
        foreach ($r in $Results) {
            $svc = 0; $ok = 0
            if ($r.EntraID.Found) { $svc++; if ($r.EntraID.Success) { $ok++ } }
            if ($r.Intune.Found) { $svc++; if ($r.Intune.Success) { $ok++ } }
            if ($r.Autopilot.Found) { $svc++; if ($r.Autopilot.Success) { $ok++ } }
            if ($r.MDE -and $r.MDE.Found) { $svc++; if ($r.MDE.Success) { $ok++ } }
            if ($svc -eq 0) { $failedCount++ }
            elseif ($ok -eq $svc) { $successCount++ }
            elseif ($ok -gt 0) { $partialCount++ }
            else { $failedCount++ }
        }

        # Build device rows
        $deviceRows = ""
        foreach ($r in $Results) {
            $entraStatus = if ($r.EntraID.Found) { if ($r.EntraID.Success) { "Removed" } else { "Failed" } } else { "N/A" }
            $entraClass = if (-not $r.EntraID.Found) { "na" } elseif ($r.EntraID.Success) { "success" } else { "failed" }
            $entraError = if ($r.EntraID.Error) { "<br><small>$([System.Web.HttpUtility]::HtmlEncode($r.EntraID.Error))</small>" } else { "" }

            $intuneStatus = if ($r.Intune.Found) { if ($r.Intune.Success) { "Removed" } else { "Failed" } } else { "N/A" }
            $intuneClass = if (-not $r.Intune.Found) { "na" } elseif ($r.Intune.Success) { "success" } else { "failed" }
            $intuneError = if ($r.Intune.Error) { "<br><small>$([System.Web.HttpUtility]::HtmlEncode($r.Intune.Error))</small>" } else { "" }

            $autopilotStatus = if ($r.Autopilot.Found) { if ($r.Autopilot.Success) { "Removed" } else { "Failed" } } else { "N/A" }
            $autopilotClass = if (-not $r.Autopilot.Found) { "na" } elseif ($r.Autopilot.Success) { "success" } else { "failed" }
            $autopilotError = if ($r.Autopilot.Error) { "<br><small>$([System.Web.HttpUtility]::HtmlEncode($r.Autopilot.Error))</small>" } else { "" }

            $mdeStatus = if ($r.MDE -and $r.MDE.Found) { if ($r.MDE.Success) { "Offboarded" } else { "Failed" } } else { "N/A" }
            $mdeClass = if (-not $r.MDE -or -not $r.MDE.Found) { "na" } elseif ($r.MDE.Success) { "success" } else { "failed" }
            $mdeError = if ($r.MDE -and $r.MDE.Error) { "<br><small>$([System.Web.HttpUtility]::HtmlEncode($r.MDE.Error))</small>" } else { "" }

            $deviceName = [System.Web.HttpUtility]::HtmlEncode($r.DeviceName)
            $serialNum = if ($r.SerialNumber) { [System.Web.HttpUtility]::HtmlEncode($r.SerialNumber) } else { "N/A" }

            # Determine row class
            $svc = 0; $ok = 0
            if ($r.EntraID.Found) { $svc++; if ($r.EntraID.Success) { $ok++ } }
            if ($r.Intune.Found) { $svc++; if ($r.Intune.Success) { $ok++ } }
            if ($r.Autopilot.Found) { $svc++; if ($r.Autopilot.Success) { $ok++ } }
            if ($r.MDE -and $r.MDE.Found) { $svc++; if ($r.MDE.Success) { $ok++ } }
            $rowClass = if ($svc -eq 0) { "row-failed" } elseif ($ok -eq $svc) { "row-success" } elseif ($ok -gt 0) { "row-partial" } else { "row-failed" }

            $deviceRows += @"
            <tr class="$rowClass">
                <td>$deviceName</td>
                <td>$serialNum</td>
                <td class="$entraClass">$entraStatus$entraError</td>
                <td class="$intuneClass">$intuneStatus$intuneError</td>
                <td class="$autopilotClass">$autopilotStatus$autopilotError</td>
                <td class="$mdeClass">$mdeStatus$mdeError</td>
            </tr>
"@
        }

        $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Device Offboarding Report</title>
<style>
    body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; background: #f8f9fa; color: #1a202c; }
    .container { max-width: 1100px; margin: 0 auto; }
    .header { background: #1B2A47; color: white; padding: 24px 32px; border-radius: 8px 8px 0 0; }
    .header h1 { margin: 0 0 8px 0; font-size: 22px; }
    .header .meta { font-size: 12px; color: #a0aec0; }
    .summary { display: flex; gap: 16px; padding: 20px 32px; background: white; border-bottom: 1px solid #e2e8f0; }
    .stat { flex: 1; text-align: center; padding: 12px; border-radius: 6px; }
    .stat .number { font-size: 28px; font-weight: bold; }
    .stat .label { font-size: 12px; color: #718096; margin-top: 4px; }
    .stat-total { background: #edf2f7; }
    .stat-success { background: #f0fff4; }
    .stat-success .number { color: #48bb78; }
    .stat-partial { background: #fffbeb; }
    .stat-partial .number { color: #ecc94b; }
    .stat-failed { background: #fef2f2; }
    .stat-failed .number { color: #f56565; }
    table { width: 100%; border-collapse: collapse; background: white; }
    th { background: #edf2f7; padding: 10px 12px; text-align: left; font-size: 12px; font-weight: 600; color: #4a5568; border-bottom: 2px solid #e2e8f0; }
    td { padding: 10px 12px; font-size: 13px; border-bottom: 1px solid #e2e8f0; }
    td small { color: #f56565; }
    .row-success { border-left: 3px solid #48bb78; }
    .row-partial { border-left: 3px solid #ecc94b; }
    .row-failed { border-left: 3px solid #f56565; }
    .success { color: #48bb78; font-weight: 500; }
    .failed { color: #f56565; font-weight: 500; }
    .na { color: #a0aec0; }
    .footer { padding: 16px 32px; background: white; border-radius: 0 0 8px 8px; border-top: 1px solid #e2e8f0; font-size: 11px; color: #a0aec0; text-align: center; }
    @media print { body { background: white; padding: 0; } .container { max-width: 100%; } }
</style>
</head>
<body>
<div class="container">
    <div class="header">
        <h1>Device Offboarding Report</h1>
        <div class="meta">Generated: $timestamp | Admin: $adminUPN | Device Offboarding Manager $version</div>
    </div>
    <div class="summary">
        <div class="stat stat-total"><div class="number">$total</div><div class="label">Total Devices</div></div>
        <div class="stat stat-success"><div class="number">$successCount</div><div class="label">Successful</div></div>
        <div class="stat stat-partial"><div class="number">$partialCount</div><div class="label">Partial</div></div>
        <div class="stat stat-failed"><div class="number">$failedCount</div><div class="label">Failed</div></div>
    </div>
    <table>
        <thead>
            <tr>
                <th>Device Name</th>
                <th>Serial Number</th>
                <th>Entra ID</th>
                <th>Intune</th>
                <th>Autopilot</th>
                <th>MDE</th>
            </tr>
        </thead>
        <tbody>
$deviceRows
        </tbody>
    </table>
    <div class="footer">Device Offboarding Manager - Audit Report</div>
</div>
</body>
</html>
"@

        [System.IO.File]::WriteAllText($exportPath, $html)
        Write-Log "Exported offboarding report to: $exportPath" -Severity "AUDIT"
        Show-Toast -Message "Report exported successfully to: $exportPath" -Type "success"
        return $true
    }
    catch {
        Write-Log "Error exporting offboarding report: $_" -Severity "ERROR"
        Show-Toast -Message "Error exporting report: $_" -Type "error" -DurationSeconds 6
        return $false
    }
}
