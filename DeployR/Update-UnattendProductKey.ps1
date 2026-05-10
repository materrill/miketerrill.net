<#
.SYNOPSIS
    Updates the unattend.xml file by adding/updating the ProductKey in the
    Microsoft-Windows-Shell-Setup component under the specialize pass.
    Automatically selects the correct AVMA key based on $OSImageName.
    Use in DeployR in the WinPE phase after the Prepare OS step.

.NOTES
    Author: Mike Terrill/2Pint Software
    Date: May 9, 2026
    Version: 26.05.09

    Version history:
    26.05.09: Initial release
    
.PARAMETER OSImageName
    The OS image name (e.g. "Windows Server 2025 SERVERDATACENTER", 
    "Windows Server 2022 SERVERSTANDARD", etc.)

.PARAMETER UnattendPath
    Path to the unattend.xml file.
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$OSImageName = ${tsenv:OSIMAGENAME},

    [string]$UnattendPath = "S:\Windows\Panther\Unattend\unattend.xml"
)

# ====================== AVMA Key Mapping ======================
# Source: https://learn.microsoft.com/en-us/windows-server/get-started/automatic-vm-activation?tabs=server2025

$avmaKeys = @{
    # Windows Server 2025
    "2025.*Datacenter" = "YQB4H-NKHHJ-Q6K4R-4VMY6-VCH67"
    "2025.*Standard"   = "WWVGQ-PNHV9-B89P4-8GGM9-9HPQ4"
    "2025.*Azure"      = "6NMQ9-T38WF-6MFGM-QYGYM-88J4F"

    # Windows Server 2022
    "2022.*Datacenter" = "W3GNR-8DDXR-2TFRP-H8P33-DV9BG"
    "2022.*Standard"   = "YDFWN-MJ9JR-3DYRK-FXXRW-78VHK"
    "2022.*Azure"      = "F7TB6-YKN8Y-FCC6R-KQ484-VMK3J"

    # Windows Server 2019
    "2019.*Datacenter" = "H3RNG-8C32Q-Q8FRX-6TDXV-WMBMW"
    "2019.*Standard"   = "TNK62-RXVTB-4P47B-2D623-4GF74"
    "2019.*Essentials" = "2CTP7-NHT64-BP62M-FV6GG-HFV28"

    # Windows Server 2016
    "2016.*Datacenter" = "TMJ3Y-NTRTM-FJYXT-T22BY-CWG3J"
    "2016.*Standard"   = "C3RCX-M6NRP-6CXC9-TW2F2-4RHYD"
    "2016.*Essentials" = "B4YNW-62DX9-W8V6M-82649-MHBKQ"
}

# Determine the correct AVMA key
$ProductKey = $null
foreach ($pattern in $avmaKeys.Keys) {
    if ($OSImageName -match $pattern) {
        $ProductKey = $avmaKeys[$pattern]
        break
    }
}

if (-not $ProductKey) {
    Write-Error "Could not determine AVMA key for OSImageName: $OSImageName"
    Write-Host "Supported patterns include: 2025 Datacenter/Standard, 2022, 2019, 2016" -ForegroundColor Yellow
    exit 1
}

Write-Host "Using AVMA key for '$OSImageName': $ProductKey" -ForegroundColor Cyan

# ====================== Update unattend.xml ======================

# Validate file exists
if (-not (Test-Path $UnattendPath)) {
    Write-Error "Unattend file not found at: $UnattendPath"
    exit 1
}

# Load the XML
[xml]$xml = Get-Content $UnattendPath -Encoding UTF8

# Define the namespace
$ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
$ns.AddNamespace("ns", "urn:schemas-microsoft-com:unattend")

# Find the specialize pass
$specialize = $xml.SelectSingleNode("//ns:settings[@pass='specialize']", $ns)

if (-not $specialize) {
    Write-Error "Could not find <settings pass='specialize'> section."
    exit 1
}

# Find the Microsoft-Windows-Shell-Setup component
$shellSetup = $specialize.SelectSingleNode(".//ns:component[@name='Microsoft-Windows-Shell-Setup']", $ns)

if (-not $shellSetup) {
    Write-Error "Could not find Microsoft-Windows-Shell-Setup component in specialize pass."
    exit 1
}

# Check if ProductKey already exists
$existingKey = $shellSetup.SelectSingleNode("ns:ProductKey", $ns)

if ($existingKey) {
    Write-Host "ProductKey already exists. Updating it..." -ForegroundColor Yellow
    $existingKey.InnerText = $ProductKey
} else {
    # Create new ProductKey element
    $keyElement = $xml.CreateElement("ProductKey", $xml.DocumentElement.NamespaceURI)
    $keyElement.InnerText = $ProductKey
    
    # Append it to the component
    $shellSetup.AppendChild($keyElement) | Out-Null
    Write-Host "Added new ProductKey element." -ForegroundColor Green
}

# Save the file
$xml.Save($UnattendPath)

Write-Host "Successfully updated $UnattendPath with ProductKey." -ForegroundColor Green
