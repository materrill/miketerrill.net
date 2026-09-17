# Update RepubQuorumSize only when needed
Write-Host -Message "Checking registry value RepubQuorumSize"
$RegistryKey = "HKLM:\SOFTWARE\Policies\Microsoft\PeerDist\DiscoveryManager"
$RegistryValue = "RepubQuorumSize"
$RegistryValueType = "DWord"
$RegistryValueData = 200

if (-not (Test-Path -Path $RegistryKey)) {
	Write-Host -Message "Creating registry key: $RegistryKey"
	$Result = New-Item -Path $RegistryKey -ItemType Directory -Force
	$Result.Handle.Close()
}

$CurrentValue = $null
try {
	$CurrentValue = Get-ItemPropertyValue -Path $RegistryKey -Name $RegistryValue -ErrorAction Stop
}
catch {
	# Value does not exist yet; it will be created below.
}

if ($CurrentValue -ne $RegistryValueData) {
	Write-Host -Message "Setting $RegistryValue to $RegistryValueData (current value: $CurrentValue)"
	New-ItemProperty -Path $RegistryKey -Name $RegistryValue -PropertyType $RegistryValueType -Value $RegistryValueData -Force | Out-Null

	# Restart the BranchCache service only when a change was made
	$ServiceName = "PeerDistSvc"
	Restart-Service -Name $ServiceName -Force

	Write-Host "check status of $ServiceName"
	Get-Service -Name $ServiceName
}
else {
	Write-Host -Message "$RegistryValue is already set to $RegistryValueData. No changes made and no service restart required."
}

# Cleanup (to prevent access denied issue unloading the registry hive)
if (Get-Variable -Name Result -ErrorAction SilentlyContinue) {
	Remove-Variable -Name Result
}
Get-Variable Registry* -ErrorAction SilentlyContinue | Remove-Variable
[gc]::collect()