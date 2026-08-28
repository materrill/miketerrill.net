<#
.SYNOPSIS
    Installs and configures the StifleR ActionHub.
.DESCRIPTION
    This script automates the install and configuration of the StifleR ActionHub.
    It logs the process and handles common errors, suitable for large-scale deployment scenarios.
.NOTES
    Author: Mike Terrill/2Pint Software
    Date: August 28, 2026
    Version: 26.08.28
    Requires: Administrative privileges, 64-bit Windows (10/11, Server 2016+), internet access
    
    Version history:
    26.08.28: Initial release
  
#>

# If using an external FQDN, set it here and uncomment the line below. If not set, the script will use the local FQDN.
# $ExternalFQDN = "server.company.com"

Write-Host "Starting the StifleR ActionHub installation and configuration..." -ForegroundColor Cyan

# Ensure the script runs with elevated privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script requires administrative privileges. Please run PowerShell as Administrator."
    exit 1
}

# Preflight check: ensure the MSI exists before continuing.
$msifile = "$PSScriptRoot\StifleR-ActionHub-x64.msi"
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

if ((Get-Variable -Name ExternalFQDN -ErrorAction SilentlyContinue) -and -not [string]::IsNullOrWhiteSpace($ExternalFQDN)) {
    $fqdn = $ExternalFQDN.Trim()
}
else {
    $fqdn = Get-LocalFqdn
}

# Configuration 
$arguments = @(
#Mandatory msiexec Arguments

    "/i"

    "`"$msiFile`""

    "AUTOSTART=1" #Automatically start the service after install

    "/qn" #Quiet - with basic interface - for NO interface use /qn instead

    "/norestart" #Do not restart after install

    "/l*v $env:TEMP\StifleRActionHub-Install.log"    #Optional logging for the install

)   

$Servers = "https://$($fqdn):9000"
$ExternalIp = "https://$($fqdn):1415"

# Configure registry settings for the StifleR ActionHub
$regPath = "HKLM:\SOFTWARE\2Pint Software\StifleR\ActionHub\GeneralSettings"

if (-not (Test-Path -Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}

Write-Host "Configuring the StifleR ActionHub registry values at $regPath"
Write-Host "Setting Servers = $Servers"
Set-ItemProperty -Path $regPath -Name "Servers" -Value $Servers -Type String
Write-Host "Setting ExternalIp = $ExternalIp"

# Install the StifleR ActionHub using msiexec
Write-Host "Using the following install commands: $arguments" 
$installProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList $arguments -Wait -PassThru

if ($installProcess.ExitCode -ne 0) {
    throw "StifleR ActionHub install failed. msiexec exit code: $($installProcess.ExitCode)"
}

Write-Host "StifleR ActionHub installation completed successfully." -ForegroundColor Green