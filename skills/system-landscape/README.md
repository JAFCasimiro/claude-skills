# system-landscape

Documents an organisation's technology estate: what systems exist, what each one is
for, who owns it, what depends on it, and where the risks are.

Most organisations that need this have nothing written down, or have a diagram that
stopped being true two years ago. This skill runs the discovery — structured
interviews plus read-only inventory scripts you run yourself — and produces two
things: a one-page A3 visual of the estate, and the full landscape document. Both in
English and European Portuguese.

## Install

```bash
# Personal, available everywhere
cp -r skills/system-landscape ~/.claude/skills/

# Or project-scoped, committed with your code
cp -r skills/system-landscape .claude/skills/
```

Claude loads it automatically when the task matches. You can also ask for it by name.

## How it works

The skill drives a five-step sequence: discovery interviews, technical collection,
inventory, dependency mapping, gap analysis.

**You run the commands.** The skill never connects to anything and never asks for
credentials. It tells you which script to run on which machine, you run it, and you
paste back what you are willing to share. That keeps the person accountable for those
systems in control of what leaves them, and it works in environments where remote
access for an AI tool would never be approved.

## The scripts

In `collect/`. All read-only: they query and change nothing.

| Script | Answers | Elevation |
|--------|---------|-----------|
| `Get-ServerInventory.ps1` | CPU, RAM, disks, OS, network, roles, uptime | Not required |
| `Get-InstalledSoftware.ps1` | What is installed, what version, patch recency | Not required |
| `Get-ServiceProfile.ps1` | Services, scheduled tasks, listening ports, shares | Recommended |
| `Get-SecurityBaseline.ps1` | Local admins, encryption, firewall, legacy protocols | Required |
| `Invoke-LandscapeCollection.ps1` | Runs the four across a list of machines | See below |

Windows Server 2012 R2 / Windows 10 and later. PowerShell 5.1. No modules to install.

### One machine

```powershell
.\Get-ServerInventory.ps1
.\Get-ServerInventory.ps1 -OutputPath C:\Temp\SRV01-inventory.json
```

Read the file before sending it anywhere. It contains hostnames, IP addresses and, in
the security baseline, account names.

### Several machines

`Invoke-LandscapeCollection.ps1` is for **servers in a domain**, where PowerShell
remoting is already enabled — it is on by default on Windows Server 2012 and later.
Point it at twenty servers and collect from all of them in one command.

It is **not** for workstations and laptops. Remoting is off by default on client
Windows, so it will fail against them, and turning remoting on across a laptop fleet
just to run an inventory is not a trade worth making. Below roughly ten servers there
is little to gain either: copying the four scripts to each machine takes about as long
as getting remoting working, and fails in fewer ways.

It needs a target list. Name them inline:

```powershell
.\Invoke-LandscapeCollection.ps1 -ComputerName SRV01,SRV02
```

Or create a list file. Copy `collect/servers.example.txt` to `servers.txt`, replace the
examples with your own machine names, and pass it:

```powershell
.\Invoke-LandscapeCollection.ps1 -ComputerListPath .\servers.txt
```

One name per line; `#` comments and blank lines are ignored. Short names, FQDNs and IP
addresses all work, as long as they resolve from where you run the script. The two
options can be combined — the lists are merged and deduplicated.

Run it with no parameters and it prints these options rather than failing.

Results land in `LandscapeData\<machine>\*.json`, with a `collection-log.json`
recording what succeeded and what did not.

`servers.txt` and the collected JSON are git-ignored, so real hostnames stay local.

### Remoting and elevation

Remote machines are collected over PowerShell remoting (WinRM). **The local machine is
not** — the runner detects it and executes the scripts directly, so a local collection
needs neither WinRM nor an elevated session.

`Get-SecurityBaseline.ps1` is the exception: without elevation most of its fields
return `Unknown`, and it says so. The runner warns you before starting.

If execution policy blocks a script, run it for that session only rather than changing
the machine's policy:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Get-ServerInventory.ps1
```

## What you get

**A one-page visual**, A3 landscape, dark theme: the estate as a grid of category
panels listing the real systems, with findings in red and unestablished facts in grey.
Built from `templates/landscape-diagram.html` and rendered to PDF with

```powershell
.\templates\Export-LandscapePdf.ps1 -HtmlPath .\acme-landscape.html
```

which drives Edge or Chrome headless. Or print it by hand: Ctrl+P, A3 landscape,
margins none, **background graphics on** — without that the dark page prints white.

**The document**, in English and European Portuguese: scope, inventory by category,
dependency map, integrations, and the gap list with owners and timeframes.

The visual is what gets shown in a meeting. The document is what gets worked from.

## What the scripts do not give you

| The scripts give you | Only people give you |
|----------------------|----------------------|
| Hardware, OS, patch level | What the system is for |
| Installed software and versions | Who owns it |
| Running services and scheduled tasks | How critical it is |
| Listening ports and shares | What happens when it breaks |
| Local admins, encryption, firewall | Whether the backup has ever been restored |

A collection run is the inventory column. The judgement columns come from the
interviews, and the document is not finished without them.

## A note on Win32_Product

These scripts read installed software from the registry, not from the `Win32_Product`
WMI class. That class is slow and triggers an MSI self-repair on every installed
package as it enumerates them, which can restart services on a production server. If
you are writing your own inventory scripts, this is worth knowing.

## Files

```
system-landscape/
├── SKILL.md                            instructions for Claude
├── collect/                            the read-only PowerShell scripts
│   └── servers.example.txt             target list template
├── templates/
│   ├── landscape-diagram.html          the one-page visual, print-ready
│   └── Export-LandscapePdf.ps1         renders it to PDF via Edge or Chrome
└── reference/
    ├── inventory-schema.md             categories, attributes, gap checklist
    ├── discovery-questions.md          interview questions by category
    └── collection-guide.md             how the collection is guided
```

`SKILL.md` is written for Claude, not for you. This README is the human-facing one.
