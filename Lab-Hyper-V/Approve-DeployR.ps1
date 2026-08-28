<#
.SYNOPSIS
    Waits for the DEPLOYR infrastructure service(s) to come online, then approves each
    and marks each as the default.

.DESCRIPTION
    1. Polls https://deployr.2pintlabs.local:9000/api/infrastructureService
    2. Looks for hostname "DEPLOYR" with online = $true
    3. Calls /approve on each service ID
    4. Calls /markAsDefault?isDefault=true on each service ID that is not already default

.NOTES
    Author: Mike Terrill / 2Pint Software
    Date: August 28, 2026
    Version: 26.08.28
    Requires: Administrative privileges, 64-bit Windows

    Version history:
    26.08.06: Initial release
    26.08.28: Added support for multiple DEPLOYR services (2PXE, iPXEWS, etc.)

.PARAMETER MaxRetries
    Maximum number of attempts to find the online service (default: 30).

.PARAMETER RetryDelaySeconds
    Seconds to wait between attempts (default: 10).

.PARAMETER ApiBaseUrl
    Base URL of the infrastructureService API (no trailing slash).

.PARAMETER TargetHostname
    Hostname of the infrastructure service to wait for (default: DEPLOYR).
#>

[CmdletBinding()]
param(
    [int]$MaxRetries = 30,
    [int]$RetryDelaySeconds = 10,
    [string]$ApiBaseUrl = "https://deployr.2pintlabs.local:9000/api/infrastructureService",
    [string]$TargetHostname = "DEPLOYR"
)

$ErrorActionPreference = "Stop"

function Get-DeployRServices {
    param(
        [string]$Uri,
        [string]$Hostname
    )

    try {
        $response = Invoke-RestMethod -Uri $Uri -Method Get -UseDefaultCredentials -TimeoutSec 15

        if ($null -eq $response) {
            return @()
        }

        # Always treat as a collection (single object or array)
        $items = @($response)

        $matches = $items | Where-Object {
            $_.hostname -eq $Hostname -and $_.online -eq $true
        }

        return @($matches)
    }
    catch {
        Write-Warning "API call failed: $($_.Exception.Message)"
        return @()
    }
}

function Invoke-DeployRAction {
    param(
        [string]$Uri,
        [string]$ActionName
    )

    try {
        $null = Invoke-RestMethod -Uri $Uri -Method Put -UseDefaultCredentials -TimeoutSec 15
        Write-Host "    $ActionName succeeded" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "    $ActionName failed: $($_.Exception.Message)"
        return $false
    }
}

# ------------------------------------------------------------------
# Wait until at least one matching online service is present
# ------------------------------------------------------------------

Write-Host "Waiting for hostname '$TargetHostname' to appear online..."
Write-Host "API Base     : $ApiBaseUrl"
Write-Host "Max retries  : $MaxRetries"
Write-Host "Retry delay  : $RetryDelaySeconds second(s)"
Write-Host ""

$attempt = 0
$services = @()

while ($attempt -lt $MaxRetries) {
    $attempt++
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Attempt $attempt of $MaxRetries ... " -NoNewline

    $services = Get-DeployRServices -Uri $ApiBaseUrl -Hostname $TargetHostname

    if ($services.Count -gt 0) {
        Write-Host "FOUND $($services.Count) online service(s)" -ForegroundColor Green
        break
    }
    else {
        Write-Host "not ready" -ForegroundColor Yellow
    }

    if ($attempt -lt $MaxRetries) {
        Start-Sleep -Seconds $RetryDelaySeconds
    }
}

if ($services.Count -eq 0) {
    Write-Host ""
    Write-Host "Failed: no '$TargetHostname' service became online after $MaxRetries attempts." -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------------
# Approve + Mark as Default for EACH matching service
# ------------------------------------------------------------------

Write-Host ""
Write-Host "Processing $($services.Count) service(s)..." -ForegroundColor Cyan

$overallSuccess = $true

foreach ($service in $services) {
    $id      = $service.id
    $type    = $service.type
    $version = $service.version
    $alreadyDefault = [bool]$service.isDefault

    Write-Host ""
    Write-Host "Service ID : $id" -ForegroundColor White
    Write-Host "  hostname : $($service.hostname)"
    Write-Host "  type     : $type"
    Write-Host "  version  : $version"
    Write-Host "  online   : $($service.online)"
    Write-Host "  isDefault: $alreadyDefault"
    Write-Host "  url      : $($service.externalUrl)"

    $approveUri = "$ApiBaseUrl/$id/approve"
    $defaultUri = "$ApiBaseUrl/$id/markAsDefault?isDefault=true"

    Write-Host "  Approving..."
    $approveOk = Invoke-DeployRAction -Uri $approveUri -ActionName "Approve"

    if ($alreadyDefault) {
        Write-Host "    Already default — skipping markAsDefault" -ForegroundColor DarkGray
        $defaultOk = $true
    }
    else {
        Write-Host "  Marking as default..."
        $defaultOk = Invoke-DeployRAction -Uri $defaultUri -ActionName "Mark as Default"
    }

    if (-not ($approveOk -and $defaultOk)) {
        $overallSuccess = $false
    }
}

Write-Host ""

if ($overallSuccess) {
    Write-Host "Success: all $($services.Count) '$TargetHostname' service(s) approved and set as default." -ForegroundColor Green
    exit 0
}
else {
    Write-Host "Completed with errors on one or more services (see warnings above)." -ForegroundColor Yellow
    exit 1
}