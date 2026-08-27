<#
.SYNOPSIS
    Installs and configures iPXE Webservice 4.0. 
.DESCRIPTION
    This script automates the install and configuration of iPXE Webservice 4.0.
    Include the MSI file and the Scripts directory from Github in the same directory as this script.
    It verifies the import, and handles common errors.
.NOTES
    Author: Mike Terrill/2Pint Software
    Date: August 27, 2026
    Version: 26.08.27
    Requires: Administrative privileges, 64-bit Windows

    Version history:
    26.08.26: Initial release
    26.08.27: Added preflight check for Scripts directory and fixed the double \\ in the AdvancedConnectionString registry value.
#>

Write-Host "Starting iPXEWS 4.0 installation and configuration..." -ForegroundColor Cyan

# Ensure the script runs with elevated privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script requires administrative privileges. Please run PowerShell as Administrator."
    exit 1
}

# Preflight check: ensure the local Scripts directory exists before continuing.
$preflightScriptsPath = Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Path) -ChildPath "Scripts"
if (-not (Test-Path -Path $preflightScriptsPath -PathType Container)) {
    Write-Error "Scripts directory not found at $preflightScriptsPath"
    exit 1
}

# Function to get the local FQDN by Johan
function Get-LocalFqdn {
    $hostName = $env:COMPUTERNAME

    # 1. Real DNS lookup, if it returns something qualified
    try {
        $name = [System.Net.Dns]::GetHostEntry($hostName).HostName
        if ($name -like '*.*') { return $name }
    } catch { }

    # 2. Primary DNS suffix, then the DHCP-supplied one (this is the Azure case)
    $tcpip = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
    foreach ($value in 'Domain', 'DhcpDomain') {
        $suffix = (Get-ItemProperty -Path $tcpip -Name $value -ErrorAction SilentlyContinue).$value
        if ($suffix) { return '{0}.{1}' -f $hostName, $suffix }
    }

    # 3. Connection-specific suffix from a connected adapter
    $suffix = Get-DnsClient -ErrorAction SilentlyContinue |
              Where-Object { $_.ConnectionSpecificSuffix } |
              Select-Object -First 1 -ExpandProperty ConnectionSpecificSuffix
    if ($suffix) { return '{0}.{1}' -f $hostName, $suffix }

    return $hostName
}

# Configuration 
# Add your license key and uncomment the line below to use it and automate the install. 
# $LicenseKey = "YOUR_LICENSE_KEY_HERE"
# Set path to MSI file
$msifile = "$PSScriptRoot\TwoPint.iPXEAnywhere.WebService.Installer64.msi"
$fqdn = Get-LocalFqdn

$arguments = @(
#Mandatory msiexec Arguments

    "/i"

    "`"$msiFile`""

    "AUTOSTART=1" #Automatically start the iPXE WS service after install

    "/qn" #Quiet - with basic interface - for NO interface use /qn instead

    "/norestart"

    "/l*v $env:TEMP\iPXEWS-Install.log"    #Optional logging for the install

)   

$SqlConnectionBy = "Advanced"
$AdvancedConnectionString= "Server=.\SQLExpress;Database=iPXEAnywhere;Trusted_Connection=True;MultipleActiveResultSets=true;TrustServerCertificate=True"
$StifleRServerApiUrl = "https://$($fqdn):9000"

# Configure registry settings for iPXEWS
$regPath = "HKLM:\SOFTWARE\2Pint Software\iPXE Anywhere Web Service\GeneralSettings"

if (-not (Test-Path -Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}

Write-Host "Configuring iPXEWS registry values at $regPath"
Write-Host "Setting SqlConnectionBy = $SqlConnectionBy"
Set-ItemProperty -Path $regPath -Name "SqlConnectionBy" -Value $SqlConnectionBy -Type String
Write-Host "Setting AdvancedConnectionString = $AdvancedConnectionString"
Set-ItemProperty -Path $regPath -Name "AdvancedConnectionString" -Value $AdvancedConnectionString -Type String
Write-Host "Setting StifleRServerApiUrl = $StifleRServerApiUrl"
Set-ItemProperty -Path $regPath -Name "StifleRServerApiUrl" -Value $StifleRServerApiUrl -Type String
if ((Get-Variable -Name LicenseKey -ErrorAction SilentlyContinue) -and -not [string]::IsNullOrWhiteSpace($LicenseKey)) {
    Write-Host "Setting LicenseKey = $($LicenseKey.Trim())"
    Set-ItemProperty -Path $regPath -Name "LicenseKey" -Value $LicenseKey.Trim() -Type String
}
else {
    Write-Host "LicenseKey is not defined. Skipping LicenseKey registry value."
}

# Install iPXEWS using msiexec
if (-not (Test-Path -Path $msiFile -PathType Leaf)) {
    throw "MSI file not found: $msiFile"
}

Write-Host "Using the following install commands: $arguments" 
$installProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList $arguments -Wait -PassThru

if ($installProcess.ExitCode -ne 0) {
    throw "iPXEWS install failed. msiexec exit code: $($installProcess.ExitCode)"
}

# Copy the iPXEWS Scripts to the iPXEWS default install directory
# The Scripts directory needs to be in the same directory as the installer script
try {
    # Get the directory where the script is located
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    
    # Define source and destination paths
    $sourcePath = Join-Path -Path $scriptDir -ChildPath "Scripts"
    $destPath = "C:\Program Files\2Pint Software\iPXE AnywhereWS"
    
    # Check if source directory exists
    if (-not (Test-Path $sourcePath)) {
        Write-Error "Scripts directory not found at $sourcePath"
        exit 1
    }
    
    # Create destination directory if it doesn't exist
    if (-not (Test-Path $destPath)) {
        New-Item -ItemType Directory -Path $destPath -Force | Out-Null
    }
    
    # Copy the Scripts directory and all contents
    Copy-Item -Path $sourcePath -Destination $destPath -Recurse -Force
    
    Write-Host "Successfully copied Scripts directory to $destPath"
}
catch {
    Write-Error "An error occurred while copying the directory: $_"
    exit 1
}

# Rename iPXEboot.ps1 to iPXEboot_CM.ps1
$bootScriptPath = Join-Path -Path $destPath -ChildPath "Scripts\Boot\iPXEboot.ps1"
$bootScriptRenamedPath = Join-Path -Path $destPath -ChildPath "Scripts\Boot\iPXEboot_CM.ps1"

if (Test-Path -Path $bootScriptPath) {
    Rename-Item -Path $bootScriptPath -NewName "iPXEboot_CM.ps1" -Force
    Write-Host "Successfully renamed iPXEboot.ps1 to iPXEboot_CM.ps1"
}
elseif (Test-Path -Path $bootScriptRenamedPath) {
    Write-Host "iPXEboot_CM.ps1 already exists; skipping rename."
}
else {
    Write-Host "iPXEboot.ps1 not found in $($destPath)\Scripts\Boot; skipping rename."
}

# Rename iPXEboot_DeployR.ps1 to iPXEboot.ps1
$deployRBootScriptPath = Join-Path -Path $destPath -ChildPath "Scripts\Boot\iPXEboot_DeployR.ps1"
$bootScriptPath = Join-Path -Path $destPath -ChildPath "Scripts\Boot\iPXEboot.ps1"

if (Test-Path -Path $deployRBootScriptPath) {
    Rename-Item -Path $deployRBootScriptPath -NewName "iPXEboot.ps1" -Force
    Write-Host "Successfully renamed iPXEboot_DeployR.ps1 to iPXEboot.ps1"
}
elseif (Test-Path -Path $bootScriptPath) {
    Write-Host "iPXEboot.ps1 already exists; skipping rename."
}
else {
    Write-Host "iPXEboot_DeployR.ps1 not found in $($destPath)\Scripts\Boot; skipping rename."
}

# Rename DeployR.ps1 to DeployR_bak.ps1
$deployRScriptPath = Join-Path -Path $destPath -ChildPath "Scripts\Custom\DeployR.ps1"
$deployRBackupPath = Join-Path -Path $destPath -ChildPath "Scripts\Custom\DeployR_bak.ps1"

if (Test-Path -Path $deployRScriptPath) {
    Rename-Item -Path $deployRScriptPath -NewName "DeployR_bak.ps1" -Force
    Write-Host "Successfully renamed DeployR.ps1 to DeployR_bak.ps1"
}
elseif (Test-Path -Path $deployRBackupPath) {
    Write-Host "DeployR_bak.ps1 already exists; skipping rename."
}
else {
    Write-Host "DeployR.ps1 not found in $($destPath)\Scripts\Custom; skipping rename."
}

# Rename Option2ForDeployR.ps1 to DeployR.ps1
$option2DeployRScriptPath = Join-Path -Path $destPath -ChildPath "Scripts\Custom\Option2ForDeployR.ps1"
$deployRScriptPath = Join-Path -Path $destPath -ChildPath "Scripts\Custom\DeployR.ps1"

if (Test-Path -Path $option2DeployRScriptPath) {
    Rename-Item -Path $option2DeployRScriptPath -NewName "DeployR.ps1" -Force
    Write-Host "Successfully renamed Option2ForDeployR.ps1 to DeployR.ps1"
}
elseif (Test-Path -Path $deployRScriptPath) {
    Write-Host "DeployR.ps1 already exists; skipping rename."
}
else {
    Write-Host "Option2ForDeployR.ps1 not found in $($destPath)\Scripts\Custom; skipping rename."
}

# Update the deployr.ps1 iPXE WS script default location with the correct FQDN
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

Write-Host "iPXEWS installation completed successfully." -ForegroundColor Green
