<#
.SYNOPSIS
    Sets a static IP in WinPE for when DHCP is not available.

.DESCRIPTION
    This will set a static IP in WinPE based on a MAC address defined below
    Include the script in the boot image and call it with the following command
    in WinPEShl.ini:
    [LaunchApps]
    powershell.exe -executionpolicy bypass x:\Set-StaticIP.ps1

.NOTES
    Author: Mike Terrill/2Pint Software
    Date: December 27, 2025
    Version: 25.12.27
    Requires: WinPE

    Version history:
    25.12.27: Initial release

.EXAMPLE
    .\Set-StaticIP.ps1
#>

# Hashtable: MAC Address -> Configuration
$AdapterConfigs = @{
    # DC
	"00-15-5D-10-10-10" = @{
        IPAddress    = "10.10.10.10"
        SubnetMask   = "255.255.255.0"
        Gateway      = "10.10.10.1"
        DNS          = @("10.10.10.1")  # Array: primary first, optional secondary
    }
	# 2PINT
	"00-15-5D-10-10-11" = @{
        IPAddress    = "10.10.10.11"
        SubnetMask   = "255.255.255.0"
        Gateway      = "10.10.10.1"
        DNS          = @("10.10.10.10")  # Array: primary first, optional secondary
    }
}

# Optional: Global DNS suffix search list (applies to the whole system)
$GlobalDNSSuffixes = @("2PintLabs.local")  # Leave empty @() for none

# Helper: Normalize MAC address (remove separators, uppercase)
function Normalize-Mac {
    param([string]$Mac)
    if (-not $Mac) { return $null }
    return ($Mac -replace '[:.-]', '').ToUpper()
}

Write-Host "Starting network configuration..." -ForegroundColor Cyan

foreach ($InputMac in $AdapterConfigs.Keys) {
    $Config = $AdapterConfigs[$InputMac]
    $NormalizedInputMac = Normalize-Mac $InputMac

    Write-Host "Looking for adapter with MAC: $InputMac (normalized: $NormalizedInputMac)"

    # Find physical network adapter by MAC using CIM (works in WinPE)
    $Adapter = Get-CimInstance -ClassName Win32_NetworkAdapter -Filter "MACAddress IS NOT NULL" |
               Where-Object { (Normalize-Mac $_.MACAddress) -eq $NormalizedInputMac -and $_.NetEnabled -eq $true }

    if (-not $Adapter) {
        Write-Warning "Adapter with MAC $InputMac not found or not enabled. Skipping."
        continue
    }

    # Get the IP-enabled configuration instance for this adapter
    $NetConfig = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "Index = $($Adapter.Index)" |
                 Where-Object { $_.IPEnabled -eq $true }

    if (-not $NetConfig) {
        Write-Warning "No IP configuration found for adapter '$($Adapter.NetConnectionID)'. Skipping."
        continue
    }

    $NetConnectionID = $Adapter.NetConnectionID.Trim()

    Write-Host "Configuring adapter: '$NetConnectionID' (MAC: $($Adapter.MACAddress))"

    # Set static IP, subnet mask, and gateway
    $setAddressCmd = "netsh interface ipv4 set address `"$NetConnectionID`" static $($Config.IPAddress) $($Config.SubnetMask) $($Config.Gateway)"
    Invoke-Expression $setAddressCmd
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to set IP address on '$NetConnectionID'"
        continue
    }

    # Set primary DNS
    & netsh interface ipv4 add dnsserver "$NetConnectionID" address=$($Config.DNS[0]) index=1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to set primary DNS on '$NetConnectionID'"
    }

    # Set secondary DNS if provided
    if ($Config.DNS.Count -gt 1) {
        & netsh interface ipv4 add dnsserver "$NetConnectionID" address=$($Config.DNS[1]) index=2
    }

    Write-Host "Configured '$NetConnectionID' -> IP: $($Config.IPAddress) Mask: $($Config.SubnetMask) Gateway: $($Config.Gateway) DNS: $($Config.DNS -join ', ')" -ForegroundColor Green
}

# Set global DNS suffix search order using CIM (static method - fixed)
if ($GlobalDNSSuffixes.Count -gt 0) {
    Write-Host "Setting global DNS suffix search order: $($GlobalDNSSuffixes -join ', ')"
    try {
        $result = Invoke-CimMethod -ClassName Win32_NetworkAdapterConfiguration `
                                   -MethodName SetDNSSuffixSearchOrder `
                                   -Arguments @{ DNSDomainSuffixSearchOrder = $GlobalDNSSuffixes }

        if ($result.ReturnValue -eq 0) {
            Write-Host "Global DNS suffixes applied successfully." -ForegroundColor Green
        } else {
            Write-Warning "Failed to apply global DNS suffixes (ReturnValue: $($result.ReturnValue))"
        }
    }
    catch {
        Write-Warning "Failed to set global DNS suffixes: $($_.Exception.Message)"
    }
} else {
    Write-Host "No global DNS suffixes configured."
}

Write-Host "Network configuration complete." -ForegroundColor Cyan
