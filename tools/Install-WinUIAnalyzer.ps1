[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\artifacts\winui-analyzer')
)

$ErrorActionPreference = 'Stop'

$commit = '7b7cfbfd97118bb477695354943ee94bb2203a52'
$baseUri = "https://raw.githubusercontent.com/microsoft/win-dev-skills/$commit/plugins/winui/skills/winui-dev-workflow/analyzer"
$files = @(
    @{
        Name = 'Microsoft.WindowsAppSDK.Analyzers.dll'
        Sha256 = 'e989099a0e369a1f2c114b4d86a82789f1006d73efc719db96e9bbe45d88671c'
    },
    @{
        Name = 'Microsoft.WindowsAppSDK.Analyzers.targets'
        Sha256 = '80e801c7d787248009cf365268a8dbdd16a30399806b3fe85a7fe87badba3727'
    }
)

New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
foreach ($file in $files) {
    $destination = Join-Path $OutputPath $file.Name
    Invoke-WebRequest -Uri "$baseUri/$($file.Name)" -OutFile $destination
    $actualHash = (Get-FileHash -Path $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $file.Sha256) {
        Remove-Item -Path $destination -Force
        throw "Hash validation failed for $($file.Name)."
    }
}

Resolve-Path $OutputPath
