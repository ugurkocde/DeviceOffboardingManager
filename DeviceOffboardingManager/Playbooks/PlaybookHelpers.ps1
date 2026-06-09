# Shared helper functions for all playbooks
# Dot-source this file at the top of each playbook:
#   $helpersPath = Join-Path $PSScriptRoot "PlaybookHelpers.ps1"
#   . $helpersPath

function ConvertTo-SafeDateTime {
    param(
        [Parameter(Mandatory = $false)]
        [string]$dateString
    )

    if ([string]::IsNullOrWhiteSpace($dateString)) {
        return $null
    }

    $formats = @(
        "yyyy-MM-ddTHH:mm:ssZ",
        "yyyy-MM-ddTHH:mm:ss.fffffffZ",
        "yyyy-MM-ddTHH:mm:ss",
        "MM/dd/yyyy HH:mm:ss",
        "dd/MM/yyyy HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss",
        "M/d/yyyy h:mm:ss tt",
        "M/d/yyyy H:mm:ss"
    )

    $culture = [System.Globalization.CultureInfo]::InvariantCulture

    foreach ($format in $formats) {
        try {
            $parsedDate = [DateTime]::ParseExact($dateString, $format, $culture, [System.Globalization.DateTimeStyles]::None)
            if ($parsedDate -eq [DateTime]::MinValue) { return $null }
            return $parsedDate
        }
        catch { continue }
    }

    try {
        $parsedDate = [DateTime]::Parse($dateString, $culture)
        if ($parsedDate -eq [DateTime]::MinValue) { return $null }
        return $parsedDate
    }
    catch {
        Write-Warning "Failed to parse date: $dateString"
        return $null
    }
}

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

            if ($statusCode -eq 429) {
                if ($attempt -gt $MaxRetries) { throw }
                $retryAfter = $BaseDelaySeconds
                if ($_.Exception.Response.Headers -and $_.Exception.Response.Headers['Retry-After']) {
                    $retryAfter = [int]$_.Exception.Response.Headers['Retry-After']
                }
                Write-Warning "Throttled (429) on $Method $Uri -- retrying in ${retryAfter}s (attempt $attempt/$MaxRetries)"
                Start-Sleep -Seconds $retryAfter
                continue
            }

            if ($null -eq $statusCode -or ($statusCode -ge 500 -and $statusCode -lt 600)) {
                if ($attempt -gt $MaxRetries) { throw }
                $delay = $BaseDelaySeconds * [Math]::Pow(2, $attempt - 1)
                Write-Warning "Server error ($statusCode) on $Method $Uri -- retrying in ${delay}s (attempt $attempt/$MaxRetries)"
                Start-Sleep -Seconds $delay
                continue
            }

            throw
        }
    }
}

function Get-GraphPagedResults {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [hashtable]$Headers = @{}
    )

    $results = @()
    $nextLink = $Uri

    do {
        try {
            $response = Invoke-GraphRequestWithRetry -Uri $nextLink -Method GET -Headers $Headers
            if ($response.value) {
                $results += $response.value
            }
            $nextLink = $response.'@odata.nextLink'
        }
        catch {
            Write-Error "Error in pagination: $_"
            break
        }
    } while ($nextLink)

    return $results
}
