# PowerShell script to import a root certificate into the Trusted Root Certification Authorities store

# Specify the path to the certificate file
$certFilePath = "C:\Program Files\2Pint Software\2PXE\x64\ca.crt"

# Check if the certificate file exists
if (-not (Test-Path -Path $certFilePath)) {
    Write-Error "Certificate file not found at: $certFilePath"
    exit 1
}

try {
    # Load the certificate
    $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
    $certificate.Import($certFilePath)
    
    # Display certificate details for verification
    Write-Host "Importing certificate: $($certificate.Subject)"
    Write-Host "Issuer: $($certificate.Issuer)"
    Write-Host "Thumbprint: $($certificate.Thumbprint)"

    # Open the Trusted Root Certification Authorities store for the Local Machine
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
        [System.Security.Cryptography.X509Certificates.StoreName]::Root,
        [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
    )
    
    # Open the store with read/write access
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    
    # Check if the certificate already exists in the store
    $existingCert = $store.Certificates | Where-Object { $_.Thumbprint -eq $certificate.Thumbprint }
    if ($existingCert) {
        Write-Warning "Certificate with thumbprint $($certificate.Thumbprint) already exists in the Trusted Root store."
    } else {
        # Add the certificate to the store
        $store.Add($certificate)
        Write-Host "Certificate successfully imported to Trusted Root Certification Authorities store."
    }
    
    # Close the store
    $store.Close()
}
catch {
    Write-Error "Failed to import certificate: $_"
    $store.Close()
    exit 1
}

# Verify the certificate was added
$store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
    [System.Security.Cryptography.X509Certificates.StoreName]::Root,
    [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
)
$store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
$certInStore = $store.Certificates | Where-Object { $_.Thumbprint -eq $certificate.Thumbprint }
$store.Close()

if ($certInStore) {
    Write-Host "Verification: Certificate with thumbprint $($certificate.Thumbprint) is present in the Trusted Root store."
} else {
    Write-Warning "Verification: Certificate with thumbprint $($certificate.Thumbprint) was not found in the Trusted Root store."
}
