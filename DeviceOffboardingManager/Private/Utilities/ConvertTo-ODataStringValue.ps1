function ConvertTo-ODataStringValue {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Value
    )

    if ($null -eq $Value) {
        return ""
    }

    return $Value.Replace("'", "''")
}
