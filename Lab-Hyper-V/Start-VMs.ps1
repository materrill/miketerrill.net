<#
.SYNOPSIS
    Starts specified Hyper-V VM(s), with optional boot order configuration.

.DESCRIPTION
    Simple script to start one or more Hyper-V VMs.
    Optionally sets the first hard disk as the primary boot device when -BootFromHDD is specified.
    Designed to work with VMs created by Create-VMsFromHashtable.ps1 or similar.

.PARAMETER VMName
    Name(s) of the VM(s) to start.
    Accepts wildcards or array of names.

.PARAMETER BootFromHDD
    If specified, sets the first SCSI hard disk as the primary boot device before starting the VM.

.NOTES
    Author: Mike Terrill / 2Pint Software
    Date: June 12, 2026
    Version: 26.06.12
    Requires: Administrative privileges, 64-bit Windows with Hyper-V module

.EXAMPLE
    .\Start-VMs.ps1 -VMName "2PINT-BASE-S01"

.EXAMPLE
    .\Start-VMs.ps1 -VMName "2PINT-BASE-S*" -BootFromHDD

.EXAMPLE
    .\Start-VMs.ps1 -VMName "2PINT-BASE-S01","2PINT-BASE-S02" -BootFromHDD
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param (
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
    [string[]]$VMName,

    [switch]$BootFromHDD
)

# -------------------------------
# Pre-checks
# -------------------------------
if (-not (Get-Module -ListAvailable -Name Hyper-V)) {
    Write-Error "Hyper-V PowerShell module not found. Please install the Hyper-V role."
    exit 1
}

# -------------------------------
# Process each VM
# -------------------------------
foreach ($name in $VMName) {

    $vm = Get-VM -Name $name -ErrorAction SilentlyContinue

    if (-not $vm) {
        Write-Warning "VM '$name' not found. Skipping."
        continue
    }

    Write-Host "`nProcessing VM: $($vm.Name)" -ForegroundColor Cyan

    if ($vm.State -eq 'Running') {
        Write-Host "VM '$($vm.Name)' is already running." -ForegroundColor Yellow
        continue
    }

    try {
        if ($BootFromHDD) {
            Write-Host "  Setting boot order: First HDD as primary boot device..." -ForegroundColor Cyan

            # Get the primary (first) hard disk drive object
            $firstHdd = Get-VMHardDiskDrive -VMName $vm.Name |
                        Where-Object { $_.ControllerType -eq 'SCSI' -and $_.ControllerNumber -eq 0 -and $_.ControllerLocation -eq 0 } |
                        Select-Object -First 1

            if ($firstHdd) {
                Set-VMFirmware -VMName $vm.Name -FirstBootDevice $firstHdd -ErrorAction Stop
                Write-Host "  Boot order updated successfully." -ForegroundColor Green
            }
            else {
                Write-Warning "  No SCSI hard disk found at Controller 0, Location 0. Boot order not changed."
            }
        }

        if ($PSCmdlet.ShouldProcess($vm.Name, "Start VM")) {
            Write-Host "  Starting VM '$($vm.Name)'..." -ForegroundColor Green
            Start-VM -Name $vm.Name -ErrorAction Stop
            Write-Host "  VM '$($vm.Name)' started successfully." -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Failed to configure/start VM '$($vm.Name)': $($_.Exception.Message)"
    }
}

Write-Host "`nDone." -ForegroundColor Green
