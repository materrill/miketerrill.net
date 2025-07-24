<#
.SYNOPSIS
    PowerShell script to automate the basic configuration of DeployR after the install
.DESCRIPTION
    This script will check the 2PXE self-signed certificates for the FQDN name of the system and will grab the thumbprint
    It will update the required values (thumbprint, connection string, client URL, StifleR Server API URL) and any optional values (content location).
    It verifies the import, and handles common errors.
.NOTES
    Author: Mike Terrill/2Pint Software
    Date: July 23, 2025
    Version: 25.07.23
    Requires: Administrative privileges, 64-bit Windows
#>

# Ensure the script runs with elevated privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script requires administrative privileges. Please run PowerShell as Administrator."
    exit 1
}

# Example: Construct FQDN dynamically using computer name and domain suffix - useful when system is not domain joined
$domain = [string](Get-DnsClient | Select-Object -ExpandProperty ConnectionSpecificSuffix)
$fqdn = "$($env:COMPUTERNAME.Trim()).$($domain.Trim())" # Or set a static value, e.g., "2PINT.corp.viamonstra.com"
$match = $false

# Required Settings
$ConnectionString = "Server=.\SQLEXPRESS;Database=DeployR;Trusted_Connection=True;MultipleActiveResultSets=true;TrustServerCertificate=True"
$ClientURL = "https://$($fqdn):7281"
$JoinInfrastructure = "True"
$StifleRServerApiUrl = "https://$($fqdn):9000"

# Optional Settings
# Uncomment and enter values
#$ContentLocation = "D:\DeployR"

# Define registry path
$regPath = "HKLM:\SOFTWARE\2Pint Software\DeployR\GeneralSettings"

try {
    # Open the Local Machine's Personal certificate store
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
        [System.Security.Cryptography.X509Certificates.StoreName]::My,
        [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
    )
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)

    # Find certificates where the issuer contains "2PintSoftware.com"
    $certificates = $store.Certificates | Where-Object { $_.Issuer -like "*2PintSoftware.com*" }

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

#Stop the DeployR Service
try {
    # Check if the DeployR service exists
    $service = Get-Service -Name "DeployRService" -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Host "The DeployR service was not found on this computer."
        exit 0
    }

    # Check the current status of the service
    Write-Host "Current status of DeployR service: $($service.Status)"

    # Stop the service if it is running
    if ($service.Status -eq 'Running') {
        Write-Host "Stopping the DeployR service..."
        Stop-Service -Name "DeployRService" -Force -ErrorAction Stop
        Write-Host "Service stop command issued. Waiting for service to stop..."

        # Wait for the service to stop (up to 30 seconds)
        $service.WaitForStatus('Stopped', '00:00:30')

        # Verify the service status
        $service.Refresh()
        if ($service.Status -eq 'Stopped') {
            Write-Host "Verification: DeployR service is now stopped."
        } else {
            Write-Warning "Verification: DeployR service is still in state: $($service.Status)"
        }
    } else {
        Write-Host "The DeployR service is already stopped or in state: $($service.Status)"
    }
}
catch {
    Write-Error "An error occurred while attempting to stop the DeployR service: $_"
    exit 1
}

# Create registry key if it doesn't exist
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}

# Set registry values
Set-ItemProperty -Path $regPath -Name "CertificateThumbprint" -Value "$Thumbprint" -Type String
Set-ItemProperty -Path $regPath -Name "ConnectionString" -Value "$ConnectionString" -Type String
Set-ItemProperty -Path $regPath -Name "ClientURL" -Value "$ClientURL" -Type String
Set-ItemProperty -Path $regPath -Name "JoinInfrastructure" -Value "$JoinInfrastructure" -Type String
Set-ItemProperty -Path $regPath -Name "StifleRServerApiUrl" -Value "$StifleRServerApiUrl" -Type String

# Set optional registry values
if ($ContentLocation) {
    Set-ItemProperty -Path $regPath -Name "ContentLocation" -Value "$ContentLocation" -Type String
}

Write-Host "Registry entries created successfully."

# Start the DeployR Service
try {
    # Check if the DeployR service exists
    $service = Get-Service -Name "DeployRService" -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Host "The DeployR service was not found on this computer."
        exit 0
    }

    # Check the current status of the service
    Write-Host "Current status of DeployR service: $($service.Status)"

    # Start the service if it is not running
    if ($service.Status -ne 'Running') {
        Write-Host "Starting the DeployR service..."
        Start-Service -Name "DeployRService" -ErrorAction Stop
        Write-Host "Service start command issued. Waiting for service to start..."

        # Wait for the service to start (up to 30 seconds)
        $service.WaitForStatus('Running', '00:00:30')

        # Verify the service status
        $service.Refresh()
        if ($service.Status -eq 'Running') {
            Write-Host "Verification: DeployR service is now running."
        } else {
            Write-Warning "Verification: DeployR service is still in state: $($service.Status)"
        }
    } else {
        Write-Host "The DeployR service is already running."
    }
}
catch {
    Write-Error "An error occurred while attempting to start the DeployR service: $_"
    exit 1
}

Write-Host "Script completed."
