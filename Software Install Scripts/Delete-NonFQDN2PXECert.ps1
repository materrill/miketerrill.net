<#
.SYNOPSIS
    PowerShell script to find certificates issued by 2PintSoftware.com and inspect Subject Alternative Names (SANs) for FQDNs
.DESCRIPTION
    This script will check the 2PXE self-signed certificates for the FQDN name of the system and will delete them if delete is enabled
    It verifies the import, and handles common errors.
.NOTES
    Author: Mike Terrill/2Pint Software
    Date: July 20, 2025
    Version: 25.07.20
    Requires: Administrative privileges, 64-bit Windows
#># 

# This will use the connection specific suffix for the fqdn - useful when system is not domain joined
$domain = [string](Get-DnsClient | Select-Object -ExpandProperty ConnectionSpecificSuffix)
$fqdn = "$($env:COMPUTERNAME.Trim()).$($domain.Trim())"
$match = $false
$delete = $true

# Ensure the script runs with elevated privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script requires administrative privileges. Please run PowerShell as Administrator."
    exit 1
}

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
                    Write-Host "  - FQDN: $SANfqdn"
                    if ($SANfqdn -eq $fqdn) {$match = $true}
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

Write-Host "SAN FQDN equals system FQDN: $match"

if ($match -eq $false) {

    try {
    # Open the Local Machine's Personal certificate store
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
        [System.Security.Cryptography.X509Certificates.StoreName]::My,
        [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
    )
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)

    # Find certificates where the issuer contains "2PintSoftware.com"
    $certificates = $store.Certificates | Where-Object { $_.Issuer -like "*2PintSoftware.com*" }

    if (-not $certificates) {
        Write-Host "No certificates found issued by 2PintSoftware.com in the Local Machine Personal store."
        $store.Close()
        exit 0
    }

    # Iterate through matching certificates
    $deletedCount = 0
    foreach ($cert in $certificates) {
        Write-Host "---------------------------------------------"
        Write-Host "Certificate Found:"
        Write-Host "Subject: $($cert.Subject)"
        Write-Host "Issuer: $($cert.Issuer)"
        Write-Host "Thumbprint: $($cert.Thumbprint)"
        Write-Host "Valid From: $($cert.NotBefore)"
        Write-Host "Valid Until: $($cert.NotAfter)"

        # Delete certificate if $delete is set to $true
        if ($delete -eq $true) {
            try {
                # Remove the certificate from the store
                $store.Remove($cert)
                Write-Host "Certificate with thumbprint $($cert.Thumbprint) deleted successfully."
                $deletedCount++
            }
            catch {
                Write-Error "Failed to delete certificate with thumbprint $($cert.Thumbprint): $_"
            }
        } else {
            Write-Host "Delete is set to false."
            Write-Host "Skipping deletion of certificate with thumbprint $($cert.Thumbprint)."
        }
        Write-Host "---------------------------------------------"
    }

    # Report summary
    Write-Host "Script completed. $deletedCount certificate(s) deleted."

    # Close the store
    $store.Close()
    }
    catch {
        Write-Error "An error occurred: $_"
        if ($store) { $store.Close() }
        exit 1
    }
}

# Verify no certificates remain
try {
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
        [System.Security.Cryptography.X509Certificates.StoreName]::My,
        [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
    )
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
    $remainingCerts = $store.Certificates | Where-Object { $_.Issuer -like "*2PintSoftware.com*" }
    $store.Close()

    if (-not $remainingCerts) {
        Write-Host "Verification: No certificates issued by 2PintSoftware.com remain in the Personal store."
    } else {
        Write-Warning "Verification: $($remainingCerts.Count) certificate(s) issued by 2PintSoftware.com still remain in the Personal store."
    }
}
catch {
    Write-Error "Verification failed: $_"
}
