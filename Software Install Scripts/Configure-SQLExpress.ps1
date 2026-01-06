<#
.SYNOPSIS
    Configures the permissions and firewall rules for Microsoft SQL Server 2022.
.DESCRIPTION
    This script grants permissions to NT AUTHORITY/SYSTEM and configures the firewall rules.
.NOTES
    Author: Mike Terrill/2Pint Software
    Date: January 6, 2026
    Version: 26.01.06
    Requires: Administrative privileges, 64-bit Windows, internet access

    Version history:
    26.01.06: Fixed the elevated privilege check
    25.08.04: Initial release
#>

# Ensure the script runs with elevated privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script requires administrative privileges. Please run PowerShell as Administrator."
    exit 1
}

# Grant NT AUTHORITY/SYSTEM sysadmin and dbcreator rights
$InstanceName = "SQLEXPRESS"
$SqlCmdPath = "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd"
$ServerInstance = ".\$InstanceName"
$TsqlQuery = "IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'NT AUTHORITY\SYSTEM') CREATE LOGIN [NT AUTHORITY\SYSTEM] FROM WINDOWS; EXEC sp_addsrvrolemember @loginame = 'NT AUTHORITY\SYSTEM', @rolename = 'sysadmin'; EXEC sp_addsrvrolemember @loginame = 'NT AUTHORITY\SYSTEM', @rolename = 'dbcreator';"

try {
    $Process = Start-Process -FilePath $SqlCmdPath -ArgumentList "-S `"$ServerInstance`" -Q `"$TsqlQuery`"" -NoNewWindow -PassThru -Wait -ErrorAction Stop
    if ($Process.ExitCode -eq 0) {
        Write-Host "Successfully granted sysadmin and dbcreator roles to NT AUTHORITY\SYSTEM on $ServerInstance."
    } else {
        Write-Error "sqlcmd failed with exit code $($Process.ExitCode)."
    }
} catch {
    Write-Error "Failed to execute sqlcmd. Error: $($_.Exception.Message)"
    Write-Host "Ensure sqlcmd is installed and the SQL Server instance ($ServerInstance) is running."
}

# Create SQL Firewall Rules
New-NetFirewallRule -DisplayName "SQLServer default instance" -Direction Inbound -LocalPort 1433 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "SQLServer Browser service" -Direction Inbound -LocalPort 1434 -Protocol UDP -Action Allow

Write-Host "Script completed successfully."
