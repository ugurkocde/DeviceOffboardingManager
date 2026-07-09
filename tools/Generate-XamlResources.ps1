[CmdletBinding()]
param(
    [string]$ProjectRoot = (Join-Path $PSScriptRoot '..\src\DeviceOffboardingManager.WinUI')
)

$ErrorActionPreference = 'Stop'

$xamlNamespace = 'http://schemas.microsoft.com/winfx/2006/xaml'
$localizableProperties = @('Title', 'Text', 'Content', 'Header', 'PlaceholderText', 'Message', 'AutomationProperties.Name', 'ToolTipService.ToolTip')
$resources = [ordered]@{}

function ConvertTo-UidPart {
    param([string]$Value)

    $clean = [regex]::Replace($Value, '[^A-Za-z0-9]+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) {
        return 'Text'
    }

    return (($clean -split '\s+' | Select-Object -First 5) | ForEach-Object {
        if ($_.Length -eq 1) { $_.ToUpperInvariant() } else { $_[0].ToString().ToUpperInvariant() + $_.Substring(1) }
    }) -join ''
}

function Get-UniqueUid {
    param(
        [System.Xml.XmlElement]$Element,
        [string]$Prefix,
        [string]$Property,
        [string]$Value,
        [hashtable]$UsedUids
    )

    $name = $Element.GetAttribute('Name', $xamlNamespace)
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = $Element.GetAttribute('AutomationProperties.AutomationId')
    }
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = "$($Element.LocalName)$(ConvertTo-UidPart $Value)"
    }

    $candidate = $Prefix + [regex]::Replace($name, '[^A-Za-z0-9_]', '')
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $candidate = "$($Element.LocalName)$Property"
    }

    $uid = $candidate
    $suffix = 2
    while ($UsedUids.ContainsKey($uid)) {
        $uid = "$candidate$suffix"
        $suffix++
    }

    $UsedUids[$uid] = $true
    return $uid
}

$xamlFiles = Get-ChildItem -Path $ProjectRoot -Recurse -Filter '*.xaml' | Sort-Object FullName
$usedUids = @{}
foreach ($xamlFile in $xamlFiles) {
    $document = [System.Xml.XmlDocument]::new()
    $document.PreserveWhitespace = $true
    $document.Load($xamlFile.FullName)
    $prefix = "$($xamlFile.BaseName)_"
    $namespaceManager = [System.Xml.XmlNamespaceManager]::new($document.NameTable)
    $namespaceManager.AddNamespace('x', $xamlNamespace)

    foreach ($existing in $document.SelectNodes('//*[@x:Uid]', $namespaceManager)) {
        $uid = $existing.GetAttribute('Uid', $xamlNamespace)
        if (-not $uid.StartsWith($prefix, [StringComparison]::Ordinal)) {
            $uid = $prefix + $uid
            $existing.SetAttribute('Uid', $xamlNamespace, $uid) | Out-Null
        }
        $usedUids[$uid] = $true
    }

    foreach ($element in $document.SelectNodes('//*')) {
        if ($element -isnot [System.Xml.XmlElement]) {
            continue
        }

        $values = [ordered]@{}
        foreach ($property in $localizableProperties) {
            if (-not $element.HasAttribute($property)) {
                continue
            }

            $value = $element.GetAttribute($property)
            if ([string]::IsNullOrWhiteSpace($value) -or $value.StartsWith('{') -or $value -eq '--') {
                continue
            }

            $values[$property] = $value
        }

        if ($values.Count -eq 0) {
            continue
        }

        $uid = $element.GetAttribute('Uid', $xamlNamespace)
        if ([string]::IsNullOrWhiteSpace($uid)) {
            $first = $values.GetEnumerator() | Select-Object -First 1
            $uid = Get-UniqueUid -Element $element -Prefix $prefix -Property $first.Key -Value $first.Value -UsedUids $usedUids
            $element.SetAttribute('Uid', $xamlNamespace, $uid) | Out-Null
        }

        foreach ($entry in $values.GetEnumerator()) {
            $resources["$uid.$($entry.Key)"] = $entry.Value
        }
    }

    $settings = [System.Xml.XmlWriterSettings]::new()
    $settings.Indent = $true
    $settings.IndentChars = '    '
    $settings.NewLineChars = "`n"
    $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
    $settings.OmitXmlDeclaration = $false
    $writer = [System.Xml.XmlWriter]::Create($xamlFile.FullName, $settings)
    try {
        $document.Save($writer)
    }
    finally {
        $writer.Dispose()
    }
}

$dynamicResourcePath = Join-Path $PSScriptRoot 'dynamic-resources.json'
if (Test-Path $dynamicResourcePath) {
    $dynamicResources = Get-Content -Path $dynamicResourcePath -Raw | ConvertFrom-Json -AsHashtable
    foreach ($entry in $dynamicResources.GetEnumerator()) {
        $resources[$entry.Key] = $entry.Value
    }
}

$resourceDirectory = Join-Path $ProjectRoot 'Strings\en-us'
New-Item -ItemType Directory -Path $resourceDirectory -Force | Out-Null
$resourcePath = Join-Path $resourceDirectory 'Resources.resw'
$resourceDocument = [System.Xml.XmlDocument]::new()
$root = $resourceDocument.CreateElement('root')
$resourceDocument.AppendChild($root) | Out-Null

foreach ($header in @{
        resmimetype = 'text/microsoft-resx'
        version = '2.0'
        reader = 'System.Resources.ResXResourceReader, System.Windows.Forms, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089'
        writer = 'System.Resources.ResXResourceWriter, System.Windows.Forms, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089'
    }.GetEnumerator()) {
    $node = $resourceDocument.CreateElement('resheader')
    $node.SetAttribute('name', $header.Key) | Out-Null
    $valueNode = $resourceDocument.CreateElement('value')
    $valueNode.InnerText = $header.Value
    $node.AppendChild($valueNode) | Out-Null
    $root.AppendChild($node) | Out-Null
}

foreach ($entry in $resources.GetEnumerator() | Sort-Object Key) {
    $node = $resourceDocument.CreateElement('data')
    $node.SetAttribute('name', $entry.Key) | Out-Null
    $node.SetAttribute('space', 'http://www.w3.org/XML/1998/namespace', 'preserve') | Out-Null
    $valueNode = $resourceDocument.CreateElement('value')
    $valueNode.InnerText = $entry.Value
    $node.AppendChild($valueNode) | Out-Null
    $root.AppendChild($node) | Out-Null
}

$resourceSettings = [System.Xml.XmlWriterSettings]::new()
$resourceSettings.Indent = $true
$resourceSettings.IndentChars = '  '
$resourceSettings.NewLineChars = "`n"
$resourceSettings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
$resourceWriter = [System.Xml.XmlWriter]::Create($resourcePath, $resourceSettings)
try {
    $resourceDocument.Save($resourceWriter)
}
finally {
    $resourceWriter.Dispose()
}

[pscustomobject]@{
    XamlFiles = $xamlFiles.Count
    Resources = $resources.Count
    Output = $resourcePath
}
