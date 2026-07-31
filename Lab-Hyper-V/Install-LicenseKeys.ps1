<#
.SYNOPSIS
    PowerShell script to install the license keys for DeployR and StifleR after the install
.DESCRIPTION
    This script will check the 2PintLicenseKeys.reg file for the license keys and will import them into the registry.
    It verifies the import, and handles common errors.
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
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$RegFilePath = 'C:\2PintLicenseKeys.reg'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)

    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-RegistryHiveInfo {
    param(
        [Parameter(Mandatory)]
        [string]$HiveName
    )

    switch ($HiveName.ToUpperInvariant()) {
        'HKEY_LOCAL_MACHINE' {
            return @{
                Hive = [Microsoft.Win32.RegistryHive]::LocalMachine
                BasePath = 'HKLM:'
            }
        }
        'HKEY_CURRENT_USER' {
            return @{
                Hive = [Microsoft.Win32.RegistryHive]::CurrentUser
                BasePath = 'HKCU:'
            }
        }
        'HKEY_CLASSES_ROOT' {
            return @{
                Hive = [Microsoft.Win32.RegistryHive]::ClassesRoot
                BasePath = 'HKCR:'
            }
        }
        'HKEY_USERS' {
            return @{
                Hive = [Microsoft.Win32.RegistryHive]::Users
                BasePath = 'HKU:'
            }
        }
        'HKEY_CURRENT_CONFIG' {
            return @{
                Hive = [Microsoft.Win32.RegistryHive]::CurrentConfig
                BasePath = 'HKCC:'
            }
        }
        default {
            throw "Unsupported registry hive in .reg file: $HiveName"
        }
    }
}

function Convert-RegPathToPsPath {
    param(
        [Parameter(Mandatory)]
        [string]$RegistryPath
    )

    $firstSeparator = $RegistryPath.IndexOf('\')
    if ($firstSeparator -lt 0) {
        throw "Invalid registry path: $RegistryPath"
    }

    $hiveName = $RegistryPath.Substring(0, $firstSeparator)
    $subKeyPath = $RegistryPath.Substring($firstSeparator + 1)
    $hiveInfo = Get-RegistryHiveInfo -HiveName $hiveName

    return Join-Path -Path $hiveInfo.BasePath -ChildPath $subKeyPath
}

function Get-RegFileTargets {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $rawLines = Get-Content -Path $Path -ErrorAction Stop
    $currentKey = $null
    $targets = New-Object System.Collections.Generic.List[object]

    foreach ($line in $rawLines) {
        $trimmedLine = $line.Trim()

        if ([string]::IsNullOrWhiteSpace($trimmedLine) -or $trimmedLine.StartsWith(';')) {
            continue
        }

        if ($trimmedLine -match '^Windows Registry Editor Version') {
            continue
        }

        if ($trimmedLine -match '^\[(.+)\]$') {
            $keyName = $matches[1]
            if ($keyName.StartsWith('-')) {
                $currentKey = $null
                continue
            }

            $currentKey = $keyName
            $targets.Add([pscustomobject]@{
                Type = 'Key'
                RegistryPath = $currentKey
                ValueName = $null
            })
            continue
        }

        if (-not $currentKey) {
            continue
        }

        if ($trimmedLine -match '^"((?:[^"\\]|\\.)*)"\s*=') {
            $valueName = $matches[1] -replace '\\"', '"' -replace '\\\\', '\\'
            $targets.Add([pscustomobject]@{
                Type = 'Value'
                RegistryPath = $currentKey
                ValueName = $valueName
            })
            continue
        }

        if ($trimmedLine -match '^@\s*=') {
            $targets.Add([pscustomobject]@{
                Type = 'Value'
                RegistryPath = $currentKey
                ValueName = ''
            })
        }
    }

    return $targets
}

function Test-RegistryTargets {
    param(
        [Parameter(Mandatory)]
        [object[]]$Targets
    )

    $missingTargets = New-Object System.Collections.Generic.List[string]
    $registryView = [Microsoft.Win32.RegistryView]::Registry64

    foreach ($target in $Targets) {
        $firstSeparator = $target.RegistryPath.IndexOf('\')
        if ($firstSeparator -lt 0) {
            $missingTargets.Add("Invalid registry path format: $($target.RegistryPath)")
            continue
        }

        $hiveName = $target.RegistryPath.Substring(0, $firstSeparator)
        $subKeyPath = $target.RegistryPath.Substring($firstSeparator + 1)
        $hiveInfo = Get-RegistryHiveInfo -HiveName $hiveName

        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hiveInfo.Hive, $registryView)
        $subKey = $baseKey.OpenSubKey($subKeyPath, $false)

        if (-not $subKey) {
            $missingTargets.Add($target.RegistryPath)
            continue
        }

        if ($target.Type -eq 'Value') {
            $valueNames = $subKey.GetValueNames()
            $hasDefaultValue = $null -ne $subKey.GetValue('', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

            if ($target.ValueName -eq '') {
                if (-not $hasDefaultValue) {
                    $missingTargets.Add("$($target.RegistryPath) (Default)")
                }
            }
            elseif ($target.ValueName -notin $valueNames) {
                $missingTargets.Add("$($target.RegistryPath)\\$($target.ValueName)")
            }
        }

        $subKey.Dispose()
        $baseKey.Dispose()
    }

    return $missingTargets
}

try {
    Write-Host "Starting registry import from $RegFilePath" -ForegroundColor Cyan

    if (-not [Environment]::Is64BitOperatingSystem) {
        throw 'This script requires a 64-bit version of Windows.'
    }

    if (-not [Environment]::Is64BitProcess) {
        throw 'Run this script in a 64-bit PowerShell session.'
    }

    if (-not (Test-IsAdministrator)) {
        throw 'Administrative privileges are required to import registry keys.'
    }

    if (-not (Test-Path -Path $RegFilePath -PathType Leaf)) {
        throw "The registry file was not found: $RegFilePath"
    }

    $regExe = Join-Path -Path $env:SystemRoot -ChildPath 'System32\reg.exe'
    if (-not (Test-Path -Path $regExe -PathType Leaf)) {
        throw 'Could not locate reg.exe in the Windows System32 directory.'
    }

    $targets = Get-RegFileTargets -Path $RegFilePath
    if (-not $targets -or $targets.Count -eq 0) {
        throw 'The registry file did not contain any importable keys or values.'
    }

    $importOutput = & $regExe import $RegFilePath 2>&1
    if ($LASTEXITCODE -ne 0) {
        $importMessage = ($importOutput | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($importMessage)) {
            $importMessage = 'reg.exe returned a non-zero exit code without additional details.'
        }

        throw "Registry import failed. $importMessage"
    }

    $missingTargets = Test-RegistryTargets -Targets $targets
    if ($missingTargets.Count -gt 0) {
        $missingMessage = $missingTargets -join [Environment]::NewLine
        throw "Registry import completed, but verification failed for the following targets:$([Environment]::NewLine)$missingMessage"
    }

    $keyCount = ($targets | Where-Object { $_.Type -eq 'Key' }).Count
    $valueCount = ($targets | Where-Object { $_.Type -eq 'Value' }).Count

    Write-Host "Registry import completed successfully." -ForegroundColor Green
    Write-Host "Verified $keyCount key(s) and $valueCount value(s)." -ForegroundColor Green
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}

