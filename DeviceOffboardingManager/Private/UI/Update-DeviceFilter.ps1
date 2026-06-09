function Update-DeviceFilter {
    if (-not $script:AllSearchResults) { return }
    $filtered = $script:AllSearchResults
    $nameFilter = $FilterDeviceName.Text
    $serialFilter = $FilterSerialNumber.Text
    $osFilter = $FilterOS.Text
    $userFilter = $FilterPrimaryUser.Text
    $compFilter = $FilterCompliance.Text
    if ($nameFilter) { $filtered = $filtered | Where-Object { $_.DeviceName -like "*$nameFilter*" } }
    if ($serialFilter) { $filtered = $filtered | Where-Object { $_.SerialNumber -like "*$serialFilter*" } }
    if ($osFilter) { $filtered = $filtered | Where-Object { $_.OperatingSystem -like "*$osFilter*" } }
    if ($userFilter) { $filtered = $filtered | Where-Object { $_.PrimaryUser -like "*$userFilter*" } }
    if ($compFilter) { $filtered = $filtered | Where-Object { $_.ComplianceState -like "*$compFilter*" } }
    $SearchResultsDataGrid.ItemsSource = @($filtered)
    $script:LastCheckedIndex = -1
}
