# DX.Comply Pilot

## What This Is

DX.Comply Pilot is a standalone FMX application that guides Delphi software companies through the full EU Cyber Resilience Act (CRA) compliance lifecycle. It transforms abstract EU regulations into concrete, trackable work steps — from product classification through SBOM generation, evidence collection, and report export. The primary user is a developer-who-is-also-compliance-officer, typical for smaller Delphi shops.

## Core Value

One place to manage your entire CRA compliance — classification, SBOM, evidence, conformity declaration, reports — so nothing falls through the cracks before the December 2027 deadline.

## Requirements

### Validated

- DX.Comply Engine v1.2.0 (SBOM generation, unit resolution, runtime packages, DLL scan) — existing
- CycloneDX 1.5 / SPDX 2.3 output — existing
- HTML and Markdown compliance reports — existing

### Active

- [ ] FMX standalone application with dashboard + wizard navigation
- [ ] Product classification wizard (Standard / Important Class I/II / Critical)
- [ ] SBOM generation integrated via DX.Comply Engine package
- [ ] Evidence collector for technical dossier (design decisions, security-by-design, test evidence, support commitments)
- [ ] Support period tracking with 5-year rule validation
- [ ] EU Declaration of Conformity with interactive guided editor
- [ ] CE marking guidance
- [ ] User security guide template
- [ ] Report generator: PDF, HTML, Markdown, ZIP archive (structured technical dossier)
- [ ] Local JSON persistence in `.dxcomply-pilot/` (Git-friendly, portable)
- [ ] Cross-platform: Windows + macOS

### Out of Scope

- Vulnerability Dashboard / CVE check against online databases — deferred to v2 (requires API integration)
- ENISA incident reporting assistant — deferred to v2 (regulation details still evolving)
- AI/KI assistance for code analysis — deferred to v2 (not core feature)
- Cloud storage or server-side processing — deliberately excluded (data stays local)
- VCL variant — FMX only for cross-platform support

## Context

- DX.Comply Pilot lives in the same repository as DX.Comply (`src/Pilot/`)
- The DX.Comply Engine package (`DX.Comply.Engine370.bpl`) is referenced, not duplicated
- `TDxComplyGenerator` is called directly for SBOM generation as one step in the workflow
- Target audience: Delphi developers at small-to-medium companies who handle compliance themselves
- EU CRA full compliance deadline: December 2027
- The app must feel like a practical guide, not a legal form — clear language, no unnecessary jargon
- All persistence is local JSON in the project directory — no database, no cloud, fully Git-versionable

## Constraints

- **Framework**: FMX (cross-platform requirement: Windows + macOS)
- **Engine dependency**: Must use DX.Comply Engine as-is (package reference, no forking)
- **Delphi version**: Delphi 13 (RAD Studio 37.0)
- **Persistence**: Local JSON files only — no SQLite, no cloud
- **Report formats**: PDF, HTML, Markdown, ZIP — all must work on both platforms
- **Naming**: Unit naming follows DX.Comply conventions (dot-notation, `DX.Comply.Pilot.*`)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| FMX over VCL | Cross-platform (Windows + macOS) required | -- Pending |
| Dashboard + Wizard navigation | User needs overview of compliance status AND step-by-step guidance | -- Pending |
| Local JSON persistence | Git-friendly, no server dependency, portable between machines | -- Pending |
| Interactive conformity editor over static template | Users need guidance filling each section, not just a blank form | -- Pending |
| Same repo as DX.Comply | Engine as package reference, shared build infrastructure | -- Pending |
| KI-Assistenz deferred to v2 | Focus v1 on the core compliance workflow | -- Pending |
| Vulnerability Dashboard deferred to v2 | Requires online API integration, regulation details still evolving | -- Pending |

---
*Last updated: 2026-03-23 after initialization*
