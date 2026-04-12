#Requires -RunAsAdministrator
#Requires -Modules Hyper-V

<#
.SYNOPSIS
    Finds Hyper-V external virtual switches that appear to have internet connectivity

.DESCRIPTION
    Looks for external virtual switches and checks:
    - If the bound physical adapter has default gateway
    - If it has a valid public IPv4 address
    - If it can reach common internet endpoints (8.8.8.8 and/or dns.google)

.EXAMPLE
    .\Get-InternetConnectedVMSwitch.ps1

    Returns the most likely internet-connected switch(es)
#>

Write-Host "Searching for Hyper-V virtual switches with internet access..." -ForegroundColor Cyan

# Get all external virtual switches
$externalSwitches = Get-VMSwitch | 
    Where-Object { $_.SwitchType -eq "External" -and $_.NetAdapterInterfaceDescription }

# For Windows 11 only, we can add the default switch to the above list
# since it can provide internet to VMs even though it's not an "external" switch
$os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
if (-not $os) {
    Write-Warning "Could not retrieve OS information"
}
else {
    if($os.ProductType -eq 1 -and $os.BuildNumber -ge 22000) {
        $defaultSwitch = Get-VMSwitch -Name "Default Switch" -ErrorAction SilentlyContinue
        if ($defaultSwitch) {
            Write-Host "Adding 'Default Switch' to the list of switches to check (Windows 11 detected)" -ForegroundColor Gray
            $externalSwitches += $defaultSwitch
        }
    }
}

if (-not $externalSwitches) {
    Write-Warning "No external virtual switches found."
    Write-Host "You need at least one external switch to provide internet to VMs." -ForegroundColor Yellow
    exit 1 # do we want to exit with an error code here? probably?
}

Write-Host "Found $($externalSwitches.Count) external virtual switch(es):" -ForegroundColor Gray
$externalSwitches | ForEach-Object { "  • $($_.Name)  →  $(if($_.NetAdapterInterfaceDescription) { $_.NetAdapterInterfaceDescription } else { "N/A" })" }

$results = @()

foreach ($vswitch in $externalSwitches) {
    # now we need to evaluate the switches for possible network connectivity
    $hasInternet = $false
    $reasons = @()
    
    # we'll start with the "Default Switch" on Windows 11 if it exists... since it's a special switch that 
    # provides NATed internet access via the host's main connection, we can just do a ping test to see if
    # the device has internet access without needing to check the physical adapter details (since it's not
    # really bound to a specific physical adapter in the traditional sense)
    if($vswitch.Name -eq "Default Switch") {
        Write-Host "Checking 'Default Switch' connectivity..." -ForegroundColor Gray
        $pingResult = Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

        if ($pingResult) {
            $hasInternet = $true
            $reasons += "Can ping 8.8.8.8 ✓"
        } else {
            $hasInternet = $false
            $reasons += "Cannot ping 8.8.8.8"
        }
        
        $results += [PSCustomObject]@{
            SwitchName          = $vswitch.Name
            PhysicalAdapter     = "N/A (Default Switch)"
            HasDefaultGateway   = "N/A (Default Switch)"
            HasPublicIP         = "N/A (Default Switch)"
            CanPingInternet     = $pingResult
            LikelyHasInternet   = $hasInternet
            Status              = ($reasons -join " | ")
        }
        continue
    }

    # Next we'll check the remaining external switches. There are two separate cases that we need to 
    # account for here depending on whether the adapter is shared with the host or not. If it's not
    # shared, we won't be able to determine if that adapter has internet access or not since none of
    # the IP configuration is shared with the host. We'll consider unshared switches as no internet
    # access. If it is shared, then we can work through the adapter details to make a best effort guess
    # at whether it has internet access or not.
    if($vswitch.AllowManagementOS -eq $false) {
        Write-Warning "Switch '$($vswitch.Name)' is not shared with the host, cannot determine internet status..."
        $results += [PSCustomObject]@{
            SwitchName          = $vswitch.Name
            PhysicalAdapter     = $vswitch.NetAdapterInterfaceDescription
            HasDefaultGateway   = "Unknown (Not shared)"
            HasPublicIP         = "Unknown (Not shared)"
            CanPingInternet     = $false
            LikelyHasInternet   = $false
            Status              = "Not shared with host, cannot determine connectivity"
        }
        continue
    }
    
    # For shared switches, we can check the physical adapter details to make a best effort guess at
    # internet connectivity. We can additionally force a ping through this adapter to confirm 
    # dns resolution and general internet access.
    
    $virtualAdapterName = "vEthernet ($($vswitch.Name))"
    $adapter = Get-NetAdapter -Name $virtualAdapterName -ErrorAction SilentlyContinue

    # If we can't find the adapter, skip it (shouldn't normally happen since it's shared, but just in case)
    if (-not $adapter) { continue }
    
    $ipConfig = Get-NetIPConfiguration -InterfaceAlias $adapter.InterfaceAlias -ErrorAction SilentlyContinue

    # First check to see if it's even connected
    if($ipConfig.NetAdapter.Status -ne "Up") {
        $reasons += "Adapter is not up"
    } else {
        $reasons += "Adapter is up"
    }

    # Next let's check for basic IP configuration options
    # If there's no default gateway, it's unlikely to have internet access (could still have local network access, but we're focused on internet connectivity here)
    if ($ipConfig.IPv4DefaultGateway) {
        $reasons += "Has default gateway"
    } else {
        $reasons += "NO default gateway"
    }

    # Has public-ish IP (not just 169.254.x.x or 192.168/10/172.16-31)
    # This doesn't have any real bearing on whether the switch has internet access or not since it
    # could be behind a NAT, but it's nice to have the information.
    $publicIP = $ipConfig.IPv4Address | Where-Object {
        $_.IPAddress -notmatch "^(169\.254\.|192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)"
    }
    if ($publicIP) {
        $reasons += "Has public IP ($($publicIP.IPAddress))"
    }

    # Try to ping Google's DNS (most reliable simple internet check)
    # Test-NetConnection does not offer a way to specify the source IP/interface for the ping test,
    # so we'll use the traditional ping command here and specify the source IP of the adapter we're testing
    # and parse the results to determine success or failure
    $pingResult = & ping 8.8.8.8 -S $ipconfig.IPv4Address[0].IPAddress -n 1
    $pingResult = $pingResult | where-object {$_ -like "Reply from 8.8.8.8*"}

    if ($pingResult) {
        $hasInternet = $true
        $reasons += "Can ping 8.8.8.8 ✓"
    } else {
        $reasons += "Cannot ping 8.8.8.8"
    }

    $results += [PSCustomObject]@{
        SwitchName          = $vswitch.Name
        PhysicalAdapter     = $vswitch.NetAdapterInterfaceDescription
        HasDefaultGateway   = [bool]$ipConfig.IPv4DefaultGateway
        HasPublicIP         = [bool]$publicIP
        CanPingInternet     = $pingSuccessful
        LikelyHasInternet   = $hasInternet
        Status              = ($reasons -join " | ")
    }
}

# Sort: working ones first, then by name
$sorted = $results | Sort-Object LikelyHasInternet, SwitchName -Descending

Write-Host "`nResults:" -ForegroundColor Cyan

if (($sorted | Where-Object LikelyHasInternet).Count -eq 0) {
    Write-Host "No virtual switch appears to have internet access right now." -ForegroundColor Yellow
} else {
    Write-Host "Most likely internet-connected switch(es):" -ForegroundColor Green
}

$sorted | Format-Table -AutoSize

# Show the "best" one (first working one)
$best = $sorted | Where-Object { $_.LikelyHasInternet } | Select-Object -First 1

if ($best) {
    Write-Host "`nRecommended switch to use for VMs:" -ForegroundColor Green
    Write-Host "  $($best.SwitchName)" -ForegroundColor White
    Write-Host "  ($($best.PhysicalAdapter))" -ForegroundColor DarkGray
    Write-Host "`nYou can use it like this:" -ForegroundColor DarkGray
    Write-Host "    Connect-VMNetworkAdapter -VMName 'YourVM' -SwitchName '$($best.SwitchName)'" -ForegroundColor DarkCyan
} 
else {
    Write-Host "`nHint: Check which physical adapter has internet and make sure" -ForegroundColor Yellow
    Write-Host "      the corresponding external virtual switch is created and bound to it." -ForegroundColor Yellow
}

Write-Host ""
$tsenv:VMSwitch = $best.SwitchName
if(-not $tsenv:VMSwitch){exit 1}
