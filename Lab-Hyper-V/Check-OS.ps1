<#
.SYNOPSIS
    Checks if the current OS is Windows Server 2022 (or later) or Windows 11 (or later)

.DESCRIPTION
    Returns $true if the OS meets the minimum version requirement:
    - Windows Server 2022 / 2025 / future
    - Windows 11 (22000+) / future Windows client versions

    Returns $false otherwise (including Windows 10, Server 2019, etc.)

.EXAMPLE
    if (Test-ModernWindowsVersion) {
        Write-Host "This system meets the minimum OS requirement" -ForegroundColor Green
    } else {
        Write-Host "This system is too old (requires Windows 11 or Server 2022+)" -ForegroundColor Red
    }
#>

function Test-ModernWindowsVersion {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # Get build number and product type
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    if (-not $os) {
        Write-Warning "Could not retrieve OS information"
        return $false
    }

    $build       = $os.BuildNumber
    $productType = $os.ProductType          # 1 = client, 3 = server
    $caption     = $os.Caption

    # Windows 11 starts at build 22000
    $isWindows11OrNewer = ($build -ge 22000) -and ($productType -eq 1)

    # Windows Server 2022 starts at build 20348
    $isServer2022OrNewer = ($build -ge 20348) -and ($productType -eq 3)

    $meetsRequirement = $isWindows11OrNewer -or $isServer2022OrNewer

    # Optional: more verbose output when running standalone
    if ($PSCmdlet.MyInvocation.Line -match '^\s*Test-ModernWindowsVersion') {
        Write-Host "OS:       $caption" -ForegroundColor Cyan
        Write-Host "Build:    $build" -ForegroundColor Cyan
        Write-Host "Type:     $(if($productType -eq 1){'Client'}else{'Server'})" -ForegroundColor Cyan
        
        if ($meetsRequirement) {
            Write-Host "Result:   Meets requirement ✓" -ForegroundColor Green
        } else {
            Write-Host "Result:   Does NOT meet requirement" -ForegroundColor Red
            if ($productType -eq 1 -and $build -lt 22000) {
                Write-Host "          (Windows 10 detected)" -ForegroundColor DarkYellow
            }
            if ($productType -eq 3 -and $build -lt 20348) {
                Write-Host "          (Server 2019 or older detected)" -ForegroundColor DarkYellow
            }
        }
        Write-Host ""
    }

    return $meetsRequirement
}


# If script is run directly (not dot-sourced), show result
if ($MyInvocation.MyCommand.Source -eq $PSCommandPath) {
    $result = Test-ModernWindowsVersion
    if ($result) {
        Write-Host "This computer meets the requirement (Win11 or Server 2022+)" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "This computer does NOT meet the requirement" -ForegroundColor Red
        exit 1
    }
}
