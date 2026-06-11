# Stop script execution on any non-terminating error
$ErrorActionPreference = "Stop"

# Find the media
$MediaRoot = $null
Get-Volume | Where-Object { Test-Path "$($_.DriveLetter):\DeployRMedia.json" } | ForEach-Object {
	$MediaRoot = "$($_.DriveLetter):\DeployR"
}
if ($null -eq $MediaRoot) {
	throw "Could not find DeployR media.  Please ensure a drive with a DeployRMedia.json file is mounted and has a drive letter assigned."
}
Write-Host "Using media = $MediaRoot"

# Determine what files are needed
if ($env:PROCESSOR_ARCHITECTURE -ieq "AMD64") {
	$contentID = "00000000-0000-0000-0001-000000000001"
	$runtimeID = "00000000-0000-0000-0001-000000000011"
} else {
	$contentID = "00000000-0000-0000-0001-000000000002"
	$runtimeID = "00000000-0000-0000-0001-000000000012"
}

# Extract the files
if (Test-Path "C:\_2P") {
	Remove-Item "C:\_2P" -Recurse -Force 
}
MkDir "C:\_2P\Client" -Force | Out-Null
Expand-WindowsImage -ImagePath "$MediaRoot\.content\$contentID\1\$contentID.wim" -Index 1 -ApplyPath "C:\_2P\Client"
Move-Item "C:\_2P\Client\content" "C:\_2P\" -Force
MkDir "C:\_2P\content\$runtimeID\1" -Force | Out-Null
Expand-WindowsImage -ImagePath "$MediaRoot\.content\$runtimeID\1\$runtimeID.wim" -Index 1 -ApplyPath "C:\_2P\content\$runtimeID\1"

# Add variables to bootstrap
if ($null -ne $DeployRBootstrap) {
	Write-Host "Adding boostrap variables:"
	# Load the bootstrap.json
	$bootstrap = Get-Content "C:\_2P\Client\Bootstrap.json" -Raw | ConvertFrom-Json
	foreach ($key in $DeployRBootstrap.Keys) {
		$bootstrap.PSObject.Properties["Variables"].Value | Add-Member -MemberType NoteProperty -Name $key -Value $DeployRBootstrap[$key] -Force
		Write-Host "$key = $($DeployRBootstrap[$key])"
	}
	# Save it back
	$bootstrap | ConvertTo-Json | Set-Content -Path "C:\_2P\Client\Bootstrap.json"
}

# -------------------------------------------------------------------------
# Start: Added logic for DeployR Labkit
# -------------------------------------------------------------------------

# -------------------------------------------------------------------------
# Hashtable: Computer Name Prefix - TSID Configuration
# -------------------------------------------------------------------------
$ComputerConfigs = @{
    # 2PINT-LABKIT (matches 2PINT-LABKIT01, 2PINT-LABKIT02, etc.)
    "2PINT-LABKIT" = @{
        TSID = "e90694a7-6b27-4a75-9f4d-656072dc1e9a:1"
        #TSID = "bec30955-d5a5-4080-bacf-fa0ef24e1745:1"
    }
    # DC
    "DC" = @{
        TSID = "3a1930ee-ea2d-4b7b-8d7a-ac8be5e92a18:1"
    }
    # DEPLOYR
    "DEPLOYR" = @{
        TSID = "9bc37783-441b-48a3-893d-a4c9e5f5799c:1"
    }
}

# -------------------------------------------------------------------------
# Helper function to get computer name
# -------------------------------------------------------------------------
function Get-ComputerName {
    try {
        # Preferred method in WinPE
        $env:COMPUTERNAME
    } catch {
        try {
            (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).Name
        } catch {
            hostname
        }
    }
}

# -------------------------------------------------------------------------
# Main logic
# -------------------------------------------------------------------------
Start-Transcript -Path "C:\_2P\logs\RunTS-BasedonComputerName.log" -Force

$JsonPath = "C:\_2P\Client\Bootstrap.json"
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

# Get computer name
$computerName = Get-ComputerName
if ([string]::IsNullOrWhiteSpace($computerName)) {
    Write-Warning "Could not determine computer name."
    exit 1
}

$computerNameUpper = $computerName.ToUpper().Trim()

Write-Host "Detected computer name: $computerName" -ForegroundColor Cyan

# Find matching prefix (longest match wins if multiple could apply)
$matchedKey = $null
$matchedConfig = $null

foreach ($key in ($ComputerConfigs.Keys | Sort-Object Length -Descending)) {
    if ($computerNameUpper.StartsWith($key.ToUpper())) {
        $matchedKey = $key
        $matchedConfig = $ComputerConfigs[$key]
        break
    }
}

if (-not $matchedConfig) {
    Write-Warning "No matching computer name prefix found in the configuration table."
    Write-Host "Detected name (upper): $computerNameUpper" -ForegroundColor Yellow
    Write-Host "Available prefixes: $($ComputerConfigs.Keys -join ', ')" -ForegroundColor Yellow
    exit 1
}

$tsidValue = $matchedConfig.TSID

Write-Host "Found matching computer name prefix:" -ForegroundColor Green
Write-Host " Prefix : $matchedKey"
Write-Host " Full Name : $computerName"
Write-Host " TSID : $tsidValue"

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

# -------------------------------------------------------------------------
# End: Added logic for DeployR Labkit
# -------------------------------------------------------------------------

# Run the bootstrap script
Push-Location
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
C:\_2P\Client\Bootstrap.ps1 -Method Interactive
Pop-Location
