function Get-SerialNumberFromPhysicalIds {
    param(
        [Parameter(Mandatory = $false)]
        $PhysicalIds
    )

    if (-not $PhysicalIds) {
        return $null
    }

    foreach ($physicalId in $PhysicalIds) {
        if ($physicalId -match '\[SerialNumber\]:(.+)') {
            return $matches[1].Trim()
        }
    }

    return $null
}
