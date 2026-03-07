# DX.Comply – Release & Milestone Plan

## Goal
Deliver a stable MVP (v1.0) for CRA-facing SBOM generation plus deep Delphi composition evidence,
followed by incremental releases for diffing and optional advisory correlation.

## Current Progress Snapshot (2026-03-07)

Completed foundation work:

- build-evidence contracts
- `TProjectInfo` expansion for search-path/output/MAP metadata
- `BuildEvidenceReader`
- `MapFileReader`
- first `UnitResolver` slice with MAP-derived unit seeding
- first `Build-Orchestrator` slice for explicit Deep-Evidence builds

Next milestone focus:

- representation refinement
- `OriginClassifier`
- `EvidenceWriter`
- Deep-Evidence CLI exposure

## Milestones
### M1 – Core (Week 1–2)
- Evidence contracts (`DX.Comply.BuildEvidence.Intf`)
- ProjectScanner extension (.dproj, search paths, output paths, runtime packages)
- BuildEvidenceReader (compiler/package evidence, response files, side artefacts)
- UnitResolver (initial MAP-seeded slice done; full direct + transitive closure still pending)
- OriginClassifier (RTL/VCL/FMX/local/third-party)
- HashService reuse (SHA-512 + optional SHA-256)
- CycloneDX Writer (release SBOM)
- Evidence Writer (unit-level sidecar manifest)

### M2 – IDE (Week 3)
- ToolsAPI Wizard
- Menu / toolbar
- Logging & error handling
- Quick SBOM vs. Deep Evidence modes

### M3 – CLI (Week 4)
- dxcomply CLI
- CI documentation (GitHub Actions / GitLab CI)
- Separate `--output` and `--evidence-output`

### M4 – Stabilisation (Week 5)
- Performance optimisation
- Schema validation
- Edge cases
- Ambiguous unit resolution handling
- Confidence scoring and evidence-source traceability

### M5 – Release (Week 6)
- Signed binaries
- Installer
- README / docs
- Example projects
- Evidence sample output for audits

## Post-v1
- v1.1: Evidence diff, better vendor/package identification, HTML evidence report
- v2.0: Optional advisory/CVE matching (opt-in), licence heuristics, policy checks
