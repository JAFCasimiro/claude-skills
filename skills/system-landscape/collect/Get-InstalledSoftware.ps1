<#
.SYNOPSIS
    Lists software installed on a Windows machine, with patch recency.

.DESCRIPTION
    READ-ONLY. Reads the uninstall registry keys and changes nothing.

    Deliberately does NOT use Win32_Product. That WMI class is slow and, worse, it
    triggers an MSI self-repair on every installed package as it enumerates them,
    which can restart services on a production server. Registry enumeration is the
    correct way to inventory installed software.

    Covers machine-wide installations (64-bit and 32-bit views) and per-user
    installations for the account running the script. Many modern applications —
    browsers, editors, chat clients — install per-user, so a machine-only
    inventory will under-report on workstations.

.PARAMETER IncludeUpdates
    Include entries that look like patches and hotfixes. Off by default — they add
    hundreds of rows and rarely matter for a landscape document.

.PARAMETER IncludeComponents
    Include entries the vendor marked SystemComponent — runtimes, redistributables
    and installer sub-packages. Off by default. Turn it on when you suspect the
    filter is hiding something you need.

.PARAMETER OutputPath
    Optional. Write JSON to this path instead of the console.

.EXAMPLE
    .\Get-InstalledSoftware.ps1

.EXAMPLE
    .\Get-InstalledSoftware.ps1 -OutputPath C:\Temp\SRV01-software.json

.EXAMPLE
    # Everything, including components and updates
    .\Get-InstalledSoftware.ps1 -IncludeUpdates -IncludeComponents

.NOTES
    Elevation: not required.
    Per-user software for OTHER accounts is not visible from here. On a
    multi-user server, note that limitation rather than assuming the list is complete.
#>

[CmdletBinding()]
param(
    [switch]$IncludeUpdates,
    [switch]$IncludeComponents,
    [string]$OutputPath
)

$ErrorActionPreference = 'SilentlyContinue'

$uninstallPaths = @(
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*';            Scope = 'Machine'; Arch = 'x64' }
    @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'; Scope = 'Machine'; Arch = 'x86' }
    @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*';            Scope = 'User';    Arch = 'x64' }
    @{ Path = 'HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'; Scope = 'User';    Arch = 'x86' }
)

$raw = foreach ($location in $uninstallPaths) {
    Get-ItemProperty -Path $location.Path | Where-Object { $_.DisplayName } | ForEach-Object {

        # SystemComponent = 1 marks runtimes, redistributables and installer
        # sub-packages the vendor considers part of something else.
        if (-not $IncludeComponents -and $_.SystemComponent -eq 1) { return }

        if (-not $IncludeUpdates -and
            $_.DisplayName -match '^(Security Update|Update for|Hotfix|KB\d{6,})') { return }

        $installDate = $null
        if ($_.InstallDate -match '^\d{8}$') {
            try {
                $installDate = [datetime]::ParseExact($_.InstallDate, 'yyyyMMdd', $null).ToString('yyyy-MM-dd')
            } catch { }
        }

        # PSCustomObject, not a hashtable. Sort-Object and Where-Object cannot
        # read properties off a hashtable, which silently collapses the list.
        [PSCustomObject]@{
            Name            = $_.DisplayName
            Version         = $_.DisplayVersion
            Publisher       = $_.Publisher
            InstallDate     = $installDate
            Scope           = $location.Scope
            Architecture    = $location.Arch
            InstallLocation = $_.InstallLocation
        }
    }
}

# Dedupe on name + version: the same product can appear in more than one view.
$software = @($raw | Sort-Object -Property Name, Version -Unique)

# --- Windows Update history -------------------------------------------------
# The last installed update is a better signal of patch discipline than any
# configured schedule.
$hotfixes = @(
    Get-HotFix | Sort-Object -Property InstalledOn -Descending | Select-Object -First 15 | ForEach-Object {
        [PSCustomObject]@{
            HotFixID    = $_.HotFixID
            Description = $_.Description
            InstalledOn = if ($_.InstalledOn) { $_.InstalledOn.ToString('yyyy-MM-dd') } else { 'Unknown' }
        }
    }
)

$lastPatch = if ($hotfixes.Count -gt 0) { $hotfixes[0].InstalledOn } else { 'Unknown' }
$daysSincePatch = 'Unknown'
if ($lastPatch -ne 'Unknown') {
    try { $daysSincePatch = [math]::Round(((Get-Date) - [datetime]$lastPatch).TotalDays) } catch { }
}

# --- Sanity check -----------------------------------------------------------
# A real machine has dozens of products. A handful means the query went wrong,
# not that the machine is clean.
if ($software.Count -lt 5) {
    Write-Warning "Only $($software.Count) product(s) found. That is unusually low - re-run with -IncludeComponents -IncludeUpdates and compare before trusting this."
}

$result = [PSCustomObject]@{
    CollectedAt        = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    HostName           = $env:COMPUTERNAME
    CollectedForUser   = "$env:USERDOMAIN\$env:USERNAME"
    Script             = 'Get-InstalledSoftware.ps1'
    FiltersApplied     = [PSCustomObject]@{
        UpdatesIncluded    = [bool]$IncludeUpdates
        ComponentsIncluded = [bool]$IncludeComponents
    }
    SoftwareCount      = $software.Count
    Software           = $software
    LastPatchDate      = $lastPatch
    DaysSinceLastPatch = $daysSincePatch
    RecentHotfixes     = $hotfixes
}

$json = $result | ConvertTo-Json -Depth 5

if ($OutputPath) {
    $json | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "Written to $OutputPath  ($($software.Count) products)"
} else {
    $json
}
