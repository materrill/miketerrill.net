<#
.SYNOPSIS
    Waits for the DEPLOYR infrastructure service to come online, then approves it
    and marks it as the default.

.DESCRIPTION
    1. Polls https://deployr.2pintlabs.local:9000/api/infrastructureService
    2. Looks for hostname "DEPLOYR" with online = $true
    3. Calls /approve on that service's ID
    4. Calls /markAsDefault?isDefault=true

.NOTES
    Author: Mike Terrill / 2Pint Software
    Date: August 6, 2026
    Version: 26.08.06
    Requires: Administrative privileges, 64-bit Windows

    Version history:
    26.08.06: Initial release

.PARAMETER MaxRetries
    Maximum number of attempts to find the online service (default: 30).

.PARAMETER RetryDelaySeconds
    Seconds to wait between attempts (default: 10).

.PARAMETER ApiBaseUrl
    Base URL of the infrastructureService API (no trailing slash).
#>

[CmdletBinding()]
param(
    [int]$MaxRetries = 30,
    [int]$RetryDelaySeconds = 10,
    [string]$ApiBaseUrl = "https://deployr.2pintlabs.local:9000/api/infrastructureService",
    [string]$TargetHostname = "DEPLOYR"
)

$ErrorActionPreference = "Stop"

function Get-DeployRService {
    param(
        [string]$Uri,
        [string]$Hostname
    )

    try {
        $response = Invoke-RestMethod -Uri $Uri -Method Get -UseDefaultCredentials -TimeoutSec 15

        if ($null -eq $response) {
            return $null
        }

        # Response is an array
        $match = $response | Where-Object {
            $_.hostname -eq $Hostname -and $_.online -eq $true
        }

        return $match
    }
    catch {
        Write-Warning "API call failed: $($_.Exception.Message)"
        return $null
    }
}

function Invoke-DeployRAction {
    param(
        [string]$Uri,
        [string]$ActionName
    )

    try {
        # Most DeployR action endpoints accept POST
        $null = Invoke-RestMethod -Uri $Uri -Method Put -UseDefaultCredentials -TimeoutSec 15
        Write-Host "  → $ActionName succeeded" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "  → $ActionName failed: $($_.Exception.Message)"
        return $false
    }
}

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------

Write-Host "Waiting for hostname '$TargetHostname' to appear online..."
Write-Host "API Base     : $ApiBaseUrl"
Write-Host "Max retries  : $MaxRetries"
Write-Host "Retry delay  : $RetryDelaySeconds second(s)"
Write-Host ""

$attempt = 0
$service = $null

while ($attempt -lt $MaxRetries) {
    $attempt++
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Attempt $attempt of $MaxRetries ... " -NoNewline

    $service = Get-DeployRService -Uri $ApiBaseUrl -Hostname $TargetHostname

    if ($null -ne $service) {
        Write-Host "FOUND and ONLINE (id: $($service.id))" -ForegroundColor Green
        break
    }
    else {
        Write-Host "not ready" -ForegroundColor Yellow
    }

    if ($attempt -lt $MaxRetries) {
        Start-Sleep -Seconds $RetryDelaySeconds
    }
}

if ($null -eq $service) {
    Write-Host ""
    Write-Host "Failed: '$TargetHostname' did not become online after $MaxRetries attempts." -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------------
# Approve + Mark as Default
# ------------------------------------------------------------------

$id = $service.id

Write-Host ""
Write-Host "Approving and setting as default..." -ForegroundColor Cyan

$approveUri   = "$ApiBaseUrl/$id/approve"
$defaultUri   = "$ApiBaseUrl/$id/markAsDefault?isDefault=true"

$approveOk = Invoke-DeployRAction -Uri $approveUri -ActionName "Approve"
$defaultOk = Invoke-DeployRAction -Uri $defaultUri -ActionName "Mark as Default"

Write-Host ""

if ($approveOk -and $defaultOk) {
    Write-Host "Success: '$TargetHostname' is approved and set as default." -ForegroundColor Green
    exit 0
}
else {
    Write-Host "Completed with errors (see warnings above)." -ForegroundColor Yellow
    exit 1
}