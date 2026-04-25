<#
.SYNOPSIS
    Suppresses the "Try Windows Admin Center and Azure Arc today" popup AND
    prevents Server Manager from automatically starting at logon.

.DESCRIPTION
    Designed to run from WinPE (before first boot) on a fresh Windows Server 2025 install.
    Mounts the offline SOFTWARE registry hive and sets two keys under
    HKLM\SOFTWARE\Microsoft\ServerManager:
      - DoNotPopWACConsoleAtSMLaunch = 1
      - DoNotOpenServerManagerAtLogon = 1

.NOTES
    Author: Mike Terrill/2Pint Software
    Date: April 25, 2026
    Version: 26.04.25

    Version history:
    26.04.25: Initial release
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$OfflineWindowsRoot
)

function Get-OfflineWindowsRoot {
    param([string]$ProvidedPath)

    if ($ProvidedPath) {
        $hivePath = Join-Path $ProvidedPath "System32\config\SOFTWARE"
        if (Test-Path $hivePath -PathType Leaf) {
            return $ProvidedPath
        }
        throw "The provided path '$ProvidedPath' does not contain a valid offline SOFTWARE registry hive."
    }

    Write-Host "Auto-detecting offline Windows installation..." -ForegroundColor Cyan
    $candidateDrives = Get-PSDrive -PSProvider FileSystem |
        Where-Object { $_.Root -match '^[A-Z]:\\$' -and $_.Name -notin @('X') } |
        Sort-Object -Property Name

    foreach ($drive in $candidateDrives) {
        $hivePath = Join-Path $drive.Root "Windows\System32\config\SOFTWARE"
        if (Test-Path $hivePath -PathType Leaf) {
            Write-Host "Found offline Windows installation at $($drive.Root)Windows" -ForegroundColor Green
            return Join-Path $drive.Root "Windows"
        }
    }

    throw "Could not automatically detect an offline Windows installation. Use -OfflineWindowsRoot parameter."
}

try {
    $WinRoot = Get-OfflineWindowsRoot -ProvidedPath $OfflineWindowsRoot
    $SoftwareHivePath = Join-Path $WinRoot "System32\config\SOFTWARE"
    $OfflineHiveKey = "HKLM:\OfflineSOFTWARE"

    # Unload if already mounted
    if (Test-Path $OfflineHiveKey) {
        Write-Warning "Offline hive was already loaded. Unloading first..."
        & reg.exe unload "HKLM\OfflineSOFTWARE" | Out-Null
    }

    Write-Host "Loading offline SOFTWARE registry hive..." -ForegroundColor Cyan
    $loadResult = & reg.exe load "HKLM\OfflineSOFTWARE" "$SoftwareHivePath" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to load registry hive: $loadResult"
    }

    $ServerManagerPath = Join-Path $OfflineHiveKey "Microsoft\ServerManager"
    if (-not (Test-Path $ServerManagerPath)) {
        New-Item -Path $ServerManagerPath -Force | Out-Null
        Write-Host "Created Microsoft\ServerManager key." -ForegroundColor Yellow
    }

    # === Suppress WAC/Azure Arc popup ===
    Set-ItemProperty -Path $ServerManagerPath `
                     -Name "DoNotPopWACConsoleAtSMLaunch" `
                     -Value 1 -Type DWord -Force
    Write-Host "Set DoNotPopWACConsoleAtSMLaunch = 1" -ForegroundColor Green

    # === Prevent Server Manager from auto-starting at logon ===
    Set-ItemProperty -Path $ServerManagerPath `
                     -Name "DoNotOpenServerManagerAtLogon" `
                     -Value 1 -Type DWord -Force
    Write-Host "Set DoNotOpenServerManagerAtLogon = 1" -ForegroundColor Green

    Write-Host "`nSUCCESS: Both Server Manager behaviors have been disabled in the offline registry." -ForegroundColor Green
    Write-Host "• WAC/Azure Arc popup will not appear" -ForegroundColor Green
    Write-Host "• Server Manager will not launch automatically at logon" -ForegroundColor Green

} finally {
    if (Test-Path $OfflineHiveKey) {
        Write-Host "`nUnloading offline SOFTWARE registry hive..." -ForegroundColor Cyan
        & reg.exe unload "HKLM\OfflineSOFTWARE" | Out-Null
    }
}

Write-Host "`nScript complete. Reboot into the installed Windows Server 2025 when ready." -ForegroundColor Cyan
