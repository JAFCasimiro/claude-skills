<#
.SYNOPSIS
    Runs the collection scripts against a list of Windows machines and saves one
    set of JSON files per machine.

.DESCRIPTION
    WHAT THIS IS FOR: servers in a domain, where PowerShell remoting is already
    enabled — it is on by default on Windows Server 2012 and later. Point it at
    twenty servers and collect from all of them in one command.

    WHAT IT IS NOT FOR: workstations and laptops. Remoting is off by default on
    client Windows, so this will simply fail against them, and enabling remoting
    on laptops purely to run an inventory is not a trade worth making.

    Below roughly ten servers, there is little to gain here. Copying the four
    Get-*.ps1 scripts to each machine and running them takes about as long as
    getting remoting working, and fails in fewer ways.

    READ-ONLY. Executes only the four Get-*.ps1 collection scripts, which query
    and change nothing.

    Remote machines are collected over PowerShell remoting (WinRM). The local
    machine is collected by running the scripts directly — no WinRM, no elevation.
    (Connecting to your own machine over WinRM requires an elevated session and
    the service running, which is a pointless hurdle for a local collection.)

    If remoting to the remote targets is not available — which is common, and is
    itself worth recording in the landscape document — copy the individual scripts
    to each machine and run them there.

    Elevation: not needed for the three inventory scripts. The Security baseline
    returns mostly Unknown without it, and the script warns you.

    Results land in one folder per machine:
        .\LandscapeData\SRV01\inventory.json
        .\LandscapeData\SRV01\software.json
        ...
    plus a collection-log.json recording what succeeded and what did not.

.PARAMETER ComputerName
    One or more machine names.

.PARAMETER ComputerListPath
    Path to a text file you create, with one machine name per line. Lines starting
    with # and blank lines are ignored. See servers.example.txt in this folder —
    copy it to servers.txt and put your own machine names in it.

    Can be combined with -ComputerName; the two lists are merged and deduplicated.

.PARAMETER OutputRoot
    Folder for the results. Default: .\LandscapeData

.PARAMETER Credential
    Optional credentials for the remote sessions.

.PARAMETER Scripts
    Which collection scripts to run. Default: all four.

.EXAMPLE
    .\Invoke-LandscapeCollection.ps1 -ComputerName SRV01,SRV02

.EXAMPLE
    .\Invoke-LandscapeCollection.ps1 -ComputerListPath .\servers.txt -Credential (Get-Credential)

.NOTES
    Run from a management workstation with the collect\ folder intact — this script
    reads the other scripts from its own directory.

    Start with one machine and read the output before running it across the estate.
#>

[CmdletBinding()]
param(
    [string[]]$ComputerName,

    [string]$ComputerListPath,

    [string]$OutputRoot = '.\LandscapeData',

    [System.Management.Automation.PSCredential]$Credential,

    [ValidateSet('Inventory', 'Software', 'Services', 'Security')]
    [string[]]$Scripts = @('Inventory', 'Software', 'Services', 'Security')
)

# --- No targets given: explain, do not prompt -------------------------------
if (-not $ComputerName -and -not $ComputerListPath) {
    Write-Host ''
    Write-Host 'This script needs a list of machines to collect from.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Either name them directly:'
    Write-Host '    .\Invoke-LandscapeCollection.ps1 -ComputerName SRV01,SRV02' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'Or create a plain text file with one machine name per line and pass it:'
    Write-Host '    .\Invoke-LandscapeCollection.ps1 -ComputerListPath .\servers.txt' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'See servers.example.txt in this folder for the format. Copy it to'
    Write-Host 'servers.txt and put your own machine names in it.'
    Write-Host ''
    Write-Host 'To try it against this machine only:'
    Write-Host "    .\Invoke-LandscapeCollection.ps1 -ComputerName $env:COMPUTERNAME" -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'Remote machines are collected over PowerShell remoting (WinRM). This'
    Write-Host 'machine is collected by running the scripts directly, so no WinRM and no'
    Write-Host 'elevation are needed for a local run.'
    Write-Host ''
    return
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$scriptMap = @{
    Inventory = @{ File = 'Get-ServerInventory.ps1';   Output = 'inventory.json' }
    Software  = @{ File = 'Get-InstalledSoftware.ps1'; Output = 'software.json'  }
    Services  = @{ File = 'Get-ServiceProfile.ps1';    Output = 'services.json'  }
    Security  = @{ File = 'Get-SecurityBaseline.ps1';  Output = 'security.json'  }
}

# --- Resolve target list ----------------------------------------------------
$targets = @()

if ($ComputerName) { $targets += $ComputerName }

if ($ComputerListPath) {
    if (-not (Test-Path $ComputerListPath)) {
        throw "Computer list not found: $ComputerListPath`n`nCreate a plain text file with one machine name per line. See servers.example.txt in this folder."
    }
    $targets += @(Get-Content $ComputerListPath |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') })
}

$targets = @($targets | Select-Object -Unique)

if ($targets.Count -eq 0) {
    throw 'The computer list contained no usable machine names (blank file, or only comments).'
}

Write-Host "Targets: $($targets.Count)" -ForegroundColor Cyan
Write-Host "Scripts: $($Scripts -join ', ')" -ForegroundColor Cyan
Write-Host ''

# Names that mean "this machine". Collecting from the local box over WinRM
# needs an elevated session and the WinRM service running; running the script
# directly needs neither, so do that instead.
$localNames = @($env:COMPUTERNAME, 'localhost', '.', '127.0.0.1', '::1')
try { $localNames += [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).HostName } catch { }

$isElevated = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (($Scripts -contains 'Security') -and -not $isElevated) {
    Write-Warning 'Not elevated. The Security baseline will return mostly Unknown for local collection.'
    Write-Host ''
}

$null = New-Item -ItemType Directory -Path $OutputRoot -Force
$log = @()

foreach ($target in $targets) {
    $local = ($target -in $localNames)
    $label = if ($local) { "$target (local)" } else { $target }
    Write-Host "[$label]" -ForegroundColor Yellow

    $targetDir = Join-Path $OutputRoot $target
    $null = New-Item -ItemType Directory -Path $targetDir -Force

    $session = $null

    if (-not $local) {
        $sessionParams = @{ ComputerName = $target; ErrorAction = 'Stop' }
        if ($Credential) { $sessionParams.Credential = $Credential }

        try {
            $session = New-PSSession @sessionParams
        } catch {
            $msg = $_.Exception.Message
            Write-Host "  unreachable over WinRM" -ForegroundColor Red

            # The raw WinRM error is a paragraph and rarely says which of the
            # three usual causes applies. Name them instead.
            Write-Host '    Usual causes: remoting not enabled on the target (off by' -ForegroundColor DarkGray
            Write-Host '    default on client Windows, on by default on Windows Server),' -ForegroundColor DarkGray
            Write-Host '    firewall, or the name does not resolve.' -ForegroundColor DarkGray
            Write-Host '    Fallback: copy the Get-*.ps1 scripts to that machine and run' -ForegroundColor DarkGray
            Write-Host '    them there.' -ForegroundColor DarkGray

            $log += [PSCustomObject][ordered]@{
                Computer = $target; Script = '(session)'; Status = 'Failed'
                Message = $msg
            }
            continue
        }
    }

    foreach ($key in $Scripts) {
        $scriptFile = Join-Path $scriptRoot $scriptMap[$key].File
        $outFile    = Join-Path $targetDir $scriptMap[$key].Output

        if (-not (Test-Path $scriptFile)) {
            Write-Host "  $key : script not found at $scriptFile" -ForegroundColor Red
            $log += [PSCustomObject][ordered]@{
                Computer = $target; Script = $key; Status = 'Failed'
                Message = 'Script file missing'
            }
            continue
        }

        try {
            if ($local) {
                $output = & $scriptFile
            } else {
                $output = Invoke-Command -Session $session -FilePath $scriptFile -ErrorAction Stop
            }
            $output | Out-File -FilePath $outFile -Encoding UTF8
            Write-Host "  $key : ok" -ForegroundColor Green
            $log += [PSCustomObject][ordered]@{
                Computer = $target; Script = $key; Status = 'Succeeded'
                Message = $outFile
            }
        } catch {
            Write-Host "  $key : $($_.Exception.Message)" -ForegroundColor Red
            $log += [PSCustomObject][ordered]@{
                Computer = $target; Script = $key; Status = 'Failed'
                Message = $_.Exception.Message
            }
        }
    }

    if ($session) { Remove-PSSession $session }
}

# --- Collection log ---------------------------------------------------------
$logPath = Join-Path $OutputRoot 'collection-log.json'
[PSCustomObject][ordered]@{
    CollectedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    CollectedBy = "$env:USERDOMAIN\$env:USERNAME"
    TargetCount = $targets.Count
    Results     = $log
} | ConvertTo-Json -Depth 4 | Out-File -FilePath $logPath -Encoding UTF8

$failed = @($log | Where-Object { $_.Status -eq 'Failed' })

Write-Host ''
Write-Host "Done. Results in $OutputRoot" -ForegroundColor Cyan
Write-Host "Succeeded: $(@($log | Where-Object { $_.Status -eq 'Succeeded' }).Count)  Failed: $($failed.Count)"

if ($failed.Count -gt 0) {
    Write-Host ''
    Write-Host 'Machines that could not be collected from belong in the landscape' -ForegroundColor Yellow
    Write-Host 'document too, as an open item rather than an omission.' -ForegroundColor Yellow
}
