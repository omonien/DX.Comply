# DX.Comply – Implementation Plan for Deep Delphi Composition Evidence

## Goal
Extend DX.Comply from a build artefact scanner to a two-layer evidence generator:

1. **Release SBOM** — standards-compliant, CRA-facing output.
2. **Composition Evidence Manifest** — Delphi-specific, unit-level internal evidence.

The guiding principle is: **CRA minimum outside, deep Delphi evidence inside.**

## Current Implementation Status (2026-03-07)

Already implemented:

- build-evidence contracts and evidence container types
- `TProjectInfo` expansion for search paths, unit scopes, output paths, and `MapFilePath`
- `BuildEvidenceReader` with MAP-derived evidence items
- dedicated `MapFileReader`
- initial `UnitResolver` with `.map`-seeded unit creation
- first `BuildOrchestrator` slice with optional explicit Deep-Evidence build execution

Still pending from the full target plan:

- representation refinement for resolved units
- `OriginClassifier`
- `EvidenceWriter`
- dedicated CLI switches for Deep Evidence
- end-to-end verification on a machine with Delphi installed

## Key Product Decisions

### 1. Two output layers instead of one overloaded SBOM
- Keep the release SBOM standards-compliant and easy to present to auditors or authorities.
- Store Delphi-specific details in a separate sidecar file, for example `bom.evidence.json`.
- Do not embed dynamic vulnerability/advisory data in the SBOM itself.

### 2. Evidence should reflect the actual build, not just source folders
- Prefer compiler/linker evidence over static folder scans.
- Build analysis must resolve the units actually used for the selected platform/configuration.
- Warnings are acceptable when certainty is not possible; silent guessing is not.

### 3. Privacy by default
- All scanning and hashing remain local by default.
- Any future online warning or correlation service must be explicit opt-in.
- No source upload; only unit name, origin metadata, version/build hints, and hashes if the user consents.

### 4. Build evidence is the truth model
- The authoritative source is the real build context, not a folder walk and not the LSP.
- DX.Comply should combine compiler inputs, linker/package side artefacts, and package metadata.
- Static search-path resolution remains a fallback only when stronger evidence is missing.
- Each resolved unit must carry a confidence level and the evidence sources that support the result.
- For **Deep Evidence**, DX.Comply may explicitly trigger a build and require a detailed `.map` file as a primary linker evidence source.

## Technical Architecture

### Proposed new engine units
- `DX.Comply.BuildEvidence.Intf.pas`
- `DX.Comply.BuildEvidence.Reader.pas`
- `DX.Comply.UnitResolver.pas`
- `DX.Comply.OriginClassifier.pas`
- `DX.Comply.Evidence.Writer.pas`
- `DX.Comply.Evidence.Model.pas`

### Existing units to extend
- `DX.Comply.ProjectScanner.pas`
- `DX.Comply.FileScanner.pas`
- `DX.Comply.HashService.pas`
- `DX.Comply.CycloneDx.Writer.pas`
- `DX.Comply.Engine.Intf.pas`
- `DX.Comply.Engine.pas`

### Boundary recommendation
- Keep `DX.Comply.Engine.Intf.pas` small and stable for the public facade.
- Place the new evidence model and resolver contracts into dedicated units instead of overloading the existing engine interface unit.
- Treat `DX.Comply.Engine.pas` as an orchestration facade that wires the new readers/resolvers together.

## Evidence Source Priority

### Strongest sources first
1. Explicit Deep-Evidence build evidence (actual compiler command line, response file, compile notifications, forced detailed `.map` output)
2. Linker/package side artefacts (`.map`, `.dcp`, `.bpl`, generated `.dcu`)
3. Project metadata (`.dproj`, runtime packages, output paths, search paths, unit scope names)
4. Search-path-based resolution heuristics

### Representation-specific rules
- `.pas`: authoritative when the build evidence or compiler inputs show source compilation for the unit
- `.dcu`: strong evidence when a compiled unit is resolved from the active search paths or output directories
- `.dcp`: strong evidence for package membership and package-to-unit relationships
- `.bpl`: strong evidence for runtime container provenance and package identity
- `unknown`: preserved when the resolver cannot prove the representation safely

### Confidence policy
- `authoritative`: supported by actual build evidence or explicit package metadata
- `strong`: supported by deterministic file/package resolution but without direct compiler proof
- `heuristic`: inferred from search paths or naming conventions only
- `unknown`: insufficient evidence, kept visible for the user

## Phase Plan

### Phase 1 — Evidence model and interfaces
Define the internal data structures:
- `TResolvedUnitInfo`
- `TUnitOriginKind`
- `TUnitEvidenceKind` (`pas`, `dcu`, `dcp`, `bpl`, `unknown`)
- `TBuildEvidenceSourceKind`
- `TResolutionConfidence`
- `TCompositionEvidence`

Each resolved unit should contain at least:
- unit name
- resolved file path
- evidence kind
- origin group
- package/container name
- platform/configuration
- primary hash (SHA-512)
- optional secondary hash (SHA-256)
- confidence / warning flags

Recommended first contracts:
- `IBuildEvidenceReader`
- `IUnitResolver`
- `IOriginClassifier`
- `IEvidenceWriter`

### Phase 2 — Build evidence collection
Implement a `BuildEvidenceReader` that gathers the strongest available proof of what was actually used in a build:
- parse `.dproj` for search paths, package references, output folders, and compiler settings
- determine the expected `.map` location for the selected build and read it when present
- capture compiler command line / response file information when available
- read linker/compiler side products such as `.map`, `.dcp`, `.bpl`, and output metadata when available
- collect package-to-unit and binary-to-unit relationships where derivable

Deep-Evidence preference:
1. trigger or consume an explicit build with detailed `.map` output
2. read `.map`-derived unit evidence first
3. enrich with package metadata and search-path resolution only where the `.map` is silent

Fallback order:
1. compiler/linker evidence
2. package metadata
3. search-path-based file resolution

Expected outputs of Phase 2:
- normalized build paths (`BplOutput`, `DcpOutput`, `DcuOutput`, main output)
- search paths and unit scope names for the selected platform/configuration
- runtime package list and package containers seen in the build
- list of evidence items that later resolution steps can cite explicitly

### Phase 3 — Unit resolution
Implement a `UnitResolver` that:
- computes the direct and transitive unit closure
- determines whether each unit came from source, compiled unit, or package container
- records ambiguous resolutions instead of hiding them

Resolver rules:
- use `.map`-derived unit membership as the first seed set when a detailed map is available
- prefer build-proven representations over search-path guesses
- keep multiple candidate sources until a stronger source removes ambiguity
- attach the exact evidence source kinds used to reach a result

### Phase 4 — Origin classification
Implement an `OriginClassifier` with deterministic rules:
- Embarcadero RTL
- Embarcadero VCL
- Embarcadero FMX
- local workspace/project
- third-party
- unknown

Matching signals:
- known Embarcadero library paths
- package names
- source/DCU directory roots
- optional vendor override configuration

### Phase 5 — Hashing and manifests
Extend hashing so that:
- release artefacts are hashed
- each resolved unit evidence file is hashed
- hashes are written both to the sidecar evidence manifest and, where appropriate, to the release SBOM

Outputs:
- `bom.json` — release SBOM
- `bom.evidence.json` — Delphi composition evidence

### Phase 6 — IDE and CLI exposure
Add separate modes:
- **Quick SBOM** — fast CRA-facing output
- **Deep Evidence** — full unit-level analysis

Recommended CLI shape:
- `--output=bom.json`
- `--evidence-output=bom.evidence.json`
- `--evidence-depth=top-level|transitive`
- `--origin-policy=auto|strict|lenient`

### Phase 7 — Diff and audit tooling
After evidence generation is stable:
- compare evidence manifests between releases
- show newly added, removed, or changed units
- highlight hash changes for same unit names

### Phase 8 — Optional advisory correlation service
Only after explicit user consent and account setup:
- upload minimal lookup material only
- match unit name + hash against a hosted archive
- return warnings when known issues affect a matching fingerprint

This service must stay logically separate from SBOM generation.

## Implementation Risks
- Delphi does not expose one single canonical API for “all units actually compiled into this binary”; multiple evidence sources may need to be combined.
- `.pas` and `.dcu` precedence can vary by search path order and package structure.
- Delphi-version-specific package metadata may require compatibility layers.
- Overly aggressive guessing would damage trust; uncertain results must remain visible.

## Recommended Delivery Order
1. Evidence model
2. Build evidence reader
3. Unit resolver
4. Origin classifier
5. Evidence writer
6. CLI switches
7. IDE UI
8. Release diff
9. Optional advisory service

## Current-Engine Integration Notes
- Extend `TProjectInfo` so later phases can carry search paths, unit scope names, and output directories without reparsing the `.dproj` multiple times.
- Extend `TProjectInfo` with the expected or resolved `MapFilePath` so the reader and resolver can treat the `.map` as a first-class artefact.
- Keep `TFileScanner` focused on shipped artefacts; do not overload it with unit-resolution logic.
- Use `THashService` unchanged as the shared hash provider for both release artefacts and resolved unit evidence.
- Refactor `TDxComplyGenerator.Generate` into an explicit pipeline:
  1. scan project metadata
  2. optionally ensure a Deep-Evidence build
  3. read build evidence
  4. resolve unit closure
  5. classify origin
  6. hash artefacts and resolved unit evidence
  7. write release SBOM and evidence sidecar

## Design Reference
See `docs/BuildEvidenceDesign.md` for the concrete first-pass Delphi records, enums, and interfaces proposed for implementation.

## Success Criteria
- A release SBOM remains standards-compliant and CRA-usable.
- A sidecar evidence manifest can explain which units ended up in the build.
- Unit origins are grouped in a way that is understandable to Delphi developers.
- Hash-based diffing between releases becomes possible.
- A future warning service can operate on minimal metadata instead of uploaded source code.