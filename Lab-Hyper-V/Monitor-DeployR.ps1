<#
.SYNOPSIS
    Monitor a DeployR task sequence running on a VM using PowerShell Direct.

.DESCRIPTION
    Continuously monitors DeployR task sequence progress from a VM using
    PowerShell Direct. Supports multiple credentials and will automatically
    retry with alternate credentials if authentication fails.

.NOTES
    Author: Mike Terrill/2Pint Software
    Date: July 31, 2026
    Version: 26.07.31
#>

param(
    [string]$VMName = "DC",

    [int]$PollIntervalSeconds = 5
)

# ---------------------------------------------------------------------
# Credential List
# Add as many credentials as required.
# ---------------------------------------------------------------------

$Credentials = @(
    [PSCredential]::new(
        "Administrator",
        (ConvertTo-SecureString "P@ssword" -AsPlainText -Force)
    ),

    [PSCredential]::new(
        "2PintLabs\Administrator",
        (ConvertTo-SecureString "P@ssword" -AsPlainText -Force)
    )
)

# ---------------------------------------------------------------------
# Find Working Credential
# ---------------------------------------------------------------------

function Get-WorkingCredential
{
    param(
        [string]$VMName,

        [PSCredential[]]$Credentials
    )

    foreach ($Cred in $Credentials)
    {
        try
        {
            Invoke-Command `
                -VMName $VMName `
                -Credential $Cred `
                -ErrorAction Stop `
                -ScriptBlock { "Connected" } | Out-Null

            Write-Host ""
            Write-Host "Using credential: $($Cred.UserName)" `
                -ForegroundColor Green

            return $Cred
        }
        catch
        {
            Write-Host "Credential failed: $($Cred.UserName)" `
                -ForegroundColor DarkYellow
        }
    }

    return $null
}

# ---------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------

$Credential = $null
$LastProgress = -1

while ($true)
{
    try
    {
        #
        # Discover a working credential if necessary
        #
        if (-not $Credential)
        {
            $Credential = Get-WorkingCredential `
                -VMName $VMName `
                -Credentials $Credentials

            if (-not $Credential)
            {
                throw "No valid credentials found."
            }
        }

        $Json = Invoke-Command `
            -VMName $VMName `
            -Credential $Credential `
            -ErrorAction Stop `
            -ScriptBlock {

                $Path = 'HKLM:\SOFTWARE\2Pint Software\DeployR'

                if (Test-Path $Path)
                {
                    (Get-ItemProperty `
                        -Path $Path `
                        -Name Progress `
                        -ErrorAction Stop).Progress
                }
                else
                {
                    $null
                }
            }

        if ([string]::IsNullOrWhiteSpace($Json))
        {
            Write-Host `
                "[$(Get-Date -Format HH:mm:ss)] Waiting for DeployR..." `
                -ForegroundColor Yellow

            Start-Sleep -Seconds $PollIntervalSeconds
            continue
        }

        $TS = $Json | ConvertFrom-Json

        $PercentComplete = 0

        if ($TS.Tasks -gt 0)
        {
            $PercentComplete = [math]::Round(($TS.Progress / $TS.Tasks) * 100, 1)
        }

        Write-Progress `
            -Activity $TS.Name `
            -Status "$($TS.TaskName) ($($TS.Progress)/$($TS.Tasks))" `
            -PercentComplete $PercentComplete

        if ($TS.Progress -ne $LastProgress)
        {
            Write-Host ""
            Write-Host (
                "[{0}] {1}%" -f `
                (Get-Date -Format HH:mm:ss),
                $PercentComplete
            ) -ForegroundColor Cyan

            Write-Host ("Task Sequence : {0}" -f $TS.Name)
            Write-Host ("Computer      : {0}" -f $TS.OSDComputerName)
            Write-Host ("Current Step  : {0}" -f $TS.TaskName)
            Write-Host ("Progress      : {0}/{1}" -f $TS.Progress, $TS.Tasks)

            if ($TS.StartTime)
            {
                $Elapsed = (Get-Date) - ([datetime]$TS.StartTime)

                Write-Host (
                    "Elapsed       : {0:hh\:mm\:ss}" -f $Elapsed
                )
            }

            $LastProgress = $TS.Progress
        }

        if ($TS.ErrorCode -ne 0)
        {
            Write-Host ""
            Write-Host (
                "ERROR {0}: {1}" -f `
                $TS.ErrorCode,
                $TS.ErrorDescription
            ) -ForegroundColor Red

            break
        }

        if (($TS.Progress -eq $TS.Tasks) -and ($TS.Tasks -gt 0))
        {
            Write-Host ""
            Write-Host "Task Sequence Complete" `
                -ForegroundColor Green

            break
        }
    }
    catch
    {
        Write-Host `
            "[$(Get-Date -Format HH:mm:ss)] Connection failed. Retrying..." `
            -ForegroundColor Yellow

        #
        # Force rediscovery of credentials on next loop.
        #
        $Credential = $null
    }

    Start-Sleep -Seconds $PollIntervalSeconds
}

Write-Progress -Activity "DeployR Monitor" -Completed