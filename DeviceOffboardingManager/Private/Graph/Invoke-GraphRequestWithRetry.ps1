function Invoke-GraphRequestWithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [string]$Method = "GET",
        [string]$Body,
        [string]$ContentType = "application/json",
        [hashtable]$Headers = @{},
        [int]$MaxRetries = 3,
        [int]$BaseDelaySeconds = 2
    )

    $attempt = 0
    while ($true) {
        try {
            $params = @{
                Uri    = $Uri
                Method = $Method
            }
            if ($Headers.Count -gt 0) { $params.Headers = $Headers }
            if ($Body) {
                $params.Body = $Body
                $params.ContentType = $ContentType
            }
            return Invoke-MgGraphRequest @params
        }
        catch {
            $attempt++
            $statusCode = $null
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            # Throttled (429)
            if ($statusCode -eq 429) {
                if ($attempt -gt $MaxRetries) { throw }
                $retryAfter = $BaseDelaySeconds
                if ($_.Exception.Response.Headers -and $_.Exception.Response.Headers['Retry-After']) {
                    $retryAfter = [int]$_.Exception.Response.Headers['Retry-After']
                }
                Write-Log "Throttled (429) on $Method $Uri -- retrying in ${retryAfter}s (attempt $attempt/$MaxRetries)" -Severity "WARN"
                Start-Sleep -Seconds $retryAfter
                continue
            }

            # Transient server errors (500-599) or network-level failures (null status)
            if ($null -eq $statusCode -or ($statusCode -ge 500 -and $statusCode -lt 600)) {
                if ($attempt -gt $MaxRetries) { throw }
                $delay = $BaseDelaySeconds * [Math]::Pow(2, $attempt - 1)
                Write-Log "Server error ($statusCode) on $Method $Uri -- retrying in ${delay}s (attempt $attempt/$MaxRetries)" -Severity "WARN"
                Start-Sleep -Seconds $delay
                continue
            }

            # Non-retryable error
            throw
        }
    }
}
