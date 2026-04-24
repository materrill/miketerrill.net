<#
.SYNOPSIS
    Checks if DHCP is installed and/or enabled/configured on the system for 2PXE.

.DESCRIPTION
    Installs DHCP if necessary, authorizes DHCP server in AD, creates a DHCP scope
    and configures scope options and policies for 2PXE

.NOTES
    Author: Mike Terrill/2Pint Software
    Date: April 23, 2026
    Version: 26.04.23

    Version history:
    26.04.23 Initial release (2PXE policies originally based on a script by Niklas Larsson

.EXAMPLE
    .\Setup-2PXE-DHCP.ps1 -CreateScope -StartIP "10.10.10.100" -EndIP "10.10.10.200" `
    -SubnetMask "255.255.255.0" -Gateway "10.10.10.1" -DNSServers "10.10.10.10" `
    -ScopeName "Headquarters" -Option66 "10.10.10.20" `
    -ExtraDHCPOptionValue "https://deployr.2pintlabs.local:8050/" 
    -ArchitectureIndexes 0,2 -EnableOption 60 -AuthorizeInAD -Force

#>

[CmdletBinding()]
param (
    # === Scope Parameters ===
    [switch]$CreateScope,
    [string]$ScopeName = "PXE Scope",
    [string]$StartIP,
    [string]$EndIP,
    [string]$SubnetMask = "255.255.255.0",
    [string]$Gateway,
    [string[]]$DNSServers,

    # === PXE / Policy Parameters ===
    [int[]]$ArchitectureIndexes = @(0, 2),                    # 0=BIOS, 1=UEFI x86, 2=UEFI x64
    [string]$Option66 = "10.10.10.20",                       # 2PXE Server IP
    [string]$ExtraDHCPOptionValue = "https://deployr.2pintlabs.local:8050/",
    [switch]$EnableOption60,                                 # Set to $true if DHCP + 2PXE on same server

    # === AD Authorization ===
    [switch]$AuthorizeInAD,                                  # Authorize this DHCP server in Active Directory
    [string]$DnsName,                                        # FQDN of the DHCP server (auto-detected if blank)
    [string]$IPAddress,                                      # IP address of the DHCP server (auto-detected if blank)

    # === Behavior ===
    [switch]$Force                                           # Skip confirmation and some existing checks
)

# ====================== Validation ======================
if ($CreateScope -and (-not ($StartIP -and $EndIP))) {
    Write-Error "When using -CreateScope you must provide -StartIP and -EndIP."
    return
}

# Normalize URL
if ($ExtraDHCPOptionValue -notmatch '/$') {
    $ExtraDHCPOptionValue += "/"
}
$ExtraDHCPOptionValue = $ExtraDHCPOptionValue.ToLower()

# ====================== Main Script ======================
Write-Host "###################### DHCP PXE Policy + Scope + AD Authorization ######################" -ForegroundColor Cyan
Write-Host "Running in automated mode" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# Ensure DHCP role is installed
$dhcpFeature = Get-WindowsFeature -Name DHCP
if (-not $dhcpFeature.Installed) {
    if (-not $Force) {
        $confirm = Read-Host "DHCP role is not installed. Install it now? (Y/N)"
        if ($confirm -notmatch '^[Yy]$') { Write-Host "Aborted."; return }
    }
    Write-Host "Installing DHCP Server role..." -ForegroundColor Cyan
    Install-WindowsFeature DHCP -IncludeManagementTools -ErrorAction Stop | Out-Null
    Write-Host "DHCP role installed." -ForegroundColor Green
} else {
    Write-Host "DHCP Server role is already installed." -ForegroundColor Green
}

# === Authorize DHCP Server in Active Directory ===
if ($AuthorizeInAD) {
    Write-Host "Authorizing DHCP server in Active Directory..." -ForegroundColor Cyan

    # Auto-detect if not provided
    if (-not $DnsName) {
        $DnsName = [System.Net.Dns]::GetHostByName($env:COMPUTERNAME).HostName
    }
    if (-not $IPAddress) {
        $IPAddress = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "169.254.*" } | Select-Object -First 1).IPAddress
    }

    try {
        # Check if already authorized
        $authorized = Get-DhcpServerInDC | Where-Object { $_.DnsName -eq $DnsName -or $_.IPAddress -eq $IPAddress }
        
        if (-not $authorized) {
            Add-DhcpServerInDC -DnsName $DnsName -IPAddress $IPAddress -ErrorAction Stop
            Write-Host "DHCP server '$DnsName' ($IPAddress) successfully authorized in AD." -ForegroundColor Green
        } else {
            Write-Host "DHCP server is already authorized in Active Directory." -ForegroundColor Green
        }
    }
    catch {
        Write-Warning "Failed to authorize DHCP server in AD: $_"
        Write-Warning "This is often due to insufficient permissions (need Domain Admin or delegated rights)."
    }
}

# Option 60 (for co-located 2PXE)
$Option60 = $EnableOption60
if ($Option60) {
    if (-not (Get-DhcpServerv4OptionDefinition -OptionId 60 -ErrorAction SilentlyContinue)) {
        Add-DhcpServerv4OptionDefinition -Name "PXEClient" -OptionId 60 -Type String -DefaultValue "PXEClient" -Description "PXE support"
        Write-Host "Added DHCP Option 60 definition." -ForegroundColor Green
    }
}

# Custom Option 175
$ExtraDHCPOptionId = 175
if (-not (Get-DhcpServerv4OptionDefinition -OptionId $ExtraDHCPOptionId -ErrorAction SilentlyContinue)) {
    Add-DhcpServerv4OptionDefinition -Name "iPXE Anywhere 2PXE server option" `
        -OptionId $ExtraDHCPOptionId -Type String `
        -DefaultValue "https://server.fqdn:8050/" `
        -Description "URL to the 2PXE https server"
}

# Architectures
$architectures = @(
    @{ Name = "BIOS x86 & x64"; Vendor = "PXEClient (BIOS x86 & x64)"; ArchID = "00000"; Option67 = "boot\x86\undionly.kpxe" },
    @{ Name = "UEFI x86";       Vendor = "PXEClient (UEFI x86)";       ArchID = "00006"; Option67 = "boot\x86\snponly_x86.efi" },
    @{ Name = "UEFI x64";       Vendor = "PXEClient (UEFI x64)";       ArchID = "00007"; Option67 = "boot\x64\snponly_x64.efi" }
)

$selectedArchs = $architectures | Where-Object { $ArchitectureIndexes -contains ($architectures.IndexOf($_)) }

# Create Vendor Classes + Policies
$bootFileOptions = @{
    "UEFI x86" = @("snponly_x86.efi", "snponly_drv_x86.efi")
    "UEFI x64" = @("snponly_x64.efi", "snponly_drv_x64.efi", "snponly_usb_x64.efi")
}

foreach ($arch in $selectedArchs) {
    if (-not (Get-DhcpServerv4Class -Name $arch.Vendor -ErrorAction SilentlyContinue)) {
        Add-DhcpServerv4Class -Type Vendor -Name $arch.Vendor -Data "PXEClient:Arch:$($arch.ArchID)" | Out-Null
        Write-Host "Added vendor class: $($arch.Vendor)" -ForegroundColor Green
    }

    $PolicyName = "File Name for $($arch.Name)"

    if (-not (Get-DhcpServerv4Policy -Name $PolicyName -ErrorAction SilentlyContinue)) {
        Write-Host "Creating policy: $PolicyName" -ForegroundColor Cyan

        if ($arch.Name -ne "BIOS x86 & x64" -and $bootFileOptions.ContainsKey($arch.Name)) {
            $selectedFile = $bootFileOptions[$arch.Name][0]
            $archFolder = $arch.Name.Split()[-1]
            $arch.Option67 = "boot\$archFolder\$selectedFile"
        }

        Add-DhcpServerv4Policy -Name $PolicyName `
            -Description "Policy for PXE boot $($arch.Name)" `
            -Condition OR -VendorClass EQ, "$($arch.Vendor)*" | Out-Null

        if ($Option60) {
            Set-DhcpServerv4OptionValue -PolicyName $PolicyName -OptionId 60 -Value "PXEClient" | Out-Null
        }

        Set-DhcpServerv4OptionValue -PolicyName $PolicyName -OptionId 66 -Value $Option66 | Out-Null
        Set-DhcpServerv4OptionValue -PolicyName $PolicyName -OptionId 67 -Value $arch.Option67 | Out-Null
        Set-DhcpServerv4OptionValue -PolicyName $PolicyName -OptionId $ExtraDHCPOptionId -Value $ExtraDHCPOptionValue | Out-Null

        Write-Host "Policy '$PolicyName' created successfully." -ForegroundColor Green
    } else {
        Write-Host "Policy '$PolicyName' already exists." -ForegroundColor Yellow
    }
}

# ====================== Create Scope ======================
if ($CreateScope) {
    Write-Host "`nCreating DHCP Scope '$ScopeName'..." -ForegroundColor Cyan

    try {
        Add-DhcpServerv4Scope -Name $ScopeName `
            -StartRange $StartIP `
            -EndRange $EndIP `
            -SubnetMask $SubnetMask `
            -Description "Scope for PXE booting with 2PXE" -ErrorAction Stop | Out-Null

        Set-DhcpServerv4Scope -ScopeId $StartIP -State Active

        if ($Gateway) {
            Set-DhcpServerv4OptionValue -ScopeId $StartIP -OptionId 3 -Value $Gateway | Out-Null
        }
        if ($DNSServers) {
            Set-DhcpServerv4OptionValue -ScopeId $StartIP -OptionId 6 -Value $DNSServers | Out-Null
        }

        Write-Host "DHCP Scope '$ScopeName' created and activated." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to create scope: $_"
    }
}

Write-Host "`n###################### Completed Successfully ######################" -ForegroundColor Green
