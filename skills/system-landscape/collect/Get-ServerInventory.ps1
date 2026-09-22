<#
.SYNOPSIS
    Collects hardware, operating system and network inventory from a Windows machine.

.DESCRIPTION
    READ-ONLY. This script queries information and changes nothing on the system.

    Run it on each server you want to document. Output is JSON: save it to a file, or
    paste it back into the conversation so the landscape document can be built from it.

    Works on Windows Server 2012 R2 and later, and on Windows 10/11.
    PowerShell 5.1 or later. No modules required.

.PARAMETER OutputPath
    Optional. Write JSON to this path instead of the console.

.EXAMPLE
    .\Get-ServerInventory.ps1

.EXAMPLE
    .\Get-ServerInventory.ps1 -OutputPath C:\Temp\SRV01-inventory.json

.NOTES
    Elevation: not required, but some fields return more detail when run as
    Administrator (physical disk media type, BIOS serial).
#>

[CmdletBinding()]
param(
    [string]$OutputPath
)

$ErrorActionPreference = 'SilentlyContinue'

function Get-SafeValue {
    param([scriptblock]$Block, $Fallback = 'Unknown')
    try {
        $result = & $Block
        if ($null -eq $result) { return $Fallback }
        # Only an EMPTY STRING counts as no value. Testing $result -eq ''
        # against a boolean coerces '' to $false, which would throw away a
        # legitimate $false and report it as Unknown.
        if (($result -is [string]) -and ($result.Length -eq 0)) { return $Fallback }
        return $result
    } catch {
        return $Fallback
    }
}

# --- Operating system -------------------------------------------------------
$os  = Get-CimInstance -ClassName Win32_OperatingSystem
$cs  = Get-CimInstance -ClassName Win32_ComputerSystem
$bios = Get-CimInstance -ClassName Win32_BIOS

# ProductType: 1 = workstation, 2 = domain controller, 3 = member server.
# Several cmdlets below exist on client Windows but throw when called there.
$productType = Get-SafeValue { [int]$os.ProductType } 0
$osRole = switch ($productType) {
    1       { 'Workstation' }
    2       { 'Domain Controller' }
    3       { 'Server' }
    default { 'Unknown' }
}
$isServerOS = ($productType -in @(2, 3))

$osInfo = [PSCustomObject][ordered]@{
    Caption          = Get-SafeValue { $os.Caption }
    Role             = $osRole
    Version          = Get-SafeValue { $os.Version }
    BuildNumber      = Get-SafeValue { $os.BuildNumber }
    Architecture     = Get-SafeValue { $os.OSArchitecture }
    InstallDate      = Get-SafeValue { $os.InstallDate.ToString('yyyy-MM-dd') }
    LastBootUpTime   = Get-SafeValue { $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm') }
    UptimeDays       = Get-SafeValue { [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 1) }
    TimeZone         = Get-SafeValue { (Get-TimeZone).Id }
}

# --- Identity and domain ----------------------------------------------------
$identity = [PSCustomObject][ordered]@{
    HostName    = $env:COMPUTERNAME
    FQDN        = Get-SafeValue { [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).HostName }
    Domain      = Get-SafeValue { $cs.Domain }
    PartOfDomain = Get-SafeValue { $cs.PartOfDomain }
    Workgroup   = Get-SafeValue { $cs.Workgroup } 'n/a'
}

# --- Hardware ---------------------------------------------------------------
$cpus = @(Get-CimInstance -ClassName Win32_Processor)

$hardware = [PSCustomObject][ordered]@{
    Manufacturer      = Get-SafeValue { $cs.Manufacturer }
    Model             = Get-SafeValue { $cs.Model }
    SerialNumber      = Get-SafeValue { $bios.SerialNumber }
    BiosVersion       = Get-SafeValue { ($bios.SMBIOSBIOSVersion) }
    # Virtual machines report a hypervisor vendor in Model or Manufacturer.
    LikelyVirtual     = Get-SafeValue {
                            $m = "$($cs.Manufacturer) $($cs.Model)"
                            [bool]($m -match 'VMware|Virtual|KVM|Xen|QEMU|Hyper-V|Parallels')
                        }
    ProcessorName     = Get-SafeValue { $cpus[0].Name }
    PhysicalProcessors = Get-SafeValue { $cpus.Count }
    TotalCores        = Get-SafeValue { ($cpus | Measure-Object -Property NumberOfCores -Sum).Sum }
    LogicalProcessors = Get-SafeValue { $cs.NumberOfLogicalProcessors }
    TotalMemoryGB     = Get-SafeValue { [math]::Round($cs.TotalPhysicalMemory / 1GB, 1) }
}

# --- Memory modules (helps answer "can we add more RAM?") -------------------
$memoryModules = @(
    Get-CimInstance -ClassName Win32_PhysicalMemory | ForEach-Object {
        [PSCustomObject][ordered]@{
            BankLabel = $_.BankLabel
            CapacityGB = [math]::Round($_.Capacity / 1GB, 1)
            SpeedMHz   = $_.Speed
        }
    }
)

# --- Logical disks ----------------------------------------------------------
$disks = @(
    Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
        $freePct = if ($_.Size -gt 0) { [math]::Round(($_.FreeSpace / $_.Size) * 100, 1) } else { 0 }
        [PSCustomObject][ordered]@{
            Drive        = $_.DeviceID
            Label        = $_.VolumeName
            FileSystem   = $_.FileSystem
            SizeGB       = [math]::Round($_.Size / 1GB, 1)
            FreeGB       = [math]::Round($_.FreeSpace / 1GB, 1)
            FreePercent  = $freePct
            LowSpace     = ($freePct -lt 15)
        }
    }
)

# --- Physical disks (media type: SSD vs HDD). Not on older builds. ----------
$physicalDisks = @()
if (Get-Command Get-PhysicalDisk -ErrorAction SilentlyContinue) {
    $physicalDisks = @(
        Get-PhysicalDisk | ForEach-Object {
            [PSCustomObject][ordered]@{
                FriendlyName = $_.FriendlyName
                MediaType    = $_.MediaType
                SizeGB       = [math]::Round($_.Size / 1GB, 1)
                HealthStatus = $_.HealthStatus
            }
        }
    )
}

# --- Network ----------------------------------------------------------------
$network = @()
if (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue) {
    $network = @(
        Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | ForEach-Object {
            $cfg = Get-NetIPConfiguration -InterfaceIndex $_.ifIndex
            [PSCustomObject][ordered]@{
                Name        = $_.Name
                Description = $_.InterfaceDescription
                MacAddress  = $_.MacAddress
                LinkSpeed   = $_.LinkSpeed
                IPv4        = @($cfg.IPv4Address.IPAddress)
                Gateway     = @($cfg.IPv4DefaultGateway.NextHop)
                DnsServers  = @($cfg.DNSServer | Where-Object { $_.AddressFamily -eq 2 } | ForEach-Object { $_.ServerAddresses })
            }
        }
    )
}

# --- Server roles and features (Windows Server only) ------------------------
# Get-WindowsFeature is PRESENT on client Windows when RSAT is installed, and
# throws when called there. Testing for the cmdlet is not enough: test the OS.
$roles = @()
$rolesNote = $null

if (-not $isServerOS) {
    $rolesNote = 'Client operating system - server roles do not apply'
} elseif (-not (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue)) {
    $rolesNote = 'Get-WindowsFeature not available (Server Core without the ServerManager module?)'
} else {
    try {
        $roles = @(Get-WindowsFeature -ErrorAction Stop |
            Where-Object { $_.Installed } |
            Select-Object -ExpandProperty Name)
    } catch {
        $rolesNote = "Could not enumerate roles: $($_.Exception.Message)"
    }
}

# --- Pending reboot ---------------------------------------------------------
$pendingReboot = Get-SafeValue {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )
    [bool](($keys | Where-Object { Test-Path $_ }).Count)
} $false

# --- Assemble ---------------------------------------------------------------
$result = [PSCustomObject][ordered]@{
    CollectedAt   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    CollectedBy   = "$env:USERDOMAIN\$env:USERNAME"
    Script        = 'Get-ServerInventory.ps1'
    Identity      = $identity
    OperatingSystem = $osInfo
    Hardware      = $hardware
    MemoryModules = $memoryModules
    LogicalDisks  = $disks
    PhysicalDisks = $physicalDisks
    Network       = $network
    InstalledRoles = $roles
    InstalledRolesNote = $rolesNote
    PendingReboot = $pendingReboot
}

$json = $result | ConvertTo-Json -Depth 6

if ($OutputPath) {
    $json | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "Written to $OutputPath"
} else {
    $json
}
