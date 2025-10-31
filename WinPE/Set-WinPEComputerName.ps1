<#
.SYNOPSIS
Set-WinPEComputerName sets the computer name in WinPE so it can be easily referenced in OSD
.DESCRIPTION
Determines the active NIC card's MAC address and then generates and executes an unattend.xml file to set the computer name
Add the following script to the WinPE boot image (I put it in ProgramData\OSD)
Add the following line to WinPEShl.ini:
%windir%\System32\WindowsPowerShell\v1.0\powershell.exe,-executionpolicy bypass -noprofile -windowstyle hidden -file "x:\ProgramData\OSD\Set-WinPEComputerName.ps1"
.CREATED BY
Mike Terrill

    24.01.23: Initial Release
    24.03.06: Updated to use part of the GUID for the WinPE computer name since the MAC isn't available right away

#>

# Script to set hostname in WinPE to the first part of the UUID 
$UUID = (Get-CimInstance -Class Win32_ComputerSystemProduct).UUID

# Generate WinPE Computer Name aka OSD ID
If ($UUID){
    $OSDID = "OSD" + $UUID.Replace('-',"").substring(0,12)
    }
Else {
    $OSDID = "RAN" + (Get-Random 999999999999)
    }

#Create Unattend.xml
$xml = [xml]@"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <EnableFirewall>false</EnableFirewall>
      <EnableNetwork>true</EnableNetwork>
      <ComputerName>MININT</ComputerName>
    </component>
  </settings>
</unattend>
"@

$xml.unattend | foreach {$_.settings} | foreach {$_.component.computername = $OSDID }
$xml.Save("$env:windir\Unattend.xml")

#Process unattend.xml
$Result = (Start-Process -FilePath $env:windir\system32\wpeinit.exe -ArgumentList "-unattend:$env:windir\unattend.xml" -Wait -PassThru -WindowStyle Hidden -ErrorAction SilentlyContinue).ExitCode
