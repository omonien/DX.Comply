# DX.Comply – Product Requirements Document (PRD)
**Version:** 1.1
**Date:** 2026-03-07
**Product:** DX.Comply (Delphi IDE Plugin + CLI Toolset)
**Target market:** Delphi/RAD Studio developers, ISVs, software houses, compliance & security teams

---

## 1. Context & Background (CRA Status)
**Regulation (EU) 2024/2847** (Cyber Resilience Act) entered into force on **10 December 2024**.
It establishes horizontal cybersecurity requirements for all "products with digital elements"
placed on the EU market. Key obligations include: secure development processes, vulnerability
management, update provision, and **transparency about software components (SBOM)**.

**Timeline (Article 71):**
- **11 September 2026** — Vulnerability and incident reporting obligations (Article 14) begin.
  Applies to all products already on the market.
- **11 June 2026** — Conformity assessment bodies must notify competent authorities.
- **11 December 2027** — Full application date. All products placed on the EU market must comply.

**SBOM requirement (Annex I, Part II, point 1):** Manufacturers must identify and document
software components in a commonly used and machine-readable format covering at least the
top-level dependencies of the product.

For DX.Comply this means:
- A **standards-compliant release SBOM** is required for CRA evidence.
- A **deeper, unit-level composition inventory** is allowed and useful as internal evidence,
  but exceeds the CRA minimum.
- **Vulnerability information must not be embedded into the SBOM itself**. Vulnerability
  handling is a separate, dynamic process and any later warning feature must consume SBOM data
  as input rather than mixing advisory data into the SBOM payload.

DX.Comply addresses the SBOM transparency requirement for Delphi/RAD Studio projects and extends
it with Delphi-specific composition evidence. It does not cover vulnerability reporting
(Article 14), CE marking, or conformity assessment.

> Note: Implementing acts may further specify technical requirements.
> DX.Comply will support versioned CRA profiles to adapt as standards evolve.

---

## 2. Goal & Value
**DX.Comply** generates standards-compliant **SBOMs** and a deeper Delphi-specific composition
inventory for Delphi projects at the push of a button — integrated into the IDE and automatable
via CLI for CI/CD.
Benefits:
- CRA readiness & audit capability
- Transparency over shipped artefacts, packages, and the actual units compiled into the product
- Foundation for vulnerability management & supply chain security
- Reproducible compliance documentation per release
- Deterministic evidence of what exactly was compiled into a release build

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
- Internal evidence of the complete Delphi unit closure used by a product build
- Optional future warning when a known issue matches a unit name + hash combination

---

## 4. Scope (In/Out)
**In Scope**
- Standards-compliant SBOM generation (CycloneDX JSON/XML), optional SPDX JSON
- Extended Delphi composition evidence for directly and indirectly used units
- Build-evidence-driven project analysis (.dproj), compiler settings, search paths, package references, linker/package side artefacts, build output scan
- Unit origin grouping (Embarcadero RTL/VCL/FMX, local project, third-party, path-based unknown)
- Detection of the representation actually used for each unit (.pas, .dcu, .dcp, package)
- Hashes for shipped artefacts and resolved unit evidence
- Configurable include/exclude rules
- IDE integration (RAD Studio Wizard)
- CLI for CI/CD
- Metadata (product, version, build info)

**Out of Scope (v1)**
- Fully automated CVE / advisory matching (optional v2)
- Per-unit licence compliance (heuristic, v2)
- Cloud backend (DX.Comply is local/CI-first)
- Upload of source code or binary contents to external services

---

## 5. Functional Requirements
1. **IDE Integration**
   - Menu: *Project -> Generate SBOM (DX.Comply)*
   - Toolbar button
   - Progress & log in the IDE message window

2. **Project & Build Analysis**
   - Read .dproj (name, platform, configuration, output paths)
   - Resolve compiler search paths and package references
   - Detect runtime packages and relevant build artefacts (.exe, .dll, .bpl, .dcp, .map)
   - Prefer actual build evidence (compiler inputs, response files, compile notifications, linker/package side artefacts) over static folder scans
   - Capture enough evidence to distinguish the units actually used for the selected platform/configuration from units that are merely present in source folders

3. **Unit Closure Resolution**
   - Determine all units directly or indirectly used by the selected project build
   - Resolve whether a unit was consumed as source (.pas), compiled unit (.dcu), package unit,
     or package container (.dcp / .bpl)
   - Link each resolved unit to the path or package from which it originated
   - Record which evidence sources support the resolution and how certain the result is
   - Preserve warnings for ambiguous or unresolved units instead of silently dropping them

4. **Origin Classification**
   - Group resolved units by provenance:
     - Embarcadero RTL
     - Embarcadero VCL
     - Embarcadero FMX
     - Local project / workspace
     - Third-party library or package
     - Unknown / path-derived
   - Record package, directory, or vendor metadata where available
   - Preserve Delphi version/build metadata for Embarcadero-supplied units where detectable

5. **Evidence Hashing**
   - Compute a cryptographic hash for each shipped artefact
   - Compute a cryptographic hash for the file actually used to satisfy each unit reference
   - Support at least SHA-512 for release evidence; optional secondary compatibility hashes may be stored

6. **Output Generation**
   - Standards-compliant CycloneDX release SBOM
   - Extended Delphi composition evidence manifest for unit-level data
   - Metadata (timestamp, product, version, platform, configuration)
   - Component list, hashes, and dependency relationships where derivable
   - Keep static composition data separate from dynamic vulnerability/advisory data

7. **CLI**
   - `dxcomply --project=<.dproj> --format=cyclonedx-json --output=bom.json`
   - `--config=dxcomply.json`
   - Separate switches for standard SBOM output and extended evidence output

8. **Configuration**
   - Project-local file `.dxcomply.json`
   - Include/exclude patterns, formats, output paths
   - Evidence depth and origin classification options

9. **Optional Advisory Correlation (Post-v1)**
   - Optional local or hosted lookup of unit name + hash combinations against a maintained archive
   - Explicit user opt-in required before any online matching or account-based use
   - No source upload; only minimal metadata required for lookup

---

## 6. Non-Functional Requirements
- **Compatibility:** Delphi 11+ / RAD Studio 12.x, with forward support for Delphi 13 metadata where available
- **Performance:** Standard SBOM generation should remain fast; deep unit evidence mode may take longer but must stay practical for CI/CD
- **Determinism:** Reproducible results per build
- **Security:** No telemetry; local processing only
- **Extensibility:** Writer interface for new formats
- **Privacy:** Future online correlation features require explicit opt-in and must not upload source contents

---

## 7. Architecture (Summary)
```
DX.Comply
 +- Core
 |   +- ProjectScanner
 |   +- BuildEvidenceReader
 |   +- UnitResolver
 |   +- OriginClassifier
 |   +- HashService
 |   +- SbomWriter
 |   +- EvidenceWriter
 +- IDE Plugin (ToolsAPI Wizard)
 +- CLI (dxcomply)
```
- Facade: `TDxComplyGenerator`
- Writer interfaces: `ISbomWriter` (CycloneDX, SPDX)
- Evidence layer separated from the standards-compliant release SBOM
- Resolver contracts separated from the public engine facade to keep the main engine API stable
- Config: `.dxcomply.json`

---

## 8. Formats & Standards
- **CycloneDX 1.6+** (JSON/XML) — primary target for release SBOMs
- **SPDX 3.x JSON** — optional / later
- Release evidence hash: **SHA-512**
- Optional compatibility hash: **SHA-256**
- Optional: purl (where applicable)
- Static composition evidence and dynamic vulnerability/advisory data remain separate

---

## 9. Roadmap
**v1 (MVP)**
- IDE + CLI, CycloneDX release SBOM, artefact scan, deep unit evidence, hashes, origin grouping

**v1.1**
- Evidence diff between releases
- Better package / vendor identification
- HTML evidence report

**v2**
- Optional advisory / CVE matching with explicit opt-in
- Licence heuristics
- Policy checks (allow/deny lists)

---

## 10. Acceptance Criteria
- SBOM validated against CycloneDX schema
- Reproducible results with identical builds
- IDE workflow without errors
- CLI executable in GitHub Actions / GitLab CI
- For a sample Delphi project, all resolved units are classified by origin and evidence type
- Each resolved unit entry contains a traceable file reference and hash
- No vulnerability/advisory data is embedded into the SBOM document itself

---

## 11. Risks & Assumptions
- Compiler evidence may be incomplete without map/package metadata -- graceful degradation required
- Actual unit closure requires combining compiler, linker, package, and project metadata rather than relying on a single Delphi API
- Dependency heuristics are not 100% accurate -- marked as "best effort"
- .dproj structure varies per project -- robust fallbacks required
- CRA detail regulations may be refined -- versioned CRA profiles planned
- Distinguishing source-used vs. DCU-used units may require Delphi-version-specific heuristics
- Any hosted advisory matching feature must be opt-in and privacy-preserving

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
dxcomply --project=MyApp.dproj --format=cyclonedx-json --output=bom.json --evidence-output=bom.evidence.json
dxcomply --ci --config=.dxcomply.json
```

---

## 15. Regulatory & Technical References
- Regulation (EU) 2024/2847 (Cyber Resilience Act), Annex I Part II point (1), Articles 13, 14, 52, 71
- European Commission CRA overview: https://digital-strategy.ec.europa.eu/en/policies/cyber-resilience-act
- BSI TR-03183-2 (Germany, national technical interpretation for CRA-related SBOM practice)
- ENISA SBOM Landscape Analysis (component inventories as input for vulnerability correlation)
