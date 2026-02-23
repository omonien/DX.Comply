# DX.Comply – Product Requirements Document (PRD)
**Version:** 1.0
**Date:** 2026-02-23
**Product:** DX.Comply (Delphi IDE Plugin + CLI Toolset)
**Target market:** Delphi/RAD Studio developers, ISVs, software houses, compliance & security teams

---

## 1. Context & Background (CRA Status)
The EU **Cyber Resilience Act (CRA)** has been adopted and is in force. Most obligations apply after
a transition period (from **late 2027**), with some requirements (e.g. reporting obligations for
actively exploited vulnerabilities) taking effect earlier. For manufacturers of "products with
digital elements" this means, among other things: secure development processes, vulnerability
management, update provision, and **transparency about software components (SBOM)**.
DX.Comply addresses these transparency and process requirements for Delphi/RAD Studio projects.

> Note: Specific deadlines and details may be further defined through implementing acts.
> DX.Comply will support versioned CRA profiles.

---

## 2. Goal & Value
**DX.Comply** generates standards-compliant **SBOMs (CycloneDX, optionally SPDX)** for Delphi
projects at the push of a button — integrated into the IDE and automatable via CLI for CI/CD.
Benefits:
- CRA readiness & audit capability
- Transparency over third-party components & shipped artefacts
- Foundation for vulnerability management & supply chain security
- Reproducible compliance documentation per release

---

## 3. Target Groups & Use Cases
**Target Groups**
- ISVs using Delphi/RAD Studio
- Enterprise teams with CRA compliance obligations
- Security/compliance officers
- CI/CD teams

**Use Cases**
- "Generate SBOM" in the project context menu
- Automatic SBOM generation during release build (CLI)
- Comparison of SBOMs between releases (delta)
- Evidence submission to customers / authorities

---

## 4. Scope (In/Out)
**In Scope**
- SBOM generation (CycloneDX JSON/XML), optional SPDX JSON
- Project analysis (.dproj), build output scan
- Hashes (SHA-256) for shipped artefacts
- Configurable include/exclude rules
- IDE integration (RAD Studio Wizard)
- CLI for CI/CD
- Metadata (product, version, build info)

**Out of Scope (v1)**
- Fully automated CVE matching (optional v2)
- Per-unit licence compliance (heuristic, v2)
- Cloud backend (DX.Comply is local/CI-first)

---

## 5. Functional Requirements (MVP)
1. **IDE Integration**
   - Menu: *Project -> Generate SBOM (DX.Comply)*
   - Toolbar button
   - Progress & log in the IDE message window

2. **Project Analysis**
   - Read .dproj (name, platform, configuration, output paths)
   - Detection of runtime packages
   - Heuristic for third-party paths

3. **Artefact Scan**
   - Recursive scan of build output
   - Detection: .exe, .dll, .bpl, .dcp, resources
   - File sizes, paths, hashes

4. **SBOM Writer**
   - CycloneDX 1.5 (JSON/XML)
   - Metadata (timestamp, product, version)
   - Component list + hashes
   - Dependencies (basic graph)

5. **CLI**
   - `dxcomply --project=<.dproj> --format=cyclonedx-json --output=bom.json`
   - `--config=dxcomply.json`

6. **Configuration**
   - Project-local file `.dxcomply.json`
   - Include/exclude patterns, formats, output paths

---

## 6. Non-Functional Requirements
- **Compatibility:** Delphi 11+ / RAD Studio 12.x
- **Performance:** SBOM generation < 3s for typical projects
- **Determinism:** Reproducible results per build
- **Security:** No telemetry; local processing only
- **Extensibility:** Writer interface for new formats

---

## 7. Architecture (Summary)
```
DX.Comply
 +- Core (ProjectScanner, FileScanner, HashService, SbomWriter)
 +- IDE Plugin (ToolsAPI Wizard)
 +- CLI (dxcomply)
```
- Facade: `TDxComplyGenerator`
- Writer interfaces: `ISbomWriter` (CycloneDX, SPDX)
- Config: `.dxcomply.json`

---

## 8. Formats & Standards
- **CycloneDX 1.5** (JSON/XML) — primary
- **SPDX 2.3 JSON** — optional
- Hash: **SHA-256**
- Optional: purl (where applicable)

---

## 9. Roadmap
**v1 (MVP)**
- IDE + CLI, CycloneDX, artefact scan, hashes

**v1.1**
- SPDX export, HTML report
- SBOM diff between releases

**v2**
- Optional CVE matching (external feeds)
- Licence heuristics
- Policy checks (allow/deny lists)

---

## 10. Acceptance Criteria
- SBOM validated against CycloneDX schema
- Reproducible results with identical builds
- IDE workflow without errors
- CLI executable in GitHub Actions / GitLab CI

---

## 11. Risks & Assumptions
- Dependency heuristics are not 100% accurate -- marked as "best effort"
- .dproj structure varies per project -- robust fallbacks required
- CRA detail regulations may be refined -- versioned CRA profiles planned

---

## 12. Licence & Distribution
- Open Core (MIT) or dual licence (Community + Pro)
- Marketplace/installer for RAD Studio
- Signed releases

---

## 13. Success Metrics (KPIs)
- Time-to-SBOM < 3s
- Adoption in >= X projects
- Reduction of manual compliance effort
- Positive audit feedback

---

## 14. CLI Examples
```
dxcomply --project=MyApp.dproj --format=cyclonedx-json --output=bom.json
dxcomply --ci --config=.dxcomply.json
```
