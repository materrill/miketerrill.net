<#
.SYNOPSIS
    Creates or updates a JSON file containing task sequence variables.

.DESCRIPTION
    Accepts one or more variable/value pairs and writes them to a JSON file.

    When -Append is specified, existing variables are preserved and only
    the supplied variables are added or updated.

.NOTES
    Author: Mike Terrill / 2Pint Software
    Date: September 2, 2026
    Version: 26.09.02
    Requires: Administrative privileges, 64-bit Windows

    Version history:
    26.09.02: Initial Release

.EXAMPLE
    .\Create-TSVarsJSONFile.ps1 `
        -OutputFile .\TSVariables.json `
        KeyboardLayout "0809:00000809;0409:00000409" `
        MyVariable "LabKit001"

.EXAMPLE
    .\Create-TSVarsJSONFile.ps1 `
        -OutputFile .\TSVariables.json `
        -Append `
        ComputerName "LAB-PC01"
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputFile = "TSVariables.json",

    [Parameter()]
    [switch]$Append,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

if (($Arguments.Count % 2) -ne 0) {
    throw "Variable arguments must be supplied as name/value pairs."
}

# Create ordered hashtable for output
$Variables = [ordered]@{}

# Load existing JSON if appending
if ($Append -and (Test-Path $OutputFile)) {

    try {
        $ExistingJson = Get-Content -Path $OutputFile -Raw | ConvertFrom-Json

        foreach ($Property in $ExistingJson.PSObject.Properties) {
            $Variables[$Property.Name] = $Property.Value
        }
    }
    catch {
        throw "Failed to load existing JSON file '$OutputFile'. $_"
    }
}

# Add/update supplied variables
for ($i = 0; $i -lt $Arguments.Count; $i += 2) {
    $Name  = $Arguments[$i].TrimStart('-')
    $Value = $Arguments[$i + 1]

    $Variables[$Name] = $Value
}

$OutputFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFile)

$OutputDir = Split-Path -Path $OutputFile -Parent
if ($OutputDir -and -not (Test-Path $OutputDir)) {
    New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
}

$Variables |
    ConvertTo-Json -Depth 10 |
    Set-Content -Path $OutputFile -Encoding UTF8

Write-Host "Saved $($Variables.Count) variable(s) to '$OutputFile'"