<#
.SYNOPSIS
    Collects security-relevant configuration from a Windows machine.

.DESCRIPTION
    READ-ONLY. Queries only; changes nothing, enables nothing, remediates nothing.

    This is inventory, not an audit against a formal benchmark. It answers the
    questions a landscape document needs: who can administer this box, is it
    protected, is it patched, and is anything obviously legacy still enabled.

    For a real CIS/STIG assessment, use a tool built for that.

.PARAMETER OutputPath
    Optional. Write JSON to this path instead of the console.

.EXAMPLE
    .\Get-SecurityBaseline.ps1 -OutputPath C:\Temp\SRV01-security.json

.NOTES
    Elevation: required for most of this. Without it, several fields return Unknown.
    Output includes account names — review before sharing outside the organisation.
#>

[CmdletBinding()]
param(
    [string]$OutputPath
)

$ErrorActionPreference = 'SilentlyContinue'

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Warning 'Not running elevated. Several fields will report Unknown.'
}

function Get-SafeValue {
    param([scriptblock]$Block, $Fallback = 'Unknown')
    try {
        $r = & $Block
        if ($null -eq $r) { return $Fallback }
        # Only an EMPTY STRING counts as no value. Testing $r -eq '' against a
        # boolean coerces '' to $false, so a legitimate $false result would be
        # thrown away and reported as Unknown. That is how "SMB1 disabled"
        # became "SMB1 unknown".
        if (($r -is [string]) -and ($r.Length -eq 0)) { return $Fallback }
        return $r
    } catch { return $Fallback }
}

# --- Administrators ---------------------------------------------------------
# The single most useful line in this whole output, and the fiddliest to get.
#
# Two traps:
#   - A DOMAIN CONTROLLER has no local groups at all. Get-LocalGroupMember
#     fails there; the built-in Administrators group lives in the directory.
#   - The group NAME is localised in some Windows installations. Query by the
#     well-known SID S-1-5-32-544 instead of by the string "Administrators".
$localAdmins = @()
$adminsSource = $null

try {
    $localAdmins = @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop | ForEach-Object {
        "$($_.Name) [$($_.ObjectClass)/$($_.PrincipalSource)]"
    })
    $adminsSource = 'Get-LocalGroupMember (SID S-1-5-32-544)'
} catch {
    # Domain controller, or the LocalAccounts module is unavailable. ADSI
    # resolves the built-in group on both, including on a DC.
    try {
        $sid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
        $groupName = $sid.Translate([System.Security.Principal.NTAccount]).Value.Split('\')[-1]
        $group = [ADSI]"WinNT://$env:COMPUTERNAME/$groupName,group"
        $localAdmins = @($group.Invoke('Members') | ForEach-Object {
            ($_.GetType().InvokeMember('AdsPath', 'GetProperty', $null, $_, $null)) -replace '^WinNT://', ''
        })
        $adminsSource = "ADSI WinNT, group '$groupName' (built-in Administrators; on a domain controller this is the domain group)"
    } catch {
        $adminsSource = "Could not enumerate: $($_.Exception.Message)"
    }
}

# --- Local accounts ---------------------------------------------------------
$localAccounts = Get-SafeValue {
    @(Get-LocalUser | ForEach-Object {
        [PSCustomObject][ordered]@{
            Name                 = $_.Name
            Enabled              = $_.Enabled
            PasswordNeverExpires = $_.PasswordNeverExpires
            LastLogon            = if ($_.LastLogon) { $_.LastLogon.ToString('yyyy-MM-dd') } else { 'Never' }
        }
    })
} @()

# --- Antivirus / Defender ---------------------------------------------------
$defender = Get-SafeValue {
    if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
        $mp = Get-MpComputerStatus
        [PSCustomObject][ordered]@{
            AntivirusEnabled      = $mp.AntivirusEnabled
            RealTimeProtection    = $mp.RealTimeProtectionEnabled
            SignatureAge          = $mp.AntivirusSignatureAge
            SignatureLastUpdated  = $mp.AntivirusSignatureLastUpdated.ToString('yyyy-MM-dd')
            TamperProtection      = $mp.IsTamperProtected
        }
    } else { 'Defender cmdlets not present' }
}

# Third-party AV registers with Security Center (workstations only; on Server
# this class does not exist).
$registeredAV = Get-SafeValue {
    @(Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName AntiVirusProduct |
        Select-Object -ExpandProperty displayName)
} @()

# --- BitLocker --------------------------------------------------------------
$bitlocker = Get-SafeValue {
    if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
        @(Get-BitLockerVolume | ForEach-Object {
            [PSCustomObject][ordered]@{
                MountPoint       = $_.MountPoint
                ProtectionStatus = "$($_.ProtectionStatus)"
                EncryptionMethod = "$($_.EncryptionMethod)"
            }
        })
    } else { 'BitLocker cmdlets not present' }
}

# --- Firewall ---------------------------------------------------------------
$firewall = Get-SafeValue {
    @(Get-NetFirewallProfile | ForEach-Object {
        [PSCustomObject][ordered]@{
            Profile  = $_.Name
            Enabled  = $_.Enabled
            InboundDefault = "$($_.DefaultInboundAction)"
        }
    })
} @()

# --- Legacy protocols -------------------------------------------------------
# Falls back to the registry, which is authoritative and works without the
# SmbShare module. Absent value means enabled: SMB1 is on unless turned off.
$smb1 = Get-SafeValue {
    if (Get-Command Get-SmbServerConfiguration -ErrorAction SilentlyContinue) {
        [bool](Get-SmbServerConfiguration -ErrorAction Stop).EnableSMB1Protocol
    } else {
        $key = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' -ErrorAction Stop
        if ($null -eq $key.SMB1) { $true } else { [bool]$key.SMB1 }
    }
}

$smb1Source = Get-SafeValue {
    if (Get-Command Get-SmbServerConfiguration -ErrorAction SilentlyContinue) {
        'Get-SmbServerConfiguration'
    } else { 'Registry (LanmanServer\Parameters\SMB1)' }
}

$smbSigning = Get-SafeValue {
    [bool](Get-SmbServerConfiguration -ErrorAction Stop).RequireSecuritySignature
}

# --- RDP --------------------------------------------------------------------
$rdp = Get-SafeValue {
    $ts = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
    $nla = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
    [PSCustomObject][ordered]@{
        Enabled = ($ts.fDenyTSConnections -eq 0)
        NetworkLevelAuthentication = ($nla.UserAuthentication -eq 1)
    }
}

# --- LAPS -------------------------------------------------------------------
$laps = Get-SafeValue {
    $legacy = Test-Path 'HKLM:\SOFTWARE\Policies\Microsoft Services\AdmPwd'
    $modern = Test-Path 'HKLM:\SOFTWARE\Microsoft\Policies\LAPS'
    if ($modern) { 'Windows LAPS policy present' }
    elseif ($legacy) { 'Legacy LAPS policy present' }
    else { 'No LAPS policy detected' }
}

# --- Patching ---------------------------------------------------------------
$lastHotfix = Get-SafeValue {
    $h = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1
    if ($h.InstalledOn) { $h.InstalledOn.ToString('yyyy-MM-dd') } else { 'Unknown' }
}

$wsus = Get-SafeValue {
    (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate').WUServer
} 'Not configured (Windows Update direct)'

# --- Assemble ---------------------------------------------------------------
$result = [PSCustomObject][ordered]@{
    CollectedAt        = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    HostName           = $env:COMPUTERNAME
    Script             = 'Get-SecurityBaseline.ps1'
    RanElevated        = $isAdmin
    LocalAdministrators = $localAdmins
    AdministratorsSource = $adminsSource
    LocalAccounts      = $localAccounts
    Defender           = $defender
    RegisteredAntivirus = $registeredAV
    BitLocker          = $bitlocker
    FirewallProfiles   = $firewall
    SMB1Enabled        = $smb1
    SMB1Source         = $smb1Source
    SMBSigningRequired = $smbSigning
    RDP                = $rdp
    LAPS               = $laps
    LastHotfixInstalled = $lastHotfix
    UpdateSource       = $wsus
}

$json = $result | ConvertTo-Json -Depth 6

if ($OutputPath) {
    $json | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "Written to $OutputPath"
} else {
    $json
}
