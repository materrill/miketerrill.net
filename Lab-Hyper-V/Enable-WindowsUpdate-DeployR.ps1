<#
.SYNOPSIS
    Re-enable Windows Update at the end of a DeployR (or other OSD) task sequence.

.DESCRIPTION
    Reverses Disable-WindowsUpdate-DeployR.ps1:
      - Removes the temporary WU / Edge / CloudContent policy values
      - Restores service start types to Windows defaults
      - Re-enables Update Orchestrator scheduled tasks

    Run as the last (or near-last) online step before the sequence finishes.

.NOTES
    Author: Mike Terrill/2Pint Software
    Date: September 19, 2026
    Version: 26.09.19

    Version history:
    26.09.19: Initial release

    Run elevated. Safe to re-run.
    Default start types (current Windows 10/11):
      wuauserv      = Manual (demand)
      UsoSvc        = Manual (demand)
      bits          = Manual (demand)
      WaaSMedicSvc  = Manual (demand)
      edgeupdate    = Automatic (delayed)
      edgeupdatem   = Manual
#>

[CmdletBinding()]
param(
    [string]$LogPath = $(
        if (Test-Path 'C:\Windows\Temp') { 'C:\Windows\Temp\Enable-WindowsUpdate-DeployR.log' }
        else { Join-Path $env:TEMP 'Enable-WindowsUpdate-DeployR.log' }
    )
)

$ErrorActionPreference = 'Continue'

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO')
    $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $Level, $Message
    Write-Host $line
    try { Add-Content -Path $LogPath -Value $line -Encoding UTF8 } catch { }
}

function Remove-RegValue {
    param([string]$Path, [string]$Name)
    if (Test-Path $Path) {
        if ($null -ne (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue)) {
            Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
            Write-Log "Removed $Path\$Name"
        } else {
            Write-Log "Value not present: $Path\$Name"
        }
    } else {
        Write-Log "Key not present: $Path"
    }
}

function Set-ServiceStart {
    param(
        [string]$Name,
        [ValidateSet('demand','delayed-auto','auto','disabled')][string]$Start
    )
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Log "Service $Name not present" 'WARN'
        return
    }
    & sc.exe config $Name start= $Start | Out-Null
    Write-Log "Set $Name start=$Start (sc exit $LASTEXITCODE)"
}

function Enable-TaskIfExists {
    param([string]$TaskPath, [string]$TaskName)
    $t = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($t) {
        Enable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue | Out-Null
        Write-Log "Enabled task $TaskPath$TaskName"
    } else {
        Write-Log "Task not found: $TaskPath$TaskName"
    }
}

Write-Log '======= Enable Windows Update (DeployR) ======='

Remove-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name 'DoNotConnectToWindowsUpdateInternetLocations'
Remove-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name 'DisableDualScan'
Remove-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name 'ExcludeWUDriversInQualityUpdate'
Remove-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name 'SetDisableUXWUAccess'
Remove-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -Name 'NoAutoUpdate'
Remove-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -Name 'AUOptions'
Remove-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsConsumerFeatures'
Remove-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' -Name 'UpdateDefault'
Remove-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' -Name 'AutoUpdateCheckPeriodMinutes'

# Restore default start types. Do not force-start WU during the last TS step.
Set-ServiceStart -Name 'wuauserv'     -Start demand
Set-ServiceStart -Name 'UsoSvc'       -Start demand
Set-ServiceStart -Name 'bits'         -Start demand
Set-ServiceStart -Name 'WaaSMedicSvc' -Start demand
Set-ServiceStart -Name 'edgeupdate'   -Start delayed-auto
Set-ServiceStart -Name 'edgeupdatem'  -Start demand

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
    Enable-TaskIfExists -TaskPath $uo -TaskName $n
}

Enable-TaskIfExists -TaskPath '\Microsoft\Windows\WindowsUpdate\' -TaskName 'Scheduled Start'
Enable-TaskIfExists -TaskPath '\Microsoft\Windows\WaaSMedic\' -TaskName 'PerformRemediation'

Write-Log '======= Enable complete ======='
exit 0
