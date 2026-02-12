<#
.SYNOPSIS
    Sets a TSID for the system to automatically run based on MAC address.

.DESCRIPTION
    This will update the Bootstrap.json file in WinPE based on a MAC address defined below
    Include the script in the boot image and call it with the following command
    in WinPEShl.ini:
    [LaunchApps]
    powershell.exe,-executionpolicy bypass -file x:\RunTS-BasedonMAC.ps1

.NOTES
    Author: Mike Terrill/2Pint Software
    Date: February 12, 2026
    Version: 26.02.12
    Requires: WinPE

    Version history:
    26.02.12: Initial release

.EXAMPLE
    powershell.exe -executionpolicy bypass -file x:\RunTS-BasedonMAC.ps1
#>

#Runs in WinPE

# -------------------------------------------------------------------------
# Hashtable: MAC Address → Configuration
# -------------------------------------------------------------------------
$AdapterConfigs = @{
    # 2PINT-POC
    "00-15-5D-10-10-01" = @{
        TSID = "b94dbbb4-2ede-4e95-8902-8a24a5a53543"
    }
    # DC
    "00-15-5D-10-10-10" = @{
        TSID = "b94dbbb4-2ede-4e95-8902-8a24a5a53543"
    }
    # DEPLOYR
    "00-15-5D-10-10-20" = @{
        TSID = "b94dbbb4-2ede-4e95-8902-8a24a5a53543"
    }
}

function Normalize-Mac {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Mac
    )
    if ([string]::IsNullOrWhiteSpace($Mac)) { return "" }
    
    # Remove separators and convert to uppercase
    $clean = $Mac -replace '[-:\.]','' -replace '\s+','' | ForEach-Object { $_.ToUpper() }
    
    # Format as XX-XX-XX-XX-XX-XX
    if ($clean.Length -eq 12) {
        return ($clean -split '(..)' -ne '' | ForEach-Object { $_ }) -join '-'
    }
    
    # Return original (invalid) for safety
    return $Mac
}

# -------------------------------------------------------------------------
# Main logic
# -------------------------------------------------------------------------

$JsonPath = "x:\_2P\Client\Bootstrap.json"

if (-not (Test-Path $JsonPath)) {
    Write-Warning "Bootstrap.json not found at $JsonPath"
    exit 1
}

Write-Host "Reading $JsonPath ..." -ForegroundColor Cyan

try {
    $jsonContent = Get-Content $JsonPath -Raw -ErrorAction Stop | ConvertFrom-Json
}
catch {
    Write-Error "Failed to parse JSON: $($_.Exception.Message)"
    exit 1
}

# Get all physical adapters with MAC and that are IP-enabled
$adapters = Get-CimInstance -ClassName Win32_NetworkAdapter -Filter "MACAddress IS NOT NULL AND NetEnabled = True" |
    Where-Object { $_.PhysicalAdapter -eq $true -or $_.AdapterTypeID -eq 0 } |
    ForEach-Object {
        $macNorm = Normalize-Mac $_.MACAddress
        [PSCustomObject]@{
            Index            = $_.Index
            Name             = $_.Name
            NetConnectionID  = $_.NetConnectionID
            MACAddress       = $_.MACAddress
            NormalizedMAC    = $macNorm
            Config           = $AdapterConfigs[$macNorm]
        }
    }

if (-not $adapters) {
    Write-Warning "No network adapters with MAC address found."
    exit 1
}

# Try to find one that has a matching config
$matched = $adapters | Where-Object { $null -ne $_.Config } | Select-Object -First 1

if (-not $matched) {
    $foundMacs = $adapters.NormalizedMAC -join ", "
    Write-Warning "None of the detected MAC addresses match the configuration table."
    Write-Host "Detected MACs (normalized): $foundMacs" -ForegroundColor Yellow
    exit 1
}

$tsidValue = $matched.Config.TSID
$usedMac   = $matched.NormalizedMAC
$adapterName = $matched.Name

Write-Host "Found matching adapter:" -ForegroundColor Green
Write-Host "  MAC (normalized) : $usedMac"
Write-Host "  Adapter          : $adapterName"
Write-Host "  TSID             : $tsidValue"

# -------------------------------------------------------------------------
# Update JSON
# -------------------------------------------------------------------------

if (-not $jsonContent.Variables) {
    $jsonContent | Add-Member -MemberType NoteProperty -Name "Variables" -Value ([PSCustomObject]@{}) -Force
}

$jsonContent.Variables | Add-Member -MemberType NoteProperty -Name "TSID" -Value $tsidValue -Force

# Write back formatted JSON (4 spaces indent)
Write-Host "Updating $JsonPath with TSID = $tsidValue" -ForegroundColor Cyan

$jsonContent | ConvertTo-Json -Depth 10 | Out-File -FilePath $JsonPath -Encoding UTF8 -Force

Write-Host "Bootstrap.json updated successfully." -ForegroundColor Green
