<#
.SYNOPSIS
    Imports DeployR task sequence variables from a JSON file.

.DESCRIPTION
    Reads a JSON file containing task sequence variables and sets
    each variable in the DeployR task sequence environment.

.NOTES
    Author: Mike Terrill / 2Pint Software
    Date: September 2, 2026
    Version: 26.09.02
    Requires: Administrative privileges, 64-bit Windows, DeployR TS environment

    Version history:
    26.09.02: Initial Release

.EXAMPLE
    .\Set-TSVarsFromJSONFile.ps1

.EXAMPLE
    .\Set-TSVarsFromJSONFile.ps1 -InputFile .\LabKit001.json

.NOTES
    Expected JSON format:

    {
        "KeyboardLayout": "0809:00000809;0409:00000409",
        "MyVariable": "LabKit001"
    }
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$InputFile = "TSVariables.json"
)

$InputFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InputFile)

if (-not (Test-Path $InputFile)) {
    throw "File not found: $InputFile"
}

try {
    $Variables = Get-Content -Path $InputFile -Raw | ConvertFrom-Json
}
catch {
    throw "Failed to parse JSON file '$InputFile'. $_"
}

$Count = 0

foreach ($Property in $Variables.PSObject.Properties) {

    $Name  = $Property.Name
    $Value = [string]$Property.Value

    Set-Item -Path "TSENV:\$Name" -Value $Value

    Write-Host "Set TS Variable: $Name = $Value"

    $Count++
}

Write-Host "Imported $Count task sequence variable(s) from '$InputFile'"