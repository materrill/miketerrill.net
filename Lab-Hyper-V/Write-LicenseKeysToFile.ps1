<#
.SYNOPSIS
    PowerShell script to read the license keys for DeployR and StifleR from TS variables and write them to a 2PintLicenseKeys.reg file.
.DESCRIPTION
    This script will read the license keys from the TS variables and write them to a 2PintLicenseKeys.reg file.
    It verifies the write, and handles common errors.
.NOTES
    Author: Mike Terrill/2Pint Software
    Date: July 30, 2026
    Version: 26.07.30
    Requires: Administrative privileges, 64-bit Windows

    Version history:
    26.07.30: Initial release
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RegFilePath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $trimmedPath = $Path.Trim()
    $looksLikeFile = [System.IO.Path]::GetExtension($trimmedPath) -ieq '.reg'

    if ($looksLikeFile) {
        $directoryPath = Split-Path -Path $trimmedPath -Parent
        if ([string]::IsNullOrWhiteSpace($directoryPath)) {
            $directoryPath = (Get-Location).Path
        }

        return [pscustomobject]@{
            DirectoryPath = $directoryPath
            FilePath      = $trimmedPath
        }
    }

    return [pscustomobject]@{
        DirectoryPath = $trimmedPath
        FilePath      = Join-Path -Path $trimmedPath -ChildPath '2PintLicenseKeys.reg'
    }
}

try {
    $stifleRKey = [string]${tsenv:StifleRKey}
    $deployRKey = [string]${tsenv:DeployRKey}

    if ([string]::IsNullOrWhiteSpace($stifleRKey)) {
        throw "Task sequence variable 'StifleRKey' is missing or empty."
    }

    if ([string]::IsNullOrWhiteSpace($deployRKey)) {
        throw "Task sequence variable 'DeployRKey' is missing or empty."
    }

    $stifleRKey = $stifleRKey.Trim()
    $deployRKey = $deployRKey.Trim()

    $resolvedPaths = Resolve-RegFilePath -Path $OutputPath
    if (-not (Test-Path -Path $resolvedPaths.DirectoryPath -PathType Container)) {
        New-Item -Path $resolvedPaths.DirectoryPath -ItemType Directory -Force | Out-Null
    }

    $licenseKeysValue = '"[' + (($stifleRKey, $deployRKey | ForEach-Object { '\"' + $_ + '\"' }) -join ',') + ']"'
    $fileContent = @(
        'Windows Registry Editor Version 5.00'
        ''
        '[HKEY_LOCAL_MACHINE\SOFTWARE\2Pint Software\StifleR\Server\GeneralSettings]'
        '"LicenseKeys"=' + $licenseKeysValue
    )

    Set-Content -Path $resolvedPaths.FilePath -Value $fileContent -Encoding ASCII -Force

    if (-not (Test-Path -Path $resolvedPaths.FilePath -PathType Leaf)) {
        throw "The registry file was not created: $($resolvedPaths.FilePath)"
    }

    $writtenContent = Get-Content -Path $resolvedPaths.FilePath -Encoding ASCII
    if (($writtenContent -join "`r`n") -ne ($fileContent -join "`r`n")) {
        throw "The registry file content verification failed: $($resolvedPaths.FilePath)"
    }

    Write-Host "Successfully wrote license keys to $($resolvedPaths.FilePath)" -ForegroundColor Green
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}

