<#
.SYNOPSIS
    Checks if the computer has at least $minimumRequiredGB of physical RAM, and at least $minimumFreeGB free RAM available.

.DESCRIPTION
    Exits 0 if the system has $minimumRequiredGB or more of installed RAM, and at least $minimumFreeGB of free RAM available.
    Exits 1 otherwise. Also displays a clear message.
    Sets $tsenv:ClientsToProvision based on the number of child client VMs that should be created
    Sets $tsenv:RamToAssign to 14 + ClientsToProvision*4

.EXAMPLE
    .\Check-MinimumRAM.ps1

    # Will output something like:
    # Installed RAM: 64 GB
    # Available RAM: 32 GB
    # Meets minimum requirement (≥ 24 GB installed, ≥ 18 GB free): Yes
    # Numer of clients to provision: 3

.NOTES
    Author:  Mike Terrill
    Requires: PowerShell 5.1 or later (works on Windows 10/11 & Server)
#>

$minimumRequiredGB = 24
$minimumFreeGB = 18

# Get physical memory information (in bytes)
$totalRAMBytes = (Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory

# Convert to GB (using base-10 / 1,000,000,000 for human-readable marketing GB)
$totalRAMGB = [math]::Round($totalRAMBytes / 1GB, 2)

# Get available physical memory (in bytes)
$availableRAMBytes = (Get-CimInstance -ClassName Win32_OperatingSystem).FreePhysicalMemory * 1024

# Convert to GB
$availableRAMGB = [math]::Round($availableRAMBytes / 1GB, 2)

Write-Host "Installed physical RAM: $totalRAMGB GB" -ForegroundColor Cyan
Write-Host "Available physical RAM: $availableRAMGB GB" -ForegroundColor Cyan

# Floor of available RAM minus 14 (for non-client VMs) divided by 4 (4GB per client)
# allow a maximum of 3 clients (min between previous math and 3)
# set the minimum $numberOfClientsToProvision to 0 (cannot have negative clients), but 0 clients will be a failure condition
$numberOfClientsToProvision = [math]::max([math]::min([math]::Floor(($availableRAMGB - 14)/4),3),0)
$tsenv:ClientsToProvision = $numberOfClientsToProvision
$tsenv:RamToAssign = 14 + ($numberOfClientsToProvision * 4)

if ($totalRAMGB -ge $minimumRequiredGB -and $availableRAMGB -ge $minimumFreeGB) {
    Write-Host "Meets minimum requirement (≥ $minimumRequiredGB GB installed, ≥ $minimumFreeGB GB free): " -NoNewline
    Write-Host "YES" -ForegroundColor Green
    Write-Host "Number of clients to provision: $numberOfClientsToProvision"
    exit 0    # Success / meets requirement
}
else {
    Write-Host "Meets minimum requirement (≥ $minimumRequiredGB GB installed, ≥ $minimumFreeGB GB free): " -NoNewline
    Write-Host "NO" -ForegroundColor Red
    Write-Host "Required: $minimumRequiredGB GB installed, $minimumFreeGB GB free | Found: $totalRAMGB GB installed, $availableRAMGB GB free" -ForegroundColor Yellow
    exit 1    # Failure / does not meet requirement
}
