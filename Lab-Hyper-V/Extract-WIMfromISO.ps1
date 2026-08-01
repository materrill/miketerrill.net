<#
.SYNOPSIS
    Extracts install.wim from ISO.

.NOTES
    Author: Mike Terrill/2Pint Software
    Date: Feb 9, 2026
    Version: 26.02.09

    Version history:
    26.02.09: Initial release
    
.PARAMETER ISO
    Path to the ISO to extract the install.wim

.PARAMETER DestinationFolder
    Location to place the extracted install.wim
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$ISO,

    [Parameter(Mandatory = $true)]
    [string]$DestinationFolder
)

# Validate that the ISO file exists
if (-not (Test-Path $ISO)) {
    Write-Host "ERROR: ISO file not found: $ISO" -ForegroundColor Red
    Write-Host "Please provide a valid path to an ISO file." -ForegroundColor Yellow
    exit 1
}

# If this is an ISO, mount it and set the path to the WIM
if ((Split-Path $ISO -Extension) -ieq ".iso") {
    Write-Host "Mounting ISO: $ISO" -ForegroundColor Cyan
    
    $MountISO = Mount-DiskImage -ImagePath $ISO -PassThru -Access ReadOnly
    $driveLetter = ($MountISO | Get-Volume).DriveLetter 
    $osWIM = "$($driveLetter):\sources\install.wim"
    
    # Verify the WIM actually exists on the mounted ISO
    if (-not (Test-Path $osWIM)) {
        Write-Host "ERROR: install.wim not found at $osWIM" -ForegroundColor Red
        Dismount-DiskImage -ImagePath $ISO -ErrorAction SilentlyContinue
        exit 1
    }
}
else {
    $osWIM = $ISO  # In case a .wim path was passed directly
}

Write-Host "Destination folder: $DestinationFolder" -ForegroundColor Cyan
    
# Ensure destination directory exists
if (-not (Test-Path $DestinationFolder)) {
    Write-Host "Creating destination folder: $DestinationFolder" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $DestinationFolder -Force | Out-Null
}

# Copy install.wim to the destination folder
Write-Host "Copying install.wim from $osWIM to $DestinationFolder" -ForegroundColor Cyan
Copy-Item -Path $osWIM -Destination $DestinationFolder -Force -Verbose

# Set Task Sequence variable
$tsenv:wimpath = "$DestinationFolder\install.wim"

# Unmount the ISO if it was mounted
if ((Split-Path $ISO -Extension) -ieq ".iso") {
    Write-Host "Unmounting ISO: $ISO" -ForegroundColor Cyan
    Dismount-DiskImage -ImagePath $ISO -ErrorAction SilentlyContinue | Out-Null
    Write-Host "ISO successfully unmounted." -ForegroundColor Green
}

Write-Host "Script completed successfully." -ForegroundColor Green
