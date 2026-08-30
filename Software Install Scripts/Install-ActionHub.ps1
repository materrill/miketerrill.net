<#
.SYNOPSIS
    Installs and configures the StifleR ActionHub.
.DESCRIPTION
    This script automates the install and configuration of the StifleR ActionHub.
    It logs the process and handles common errors, suitable for large-scale deployment scenarios.
.NOTES
    Author: Mike Terrill/2Pint Software
    Date: August 29, 2026
    Version: 26.08.29
    Requires: Administrative privileges, 64-bit Windows (10/11, Server 2016+), internet access
    
    Version history:
    26.08.28: Initial release
    26.08.29: Updated to take ExternalFQDN and an optional parameter.
  
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ExternalFQDN
)

# Optional: pass -ExternalFQDN "server.company.com". If not set, the script will use the local FQDN.

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

try {
    # Open the Local Machine's Personal certificate store
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
        [System.Security.Cryptography.X509Certificates.StoreName]::My,
        [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
    )
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)

    # Find certificates where the issuer contains "2PintSoftware.com"
    $certificates = $store.Certificates | Where-Object { $_.Issuer -like "*2Pint*" }

    if (-not $certificates) {
        Write-Host "No certificates found issued by 2PintSoftware.com in the Local Machine Personal store."
        $store.Close()
        exit 0
    }

    # Iterate through matching certificates
    foreach ($cert in $certificates) {
        Write-Host "---------------------------------------------"
        Write-Host "Certificate Found:"
        Write-Host "Subject: $($cert.Subject)"
        Write-Host "Issuer: $($cert.Issuer)"
        Write-Host "Thumbprint: $($cert.Thumbprint)"
        Write-Host "Valid From: $($cert.NotBefore)"
        Write-Host "Valid Until: $($cert.NotAfter)"

        # Check for Subject Alternative Name extension
        $sanExtension = $cert.Extensions | Where-Object { $_.Oid.FriendlyName -eq "Subject Alternative Name" }

        if ($sanExtension) {
            Write-Host "Subject Alternative Names (SANs):"
            # Parse the SAN extension
            $sanRawData = $sanExtension.Format($true)
            # Split the SAN data into lines and look for DNS names
            $sanEntries = $sanRawData -split "`n" | Where-Object { $_ -match "DNS Name=" }
            
            if ($sanEntries) {
                foreach ($entry in $sanEntries) {
                    # Extract the FQDN from the DNS Name entry
                    $SANfqdn = $entry -replace "DNS Name=", "" -replace "\s", ""
                    $Thumbprint = $cert.Thumbprint
                    Write-Host "  - FQDN: $SANfqdn"
                    Write-Host "  - Thumbprint: $Thumbprint"
                    if ($SANfqdn -eq $fqdn) {
                        $match = $true
                        $Thumbprint = $cert.Thumbprint
                    }
                }
            } else {
                Write-Host "  No DNS Names found in SAN."
            }
        } else {
            Write-Host "No Subject Alternative Name extension found."
        }
        Write-Host "---------------------------------------------"
    }

    # Close the store
    $store.Close()
}
catch {
    Write-Error "An error occurred: $_"
    if ($store) { $store.Close() }
    exit 1
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
Set-ItemProperty -Path $regPath -Name "ExternalIp" -Value $ExternalIp -Type String
Write-Host "Setting CertificateThumbprint = $Thumbprint"
Set-ItemProperty -Path $regPath -Name "CertificateThumbprint" -Value $Thumbprint -Type String

# Install the StifleR ActionHub using msiexec
Write-Host "Using the following install commands: $arguments" 
$installProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList $arguments -Wait -PassThru

if ($installProcess.ExitCode -ne 0) {
    throw "StifleR ActionHub install failed. msiexec exit code: $($installProcess.ExitCode)"
}

Write-Host "StifleR ActionHub installation completed successfully." -ForegroundColor Green