<#
.SYNOPSIS
    Starts specified Hyper-V VM(s).

.DESCRIPTION
    Simple script to start one or more Hyper-V VMs.
    Designed to work with VMs created by Create-VMsFromHashtable.ps1 or similar.

.PARAMETER VMName
    Name(s) of the VM(s) to start.
    Accepts wildcards or array of names.

.NOTES
    Author: Mike Terrill / 2Pint Software
    Date: June 11, 2026
    Version: 26.06.11
    Requires: Administrative privileges, 64-bit Windows with Hyper-V module

.EXAMPLE
    .\Start-VMs.ps1 -VMName "2PINT-BASE-S01"

.EXAMPLE
    .\Start-VMs.ps1 -VMName "2PINT-BASE-S*"

.EXAMPLE
    .\Start-VMs.ps1 -VMName "2PINT-BASE-S01","2PINT-BASE-S02"
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param (
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
    [string[]]$VMName
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
        if ($PSCmdlet.ShouldProcess($vm.Name, "Start VM")) {
            Write-Host "  Starting VM '$($vm.Name)'..." -ForegroundColor Green
            Start-VM -Name $vm.Name -ErrorAction Stop
            Write-Host "  VM '$($vm.Name)' started successfully." -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Failed to start VM '$($vm.Name)': $($_.Exception.Message)"
    }
}

Write-Host "`nDone." -ForegroundColor Green
