<#
.SYNOPSIS
    PowerShell script to update the deployr.ps1 iPXE WS script with the correct FQDN 
.DESCRIPTION
    This script will update the deployr.ps1 iPXE WS script with the correct FQDN.
    It verifies the scripts exists in the default location and updates it.
.NOTES
    Author: Mike Terrill/2Pint Software
    Date: July 21, 2025
    Version: 25.07.21
    Requires: Administrative privileges, 64-bit Windows
#>

# This will use the connection specific suffix for the fqdn - useful when system is not domain joined
$domain = [string](Get-DnsClient | Select-Object -ExpandProperty ConnectionSpecificSuffix)
$fqdn = "$($env:COMPUTERNAME.Trim()).$($domain.Trim())"

# Define the path to the deployr.ps1 file
$scriptPath = "C:\Program Files\2Pint Software\iPXE AnywhereWS\Scripts\Custom\deployr.ps1"

try {
    # Check if the file exists
    if (-not (Test-Path $scriptPath)) {
        Write-Error "deployr.ps1 file not found at $scriptPath"
        exit 1
    }

    # Read the content of the file
    $content = Get-Content $scriptPath -Raw

    # Replace the server.company.com with the new FQDN
    $newContent = $content -replace "server\.company\.com", $fqdn

    # Write the modified content back to the file
    Set-Content -Path $scriptPath -Value $newContent

    Write-Host "Successfully replaced 'server.company.com' with '$fqdn' in $scriptPath"
}
catch {
    Write-Error "An error occurred while updating the file: $_"
    exit 1
}
