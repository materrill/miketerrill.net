<#
.SYNOPSIS
    Disable Windows Update during a DeployR (or other OSD) task sequence.

.DESCRIPTION
    Intended to run in the full OS after Windows has been applied and first-booted,
    before app installs / remaining customizations. Blocks WU from scanning, downloading,
    or installing while the sequence is still running.

    Actions:
      - Sets Windows Update policy keys (no internet WU, no auto update, no dual scan, no WU drivers)
      - Stops and disables wuauserv, UsoSvc, bits (optional), WaaSMedicSvc when possible
      - Disables Update Orchestrator scheduled tasks

    Pair with Enable-WindowsUpdate-DeployR.ps1 at the end of the sequence.

.NOTES
    Author: Mike Terrill/2Pint Software
    Date: September 19, 2026
    Version: 26.09.19

    Version history:
    26.09.19: Initial release

    Run elevated. Safe to re-run.
    Does not rename binaries or take ownership of TrustedInstaller files.
#>

[CmdletBinding()]
param(
    [string]$LogPath = $(
        if (Test-Path 'C:\Windows\Temp') { 'C:\Windows\Temp\Disable-WindowsUpdate-DeployR.log' }
        else { Join-Path $env:TEMP 'Disable-WindowsUpdate-DeployR.log' }
    )
)

$ErrorActionPreference = 'Continue'

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO')
    $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $Level, $Message
    Write-Host $line
    try { Add-Content -Path $LogPath -Value $line -Encoding UTF8 } catch { }
}

function Set-RegValue {
    param(
        [string]$Path,
        [string]$Name,
        [ValidateSet('DWord','String')][string]$Type,
        $Value
    )
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
        Write-Log "Created key $Path"
    }
    New-ItemProperty -Path $Path -Name $Name -PropertyType $Type -Value $Value -Force | Out-Null
    Write-Log "Set $Path\$Name = $Value ($Type)"
}

function Disable-AndStopService {
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Log "Service $Name not present" 'WARN'
        return
    }
    Write-Log "Service $Name status=$($svc.Status) starttype=$($svc.StartType)"
    try {
        & sc.exe config $Name start= disabled | Out-Null
        Write-Log "Set $Name start=disabled (sc exit $LASTEXITCODE)"
    } catch {
        Write-Log "Failed to disable $Name : $($_.Exception.Message)" 'WARN'
    }
    if ($svc.Status -ne 'Stopped') {
        try {
            Stop-Service -Name $Name -Force -ErrorAction Stop
            Write-Log "Stopped $Name"
        } catch {
            & sc.exe stop $Name | Out-Null
            Write-Log "Stop $Name via sc.exe (exit $LASTEXITCODE)"
        }
    }
}

function Disable-TaskIfExists {
    param([string]$TaskPath, [string]$TaskName)
    $t = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($t) {
        Disable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue | Out-Null
        Write-Log "Disabled task $TaskPath$TaskName"
    } else {
        Write-Log "Task not found: $TaskPath$TaskName"
    }
}

Write-Log '======= Disable Windows Update (DeployR) ======='

# Policy: do not talk to Microsoft WU / MU
Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name 'DoNotConnectToWindowsUpdateInternetLocations' -Type DWord -Value 1
Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name 'DisableDualScan' -Type DWord -Value 1
Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name 'ExcludeWUDriversInQualityUpdate' -Type DWord -Value 1
Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name 'SetDisableUXWUAccess' -Type DWord -Value 1

# Classic AU policy
Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -Name 'NoAutoUpdate' -Type DWord -Value 1
Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -Name 'AUOptions' -Type DWord -Value 1

# Reduce Store / consumer / Edge noise during OSD
Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsConsumerFeatures' -Type DWord -Value 1
Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' -Name 'UpdateDefault' -Type DWord -Value 0
Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' -Name 'AutoUpdateCheckPeriodMinutes' -Type DWord -Value 0

# Services. WaaSMedicSvc often resists Disable; sc.exe is more reliable than Set-Service.
foreach ($s in @('wuauserv','UsoSvc','bits','WaaSMedicSvc','edgeupdate','edgeupdatem')) {
    Disable-AndStopService -Name $s
}

# Orchestrator tasks that scan / reboot
$uo = '\Microsoft\Windows\UpdateOrchestrator\'
foreach ($n in @(
    'Schedule Scan',
    'Schedule Scan Static Task',
    'Schedule Maintenance Work',
    'Backup Scan',
    'Reboot',
    'USO_UxBroker',
    'UpdateModelTask',
    'MusUx_UpdateInterval'
)) {
    Disable-TaskIfExists -TaskPath $uo -TaskName $n
}

Disable-TaskIfExists -TaskPath '\Microsoft\Windows\WindowsUpdate\' -TaskName 'Scheduled Start'
Disable-TaskIfExists -TaskPath '\Microsoft\Windows\WaaSMedic\' -TaskName 'PerformRemediation'

Write-Log '======= Disable complete ======='
exit 0
