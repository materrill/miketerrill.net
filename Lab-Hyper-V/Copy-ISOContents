<#
.SYNOPSIS
    Copies the contents of an ISO.

.NOTES
    Author: Mike Terrill/2Pint Software
    Date: June 17, 2026
    Version: 26.06.17

    Version history:
    26.06.17: Initial release
    
.PARAMETER ISO
    Path to the ISO to copy

.PARAMETER DestinationFolder
    Location to copy contents of the ISO
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$ISO,

    [Parameter(Mandatory = $true)]
    [string]$Destination
)

# Validate that the ISO file exists
if (-not (Test-Path $ISO)) {
    Write-Host "ERROR: ISO file not found: $ISO" -ForegroundColor Red
    Write-Host "Please provide a valid path to an ISO file." -ForegroundColor Yellow
    exit 1
}

# If this is an ISO, mount it and set the path to the WIM
if ((Split-Path $ISO -Extension) -ieq ".iso") {
    $ISO = (Get-Item -Path $ISO).FullName
    Write-Host "Mounting ISO: $ISO" -ForegroundColor Cyan
    
    $MountISO = Mount-DiskImage -ImagePath $ISO -PassThru -Access ReadOnly
    $DriveLetter = ($MountISO | Get-Volume).DriveLetter 
}

Write-Host "Destination: $Destination" -ForegroundColor Cyan
    
# Ensure destination exists
if (-not (Test-Path $Destination)) {
    Write-Host "Error: destination: $Destination does not exist. Exiting" -ForegroundColor Red
    Dismount-DiskImage -ImagePath $ISO -ErrorAction SilentlyContinue | Out-Null
    Write-Host "ISO successfully unmounted." -ForegroundColor Green
    exit 1
}

# Copy contents to the destination
Write-Host "Copying contents from $($DriveLetter):\ to $($Destination)\" -ForegroundColor Cyan
Copy-Item -Path "$($DriveLetter):\*" -Destination "$($Destination)\" -Recurse -Force -Verbose

# Unmount the ISO if it was mounted
if ((Split-Path $ISO -Extension) -ieq ".iso") {
    Write-Host "Unmounting ISO: $ISO" -ForegroundColor Cyan
    Dismount-DiskImage -ImagePath $ISO -ErrorAction SilentlyContinue | Out-Null
    Write-Host "ISO successfully unmounted." -ForegroundColor Green
}

Write-Host "Script completed successfully." -ForegroundColor Green
