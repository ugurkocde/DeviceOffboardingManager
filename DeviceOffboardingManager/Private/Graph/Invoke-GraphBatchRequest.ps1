function Invoke-GraphBatchRequest {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Requests
    )

    $allResponses = @()
    $chunkSize = 20

    for ($i = 0; $i -lt $Requests.Count; $i += $chunkSize) {
        $end = [Math]::Min($i + $chunkSize, $Requests.Count) - 1
        $chunk = $Requests[$i..$end]

        $batchBody = @{ requests = $chunk } | ConvertTo-Json -Depth 10
        $batchResponse = Invoke-GraphRequestWithRetry -Uri "https://graph.microsoft.com/beta/`$batch" -Method POST -Body $batchBody -ContentType "application/json"

        if ($batchResponse.responses) {
            # Retry individual sub-requests that returned 429 or 5xx
            $retryable = $batchResponse.responses | Where-Object { $_.status -eq 429 -or ($_.status -ge 500 -and $_.status -lt 600) }
            $successful = $batchResponse.responses | Where-Object { $_.status -lt 429 -or ($_.status -gt 429 -and $_.status -lt 500) -or $_.status -ge 600 }
            $allResponses += $successful

            $retryAttempt = 0
            while ($retryable -and $retryAttempt -lt 3) {
                $retryAttempt++
                $delay = 2 * [Math]::Pow(2, $retryAttempt - 1)
                Write-Log "Batch: retrying $($retryable.Count) sub-requests (attempt $retryAttempt/3)" -Severity "WARN"
                Start-Sleep -Seconds $delay

                $retryRequests = foreach ($resp in $retryable) {
                    $chunk | Where-Object { $_.id -eq $resp.id }
                }
                $retryBody = @{ requests = @($retryRequests) } | ConvertTo-Json -Depth 10
                $retryResponse = Invoke-GraphRequestWithRetry -Uri "https://graph.microsoft.com/beta/`$batch" -Method POST -Body $retryBody -ContentType "application/json"

                if ($retryResponse.responses) {
                    $retryable = $retryResponse.responses | Where-Object { $_.status -eq 429 -or ($_.status -ge 500 -and $_.status -lt 600) }
                    $newSuccessful = $retryResponse.responses | Where-Object { $_.status -lt 429 -or ($_.status -gt 429 -and $_.status -lt 500) -or $_.status -ge 600 }
                    $allResponses += $newSuccessful
                } else {
                    break
                }
            }
            # If still retryable after max attempts, add them as-is
            if ($retryable) {
                $allResponses += $retryable
            }
        }
    }

    return $allResponses
}
