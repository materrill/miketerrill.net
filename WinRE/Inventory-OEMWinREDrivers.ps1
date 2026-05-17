<#
.SYNOPSIS
    Inventories the OEM drivers for WinRE.
.DESCRIPTION
    This script automates the process of inventorying the Windows Recovery Environment (WinRE) drivers by mounting the WinRE.wim,
    inventorying the drivers, and then generating a JSON catalog file. Optionally it will create a WinRE Driver Pack.
    It includes error handling, logging, and validation for robustness.
.EXAMPLE
    .\Inventory-OEMWinREDrivers.ps1
    .\Inventory-OEMWinREDrivers.ps1 -CreateWinREDriverPack
.USAGE
    - Requires administrative privileges.
    - Must be run on a Windows system with DISM and Reagentc.exe available.
    - Ensure the WinRE WIM is accessible and not corrupted. Run on a system with the OEM Image.
    - Logs are saved to a file in the same directory as the script.
.NOTES
    AUTHOR: Mike Terrill/2Pint Software
    CONTACT: @miketerrill
    VERSION: 26.05.16
.CHANGELOG
    26.05.15 : Initial version
    26.05.16 : Added JSON export to user's Downloads folder with specified format
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param (
    [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
    [switch] $CreateWinREDriverPack
)

# Define variables
$LogFile = "$env:USERPROFILE\Downloads\Inventory-OEMWinREDrivers.log"
$WinREDriverPack = "$env:USERPROFILE\Downloads\WinREDriverPack"
$WinREMount = "C:\Windows\Temp\WinREMount"
$DownloadsPath = "$env:USERPROFILE\Downloads"

function Write-Log {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$false)]
        $Message,
        [Parameter(Mandatory=$false)]
        $ErrorMessage,
        [Parameter(Mandatory=$false)]
        $Component = "Script",
        [Parameter(Mandatory=$false)]
        [int]$Type
    )
    <#
    Type: 1 = Normal, 2 = Warning (yellow), 3 = Error (red)
    #>
    $Time = Get-Date -Format "HH:mm:ss.ffffff"
    $Date = Get-Date -Format "MM-dd-yyyy"
    if ($ErrorMessage -ne $null) {$Type = 3}
    if ($Component -eq $null) {$Component = " "}
    if ($Type -eq $null) {$Type = 1}
    $LogMessage = "<![LOG[$Message $ErrorMessage" + "]LOG]!><time=`"$Time`" date=`"$Date`" component=`"$Component`" context=`"`" type=`"$Type`" thread=`"`" file=`"`">"
    $LogMessage.Replace("`0","") | Out-File -Append -Encoding UTF8 -FilePath $LogFile
}

# Start logging
Write-Log -Message "Starting Inventory-OEMWinREDrivers" -Type 1

# Check for administrative privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Log -Message "This script requires administrative privileges. Please run as Administrator." -ErrorMessage "ERROR"
    exit 1
}

# Validate that DISM and Reagentc are available
if (-not (Get-Command "dism.exe" -ErrorAction SilentlyContinue)) {
    Write-Log -Message "DISM.exe is not available on this system." -ErrorMessage "ERROR"
    exit 1
}
if (-not (Get-Command "reagentc.exe" -ErrorAction SilentlyContinue)) {
    Write-Log -Message "Reagentc.exe is not available on this system." -ErrorMessage "ERROR"
    exit 1
}

# Build a hashtable for local info
$LocalInfo = @{}

# Get Make and Model information (existing code unchanged)
Get-CimInstance -ClassName Win32_ComputerSystem | ForEach-Object {
    $LocalInfo['Manufacturer'] = "$($_.Manufacturer)".Trim()
    $LocalInfo['Make'] = "$($_.Manufacturer)".Trim()
    $LocalInfo['Model'] = "$($_.Model)".Trim()
    $LocalInfo['Memory'] = [int] ($_.TotalPhysicalMemory / 1024 / 1024)
}

if ($LocalInfo['Make'] -eq "") {
    $Make = "$(Get-CimInstance -ClassName Win32_BaseBoard | Select-Object -ExpandProperty Manufacturer)".Trim()
    $LocalInfo['Make'] = $Make
    $LocalInfo['Manufacturer'] = $Make
}

if ($LocalInfo['Model'] -eq "") {
    $LocalInfo['Model'] = "$(Get-CimInstance -ClassName Win32_BaseBoard | Select-Object -ExpandProperty Product)".Trim()
}

Get-CimInstance -ClassName Win32_ComputerSystemProduct | ForEach-Object {
    $LocalInfo['UUID'] = "$($_.UUID)".Trim()
    $LocalInfo['CSPVersion'] = "$($_.Version)".Trim()
}

Get-CimInstance -ClassName MS_SystemInformation -NameSpace root\WMI | ForEach-Object {
    $LocalInfo['BaseBoardProduct'] = "$($_.BaseBoardProduct)".Trim()
    $LocalInfo['SystemSku'] = "$($_.SystemSku)".Trim()
}

Get-CimInstance -ClassName Win32_BaseBoard | ForEach-Object {
    $LocalInfo['Product'] = "$($_.Product)".Trim()
}

# Generate ModelAlias, MakeAlias and SystemAlias (existing switch logic unchanged)
$LocalInfo['IsVM'] = "False"
Switch -Wildcard ($LocalInfo['Make']) {
    "*Microsoft*" {
        $LocalInfo['MakeAlias'] = "Microsoft"
        $LocalInfo['ModelAlias'] = "$(Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model)".Trim()
        $LocalInfo['SystemAlias'] = Get-CimInstance -ClassName MS_SystemInformation -Namespace root\wmi | Select-Object -ExpandProperty SystemSKU
        # Logic for Hyper-V Testing
        If ($LocalInfo['ModelAlias'] -eq "Virtual Machine") {
            $LocalInfo['SystemAlias'] = Get-CimInstance -ClassName MS_SystemInformation -Namespace root\wmi | Select-Object -ExpandProperty SystemVersion
            if ([string]::IsNullOrEmpty($LocalInfo['SystemAlias'])) {
                $LocalInfo['SystemAlias'] = $LocalInfo['ModelAlias']
            }
            $LocalInfo['IsVM'] = "True"
        }
    }
    "*HP*" {
        $LocalInfo['MakeAlias'] = "HP"
        $LocalInfo['ModelAlias'] = "$(Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model)".Trim()
        $LocalInfo['SystemAlias'] = "$((Get-CimInstance -ClassName MS_SystemInformation -NameSpace root\wmi).BaseBoardProduct)".Trim()
    }
    "*VMWare*" {
        $LocalInfo['MakeAlias'] = "VMWare"
        $LocalInfo['ModelAlias'] = ("$(Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model)".Trim()).replace(" ","_").replace(",","_")
        $LocalInfo['SystemAlias'] = "VMWare"
        $LocalInfo['IsVM'] = "True"
    }
    "*QEMU*" {
        $LocalInfo['MakeAlias'] = "QEMU"
        $LocalInfo['ModelAlias'] = "$(Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model)".Trim()
        $LocalInfo['SystemAlias'] = Get-CimInstance -ClassName MS_SystemInformation -Namespace root\wmi | Select-Object -ExpandProperty SystemSKU
        $LocalInfo['IsVM'] = "True"
    }
    "*Innotek*" {
        $LocalInfo['MakeAlias'] = "Innotek"
        $LocalInfo['ModelAlias'] = "$(Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model)".Trim()
        $LocalInfo['SystemAlias'] = Get-CimInstance -ClassName MS_SystemInformation -Namespace root\wmi | Select-Object -ExpandProperty SystemSKU
        $LocalInfo['IsVM'] = "True"
    }
    "*Hewlett-Packard*" {
        $LocalInfo['MakeAlias'] = "HP"
        $LocalInfo['ModelAlias'] = "$(Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model)".Trim()
        $LocalInfo['SystemAlias'] = "$((Get-CimInstance -ClassName MS_SystemInformation -NameSpace root\wmi).BaseBoardProduct)".Trim()
    }
    "*Dell*" {
        $LocalInfo['MakeAlias'] = "Dell"
        $LocalInfo['ModelAlias'] = "$(Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model)".Trim()
        $LocalInfo['SystemAlias'] = "$((Get-CimInstance -ClassName MS_SystemInformation -NameSpace root\wmi ).SystemSku)".Trim()
    }
    "*Lenovo*" {
        $LocalInfo['MakeAlias'] = "Lenovo"
        $LocalInfo['ModelAlias'] = "$(Get-CimInstance -ClassName Win32_ComputerSystemProduct | Select-Object -ExpandProperty Version)".Trim()
        $LocalInfo['SystemAlias'] = "$((Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model).SubString(0, 4))".Trim()
    }
    "*Intel(R) Client Systems*" {
        $LocalInfo['MakeAlias'] = "Intel(R) Client Systems"
        $LocalInfo['ModelAlias'] = "$(Get-CimInstance -ClassName Win32_ComputerSystemProduct | Select-Object -ExpandProperty Version)".Trim()
        $LocalInfo['SystemAlias'] = ("$(Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model)".Trim())
        $LocalInfo['SystemAlias'] = "$($LocalInfo['SystemAlias'].SubString(0, $LocalInfo['SystemAlias'].IndexOf("i")))".Trim()
    }
    "*Panasonic*" {
        $LocalInfo['MakeAlias'] = "Panasonic Corporation"
        $LocalInfo['ModelAlias'] = "$(Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model)".Trim()
        $LocalInfo['SystemAlias'] = "$((Get-CimInstance -ClassName MS_SystemInformation -NameSpace root\wmi ).BaseBoardProduct)".Trim()
    }
    "*Viglen*" {
        $LocalInfo['MakeAlias'] = "Viglen"
        $LocalInfo['ModelAlias'] = "$(Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model)".Trim()
        $LocalInfo['SystemAlias'] = "$(Get-CimInstance -ClassName Win32_BaseBoard | Select-Object -ExpandProperty SKU)".Trim()
    }
    "*AZW*" {
        $LocalInfo['MakeAlias'] = "AZW"
        $LocalInfo['ModelAlias'] = "$(Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model)".Trim()
        $LocalInfo['SystemAlias'] = "$((Get-CimInstance -ClassName MS_SystemInformation -NameSpace root\wmi ).BaseBoardProduct)".Trim()
    }
    "*Fujitsu*" {
        $LocalInfo['MakeAlias'] = "Fujitsu"
        $LocalInfo['ModelAlias'] = "$(Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model)".Trim()
        $LocalInfo['SystemAlias'] = "$(Get-CimInstance -ClassName Win32_BaseBoard | Select-Object -ExpandProperty SKU)".Trim()
    }
    "*Acer*" {
        $LocalInfo['MakeAlias'] = "Acer"
        $LocalInfo['ModelAlias'] = "$(Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model)".Trim()
        $LocalInfo['SystemAlias'] = $LocalInfo['ModelAlias']
    }
    Default {
        $LocalInfo['MakeAlias'] = "NA"
        $LocalInfo['ModelAlias'] = "NA"
        $LocalInfo['SystemAlias'] = "NA"
    }
}

# Creating the WinREMount directory
Write-Log -Message "Creating WinRE Mount directory: $WinREMount"
try {
    if (Test-Path -Path $WinREMount) {
        Write-Log -Message "Cleaning up previously created directory: $WinREMount"
        Remove-Item $WinREMount -Force -Verbose -Recurse | Out-Null
    }
    New-Item -ItemType Directory -Path $WinREMount -Force -ErrorAction Stop | Out-Null
} catch {
    Write-Log -Message "Failed to create WinRE mount directory: $WinREMount" -ErrorMessage "ERROR"
    exit 1
}

# Mount WinRE.wim
Write-Log "Mounting WinRE WIM to: $WinREMount"
try {
    $mountResult = reagentc.exe /mountre /path $WinREMount 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log -Message "Failed to mount WinRE WIM. Error: $mountResult" -ErrorMessage "ERROR"
        exit 1
    }
    Write-Log -Message "Successfully mounted WinRE WIM"
} catch {
    Write-Log -Message "Exception while mounting WinRE WIM: $_" -ErrorMessage "ERROR"
    exit 1
}

# Get all installed drivers
Write-Log -Message "Getting all of the drivers installed in WinRE"
try {
    $Drivers = Get-WindowsDriver -Path $WinREMount
} catch {
    Write-Log "Failed to retrieve drivers using Get-WindowsDriver: $_" -ErrorMessage "ERROR"
    exit
}

# Build JSON Structure ===
Write-Log -Message "Building WinRE Drivers JSON catalog"

$LastDateModified = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$WinREDriverList = @()
foreach ($Driver in $Drivers) {
    $WinREDriverList += [PSCustomObject]@{
        FileName         = Split-Path $Driver.OriginalFileName -Leaf
        Version          = $Driver.Version
        Inbox            = $Driver.Inbox.ToString()
        CatalogFile      = Split-Path $Driver.CatalogFile -Leaf
        ClassName        = $Driver.ClassName
        ClassGuid        = $Driver.ClassGuid
        BootCritical     = $Driver.BootCritical.ToString()
        DriverSignature  = $Driver.DriverSignature
        ProviderName     = $Driver.ProviderName
        Date             = $Driver.Date.ToString("M/d/yyyy h:mm:ss tt")
    }
}

$ModelEntry = [PSCustomObject]@{
    ModelAlias   = $LocalInfo['ModelAlias']
    SystemAlias  = $LocalInfo['SystemAlias']
    WinREDrivers = $WinREDriverList
}

$JsonData = [PSCustomObject]@{
    LastDateModified = $LastDateModified
    MakeAlias        = $LocalInfo['MakeAlias']
    Models           = @($ModelEntry)
}

# Determine Downloads folder
$JsonFileName = "WinREDrivers_$($LocalInfo['MakeAlias'])_$($LocalInfo['ModelAlias']).json"
$JsonFilePath = Join-Path $DownloadsPath $JsonFileName

# Ensure Downloads folder exists
if (-not (Test-Path $DownloadsPath)) {
    New-Item -ItemType Directory -Path $DownloadsPath -Force | Out-Null
}

# Export to JSON (pretty-printed)
$JsonData | ConvertTo-Json -Depth 10 | Out-File -FilePath $JsonFilePath -Encoding UTF8 -Force

Write-Log -Message "JSON catalog saved to: $JsonFilePath"

# Create WinRE Driver Pack
if ($CreateWinREDriverPack) {
    # Creating the WinREDriver Pack directory
    Write-Log -Message "Creating WinRE drivers directory: $WinREDriverPack"
    try {
        if (Test-Path -Path $WinREDriverPack) {
            Write-Log -Message "Cleaning up previously created directory: $WinREDriverPack"
            Remove-Item $WinREDriverPack -Force -Verbose -Recurse | Out-Null
        }
     
        New-Item -ItemType Directory -Path $WinREDriverPack -Force -ErrorAction Stop | Out-Null
    
    } catch {
        Write-Log -Message "Failed to create WinRE drivers directory: $WinREDriverPack" -ErrorMessage "ERROR"
        exit 1
    }

    # Create a hashtable to store the newest driver for each INF
    $DriverTable = @{}

    # Iterate through drivers to find the newest version for each INF
    foreach ($Driver in $Drivers) {
        $InfName = [System.IO.Path]::GetFileName($Driver.OriginalFileName).ToLower()
        $DriverVersion = $Driver.Version

        # Skip if InfName is empty (shouldn't happen due to filter)
        if (-not $InfName) { continue }

        # Convert DriverVersion to a Version object for comparison
        try {
            $Version = [Version]$DriverVersion
        } catch {
            Write-Log -Message "Unable to parse version for driver with INF: $InfName. Skipping." -ErrorMessage "ERROR"
            continue
        }

        # If INF is not in the hashtable or the current driver has a newer version, update the hashtable
        if (-not $DriverTable.ContainsKey($InfName) -or [Version]$DriverTable[$InfName].Version -lt $Version) {
            $DriverTable[$InfName] = $Driver
        }
    }

    # Check if any drivers were found
    if ($DriverTable.Count -eq 0) {
        Write-Log -Message "No drivers found for the specified INF files...exiting script." 
        exit
    }

    # Export the newest drivers
    foreach ($InfName in $DriverTable.Keys) {
        $Driver = $DriverTable[$InfName]
        $DriverVersion = $Driver.Version
        $DriverInf = $InfName
        $ProviderName = $Driver.ProviderName
        $DriverOemInf = $Driver.Driver  # Use Driver property (OEM INF name, e.g., oemXX.inf)

        # Extract subdirectory name from OriginalFileName
        $OriginalFileName = $Driver.OriginalFileName
        $SubDirName = [System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName($OriginalFileName))
        $ExportSubDir = Join-Path -Path $WinREDriverPack -ChildPath $SubDirName

        # Create subdirectory for this driver
        if (-not (Test-Path -Path $ExportSubDir)) {
            New-Item -ItemType Directory -Path $ExportSubDir -Force | Out-Null
        }

        Write-Log -Message "Exporting driver: $ProviderName (INF: $DriverInf, Version: $DriverVersion, OEM INF: $DriverOemInf, Subdirectory: $SubDirName)" 

        # Use pnputil to export the driver using the Driver property
        try {
            $PnPUtilCommand = "pnputil.exe /export-driver $DriverOemInf `"$ExportSubDir`""
            $Result = Invoke-Expression $PnPUtilCommand 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Log -Message "Failed to export driver $DriverOemInf to $ExportSubDir. Error: $Result" -ErrorMessage "ERROR"
                # Clean up empty directory
                Remove-Item $ExportSubDir -Force -Verbose -Recurse | Out-Null
            } else {
                Write-Log -Message "Successfully exported $DriverOemInf to $ExportSubDir" 
            }
        } catch {
            Write-Log -Message "Error exporting driver $DriverOemInf to $ExportSubDir : $_"
        }
    }

    # Driver Export Finish
    Write-Log -Message "Driver export completed."
}

# Unmount WinRE.wim 
Write-Log -Message "Unmounting WinRE WIM"
try {
    $unmountResult = dism /unmount-image /mountdir:$WinREMount /discard 2>&1
    #$unmountResult = reagentc.exe /unmountre /path $WinREMount /discard 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log -Message "Failed to unmount WinRE WIM. Error: $unmountResult" -ErrorMessage "ERROR"
        exit 1
    }
    Write-Log -Message "Successfully unmounted WinRE WIM"
} catch {
    Write-Log -Message "Exception while unmounting WinRE WIM: $_" -ErrorMessage "ERROR"
    exit 1
}

# Clean up scratch directories 
Write-Log -Message "Cleaning up directories: $WinREMount"
try {
    if (Test-Path -Path $WinREMount) {
        Remove-Item -Path $WinREMount -Recurse -Force -ErrorAction Stop
        Write-Log -Message "Deleted directory: $WinREMount"
    }
} catch {
    Write-Log -Message "Failed to clean up directories: $_" -ErrorMessage "WARNING"
}

# Final summary
Write-Log -Message "WinRE inventory process completed successfully. JSON created at $JsonFilePath"
if ($CreateWinREDriverPack) {
    Write-Log -Message "WinRE Driver Pack created at $WinREDriverPack"
}
