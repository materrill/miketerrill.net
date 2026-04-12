# Get all local fixed drives (type 3 = fixed disk)
$drives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType = 3" |
    Where-Object { $_.Size -gt 0 -and $_.FreeSpace -gt 0 } |
    Select-Object DeviceID,
                  @{Name='FreeGB';     Expression={[math]::Round($_.FreeSpace / 1GB, 2)}},
                  @{Name='TotalGB';    Expression={[math]::Round($_.Size / 1GB, 2)}},
                  @{Name='UsedGB';     Expression={[math]::Round(($_.Size - $_.FreeSpace) / 1GB, 2)}},
                  @{Name='FreePercent';Expression={[math]::Round(($_.FreeSpace / $_.Size) * 100, 1)}} |
    Sort-Object TotalGB -Descending

# Filter drives with ≥ 600 GB free
$qualifying = $drives | Where-Object { $_.FreeGB -ge 600 }

if ($qualifying.Count -eq 0) {
    Write-Host "No drive found with at least 600 GB free space." -ForegroundColor Yellow
    exit 1
}

# Among qualifying drives, get the one with largest total size
$largest = $qualifying | Select-Object -First 1

Write-Host "Largest qualifying drive:" -ForegroundColor Cyan
Write-Host "  Drive letter : $($largest.DeviceID)"
Write-Host "  Total size   : $($largest.TotalGB) GB"
Write-Host "  Free space   : $($largest.FreeGB) GB"
Write-Host "  Used space   : $($largest.UsedGB) GB"
Write-Host "  Free %       : $($largest.FreePercent)%"

# If you just want the drive letter (for scripting/automation):
# Write-Output $largest.DeviceID
$tsenv:DriveLetter = $largest.DeviceID
