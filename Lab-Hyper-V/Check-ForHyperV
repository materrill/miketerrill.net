<#
.SYNOPSIS
    Checks if Hyper-V is installed and/or enabled on the system.

.DESCRIPTION
    Returns detailed information about Hyper-V installation status using multiple detection methods.

.EXAMPLE
    .\Check-HyperV.ps1

    Shows whether Hyper-V is installed and enabled.
#>

Write-Host "Hyper-V Detection" -ForegroundColor Cyan
Write-Host "======================" -ForegroundColor Cyan

# Method 1: Check Windows Optional Feature (most reliable modern method)
try {
    $hyperVFeature = Get-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V" -ErrorAction Stop
    
    Write-Host "Windows Optional Feature status:" -ForegroundColor Gray
    if ($hyperVFeature.State -eq "Enabled") {
        Write-Host "Hyper-V is " -NoNewline
        Write-Host "ENABLED" -ForegroundColor Green
    }
    elseif ($hyperVFeature.State -eq "Disabled") {
        Write-Host "Hyper-V is " -NoNewline
        Write-Host "DISABLED" -ForegroundColor Yellow
    }
    else {
        Write-Host "Hyper-V feature state: $($hyperVFeature.State)" -ForegroundColor Magenta
    }
}
catch {
    Write-Host "Could not query Windows Optional Feature (older OS?)" -ForegroundColor DarkGray
}

# Method 2: Check Hyper-V role via Server Manager (good for Windows Server / some client SKUs)
if (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue) {
    $hyperVRole = Get-WindowsFeature -Name Hyper-V
    
    Write-Host "`nServer Role status:" -ForegroundColor Gray
    if ($hyperVRole.Installed) {
        Write-Host "Hyper-V role is " -NoNewline
        Write-Host "INSTALLED" -ForegroundColor Green
    }
    else {
        Write-Host "Hyper-V role is " -NoNewline
        Write-Host "NOT installed" -ForegroundColor Yellow
    }
}

# Method 3: Quick environment + service check (fast fallback)
Write-Host "`nQuick checks:" -ForegroundColor Gray

# VMMS = Virtual Machine Management Service (core Hyper-V service)
$vmms = Get-Service -Name vmms -ErrorAction SilentlyContinue
if ($vmms) {
    Write-Host "✓ VMMS service exists" -ForegroundColor Green
    if ($vmms.Status -eq "Running") {
        Write-Host "  └─ Status: Running" -ForegroundColor Green
    }
    else {
        Write-Host "  └─ Status: $($vmms.Status)" -ForegroundColor Yellow
    }
}
else {
    Write-Host "VMMS service not found" -ForegroundColor DarkGray
}

# Hyper-V Virtual Machine Management root namespace
$hyperVNamespace = Get-CimInstance -Namespace "root\virtualization\v2" -ClassName Msvm_ComputerSystem -ErrorAction SilentlyContinue
if ($hyperVNamespace) {
    Write-Host "✓ Hyper-V WMI namespace (v2) exists" -ForegroundColor Green
}
else {
    Write-Host "Hyper-V WMI namespace not found" -ForegroundColor DarkGray
}

# Final verdict (simple one-liner summary)
Write-Host "`nConclusion: " -NoNewline -ForegroundColor White

if ($hyperVFeature -and $hyperVFeature.State -eq "Enabled") {
    Write-Host "Hyper-V is INSTALLED and ENABLED" -ForegroundColor Green
}
elseif ($vmms -or $hyperVNamespace) {
    Write-Host "Hyper-V appears to be INSTALLED (possibly enabled)" -ForegroundColor Green
}
else {
    Write-Host "Hyper-V is NOT installed" -ForegroundColor Yellow
    Exit 1
}

Write-Host ""
