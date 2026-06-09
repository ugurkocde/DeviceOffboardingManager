function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Message,
        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARN", "ERROR", "AUDIT")]
        [string] $Severity = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $admin = if ($script:AdminUPN) { $script:AdminUPN } else { "N/A" }
    $logMessage = "$timestamp | $Severity | $admin | $Message"

    Add-Content -Path $script:LogFilePath -Value $logMessage

    if ($script:VerboseMode -and $Severity -in @("WARN", "ERROR")) {
        $color = if ($Severity -eq "ERROR") { "Red" } else { "Yellow" }
        Write-Host "[$Severity] $Message" -ForegroundColor $color
    }
}
