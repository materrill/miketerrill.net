<#
.SYNOPSIS
    Creates Hyper-V Gen2 VMs from an in-script configuration hashtable with proper folder structure and full error handling.

.DESCRIPTION
    VM config → $VMPath\VMName\Virtual Machines\
    VHDX files → $VMPath\VMName\Virtual Hard Disks\
    Supports Secure Boot, TPM, dual disks, DVD, checkpoints, auto actions, nested virtualization.

.NOTES
    Author: Mike Terrill / 2Pint Software
    Date: February 10, 2026
    Version: 26.02.10
    Requires: Administrative privileges, 64-bit Windows

    Version history:
    26.02.10: Initial release (based on Create-VMsFromCSV.ps1)

.EXAMPLE
    .\Create-VMs.ps1
#>

[CmdletBinding()]
param (
    # No parameters needed anymore — configuration is embedded
)

# -------------------------------
# Embedded VM Configuration
# -------------------------------
$VMConfigs = @(
    @{
        VMPath              = "D:\Hyper-V"
        VMName              = "DC"
        ConfigVersion       = "10.0"
        SecureBoot          = "True"
        TPM                 = "False"
        Memory              = "4"
        Processors          = "4"
        DiskSize            = "64"
        SecondDiskSize      = ""
        DVD                 = "True"
        MACAddress          = "00-15-5D-10-10-10"
        VMSwitch            = "Headquarters"
        StandardCheckpoints = "True"
        AutoCheckpoints     = "False"
        AutoStartAction     = "StartIfRunning"
        AutoStopAction      = "Save"
        NestedVirtualization = "False"
    },
    @{
        VMPath              = "D:\Hyper-V"
        VMName              = "DEPLOYR"
        ConfigVersion       = "10.0"
        SecureBoot          = "True"
        TPM                 = "False"
        Memory              = "6"
        Processors          = "4"
        DiskSize            = "80"
        SecondDiskSize      = "150"
        DVD                 = "True"
        MACAddress          = "00-15-5D-10-10-20"
        VMSwitch            = "Headquarters"
        StandardCheckpoints = "True"
        AutoCheckpoints     = "False"
        AutoStartAction     = "StartIfRunning"
        AutoStopAction      = "Save"
        NestedVirtualization = "False"
    },
    @{
        VMPath              = "D:\Hyper-V"
        VMName              = "PC01"
        ConfigVersion       = "10.0"
        SecureBoot          = "False"
        TPM                 = "False"
        Memory              = "4"
        Processors          = "4"
        DiskSize            = "64"
        SecondDiskSize      = ""
        DVD                 = "True"
        MACAddress          = ""
        VMSwitch            = "Headquarters"
        StandardCheckpoints = "True"
        AutoCheckpoints     = "False"
        AutoStartAction     = "StartIfRunning"
        AutoStopAction      = "Save"
        NestedVirtualization = "False"
    },
    @{
        VMPath              = "D:\Hyper-V"
        VMName              = "PC02"
        ConfigVersion       = "10.0"
        SecureBoot          = "False"
        TPM                 = "False"
        Memory              = "4"
        Processors          = "4"
        DiskSize            = "64"
        SecondDiskSize      = ""
        DVD                 = "True"
        MACAddress          = ""
        VMSwitch            = "Headquarters"
        StandardCheckpoints = "True"
        AutoCheckpoints     = "False"
        AutoStartAction     = "StartIfRunning"
        AutoStopAction      = "Save"
        NestedVirtualization = "False"
    },
    @{
        VMPath              = "D:\Hyper-V"
        VMName              = "PC03"
        ConfigVersion       = "10.0"
        SecureBoot          = "False"
        TPM                 = "False"
        Memory              = "4"
        Processors          = "4"
        DiskSize            = "64"
        SecondDiskSize      = ""
        DVD                 = "True"
        MACAddress          = ""
        VMSwitch            = "Headquarters"
        StandardCheckpoints = "True"
        AutoCheckpoints     = "False"
        AutoStartAction     = "StartIfRunning"
        AutoStopAction      = "Save"
        NestedVirtualization = "False"
    }
)

# -------------------------------
# Logging Setup
# -------------------------------
$LogPath = "$env:TEMP\Create-HyperVVMs_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR')]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "$timestamp [$Level] $Message"
    $logLine | Out-File -FilePath $LogPath -Append -Encoding UTF8
    switch ($Level) {
        'INFO'  { Write-Host $Message -ForegroundColor Cyan }
        'WARN'  { Write-Host $Message -ForegroundColor Yellow }
        'ERROR' { Write-Host $Message -ForegroundColor Red }
    }
}

# -------------------------------
# Pre-flight Checks
# -------------------------------
if (-not (Get-Module -ListAvailable -Name Hyper-V)) {
    Write-Log "Hyper-V PowerShell module not found. Install Hyper-V role." "ERROR"
    exit 1
}
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole("Administrators")) {
    Write-Log "Script must run as Administrator." "ERROR"
    exit 1
}

Write-Log "Using embedded configuration — $($VMConfigs.Count) VMs defined."

# -------------------------------
# Helper: Validate MAC Address Format
# -------------------------------
function Test-MacAddress {
    param([string]$Mac)
    if ([string]::IsNullOrWhiteSpace($Mac)) { return $false }
    $Mac = $Mac.Trim()
    return $Mac -match '^([0-9A-Fa-f]{2}[:-]?){5}[0-9A-Fa-f]{2}$'
}

# -------------------------------
# Process Each VM
# -------------------------------
foreach ($config in $VMConfigs) {

    # --- Safe extraction of VMName ---
    $vmName = $null
    if ($config.ContainsKey('VMName') -and $config.VMName) {
        $vmName = $config.VMName.ToString().Trim()
    }
    if ([string]::IsNullOrWhiteSpace($vmName)) {
        Write-Log "VMName missing or empty. Skipping entry." "WARN"
        continue
    }

    Write-Log "Processing VM: $vmName"

    # --- Validate required fields ---
    $required = 'VMPath','Memory','Processors','DiskSize','VMSwitch','SecureBoot','TPM','StandardCheckpoints','DVD'
    $missing = $required | Where-Object { 
        -not $config.ContainsKey($_) -or 
        [string]::IsNullOrWhiteSpace($config[$_])
    }
    if ($missing) {
        Write-Log "Missing required fields: $($missing -join ', '). Skipping VM '$vmName'." "ERROR"
        continue
    }

    # --- Parse values safely ---
    try {
        $basePath           = $config.VMPath.Trim()
        $memoryGB           = [long]$config.Memory
        $processors         = [int]$config.Processors
        $diskSizeGB         = [long]$config.DiskSize
        $secondDiskSizeGB   = if ($config.SecondDiskSize -and $config.SecondDiskSize -match '^\d+$') { [long]$config.SecondDiskSize } else { 0 }
        $dvdEnabled         = $config.DVD -eq "True"
        $vmSwitch           = $config.VMSwitch.Trim()
        $secureBoot         = $config.SecureBoot -eq "True"
        $tpmEnabled         = $config.TPM -eq "True"
        $standardCheckpoints = $config.StandardCheckpoints -eq "True"
        $autoCheckpoints    = if ($config.AutoCheckpoints) { $config.AutoCheckpoints -eq "True" } else { $false }
        $autoStartAction    = if ($config.AutoStartAction) { $config.AutoStartAction } else { "StartIfRunning" }
        $autoStopAction     = if ($config.AutoStopAction)  { $config.AutoStopAction }  else { "Save" }
        $nestedVirtualization = if ($config.NestedVirtualization) { $config.NestedVirtualization -eq "True" } else { $false }

        # Optional static MAC address
        $rawMac = if ($config.MACAddress) { $config.MACAddress.Trim() } else { $null }
        $staticMac = $null
        if ($rawMac -and (Test-MacAddress $rawMac)) {
            $staticMac = ($rawMac -replace '[:.]', '-' -replace '^(.{2})(.{2})(.{2})(.{2})(.{2})(.{2})$', '$1-$2-$3-$4-$5-$6').ToUpper()
        } elseif ($rawMac) {
            Write-Log "Invalid MAC address format '$rawMac' for VM '$vmName'. Using dynamic MAC." "WARN"
        }       
        
        # VM Configuration Version
        $versionStr = if ($config.ConfigVersion) { $config.ConfigVersion.Trim() } else { "10.0" }
        try { $configVersion = [version]$versionStr }
        catch {
            Write-Log "Invalid ConfigVersion '$versionStr'. Using 10.0" "WARN"
            $configVersion = [version]"10.0"
        }
    }
    catch {
        Write-Log "Data parsing failed for VM '$vmName': $($_.Exception.Message)" "ERROR"
        continue
    }

    # --- Define Paths ---
    $vmRootPath     = Join-Path $basePath $vmName
    $vmVhdPath      = Join-Path $vmRootPath "Virtual Hard Disks"

    # Create directories
    foreach ($path in @($vmRootPath, $vmVhdPath)) {
        if (-not (Test-Path $path)) {
            try {
                New-Item -Path $path -ItemType Directory -Force | Out-Null
                Write-Log "Created directory: $path"
            }
            catch {
                Write-Log "Failed to create directory '$path': $($_.Exception.Message)" "ERROR"
                continue 2  # skip to next VM
            }
        }
    }

    # --- Validate VMSwitch ---
    if (-not (Get-VMSwitch -Name $vmSwitch -ErrorAction SilentlyContinue)) {
        Write-Log "VMSwitch '$vmSwitch' not found!" "ERROR"
        continue
    }

    # --- Skip if VM exists ---
    if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) {
        Write-Log "VM '$vmName' already exists. Skipping." "WARN"
        continue
    }

    # --- Create VM ---
    try {
        Write-Log "Creating VM '$vmName' (Version $configVersion)..."

        New-VM -Name $vmName `
               -Path $basePath `
               -Generation 2 `
               -Version $configVersion `
               -MemoryStartupBytes ($memoryGB * 1GB) `
               -NoVHD `
               -SwitchName $vmSwitch `
               -ErrorAction Stop | Out-Null

        Set-VMProcessor -VMName $vmName -Count $processors -ErrorAction Stop

        if ($nestedVirtualization) {
            Write-Log "Enabling nested virtualization"
            Set-VMProcessor -VMName $vmName -ExposeVirtualizationExtensions $true

            Write-Log "Enabling MAC address spoofing"
            Get-VMNetworkAdapter -VMName $vmName | Set-VMNetworkAdapter -MacAddressSpoofing On
        }

        # Primary VHDX
        $primaryVhd = Join-Path $vmVhdPath "$vmName-Disk1.vhdx"
        Invoke-Expression "`${tsenv:$vmName-primaryVhd} = `$primaryVhd"
        New-VHD -Path $primaryVhd -SizeBytes ($diskSizeGB * 1GB) -Dynamic -ErrorAction Stop | Out-Null
        Add-VMHardDiskDrive -VMName $vmName -Path $primaryVhd -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 0 -ErrorAction Stop
        Write-Log "Attached primary disk: $primaryVhd"

        # Secondary disk
        if ($secondDiskSizeGB -gt 0) {
            $secondaryVhd = Join-Path $vmVhdPath "$vmName-Disk2.vhdx"
            New-VHD -Path $secondaryVhd -SizeBytes ($secondDiskSizeGB * 1GB) -Dynamic -ErrorAction Stop | Out-Null
            Add-VMHardDiskDrive -VMName $vmName -Path $secondaryVhd -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 1 -ErrorAction Stop
            Write-Log "Attached secondary disk: $secondaryVhd"
        }

        # DVD Drive
        if ($dvdEnabled) {
            Add-VMDvdDrive -VMName $vmName -ControllerNumber 0 -ControllerLocation 2 -ErrorAction Stop
            Write-Log "DVD drive added"
        }

        # Set Static MAC Address if specified
        $adapter = Get-VMNetworkAdapter -VMName $vmName
        if ($staticMac) {
            Set-VMNetworkAdapter -VMNetworkAdapter $adapter -StaticMacAddress $staticMac -ErrorAction Stop
            Write-Log "Assigned static MAC address: $staticMac"
        } else {
            Set-VMNetworkAdapter -VMNetworkAdapter $adapter -DynamicMacAddress -ErrorAction Stop
            Write-Log "Using dynamic (random) MAC address"
        }

        # Secure Boot
        Set-VMFirmware -VMName $vmName -EnableSecureBoot $(if ($secureBoot) { "On" } else { "Off" }) -ErrorAction Stop

        # TPM
        if ($tpmEnabled) {
            Enable-VMTPM -VMName $vmName -ErrorAction Stop
            Write-Log "TPM enabled"
        }

        # Checkpoints
        $checkpointType = if ($standardCheckpoints) { "Standard" } else { "Production" }
        Set-VM -VMName $vmName -CheckpointType $checkpointType -AutomaticCheckpointsEnabled $autoCheckpoints -SnapshotFileLocation $vmRootPath -ErrorAction Stop

        # Auto Start/Stop
        Set-VM -VMName $vmName -AutomaticStartAction $autoStartAction -AutomaticStopAction $autoStopAction -ErrorAction Stop

        Write-Log "Successfully created VM: $vmName" "INFO"
    }
    catch {
        Write-Log "Failed to create VM '$vmName': $($_.Exception.Message)" "ERROR"
        # Cleanup partial VM
        if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) {
            Remove-VM -Name $vmName -Force -ErrorAction SilentlyContinue
            Write-Log "Cleaned up failed VM: $vmName"
        }
    }
}

# -------------------------------
# Completion
# -------------------------------
Write-Log "Script completed. Log: $LogPath"
Write-Host "`nDone! Full log: $LogPath" -ForegroundColor Green
