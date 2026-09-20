<#
.SYNOPSIS
    Takes Hyper-V checkpoints for a list of virtual machines.

.DESCRIPTION
    Creates a checkpoint for one or more Hyper-V VMs on the local host or a
    specified host. Supports a VM name list, a text file of names, or pipeline input.
    Validates that each VM exists and reports success/failure per VM.

    Checkpoint type is a VM setting, not a parameter of Checkpoint-VM. If you pass
    -CheckpointType, the script temporarily sets that type on the VM, takes the
    checkpoint, then restores the original type. If you omit it, the VM's current
    checkpoint type is used.

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

.PARAMETER CheckpointType
    Optional. Temporarily set the VM checkpoint type before creating the checkpoint.
    Standard        - includes memory / running state
    Production      - VSS/FS freeze; falls back to Standard if production fails
    ProductionOnly  - VSS/FS freeze; fails if production checkpoint is not possible

    If omitted, the VM's existing CheckpointType is used.

.EXAMPLE
    .\Checkpoint-HyperVVms.ps1 -VMName 'DC','DEPLOYR' -SnapshotName 'New Install'

.EXAMPLE
    .\Checkpoint-HyperVVms.ps1 -Path C:\Scripts\vm-list.txt -SnapshotName 'Pre-Patch'

.EXAMPLE
    'WSUS01','APP01' | .\Checkpoint-HyperVVms.ps1 -CheckpointType Production

.NOTES
    Author: Mike Terrill/2Pint Software
    Date: September 19, 2026
    Version: 26.09.20

    Version history:
    26.09.19: Initial release
    26.09.20: Fixed issue with CheckpointType

    Requires the Hyper-V PowerShell module and an account with Hyper-V Administrator rights.
    Run from an elevated session on the Hyper-V host, or remotely with WinRM as needed.

    Checkpoint-VM does not accept -SnapshotType or -Wait. Those were the source of
    the previous parameter errors. Checkpoint-VM is synchronous unless -AsJob is used.
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

    [ValidateSet('Standard', 'Production', 'ProductionOnly')]
    [string]$CheckpointType
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
    $typeLabel = if ($PSBoundParameters.ContainsKey('CheckpointType')) {
        $CheckpointType
    }
    else {
        'VM default'
    }

    Write-Status "Target host     : $ComputerName"
    Write-Status "Checkpoint name : $SnapshotName"
    Write-Status "Checkpoint type : $typeLabel"
    Write-Status "VM count        : $($uniqueNames.Count)"
    Write-Host ''

    foreach ($name in $uniqueNames) {
        $entry = [pscustomobject]@{
            VMName           = $name
            ComputerName     = $ComputerName
            SnapshotName     = $SnapshotName
            CheckpointType   = $null
            PreviousType     = $null
            Status           = 'Pending'
            Message          = $null
            Time             = Get-Date
        }

        $originalType = $null
        $typeChanged = $false

        try {
            $vm = Get-VM -Name $name -ComputerName $ComputerName -ErrorAction Stop
            $originalType = $vm.CheckpointType
            $entry.PreviousType = [string]$originalType

            $effectiveType = if ($PSBoundParameters.ContainsKey('CheckpointType')) {
                $CheckpointType
            }
            else {
                [string]$originalType
            }
            $entry.CheckpointType = $effectiveType

            if ($effectiveType -eq 'Disabled' -or $originalType -eq 'Disabled' -and -not $PSBoundParameters.ContainsKey('CheckpointType')) {
                throw "Checkpoints are disabled on VM '$name'. Set -CheckpointType Standard/Production/ProductionOnly or enable checkpoints on the VM."
            }

            if (-not $PSCmdlet.ShouldProcess($name, "Create checkpoint '$SnapshotName' (type: $effectiveType)")) {
                $entry.Status = 'WhatIf'
                $entry.Message = 'No changes made (WhatIf).'
                $results.Add($entry)
                continue
            }

            if ($PSBoundParameters.ContainsKey('CheckpointType') -and [string]$originalType -ne $CheckpointType) {
                Set-VM -VM $vm -CheckpointType $CheckpointType -ErrorAction Stop
                $typeChanged = $true
            }

            Checkpoint-VM -VM $vm -SnapshotName $SnapshotName -ErrorAction Stop

            $entry.Status = 'Success'
            $entry.Message = "Checkpoint '$SnapshotName' created."
            Write-Status "[OK] $name ($effectiveType)" -Level Success
        }
        catch {
            $entry.Status = 'Failed'
            $entry.Message = $_.Exception.Message
            Write-Status "[FAIL] $name : $($_.Exception.Message)" -Level Error
        }
        finally {
            if ($typeChanged) {
                try {
                    $vmToRestore = Get-VM -Name $name -ComputerName $ComputerName -ErrorAction Stop
                    Set-VM -VM $vmToRestore -CheckpointType $originalType -ErrorAction Stop
                }
                catch {
                    Write-Status "[WARN] $name : checkpoint ran but original CheckpointType '$originalType' could not be restored. $($_.Exception.Message)" -Level Warning
                    if ($entry.Status -eq 'Success') {
                        $entry.Message += " Original CheckpointType '$originalType' was not restored."
                    }
                }
            }
        }

        $results.Add($entry)
    }

    Write-Host ''
    $success = @($results | Where-Object Status -eq 'Success').Count
    $failed  = @($results | Where-Object Status -eq 'Failed').Count
    Write-Status "Completed. Success: $success  Failed: $failed" -Level $(if ($failed -gt 0) { 'Warning' } else { 'Success' })

    $results
}
