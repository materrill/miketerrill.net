<#
.SYNOPSIS
    Takes Hyper-V checkpoints for a list of virtual machines.

.DESCRIPTION
    Creates a checkpoint (snapshot) for one or more Hyper-V VMs on the local host
    or a specified host. Supports a VM name list, a text file of names, or pipeline input.
    Validates that each VM exists, reports success/failure per VM, and optionally
    waits until the checkpoint operation completes.

.PARAMETER VMName
    One or more virtual machine names. Accepts pipeline input.

.PARAMETER Path
    Path to a text file containing one VM name per line. Blank lines and lines
    starting with # are ignored.

.PARAMETER ComputerName
    Hyper-V host. Defaults to the local computer.

.PARAMETER SnapshotName
    Name of the checkpoint. If omitted, a timestamped name is generated:
    "Manual-{yyyy-MM-dd-HHmmss}"

.PARAMETER SnapshotType
    Standard (includes memory / running state) or Production (VSS-aware, no memory).
    Default: Standard.

.PARAMETER Wait
    Wait for each checkpoint operation to finish before moving to the next VM.

.PARAMETER WhatIf
    Shows what would happen without creating checkpoints.

.EXAMPLE
    .\Checkpoint-HyperVVms.ps1 -VMName 'DC01','FS01'

.EXAMPLE
    .\Checkpoint-HyperVVms.ps1 -Path C:\Scripts\vm-list.txt -SnapshotName 'Pre-Patch' -Wait

.EXAMPLE
    'WSUS01','APP01' | .\Checkpoint-HyperVVms.ps1 -SnapshotType Production

.NOTES
    Author: Mike Terrill/2Pint Software
    Date: September 19, 2026
    Version: 26.09.19

    Version history:
    26.09.19: Initial release

    Requires the Hyper-V PowerShell module and an account with Hyper-V Administrator rights.
    Run from an elevated session on the Hyper-V host, or remotely with CredSSP/WinRM as needed.
#>

[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'ByName')]
param(
    [Parameter(ParameterSetName = 'ByName', Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [Alias('Name')]
    [string[]]$VMName,

    [Parameter(ParameterSetName = 'ByFile', Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$Path,

    [string]$ComputerName = $env:COMPUTERNAME,

    [string]$SnapshotName,

    [ValidateSet('Standard', 'Production')]
    [string]$SnapshotType = 'Standard',

    [switch]$Wait
)

begin {
    $ErrorActionPreference = 'Stop'

    if (-not $SnapshotName) {
        $SnapshotName = 'Manual-{0}' -f (Get-Date -Format 'yyyy-MM-dd-HHmmss')
    }

    try {
        Import-Module Hyper-V -ErrorAction Stop
    }
    catch {
        throw "Hyper-V module could not be loaded. Install Hyper-V management tools or run this on a Hyper-V host. $_"
    }

    $names = [System.Collections.Generic.List[string]]::new()
    $results = [System.Collections.Generic.List[pscustomobject]]::new()

    function Write-Status {
        param(
            [string]$Message,
            [ValidateSet('Info', 'Success', 'Warning', 'Error')]
            [string]$Level = 'Info'
        )
        switch ($Level) {
            'Success' { Write-Host $Message -ForegroundColor Green }
            'Warning' { Write-Warning $Message }
            'Error'   { Write-Host $Message -ForegroundColor Red }
            default   { Write-Host $Message }
        }
    }
}

process {
    if ($PSCmdlet.ParameterSetName -eq 'ByFile' -and $names.Count -eq 0) {
        Get-Content -LiteralPath $Path |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and $_ -notmatch '^\s*#' } |
            ForEach-Object { $names.Add($_) }
    }
    elseif ($VMName) {
        foreach ($n in $VMName) {
            if ($n) { $names.Add($n.Trim()) }
        }
    }
}

end {
    if ($names.Count -eq 0) {
        throw 'No virtual machine names were provided.'
    }

    $uniqueNames = $names | Select-Object -Unique
    Write-Status "Target host : $ComputerName"
    Write-Status "Checkpoint  : $SnapshotName ($SnapshotType)"
    Write-Status "VM count    : $($uniqueNames.Count)"
    Write-Host ''

    foreach ($name in $uniqueNames) {
        $entry = [pscustomobject]@{
            VMName        = $name
            ComputerName  = $ComputerName
            SnapshotName  = $SnapshotName
            SnapshotType  = $SnapshotType
            Status        = 'Pending'
            Message       = $null
            Time          = Get-Date
        }

        try {
            $vm = Get-VM -Name $name -ComputerName $ComputerName -ErrorAction Stop

            if (-not $PSCmdlet.ShouldProcess($name, "Create $SnapshotType checkpoint '$SnapshotName'")) {
                $entry.Status = 'WhatIf'
                $entry.Message = 'No changes made (WhatIf).'
                $results.Add($entry)
                continue
            }

            $checkpointParams = @{
                VM            = $vm
                SnapshotName  = $SnapshotName
                SnapshotType  = $SnapshotType
                ErrorAction   = 'Stop'
            }
            if ($Wait) {
                $checkpointParams['Wait'] = $true
            }

            Checkpoint-VM @checkpointParams

            $entry.Status = 'Success'
            $entry.Message = "Checkpoint '$SnapshotName' created."
            Write-Status "[OK] $name" -Level Success
        }
        catch {
            $entry.Status = 'Failed'
            $entry.Message = $_.Exception.Message
            Write-Status "[FAIL] $name : $($_.Exception.Message)" -Level Error
        }

        $results.Add($entry)
    }

    Write-Host ''
    $success = @($results | Where-Object Status -eq 'Success').Count
    $failed  = @($results | Where-Object Status -eq 'Failed').Count
    Write-Status "Completed. Success: $success  Failed: $failed" -Level $(if ($failed -gt 0) { 'Warning' } else { 'Success' })

    $results
}
