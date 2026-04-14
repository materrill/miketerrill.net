<#
.SYNOPSIS
    Downloads a file using BITS (Background Intelligent Transfer Service)
    
.DESCRIPTION
    Uses BITS to download a file with automatic resume capability and efficient bandwidth usage.
    Falls back to Invoke-WebRequest if BITS is not available.
    Supports optional file hash verification and smart existing file detection.

.NOTES
    Author: Mike Terrill/2Pint Software
    Date: April 14, 2026
    Version: 26.04.14

    Version history:
    26.04.14: Initial release (originally based on a script by Gary Blok)

.PARAMETER Url
    The URL of the file to download

.PARAMETER Destination
    The full path where the file should be saved (including filename).
    If not specified, defaults to $env:USERPROFILE\Downloads\<filename-from-url>

.PARAMETER Hash
    Optional file hash to verify after download (or to skip download if file already matches).
    Supported algorithms: SHA256 (default), SHA1, MD5

.EXAMPLE
    Download-FileWithBITS -Url "https://example.com/file.iso"

.EXAMPLE
    Download-FileWithBITS -Url "https://example.com/file.iso" -Destination "C:\Temp\file.iso" -Hash "A1B2C3D4..."

.EXAMPLE
    Download-FileWithBITS -Url "https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso" 
                          -Hash "SHA256:D0EF4502E350E3C6C53C15B1B3020D38A5DED011BF04998E950720AC8579B23D"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Url,
        
    [Parameter(Mandatory=$false)]
    [string]$Destination,
    
    [Parameter(Mandatory=$false)]
    [string]$Hash
)

try {
    # === Determine Destination if not provided ===
    if (-not $Destination) {
        $fileName = Split-Path -Leaf $Url
        $Destination = Join-Path -Path $env:USERPROFILE -ChildPath "Downloads\$fileName"
    }

    Write-Host "Downloading from: $Url" -ForegroundColor Cyan
    Write-Host "Destination: $Destination" -ForegroundColor Cyan
    if ($Hash) {
        Write-Host "Expected hash: $Hash" -ForegroundColor Cyan
    }

    # Ensure destination directory exists
    $destFolder = Split-Path -Parent $Destination
    if (-not (Test-Path $destFolder)) {
        Write-Host "Creating destination folder: $destFolder" -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $destFolder -Force | Out-Null
    }

    # === Smart existing file check ===
    $fileExists = Test-Path $Destination
    $hashMatches = $false

    if ($fileExists -and $Hash) {
        Write-Host "File already exists. Verifying hash..." -ForegroundColor Yellow
        
        # Determine hash algorithm
        $algorithm = "SHA256"
        $hashValue = $Hash
        
        if ($Hash -match '^(SHA256|SHA1|MD5):(.+)$') {
            $algorithm = $Matches[1]
            $hashValue = $Matches[2]
        }

        $actualHash = (Get-FileHash -Path $Destination -Algorithm $algorithm).Hash
        
        if ($actualHash -eq $hashValue) {
            $hashMatches = $true
            Write-Host "File already exists and hash matches ($algorithm). Skipping download." -ForegroundColor Green
            $tsenv:ServerISO = $Destination
            Write-Host "Setting tsenv:ServerISO to $($tsenv:ServerISO)" -ForegroundColor Green
            return [PSCustomObject]@{
                Success   = $true
                FilePath  = $Destination
                Message   = "File already exists with matching $algorithm hash"
                Skipped   = $true
            }
        }
        else {
            Write-Host "Existing file hash does not match. Will re-download." -ForegroundColor Yellow
            Write-Host "Expected: $hashValue" -ForegroundColor Gray
            Write-Host "Actual  : $actualHash" -ForegroundColor Gray
        }
    }
    elseif ($fileExists) {
        Write-Host "File already exists at $Destination." -ForegroundColor Yellow
        $overwrite = "Y" #Read-Host "Overwrite? (Y/N) [Default: N]"
        if ($overwrite -notmatch '^Y$') {
            Write-Host "Download cancelled by user." -ForegroundColor Yellow
            return [PSCustomObject]@{
                Success  = $false
                FilePath = $Destination
                Message  = "Download cancelled - file already exists"
            }
        }
        Remove-Item $Destination -Force
    }

    # === Perform Download ===
    Write-Host "Starting download..." -ForegroundColor Green

    try {
        # Try BITS first
        Write-Host "Using BITS transfer..." -ForegroundColor Green
            
        $bitsJob = Start-BitsTransfer -Source $Url -Destination $Destination `
                    -DisplayName "Download File" -Description "Downloading via BITS" -Asynchronous

        $lastProgress = -1
        do {
            $bitsJob = Get-BitsTransfer -JobId $bitsJob.JobId -ErrorAction SilentlyContinue

            if (-not $bitsJob) {
                Write-Warning "BITS job disappeared."
                break
            }

            switch ($bitsJob.JobState) {
                'Transferred' {
                    Write-Progress -Activity "Downloading" -Completed
                    Complete-BitsTransfer -BitsJob $bitsJob
                    Write-Host "Download completed successfully using BITS!" -ForegroundColor Green
                    break
                }
                'Error' {
                    $errorMsg = $bitsJob.ErrorDescription
                    Remove-BitsTransfer -BitsJob $bitsJob -ErrorAction SilentlyContinue
                    throw "BITS Error: $errorMsg"
                }
                'TransientError' {
                    Write-Warning "Transient error. Retrying..."
                    Start-Sleep -Seconds 2
                }
                default {
                    if ($bitsJob.BytesTotal -gt 0) {
                        $progress = [int](($bitsJob.BytesTransferred / $bitsJob.BytesTotal) * 100)
                        if ($progress -ne $lastProgress) {
                            $downloadedMB = [math]::Round($bitsJob.BytesTransferred / 1MB, 2)
                            $totalMB = [math]::Round($bitsJob.BytesTotal / 1MB, 2)
                            Write-Progress -Activity "Downloading file" `
                                           -Status "$progress% ($downloadedMB MB / $totalMB MB)" `
                                           -PercentComplete $progress
                            $lastProgress = $progress
                        }
                    }
                    Start-Sleep -Milliseconds 500
                }
            }
        } while ($bitsJob.JobState -notin @('Transferred', 'Error', 'Cancelled'))

        if ($bitsJob.JobState -eq 'Transferred') {
            Complete-BitsTransfer -BitsJob $bitsJob
        }
    }
    catch {
        Write-Warning "BITS failed: $($_.Exception.Message)"
        Write-Host "Falling back to Invoke-WebRequest..." -ForegroundColor Yellow

        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
        $ProgressPreference = 'Continue'
        
        Write-Host "Download completed using Invoke-WebRequest fallback." -ForegroundColor Green
    }

    # === Post-download hash verification (if hash was provided) ===
    if ($Hash) {
        Write-Host "Verifying downloaded file hash..." -ForegroundColor Yellow
        
        $algorithm = "SHA256"
        $expectedHash = $Hash
        if ($Hash -match '^(SHA256|SHA1|MD5):(.+)$') {
            $algorithm = $Matches[1]
            $expectedHash = $Matches[2]
        }

        $actualHash = (Get-FileHash -Path $Destination -Algorithm $algorithm).Hash

        if ($actualHash -ne $expectedHash) {
            throw "Hash verification failed! Expected: $expectedHash, Got: $actualHash"
        }
        
        Write-Host "Hash verification passed ($algorithm)." -ForegroundColor Green
    }

    $tsenv:ServerISO = $Destination
    Write-Host "Setting tsenv:ServerISO to $($tsenv:ServerISO)"
    
    return [PSCustomObject]@{
        Success   = $true
        FilePath  = $Destination
        Message   = "Downloaded successfully"
        Method    = if ($bitsJob -and $bitsJob.JobState -eq 'Transferred') { "BITS" } else { "Invoke-WebRequest" }
    }
}
catch {
    Write-Error "Download failed: $($_.Exception.Message)"
    return [PSCustomObject]@{
        Success  = $false
        FilePath = $Destination
        Message  = "Download failed: $($_.Exception.Message)"
    }
}
