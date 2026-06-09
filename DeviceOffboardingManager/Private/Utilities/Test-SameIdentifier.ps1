function Test-SameIdentifier {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Left,
        [Parameter(Mandatory = $false)]
        [string]$Right
    )

    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) {
        return $false
    }

    return $Left.Trim().Equals($Right.Trim(), [System.StringComparison]::OrdinalIgnoreCase)
}
