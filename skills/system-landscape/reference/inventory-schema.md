# Inventory schema

## Categories

Use these as the table groupings in the document. Skip any that do not apply; do not
invent a system to fill an empty category.

| # | Category | What belongs here |
|---|----------|-------------------|
| 1 | Business applications | ERP, CRM, WMS, POS, e-commerce, BI/reporting, sector-specific systems |
| 2 | Collaboration & productivity | Email, office suite, file storage, chat, meetings, intranet |
| 3 | Identity & access | Directory, SSO/IdP, MFA, privileged access, joiner-mover-leaver process |
| 4 | Compute & storage | Physical servers, hypervisors, cloud tenants and subscriptions, NAS/SAN |
| 5 | Network & connectivity | Sites, ISPs, WAN/SD-WAN, firewalls, VPN, Wi-Fi, DNS, certificates |
| 6 | Endpoints & mobility | Workstations, laptops, mobile devices, MDM, print |
| 7 | Data protection | Backup, replication, retention, DR site, restore testing |
| 8 | Security controls | EDR/AV, email security, web filtering, logging/SIEM, vulnerability management |
| 9 | Operations | Monitoring, alerting, ticketing, runbooks, on-call, change management |
| 10 | Integrations & data flows | Interfaces between systems, EDI, APIs, scheduled file transfers, middleware |
| 11 | Suppliers & contracts | Managed service providers, support contracts, renewal dates, escalation paths |

Two categories are routinely forgotten and routinely matter: **10** (the interfaces
nobody owns) and **11** (the contract that auto-renews or the supplier with no named
escalation).

## Attributes per system

Capture what is known. Write **Unknown** where it is not — do not guess.

| Attribute | Notes |
|-----------|-------|
| Name | As people actually call it, with the official product name if different |
| Purpose | One sentence, in business terms |
| Business owner | The person who decides about it |
| Technical owner | The person called when it breaks |
| Users | Approximate count and which teams |
| Hosting | On-premises / IaaS / SaaS, and region if relevant |
| Criticality | Tier, assigned by the business (see below) |
| RTO / RPO | Target and whether it has ever been demonstrated |
| Authentication | Method, and whether MFA is enforced |
| Data | What kind, and whether it includes personal data |
| Version & support | Version, vendor support status, end-of-life date |
| Backup | Method, frequency, retention, **date of last successful restore test** |
| Dependencies | What it needs, and what needs it |
| Supplier | Vendor or MSP, support level, contract renewal date |
| Internet-facing | Yes/no, and how it is protected |
| Source | Where this information came from |
| Notes | Known problems, planned changes, workarounds in use |

## Criticality tiers

Define these in the document rather than assuming the reader shares them.

| Tier | Meaning | Test question |
|------|---------|---------------|
| 1 — Critical | The business stops | "Can you work at all without it?" |
| 2 — Important | Significant disruption, workarounds exist | "What do you do instead for a day?" |
| 3 — Standard | Inconvenient, absorbed | "Would you notice by the end of the week?" |
| 4 — Low | Little immediate impact | — |

Ask the business owner, record their answer, and note when IT disagrees.

## Gap checklist

Run every system against this list. Each hit becomes an entry in the gaps section with
a consequence, an owner and a timeframe.

**Ownership**
- No named business owner, or no named technical owner
- One person is the only one who knows how it works
- Supplier with no named escalation contact

**Resilience**
- Criticality never agreed with the business
- RTO/RPO stated but never demonstrated
- Single point of failure with no redundancy
- Restore never tested, or last test older than twelve months
- No DR arrangement for a Tier 1 system

**Security**
- Local accounts instead of central identity
- MFA not enforced, especially on anything internet-facing
- Administrative access not separated from daily-use accounts
- No logging, or logs kept somewhere nobody looks
- Out of vendor support, or EOL date already passed
- Leavers' access not reliably removed

**Lifecycle**
- Version significantly behind, with no upgrade path agreed
- Contract renewing automatically with no review
- System nobody could name an owner or purpose for

**Documentation**
- Integration with no owner and no documentation
- Configuration that exists only in one person's head
- Procedure documented but never followed
