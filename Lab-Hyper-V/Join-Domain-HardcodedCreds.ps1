<#
.SYNOPSIS
    Joins computer to domain with hardcoded credentials + waits for DC availability
    Used for building out lab kits

.WARNING
    Hardcoding credentials in script is INSECURE.
    Use only in isolated/test environments or if script is strongly protected.
    Consider secrets management (Azure Key Vault, SecretServer, etc.) in real use.

.NOTES
    Author: Mike Terrill/2Pint Software
    Date: April 21, 2026
    Version: 26.04.21

    Version history:
    26.04.21: Initial release

.PARAMETER DomainName
    FQDN of the domain (e.g. corp.example.com)

.PARAMETER DomainAdminUser
    Domain account in format: DOMAIN\username or user@domain.com

.PARAMETER DomainAdminPassword
    Plain text password (will be converted to secure string)

.PARAMETER OUPath
    Optional LDAP path for computer account placement

.PARAMETER TimeoutSeconds
    Max seconds to wait for DC availability (default 600 = 10 min)

.EXAMPLE
    .\Join-Domain-HardcodedCreds.ps1 -DomainName "corp.example.com" `
                                     -DomainAdminUser "CORP\JoinAccount" `
                                     -DomainAdminPassword "P@ssw0rd123!"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$DomainName,

    [Parameter(Mandatory = $true)]
    [string]$DomainAdminUser,

    [Parameter(Mandatory = $true)]
    [string]$DomainAdminPassword,

    [string]$OUPath,

    [int]$TimeoutSeconds = 600
)

# ────────────────────────────────────────────────────────────────
#  1. Convert plain password → SecureString + PSCredential
# ────────────────────────────────────────────────────────────────
$securePass = ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($DomainAdminUser, $securePass)

# ────────────────────────────────────────────────────────────────
#  2. Wait for domain controller availability
# ────────────────────────────────────────────────────────────────
Write-Host "`nWaiting for domain controller availability..." -ForegroundColor Cyan
Write-Host "Domain: $DomainName"
Write-Host "Timeout: $TimeoutSeconds seconds`n"

$startTime = Get-Date
$dcReady = $false


while (-not $dcReady -and ((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
    try {
        $dcRecords = Resolve-DnsName "_ldap._tcp.dc._msdcs.$DomainName" -Type SRV -ErrorAction Stop
        
        if ($dcRecords) {
            $dcHost = $dcRecords | Select-Object -First 1 -ExpandProperty NameTarget
            $tcpTest = Test-NetConnection -ComputerName $dcHost -Port 389 -WarningAction SilentlyContinue -InformationLevel Quiet
            
            if ($tcpTest) {
                Write-Host "Domain controller reachable: $dcHost (LDAP port 389 open)" -ForegroundColor Green
                $dcReady = $true
                break
            }
        }
    }
    catch { }

    Write-Host "." -NoNewline -ForegroundColor Yellow
    Start-Sleep -Seconds 5
}

if (-not $dcReady) {
    Write-Host "`n`nTimeout reached ($TimeoutSeconds sec). Could not contact domain controller." -ForegroundColor Red
    Write-Host "Check network, DNS settings, and VPN/firewall." -ForegroundColor Red
    exit 1
}

Write-Host "`nDomain controller is available. Proceeding with domain join..." -ForegroundColor Green

# ────────────────────────────────────────────────────────────────
#  3. Perform the domain join
# ────────────────────────────────────────────────────────────────
try {
    $joinParams = @{
        DomainName  = $DomainName
        Credential  = $credential
        Force       = $true
        Restart     = $false
        Verbose     = $true
        ErrorAction = 'Stop'
    }

    if ($OUPath) {
        $joinParams['OUPath'] = $OUPath
    }

    Add-Computer @joinParams

    Write-Host "`nJoin command accepted. Machine will restart shortly..." -ForegroundColor Green
}
catch {
    Write-Host "`nDomain join FAILED!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    if ($_.Exception.Message -match "access denied|permission|rights|trusted|account") {
        Write-Host "`nCommon issues:" -ForegroundColor Yellow
        Write-Host "• Credentials incorrect or lack join rights"
        Write-Host "• Computer already exists in domain (needs reset or delete)"
        Write-Host "• Account locked / expired / restricted"
    }

    exit 1
}

# Brief pause so user can read output
Start-Sleep -Seconds 8
