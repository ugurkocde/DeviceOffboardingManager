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
            Write-Log "Error in pagination: $_"
            break
        }
    } while ($nextLink)

    return $results
}
