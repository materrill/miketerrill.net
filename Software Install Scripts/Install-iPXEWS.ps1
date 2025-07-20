<#
.SYNOPSIS
    PowerShell script to perform an unattended install of iPXE Webservice 
.DESCRIPTION
    This script automates installing iPXE Webservice and will grab the certificate thumbprint
    from a 2PXE FQDN self-signed certificate. Make sure 2PXE is installed first and a FQDN cert
    has been generated.
    It verifies the import, and handles common errors.
.NOTES
    Author: Mike Terrill/2Pint Software
    Date: July 20, 2025
    Version: 25.07.20
    Requires: Administrative privileges, 64-bit Windows
#>

# Set path to MSI file
$msifile = "$PSScriptRoot\iPXEAnywhere.WebService.Installer64.msi"

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
                    $Thumbprint = $cert.Thumbprint
                    Write-Host "  - FQDN: $SANfqdn"
                    Write-Host "  - Thumbprint: $Thumbprint"
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

$arguments = @(
#Mandatory msiexec Arguments

    "/i"

    "`"$msiFile`""

#Mandatory 2Pint Arguments
    
    "ODBC_SERVER=`"$env:COMPUTERNAME\SQLEXPRESS`""   # Change to the correct database server and instance
    "CERTHASH=`"$Thumbprint`""                       # Certificate thumbprint detected above or change if previously known

#Non Mandatory 2Pint Arguments - Uncomment+change the settings that you need - otherwise the default will be used.

# "LICENSEKEY=`"ABC123`""                            # License key 
# "LICENSETYPE=`"#3`""                               # Uncomment if a license key was entered 

#Other MSIEXEC params
    "/qn" #Quiet - with basic interface - for NO interface use /qn instead

    "/norestart"

    "/l*v $env:TEMP\iPXEWSInstall.log"    #Optional logging for the install

)

write-host "Using the following install commands: $arguments" #uncomment this line to see the command line

#Install the iPXE Webservice
start-process "msiexec.exe" -arg $arguments -Wait
