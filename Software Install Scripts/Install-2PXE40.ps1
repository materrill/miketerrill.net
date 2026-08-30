<#
.SYNOPSIS
    Installs and configures 2PXE 4.0.
.DESCRIPTION
    This script automates the install and configuration of 2PXE 4.0.
    It logs the process and handles common errors, suitable for large-scale deployment scenarios.
.NOTES
    Author: Mike Terrill/2Pint Software
    Date: August 29, 2026
    Version: 26.08.29
    Requires: Administrative privileges, 64-bit Windows (10/11, Server 2016+), internet access
    
    Version history:
    26.08.26: Initial release
    26.08.27: Added preflight check for MSI file. Support for External FQDN.
    26.08.29: Added $LicenseKey and $ExternalFQDN parameters to allow passing in values from outside the script.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$LicenseKey,

    [Parameter(Mandatory = $false)]
    [string]$ExternalFQDN
)

Write-Host "Starting 2PXE 4.0 installation and configuration..." -ForegroundColor Cyan

# Ensure the script runs with elevated privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script requires administrative privileges. Please run PowerShell as Administrator."
    exit 1
}

# Preflight check: ensure the MSI exists before continuing.
$msifile = "$PSScriptRoot\TwoPint.TwoPxe.Installer.msi"
if (-not (Test-Path -Path $msiFile -PathType Leaf)) {
    Write-Error "MSI file not found: $msiFile"
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

if (-not [string]::IsNullOrWhiteSpace($ExternalFQDN)) {
    $fqdn = $ExternalFQDN.Trim()
}
else {
    $fqdn = Get-LocalFqdn
}

# Grabs the IPv4 address - used for teh BINDTOIP property
$IPv4 = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled = 1" | % { $_.IPAddress | ? { -not $_.Contains(":") } }

# Configuration 
$arguments = @(
#Mandatory msiexec Arguments

    "/i"

    "`"$msiFile`""

    "AUTOSTART=1" #Automatically start the 2PXE service after install

    "/qn" #Quiet - with basic interface - for NO interface use /qn instead

    "/norestart" #Do not restart after install

    "/l*v $env:TEMP\2PXE-Install.log"    #Optional logging for the install

)   

$IntegrationMode = "PowerShell"
$BindToIP = $IPv4
$EnablediPXEAnywhereWebServiceFeatures = "BootRequest, ReportBootConfiguration, ReportDLStart, ReportDLComplete, ReportDLBoot, RunCmdLineWinPE, ExtraFile, WinPEShl, Config, RunCmdLineWinPEEnd"
$iPXEAnywhereWebServiceURI = "https://$($fqdn):8051"
$StifleRWebServiceURI = "https://$($fqdn):9000"
$IntegrateWithiPXEAnywhereWebService = "True"

# Configure registry settings for 2PXE
$regPath = "HKLM:\SOFTWARE\2Pint Software\2PXE\GeneralSettings"

if (-not (Test-Path -Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}

Write-Host "Configuring 2PXE registry values at $regPath"
Write-Host "Setting IntegrationMode = $IntegrationMode"
Set-ItemProperty -Path $regPath -Name "IntegrationMode" -Value $IntegrationMode -Type String
Write-Host "Setting BindToIP = $BindToIP"
Set-ItemProperty -Path $regPath -Name "BindToIP" -Value $BindToIP -Type String
Write-Host "Setting EnablediPXEAnywhereWebServiceFeatures = $EnablediPXEAnywhereWebServiceFeatures"
Set-ItemProperty -Path $regPath -Name "EnablediPXEAnywhereWebServiceFeatures" -Value $EnablediPXEAnywhereWebServiceFeatures -Type String
Write-Host "Setting iPXEAnywhereWebServiceURI = $iPXEAnywhereWebServiceURI"
Set-ItemProperty -Path $regPath -Name "iPXEAnywhereWebServiceURI" -Value $iPXEAnywhereWebServiceURI -Type String
Write-Host "Setting StifleRWebServiceURI = $StifleRWebServiceURI"
Set-ItemProperty -Path $regPath -Name "StifleRWebServiceURI" -Value $StifleRWebServiceURI -Type String
Write-Host "Setting IntegrateWithiPXEAnywhereWebService = $IntegrateWithiPXEAnywhereWebService"
Set-ItemProperty -Path $regPath -Name "IntegrateWithiPXEAnywhereWebService" -Value $IntegrateWithiPXEAnywhereWebService -Type String
if (-not [string]::IsNullOrWhiteSpace($ExternalFQDN)) {
    Write-Host "Setting ExternalFQDNOverride = $($ExternalFQDN.Trim())"
    Set-ItemProperty -Path $regPath -Name "ExternalFQDNOverride" -Value $ExternalFQDN.Trim() -Type String
}
Write-Host "Setting LicenseKey = $($LicenseKey.Trim())"
Set-ItemProperty -Path $regPath -Name "LicenseKey" -Value $LicenseKey.Trim() -Type String

# Install 2PXE using msiexec
Write-Host "Using the following install commands: $arguments" 
$installProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList $arguments -Wait -PassThru

if ($installProcess.ExitCode -ne 0) {
    throw "2PXE install failed. msiexec exit code: $($installProcess.ExitCode)"
}

Write-Host "2PXE installation completed successfully." -ForegroundColor Green