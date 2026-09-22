<#
.SYNOPSIS
    Shows what a Windows machine actually does: third-party services, scheduled
    tasks, listening ports and shares.

.DESCRIPTION
    READ-ONLY. Queries only; changes nothing.

    An installed-software list tells you what was put on a server. This tells you
    what is running on it now — which is usually a shorter and more honest list.

    Four things worth reading carefully in the output:
      - Services running under a named domain account (a service account nobody
        documented, often with a password that never expires)
      - Scheduled tasks pointing at scripts in user profiles or temp folders
      - Listening ports on 0.0.0.0 that nobody can explain
      - Shares outside the standard administrative ones

.PARAMETER OutputPath
    Optional. Write JSON to this path instead of the console.

.EXAMPLE
    .\Get-ServiceProfile.ps1 -OutputPath C:\Temp\SRV01-services.json

.NOTES
    Elevation: recommended. Without it, scheduled task actions and some process
    owners are not visible.
#>

[CmdletBinding()]
param(
    [string]$OutputPath
)

$ErrorActionPreference = 'SilentlyContinue'

# --- Services ---------------------------------------------------------------
# Win32_Service carries the logon account and the binary path, which Get-Service
# does not.
$builtInAccounts = @('LocalSystem', 'NT AUTHORITY\LocalService', 'NT AUTHORITY\NetworkService')

$services = @(
    Get-CimInstance -ClassName Win32_Service | ForEach-Object {
        [PSCustomObject][ordered]@{
            Name          = $_.Name
            DisplayName   = $_.DisplayName
            State         = $_.State
            StartMode     = $_.StartMode
            LogonAccount  = $_.StartName
            PathName      = $_.PathName
            # A service under a named account is a service account with a password
            # somewhere. These are the ones that break when someone rotates it.
            CustomAccount = ($_.StartName -notin $builtInAccounts)
        }
    }
)

$customAccountServices = @($services | Where-Object { $_.CustomAccount -and $_.State -eq 'Running' })

# Third-party services: not under the Windows directory.
$thirdPartyServices = @(
    $services | Where-Object {
        $_.State -eq 'Running' -and $_.PathName -and $_.PathName -notmatch '(?i)^"?C:\\Windows\\'
    }
)

# --- Scheduled tasks --------------------------------------------------------
$tasks = @()
if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
    $tasks = @(
        Get-ScheduledTask |
            Where-Object { $_.State -ne 'Disabled' -and $_.TaskPath -notmatch '^\\Microsoft\\' } |
            ForEach-Object {
                $info = Get-ScheduledTaskInfo -TaskName $_.TaskName -TaskPath $_.TaskPath
                [PSCustomObject][ordered]@{
                    TaskName    = $_.TaskName
                    TaskPath    = $_.TaskPath
                    State       = "$($_.State)"
                    RunAsUser   = $_.Principal.UserId
                    Actions     = @($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)".Trim() })
                    LastRunTime = if ($info.LastRunTime) { $info.LastRunTime.ToString('yyyy-MM-dd HH:mm') } else { 'Never' }
                    LastResult  = $info.LastTaskResult
                    NextRunTime = if ($info.NextRunTime) { $info.NextRunTime.ToString('yyyy-MM-dd HH:mm') } else { 'None' }
                }
            }
    )
}

# --- Listening ports --------------------------------------------------------
$listening = @()
if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
    $listening = @(
        Get-NetTCPConnection -State Listen | ForEach-Object {
            $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
            [PSCustomObject][ordered]@{
                LocalAddress = $_.LocalAddress
                LocalPort    = $_.LocalPort
                Process      = if ($proc) { $proc.ProcessName } else { 'Unknown' }
                ProcessPath  = if ($proc) { $proc.Path } else { $null }
                # Bound to all interfaces: reachable from anywhere that can route here.
                AllInterfaces = ($_.LocalAddress -in @('0.0.0.0', '::'))
            }
        } | Sort-Object -Property LocalPort, LocalAddress -Unique
    )
}

# --- Shares -----------------------------------------------------------------
$shares = @(
    Get-CimInstance -ClassName Win32_Share | Where-Object { $_.Name -notmatch '\$$' } | ForEach-Object {
        [PSCustomObject][ordered]@{
            Name        = $_.Name
            Path        = $_.Path
            Description = $_.Description
        }
    }
)

$result = [PSCustomObject][ordered]@{
    CollectedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    HostName    = $env:COMPUTERNAME
    Script      = 'Get-ServiceProfile.ps1'
    Summary     = [PSCustomObject][ordered]@{
        RunningServices          = @($services | Where-Object { $_.State -eq 'Running' }).Count
        ThirdPartyRunning        = $thirdPartyServices.Count
        ServicesOnNamedAccounts  = $customAccountServices.Count
        NonMicrosoftTasks        = $tasks.Count
        ListeningPorts           = $listening.Count
        NonAdminShares           = $shares.Count
    }
    ThirdPartyServices          = $thirdPartyServices
    ServicesOnNamedAccounts     = $customAccountServices
    ScheduledTasks              = $tasks
    ListeningPorts              = $listening
    Shares                      = $shares
}

$json = $result | ConvertTo-Json -Depth 6

if ($OutputPath) {
    $json | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "Written to $OutputPath"
} else {
    $json
}
