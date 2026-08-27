<#
.SYNOPSIS
    Installs and configures 2PXE 4.0.
.DESCRIPTION
    This script automates the install and configuration of 2PXE 4.0.
    It logs the process and handles common errors, suitable for large-scale deployment scenarios.
.NOTES
    Author: Mike Terrill/2Pint Software
    Date: August 26, 2026
    Version: 26.08.26
    Requires: Administrative privileges, 64-bit Windows (10/11, Server 2016+), internet access
    
    Version history:
    26.08.26: Initial release
#>

# Configuration 
# Set path to MSI file
$msifile = "$PSScriptRoot\2Pint Software 2PXE Service (x64).msi"
# This will use the connection specific suffix for the fqdn - useful when system is not domain joined
$domain = [string](Get-DnsClient | Select-Object -ExpandProperty ConnectionSpecificSuffix)
$fqdn = "$($env:COMPUTERNAME.Trim()).$($domain.Trim())"
$iPXEWSURL = "https://$($fqdn):8051"
# Grabs the IPv4 address - used for teh BINDTOIP property
$IPv4 = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled = 1" | % { $_.IPAddress | ? { -not $_.Contains(":") } }
