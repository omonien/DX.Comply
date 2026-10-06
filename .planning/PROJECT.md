# DX.Comply Pilot

## What This Is

DX.Comply Pilot is a concept for a later standalone FMX application. It would help a Delphi team collect more of the technical documentation for the EU Cyber Resilience Act (CRA). It is not a certification, and it does not make a product compliant.

The current DX.Comply tool writes build evidence and a component list (an SBOM). That list is a starting point for the SBOM part of the technical documentation. Pilot, if built, would add further steps around that list: classification notes, evidence files, and draft reports. The primary user in this concept is a developer who also handles product documentation, which is common in smaller Delphi shops.

## Core Value

One place to keep the notes that sit next to the SBOM: classification, evidence, a draft conformity declaration, and reports. The December 2027 date is the date the CRA applies in full. The app would not complete that file by itself.

## Requirements

### Already in DX.Comply

- DX.Comply Engine (SBOM generation, unit resolution, runtime packages, DLL scan)
- CycloneDX 1.5 and SPDX 2.3 output
- HTML and Markdown SBOM reports (an internal structural check, not an official schema validation)

### Active (concept only, not built)

- [ ] FMX standalone application with dashboard and wizard navigation
- [ ] Product classification notes (Standard / Important Class I/II / Critical)
- [ ] SBOM generation called from the DX.Comply Engine package
- [ ] Evidence collector for a technical file (design decisions, security-by-design notes, test evidence, support commitments)
- [ ] Support period tracking with a 5-year check
- [ ] Draft EU Declaration of Conformity with a guided editor (a draft, not a certificate)
- [ ] CE marking notes
- [ ] User security guide template
- [ ] Report generator: PDF, HTML, Markdown, ZIP archive (structured technical file)
- [ ] Local JSON persistence in `.dxcomply-pilot/` (Git-friendly, portable)
- [ ] Cross-platform: Windows and macOS

### Out of Scope

- Vulnerability dashboard / CVE check against online databases (deferred; would need an API)
- ENISA incident reporting assistant (deferred)
- AI assistance for code analysis (deferred; not a core feature)
- Cloud storage or server-side processing (data stays local)
- VCL variant (this concept is FMX)

## Context

- DX.Comply Pilot would live in the same repository as DX.Comply (`src/Pilot/`)
- The DX.Comply Engine package would be referenced, not duplicated
- `TDxComplyGenerator` would be called for SBOM generation as one step
- Target audience: Delphi developers at small and medium companies who write their own product documentation
- EU CRA applies in full in December 2027
- The concept should read as a practical guide, in clear language
- Persistence would be local JSON in the project directory (no database, no cloud, suitable for Git)

## Constraints

- **Framework**: FMX (Windows and macOS)
- **Engine dependency**: Use the DX.Comply Engine as it is (package reference, no fork)
- **Delphi version**: Delphi 13 (RAD Studio 37.0) for this concept
- **Persistence**: Local JSON files only (no SQLite, no cloud)
- **Report formats**: PDF, HTML, Markdown, ZIP
- **Naming**: Unit names follow DX.Comply conventions (dot notation, `DX.Comply.Pilot.*`)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| FMX over VCL | Windows and macOS | -- Pending |
| Dashboard and wizard navigation | Overview of the file, plus step by step notes | -- Pending |
| Local JSON persistence | Git-friendly, no server, portable between machines | -- Pending |
| Guided conformity editor | Help filling each section of a draft, not a blank form | -- Pending |
| Same repo as DX.Comply | Engine as a package reference, shared build | -- Pending |
| AI assistance deferred | Keep the first version on the documentation steps | -- Pending |
| Vulnerability dashboard deferred | Would need an online API | -- Pending |

---
*Last updated: 2026-10-06 to match the public wording: SBOM and build evidence, not a CRA certification.*
