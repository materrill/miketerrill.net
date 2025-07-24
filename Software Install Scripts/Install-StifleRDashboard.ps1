<#
.SYNOPSIS
    PowerShell script to perform an unattended install of StifleR Dashboard 
.DESCRIPTION
    This script automates installing StifleR Dashboard and will determine the FQDN of the server and use
    it for the dashboard configuration. Make sure 2PXE is installed first and a FQDN cert
    has been generated and the IIS 443 bindings have been configured. It will also create the IIS virtual
    directory for the dashboard.
.NOTES
    Author: Mike Terrill/2Pint Software
    Date: July 23, 2025
    Version: 25.07.23
    Requires: Administrative privileges, 64-bit Windows
#>

# Set path to MSI file
$msifile = "$PSScriptRoot\StifleR-Dashboard-x64.msi"

# Ensure the script runs with elevated privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script requires administrative privileges. Please run PowerShell as Administrator."
    exit 1
}

# This will use the connection specific suffix for the fqdn - useful when system is not domain joined
$domain = [string](Get-DnsClient | Select-Object -ExpandProperty ConnectionSpecificSuffix)
$fqdn = "$($env:COMPUTERNAME.Trim()).$($domain.Trim())"
$STIFLERSERVER = "STIFLERSERVER=https://$($fqdn):1414"
$STIFLERLOCSERVER = "STIFLERLOCSERVER=https://$($fqdn):9000"

$arguments = "/i `"$msifile`" $STIFLERSERVER $STIFLERLOCSERVER /qn /norestart /l*v C:\Windows\Temp\StifleRDashboardInstall.log"

write-host "Using the following install commands: $arguments" #uncomment this line to see the command line

# Install the StifleR Dashboard
start-process "msiexec.exe" -arg $arguments -Wait

# Create the StifleR Dashboard IIS Virtual Directory
Import-Module WebAdministration
New-WebVirtualDirectory -Site "Default Web Site" -Name "StifleRDashboard" -PhysicalPath 'C:\Program Files\2Pint Software\StifleR Dashboards\Dashboard Files'

# Configure IIS for Authentication
$partofdomain = (Get-CimInstance win32_computersystem).PartOfDomain
$siteName = "Default Web Site/StifleRDashboard"

Write-Host "Removing Anonymous Authentication from website."
Set-WebConfigurationProperty -filter /system.webServer/security/authentication/AnonymousAuthentication -name enabled -value false -PSPath IIS:\ -location $siteName

Write-Host "Configuring IIS for Windows Authentication."
Set-WebConfigurationProperty -filter /system.webServer/security/authentication/WindowsAuthentication -name enabled -value True -PSPath IIS:\ -location $siteName

Write-Host "Configuring Windows Auth Providers"
#First we remove all providers, disable Kernel-mode authentication, then re-add single authentication provider.
Get-WebConfigurationProperty -Filter system.webServer/security/authentication/WindowsAuthentication `
 -Location $siteName -Name providers.Collection | Select-Object -ExpandProperty Value | ForEach-Object {Remove-WebConfigurationProperty -Filter system.webServer/security/authentication/WindowsAuthentication -Location $SiteName -Name providers.Collection -AtElement @{value=$_}}

$winKernel = (Get-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -location $siteName -filter /system.WebServer/security/authentication/windowsAuthentication -name "useKernelMode").Value
if ($winKernel -eq $True){
    Write-Host "Disabling Kernel-mode authentication."
    Set-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -location $siteName -filter /system.WebServer/security/authentication/windowsAuthentication -name "useKernelMode" -value false
}

# If StifleR is running on a domain joined server, auth provider is configured to Negotiate:Kerberos.
if ($partofdomain -eq $true){
    Write-Host "Server is domain joined. Configuring Negotiate:Kerberos as authentication provider."
    Add-WebConfigurationProperty -Filter system.webServer/security/authentication/WindowsAuthentication `
 -Location $siteName -Name providers.Collection -AtIndex 0 -Value "Negotiate:Kerberos"
}
# If StifleR is running on a non-domain joined server, auth provider is configured to NTLM
if ($partofdomain -eq $false){
    Write-Host "Server is not member of a domain. Configuring NTLM as authentication provider."
    Add-WebConfigurationProperty -Filter system.webServer/security/authentication/WindowsAuthentication `
    -Location $siteName -Name providers.Collection -AtIndex 0 -Value "NTLM"
}

# Accessing server locally with fqdn can cause authentication prompt loop on workgroup server
if ($partofdomain -eq $false) {
    Write-Host "Server is not member of a domain. Configuring BackConnectionHostNames."
    $multiStringData = @("$fqdn")
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" -Name "BackConnectionHostNames" -Value $multiStringData -Type MultiString
}

Write-Host "Script completed."
