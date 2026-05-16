<#
.SYNOPSIS
    Partitions and formats a VHDX file. Optionally copies an ISO and/or WIM.

.DESCRIPTION
    To be used in a DeployR Task Sequence
    This will copy the DeployR ISO that was used to initiate the TS to the VHDX
    and also copy the install.wim file from the Server ISO to the VHDX

.NOTES
    Author: Mike Terrill / 2Pint Software
    Date: February 10, 2026
    Version: 26.02.10
    Requires: Administrative privileges, 64-bit Windows

    Version history:
    26.02.10: Initial release (based on Create-VMsFromCSV.ps1)

.EXAMPLE
    To be used in a DeployR Task Sequence
    Passing the following parameters on the Run Powershell script step:
    -TargetDisk ${tsenv:2PINT-LABKIT-primaryVhd} -CopyISO -CopyWIM
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param (
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
    [string]$TargetDisk,
    [switch] $CopyISO,
    [switch] $CopyWIM
)

# Mount the VHD and get the disk number
$disk = Mount-VHD -Path $TargetDisk -PassThru |
        Get-Disk |
        Where-Object { $_.PartitionStyle -eq 'RAW' }

if (-not $disk) {
    throw "Could not find newly mounted raw disk"
}

$diskNumber = $disk.Number

Write-Host "Initializing disk $diskNumber as GPT..."

Initialize-Disk -Number $diskNumber -PartitionStyle GPT -Confirm:$false -ErrorAction Stop

# ────────────────────────────────────────────────
# 1. EFI System Partition – 499 MB FAT32
# ────────────────────────────────────────────────
Write-Host "Creating EFI system partition (499 MB FAT32)..."
$efiPartition = New-Partition -DiskNumber $diskNumber `
    -Size 499MB `
    -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' `
    -Assign

Format-Volume -Partition $efiPartition -FileSystem FAT32 -NewFileSystemLabel "System" -Confirm:$false -Force

# ────────────────────────────────────────────────
# 2. Microsoft Reserved Partition (MSR) – 128 MB
# ────────────────────────────────────────────────
Write-Host "Creating MSR partition (128 MB)..."
$null = New-Partition -DiskNumber $diskNumber `
    -Size 128MB `
    -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}' 


# ────────────────────────────────────────────────
# 3. Primary Windows partition – max size initially, NTFS
# ────────────────────────────────────────────────
Write-Host "Creating primary Windows partition (max size temporarily, NTFS)..."
$windowsPartition = New-Partition -DiskNumber $diskNumber `
    -UseMaximumSize `
    -Assign

Format-Volume -Partition $windowsPartition -FileSystem NTFS -NewFileSystemLabel "Windows" -Confirm:$false -Force

# ────────────────────────────────────────────────
# Shrink the Windows partition by 984 MB to make room for Recovery at the end
# ────────────────────────────────────────────────
Write-Host "Shrinking Windows partition by 984 MB to create space for Recovery..."
$shrinkSizeBytes = 984MB
Resize-Partition -DiskNumber $diskNumber -Partition $windowsPartition.PartitionNumber -Size ($windowsPartition.Size - $shrinkSizeBytes) -Confirm:$false

# ────────────────────────────────────────────────
# 4. Recovery partition – 984 MB, NTFS, hidden & protected
# ────────────────────────────────────────────────
Write-Host "Creating Recovery partition (984 MB, NTFS) in the newly freed space..."
$recoveryPartition = New-Partition -DiskNumber $diskNumber `
    -Size 984MB `
    -GptType '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}'

Format-Volume -Partition $recoveryPartition -FileSystem NTFS -NewFileSystemLabel "Recovery" -Confirm:$false -Force

# Critical: Set GPT attributes via DiskPart
Write-Host "Setting GPT attributes on Recovery partition (0x8000000000000001)..."
$diskpartScript = @"
select disk $diskNumber
select partition $($recoveryPartition.PartitionNumber)
gpt attributes=0x8000000000000001
exit
"@
$diskpartScript | diskpart | Out-Null

Write-Host "Partition layout completed."

# Show the final layout (with sizes in GB for clarity)
Get-Partition -DiskNumber $diskNumber | 
    Select-Object Number, Type, @{Name='SizeGB';Expression={[math]::Round($_.Size / 1GB, 2)}}, GptType | 
    Format-Table -AutoSize

# Optional: Detailed partition view
# Get-Partition -DiskNumber $diskNumber | Format-List *

# Create 2Pint_Downloads directory on the Windows drive
if ($CopyISO -or $CopyWIM) {
    # Check if the directory already exists, and create it only if it doesn't
    $downloadPath = "$($windowsPartition.DriveLetter):\2Pint_Downloads"

    if (-not (Test-Path -Path $downloadPath)) {
        New-Item -Path "$($windowsPartition.DriveLetter):\" -Name "2Pint_Downloads" -ItemType Directory -Force | Out-Null
        Write-Host "Created directory: $downloadPath" -ForegroundColor Green
    } else {
        Write-Host "Directory already exists: $downloadPath" -ForegroundColor Yellow
    }
}

# Copy the ISO to the 2Pint_Downloads directory
if ($CopyISO) {
    Write-Host "Copying $tsenv:DeployRISO to $($windowsPartition.DriveLetter):\2Pint_Downloads"
    Copy-Item -Path $tsenv:DeployRISO -Destination "$($windowsPartition.DriveLetter):\2Pint_Downloads" -Force
}

# Copy the install.wim to the 2Pint_Downloads directory
if ($CopyWIM) {
    Write-Host "Copying $tsenv:wimpath to $($windowsPartition.DriveLetter):\2Pint_Downloads"
    Copy-Item -Path $tsenv:wimpath -Destination "$($windowsPartition.DriveLetter):\2Pint_Downloads" -Force
}

# Unmount VHDX
Dismount-VHD -Path $TargetDisk
