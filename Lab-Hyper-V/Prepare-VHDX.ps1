<#
.SYNOPSIS
    Prepare-VHDX.ps1 Partitions and formats a VHDX file. Optionally applies WIM, and copies a DeployR ISO and/or WIM.

.DESCRIPTION
    To be used in a DeployR Task Sequence
    This will copy the DeployR ISO that was used to initiate the TS to the VHDX
    and also copy the install.wim file from the Server ISO to the VHDX

.NOTES
    Author: Mike Terrill / 2Pint Software
    Date: June 12, 2026
    Version: 26.06.12
    Requires: Administrative privileges, 64-bit Windows

    Version history:
    26.06.12: Added copying and modifying the matching unattend file
              Added copying of the DeployR ISO contents and the DeployR-BuildLabKit.ps1 to the root of the VHDX Windows drive
    26.06.10: Added a TS variable (OfflineWindows) for the offline Windows drive letter and a parameter for unmounting and applying WIM
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
    [switch] $ApplyWIM,
    [switch] $CopyISO,
    [switch] $CopyWIM,
    [switch] $Unmount
)

# Mount the VHD and get the disk number
$disk = Mount-VHD -Path $TargetDisk -PassThru |
        Get-Disk |
        Where-Object { $_.PartitionStyle -eq 'RAW' }

if (-not $disk) {
    throw "Could not find newly mounted raw disk"
}

$diskNumber = $disk.Number
$tsenv:VHDXMount = $true

Write-Host "Initializing disk $diskNumber as GPT..."

Initialize-Disk -Number $diskNumber -PartitionStyle GPT -Confirm:$false -ErrorAction Stop

# ????????????????????????????????????????????????
# 1. EFI System Partition - 499 MB FAT32
# ????????????????????????????????????????????????
Write-Host "Creating EFI system partition (499 MB FAT32)..."
$efiPartition = New-Partition -DiskNumber $diskNumber `
    -Size 499MB `
    -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' `
    -Assign

Format-Volume -Partition $efiPartition -FileSystem FAT32 -NewFileSystemLabel "System" -Confirm:$false -Force

# ????????????????????????????????????????????????
# 2. Microsoft Reserved Partition (MSR) - 128 MB
# ????????????????????????????????????????????????
Write-Host "Creating MSR partition (128 MB)..."
$null = New-Partition -DiskNumber $diskNumber `
    -Size 128MB `
    -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}' 


# ????????????????????????????????????????????????
# 3. Primary Windows partition - max size initially, NTFS
# ????????????????????????????????????????????????
Write-Host "Creating primary Windows partition (max size temporarily, NTFS)..."
$windowsPartition = New-Partition -DiskNumber $diskNumber `
    -UseMaximumSize `
    -Assign

Format-Volume -Partition $windowsPartition -FileSystem NTFS -NewFileSystemLabel "Windows" -Confirm:$false -Force
$tsenv:OfflineWindows = "$($windowsPartition.DriveLetter):"

# ????????????????????????????????????????????????
# Shrink the Windows partition by 984 MB to make room for Recovery at the end
# ????????????????????????????????????????????????
Write-Host "Shrinking Windows partition by 984 MB to create space for Recovery..."
$shrinkSizeBytes = 984MB
Resize-Partition -DiskNumber $diskNumber -Partition $windowsPartition.PartitionNumber -Size ($windowsPartition.Size - $shrinkSizeBytes) -Confirm:$false

# ????????????????????????????????????????????????
# 4. Recovery partition - 984 MB, NTFS, hidden & protected
# ????????????????????????????????????????????????
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

# Apply WIM to VHDX and stage unattend.xml
if ($ApplyWIM) {
    Write-Host "Applying $tsenv:wimpath to $($windowsPartition.DriveLetter):"
    Expand-WindowsImage -ImagePath $tsenv:wimPath -Index 4 -ApplyPath "$($windowsPartition.DriveLetter):\"
    Write-Host "Applying bcdboot to $($efiPartition.DriveLetter):"
    bcdboot "$($windowsPartition.DriveLetter):\Windows" /s "$($efiPartition.DriveLetter):" /f UEFI
    
    # Get the computer name of the VM
    $Computername = $tsenv:VMName
    if (-not $computerName) {
        Write-Error "ComputerName task sequence variable is empty."
        exit 1
    }
    Write-Host "VMName = $Computername"

    # Determine which unattend template to use based on Computername prefix
    $templateFile = $null

    if ($Computername -like "2PINT-LABKIT*") {
        $templateFile = "2PINT-LABKIT.xml"
    }
    elseif ($Computername -like "DC*") {
        $templateFile = "DC.xml"
    }
    elseif ($Computername -like "DEPLOYR*") {
    $templateFile = "DEPLOYR.xml"
    }
    else {
        Write-Error "Computername '$Computername' does not match any known prefix (2PINT-LABKIT, DC, or DEPLOYR)."
        exit 1
    }
    
    # Build full source path
    $scriptRoot = $PSScriptRoot
    $sourcePath = Join-Path $scriptRoot $templateFile

    if (-not (Test-Path $sourcePath)) {
        Write-Error "Template file not found: $sourcePath"
        exit 1
    }

    Write-Host "Using template: $templateFile" -ForegroundColor Green

    # Panther destination
    $pantherPath = "$($windowsPartition.DriveLetter):\Windows\Panther"

    # Create Panther folder if it doesn't exist
    if (-not (Test-Path $pantherPath)) {
        Write-Host "Creating Panther directory: $pantherPath" -ForegroundColor Cyan
        New-Item -Path $pantherPath -ItemType Directory -Force | Out-Null
    } else {
        Write-Host "Panther directory already exists." -ForegroundColor Gray
    }

    # Copy as Unattend.xml (overwrite if exists)
    $destinationFile = Join-Path $pantherPath "Unattend.xml"

    Copy-Item -Path $sourcePath -Destination $destinationFile -Force

    # Replace %Computername% placeholder with the actual computer name
    if ($Computername -like "2PINT-LABKIT*") {
        if (Test-Path $destinationFile) {
            $content = Get-Content $destinationFile -Raw -Encoding UTF8
            $updatedContent = $content -replace '%Computername%', $computerName
            
            Set-Content -Path $destinationFile -Value $updatedContent -Encoding UTF8 -Force
            
            Write-Host "Successfully copied $templateFile to $destinationFile and updated Computername to '$computerName'" -ForegroundColor Green
        } else {
            Write-Error "Failed to copy unattend file to Panther directory."
            exit 1
        }
    }

    # Copy the contents of the DeployR ISO to the root of the VHDX
    if ($tsenv:ISODriveLetter) {
        $source = "$($tsenv:ISODriveLetter)\*"
        Write-Host "Copying the ISO contents to $($windowsPartition.DriveLetter):\"
        Copy-Item -Path $source -Destination "$($windowsPartition.DriveLetter):\" -Recurse -Force
    }

    # Copy DeployR-BuildLabKit.ps1 to VHDX
    $scriptPath = Join-Path $scriptRoot "DeployR-BuildLabKit.ps1"
    Write-Host "Copying DeployR-BuildLabKit.ps1 to $($windowsPartition.DriveLetter):\"
    Copy-Item -Path $scriptPath -Destination "$($windowsPartition.DriveLetter):\" -Force

    # Set lock screen image
    $imagePath = Join-Path $scriptRoot "2pint-desktop-stripes-dark-1920x1080.png"
    if (Test-Path $imagePath) {
        Write-Output "Running Command: Copy-Item $imagePath $($windowsPartition.DriveLetter):\windows\web\Screen\img100.jpg -Force -Verbose"
        Copy-Item -Path $imagePath -Destination "$($windowsPartition.DriveLetter):\windows\web\Screen\img100.jpg" -Force -Verbose
        Write-Output "Running Command: Copy-Item $imagePath $($windowsPartition.DriveLetter):\windows\web\Screen\img105.jpg -Force -Verbose"
        Copy-Item -Path $imagePath -Destination "$($windowsPartition.DriveLetter):\windows\web\Screen\img105.jpg" -Force -Verbose
    }
}

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
if ($Unmount) {
    Write-Host "Unmounting $TargetDisk"
    Dismount-VHD -Path $TargetDisk
    $tsenv:VHDXMount = $false
}
