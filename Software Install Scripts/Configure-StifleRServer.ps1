<#
.SYNOPSIS
    PowerShell script to automate the basic configuration of StifleR Server after the install
.DESCRIPTION
    This script will check the 2PXE self-signed certificates for the FQDN name of the system and will grab the thumbprint
    It will update the required values (thumbprint) and any optional values (license key, groups).
    It verifies the import, and handles common errors.
.NOTES
    Author: Mike Terrill/2Pint Software
    Date: August 4, 2025
    Version: 25.08.04
    Requires: Administrative privileges, 64-bit Windows
#>

# Ensure the script runs with elevated privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script requires administrative privileges. Please run PowerShell as Administrator."
    exit 1
}

# Specify the new ExternalFQDNOverride value (e.g., dynamically constructed or static)
# Example: Construct FQDN dynamically using computer name and domain suffix - useful when system is not domain joined
$domain = [string](Get-DnsClient | Select-Object -ExpandProperty ConnectionSpecificSuffix)
$fqdn = "$($env:COMPUTERNAME.Trim()).$($domain.Trim())"
$newExternalFQDN = $fqdn  # Or set a static value, e.g., "2PINT.corp.viamonstra.com"
$match = $false

# Optional Settings
# Uncomment and enter values
# Be sure to leave the double back slash (\\) between the hostname/domain and group/user name
#$LicenseKey = "abc123"
#$Administrators = "Domain\\Group"
#$ReadAccess = "Hostname\\Group"

# Define registry path
$regPath = "HKLM:\SOFTWARE\2Pint Software\StifleR\Server\GeneralSettings"

# This will use the connection specific suffix for the fqdn - useful when system is not domain joined
$domain = [string](Get-DnsClient | Select-Object -ExpandProperty ConnectionSpecificSuffix)
$fqdn = "$($env:COMPUTERNAME.Trim()).$($domain.Trim())"

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

#Stop the Stifler Server Service
try {
    # Check if the Stifler Server service exists
    $service = Get-Service -Name "StifleRServer" -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Host "The Stifler Server service was not found on this computer."
        exit 0
    }

    # Check the current status of the service
    Write-Host "Current status of Stifler Server service: $($service.Status)"

    # Stop the service if it is running
    if ($service.Status -eq 'Running') {
        Write-Host "Stopping the Stifler Server service..."
        Stop-Service -Name "StifleRServer" -Force -ErrorAction Stop
        Write-Host "Service stop command issued. Waiting for service to stop..."

        # Wait for the service to stop (up to 30 seconds)
        $service.WaitForStatus('Stopped', '00:00:30')

        # Verify the service status
        $service.Refresh()
        if ($service.Status -eq 'Stopped') {
            Write-Host "Verification: Stifler Server service is now stopped."
        } else {
            Write-Warning "Verification: Stifler Server service is still in state: $($service.Status)"
        }
    } else {
        Write-Host "The Stifler Server service is already stopped or in state: $($service.Status)"
    }
}
catch {
    Write-Error "An error occurred while attempting to stop the Stifler Server service: $_"
    exit 1
}

# Create registry key if it doesn't exist
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}

# Set registry values
Set-ItemProperty -Path $regPath -Name "SignalRCertificateThumbprint" -Value "$Thumbprint" -Type String
Set-ItemProperty -Path $regPath -Name "WSCertificateThumbprint" -Value "$Thumbprint" -Type String

# Set optional registry values
if ($LicenseKey) {
    Set-ItemProperty -Path $regPath -Name "LicenseKey" -Value "$LicenseKey" -Type String
}
if ($Administrators) {
    Set-ItemProperty -Path $regPath -Name "Administrators" -Value "[`"$Administrators`"]" -Type String
}
if ($ReadAccess) {
    Set-ItemProperty -Path $regPath -Name "ReadAccess" -Value "[`"$ReadAccess`"]" -Type String
}

Write-Host "Registry entries created successfully."

# Start the StifleR Server Service
$serviceName = "StifleRServer"
try {
    # Check if the Stifler Server service exists
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Host "The $serviceName service was not found on this computer."
        exit 0
    }

    # Check the current status of the service
    Write-Host "Current status of $serviceName service: $($service.Status)"

    # Start the service if it is not running
    if ($service.Status -ne 'Running') {
        Write-Host "Starting the $serviceName service..."
        Start-Service -Name $serviceName -ErrorAction Stop
        Write-Host "Service start command issued. Waiting for service to start..."

        # Wait for the service to start (up to 30 seconds)
        $service.WaitForStatus('Running', '00:00:30')

        # Verify the service status
        $service.Refresh()
        if ($service.Status -eq 'Running') {
            Write-Host "Verification: $serviceName service is now running."
        } else {
            Write-Warning "Verification: $serviceName service is still in state: $($service.Status)"
        }
    } else {
        Write-Host "The $serviceName service is already running."
    }

    # Set StifleR Server Service Startup Type to Automatic
    if ($service.StartType -ne "Automatic") {
        try {
            Set-Service -Name $serviceName -StartupType Automatic -ErrorAction Stop
            Write-Host "Startup type for '$serviceName' changed to Automatic."
            $updatedService = Get-Service -Name $serviceName
            Write-Host "Verified new startup type: $($updatedService.StartType)"
            } 
        catch {
            Write-Host "Failed to set startup type for $serviceName to Automatic"
            exit 1
        }
    } 
    else {
        Write-Host "Startup type for $serviceName is already Automatic. No action taken."
    }
}
catch {
    Write-Host "An error occurred while attempting to start and configure the $serviceName service"
    exit 1
}

Write-Host "Script completed."
