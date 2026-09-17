<#
.SYNOPSIS
    Tests the connection to the DeployR Server.
.DESCRIPTION
    This script tests the network connectivity to the DeployR Server.
    It will first check for a valid network configuration, and then attempt to connect to the DeployR Server on port 7281.
    Add this to the PostInit.ps1 script in WinPE/WinRE:
    . "$PSScriptRoot\Test-DeployRConnection.ps1"

.NOTES
    Author: Mike Terrill/2Pint Software
    Date: September 17, 2026
    Version: 26.09.17
        
    Version history:
    26.09.17: Initial release
 
#>

$DeployRServer = "deployr.2pintdemo.net"

$MaxWaitSeconds = 120
$IntervalSeconds = 10

function Get-NetworkInfo {

    $Config = Get-NetIPConfiguration | Where-Object {
        $_.IPv4Address -or $_.IPv4DefaultGateway
    } | Select-Object -First 1

    if (-not $Config) {
        return $null
    }

    $IPInfo = Get-NetIPAddress `
        -InterfaceIndex $Config.InterfaceIndex `
        -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -notlike '169.254*' } |
        Select-Object -First 1

    if (-not $IPInfo) {
        return $null
    }

    $WmiAdapter = Get-CimInstance Win32_NetworkAdapterConfiguration |
        Where-Object {
            $_.IPEnabled -and
            $_.InterfaceIndex -eq $Config.InterfaceIndex
        }

    $SubnetMask = $WmiAdapter.IPSubnet |
        Where-Object { $_ -and $_ -notlike '*:*' } |
        Select-Object -First 1

    [PSCustomObject]@{
        Adapter    = $Config.InterfaceAlias
        IPAddress  = $IPInfo.IPAddress
        SubnetMask = $SubnetMask
        Gateway    = $Config.IPv4DefaultGateway.NextHop
        DHCPServer = $WmiAdapter.DHCPServer
        DNSServers = ($Config.DNSServer.ServerAddresses -join ', ')
    }
}

#
# Phase 1 - Wait for network configuration
#
$Elapsed = 0
$NetworkInfo = $null

while ($Elapsed -lt $MaxWaitSeconds) {

    $NetworkInfo = Get-NetworkInfo

    if ($NetworkInfo) {
        Write-Host "Network configuration detected." -ForegroundColor Green
        $NetworkInfo | Format-List
        break
    }

    Write-Host "Waiting for network configuration... ($Elapsed/$MaxWaitSeconds seconds)"
    Start-Sleep -Seconds $IntervalSeconds
    $Elapsed += $IntervalSeconds
}

if (-not $NetworkInfo) {
    Write-Warning "No network configuration detected after $MaxWaitSeconds seconds."
    exit 1
}

#
# Phase 2 - Wait for DeployR connectivity
#
Write-Host ""
Write-Host "Testing connectivity to $DeployRServer on port 7281..." -ForegroundColor Cyan

$Elapsed = 0
$Connected = $false

while ($Elapsed -lt $MaxWaitSeconds) {

    try {
        $Test = Test-NetConnection `
            -ComputerName $DeployRServer `
            -Port 7281 `
            -WarningAction SilentlyContinue `
            -InformationLevel Quiet

        if ($Test) {
            Write-Host "Successfully connected to $DeployRServer on port 7281." -ForegroundColor Green
            $Connected = $true
            break
        }
    }
    catch {
        # Ignore and retry
    }

    Write-Host "Unable to connect to $DeployRServer:7281. Retrying... ($Elapsed/$MaxWaitSeconds seconds)"
    Start-Sleep -Seconds $IntervalSeconds
    $Elapsed += $IntervalSeconds
}

if (-not $Connected) {
    Write-Warning "Failed to connect to $DeployRServer on port 7281 after $MaxWaitSeconds seconds."
    exit 2
}

exit 0