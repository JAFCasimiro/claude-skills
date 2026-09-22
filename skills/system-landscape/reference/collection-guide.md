# Guided collection

How to walk someone through gathering technical inventory, and what to do with what
comes back.

## The principle

The user runs the commands. Claude does not connect to anything, does not ask for
credentials, and does not need access to the environment. The user runs a script on a
machine they already administer and pastes the result back.

This is deliberate. It keeps the person who is accountable for those systems in
control of what leaves them, and it works in environments where no remote access to an
AI tool would ever be permitted.

## What the scripts cover, and what they do not

| The scripts give you | Only people give you |
|----------------------|----------------------|
| Hardware, OS, patch level | What the system is for |
| Installed software and versions | Who owns it |
| Running services and scheduled tasks | How critical it is |
| Listening ports and shares | What happens when it breaks |
| Local admins, encryption, firewall | Whether the backup has ever been restored |

Never present script output as a finished landscape. It is the inventory column; the
judgement columns are still empty.

## Sequence

Work one machine at a time until the user is comfortable with the output, then scale.

**1. Establish the target list.** Ask for the list of servers. If there is no list,
that is the first finding — and Active Directory can produce a starting point:

```powershell
Get-ADComputer -Filter { OperatingSystem -like '*Server*' } -Properties OperatingSystem, LastLogonDate |
    Select-Object Name, OperatingSystem, LastLogonDate |
    Sort-Object LastLogonDate -Descending |
    Format-Table -AutoSize
```

Machines that have not authenticated in 90 days are either decommissioned and still in
AD, or running and unmanaged. Both matter.

**2. Start with one server.** Pick a non-critical one. Have the user run:

```powershell
.\Get-ServerInventory.ps1 -OutputPath C:\Temp\SRV01-inventory.json
```

Ask them to open the file and read it before sending anything. They need to see what
is in it. This is also where they decide whether serial numbers and IP addresses are
acceptable to share.

**3. Read it back to them.** Summarise what the output says and ask the questions it
raises — "this box has been up 412 days, when was it last patched?", "there is 6% free
on D:, is that expected?". The output is a conversation starter, not an answer.

**4. Then the remaining three scripts** on the same machine, then the rest of the
estate — either script by script, or with `Invoke-LandscapeCollection.ps1` if WinRM is
available.

The runner needs a target list, which the user creates. Either name machines inline:

```powershell
.\Invoke-LandscapeCollection.ps1 -ComputerName SRV01,SRV02
```

or copy `servers.example.txt` to `servers.txt`, replace the examples with real machine
names, and pass it:

```powershell
.\Invoke-LandscapeCollection.ps1 -ComputerListPath .\servers.txt
```

Run with no parameters and it prints these options rather than failing. `servers.txt`
and the collected JSON are git-ignored, so real hostnames stay local.

## The scripts

| Script | Answers | Elevation |
|--------|---------|-----------|
| `Get-ServerInventory.ps1` | What is this machine — CPU, RAM, disks, OS, network, roles, uptime | Not required |
| `Get-InstalledSoftware.ps1` | What is installed, what version, when was it last patched | Not required |
| `Get-ServiceProfile.ps1` | What does it actually do — services, tasks, ports, shares | Recommended |
| `Get-SecurityBaseline.ps1` | Who administers it, is it protected, is anything legacy enabled | Required |
| `Invoke-LandscapeCollection.ps1` | Runs the four across a list of machines | Depends on targets |

All are read-only. None install anything, change any setting, or write outside the path
the user specifies.

## Before anything is pasted back

Tell the user plainly what the output contains and let them decide. Depending on the
script it can include hostnames, IP addresses, BIOS serial numbers, service account
names, local user account names and file paths.

If the result will be shared outside the organisation, or the user is uneasy, ask them
to redact before sending, or use `-OutputPath` and work from a summary they read out.
Do not press for the raw file.

If execution policy blocks the script, the correct instruction is to run it for that
session only:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Get-ServerInventory.ps1
```

Never tell someone to change the machine's execution policy permanently.

## Reading the output

Things worth flagging every time they appear:

| Signal | Why it matters |
|--------|----------------|
| Uptime over ~90 days | Patches are not being applied, or reboots are being avoided |
| `DaysSinceLastPatch` over 60 | Patch process is not working, whatever the policy says |
| `LowSpace` true | Predictable outage waiting to happen |
| OS past end of support | No security updates, and usually a compliance finding |
| Services on named accounts | Undocumented service accounts, passwords that never rotate |
| Tasks running scripts from user profiles or Temp | Fragile, and a common persistence location |
| `AllInterfaces` listeners on unexpected ports | Exposure nobody has reviewed |
| `SMB1Enabled` true | Legacy protocol, should be gone |
| Local admins that are individual named users | No privileged access model |
| `No LAPS policy detected` with local admin accounts | Shared local admin password, probably identical everywhere |
| `RanElevated` false | Read the output knowing several fields are simply missing |

Report these as observations with consequences, not as alarms. The person reading the
document usually already suspects most of them.

## When the output looks wrong

Check plausibility before reading anything into a result. A machine with three
installed products, one listening port or no local administrators is a broken query,
not a finding.

- **Software count under ~5** — the script warns about this itself. Re-run with
  `-IncludeUpdates -IncludeComponents` and compare. On a workstation, also remember
  that per-user installs for other accounts are invisible.
- **One listening port** — the machine is not that quiet. Something went wrong.
- **Everything `Unknown` in the security baseline** — check `RanElevated`. Without
  elevation most of that script returns nothing.
- **No roles on a Windows Server** — `Get-WindowsFeature` is absent on Server Core
  installs without the relevant module, and on client Windows.

Say so plainly when a result looks implausible, and re-run rather than writing it up.
A landscape document that reports an empty estate because a query failed is worse than
no document.

## Machines the scripts cannot reach

Record them. A server nobody can connect to, a box whose owner is unknown, an appliance
with no shell — these belong in the document as open items. An estate map that silently
omits what could not be collected is worse than one that says "four machines could not
be reached, here they are".

## Non-Windows systems

These scripts are Windows only. For Linux, network appliances, hypervisors and SaaS,
fall back to the interview questions and to each platform's own inventory view
(vCenter, the cloud portal, the firewall's configuration export). Note in the document
which parts of the estate were inventoried by script and which by conversation — they
carry different confidence.
