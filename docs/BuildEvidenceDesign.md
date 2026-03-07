# DX.Comply – Build Evidence Design

## Goal
Define the first concrete Delphi-facing model for build-evidence-driven unit resolution without committing to implementation details too early.

Implementation note: parts of this design are already implemented. For the
current handover state, see `docs/CurrentStatus.md`.

## Design Principles
- Use the real build as the source of truth.
- Prefer an explicit Deep-Evidence build with detailed `.map` generation whenever possible.
- Separate public engine contracts from deep evidence contracts.
- Preserve ambiguity instead of hiding it.
- Keep evidence provenance explicit and traceable.
- Align with the existing code style: records with `Create` / `Free` where owned lists are needed, plus small focused interfaces.

## Recommended Unit Boundaries
- `DX.Comply.Engine.Intf.pas`
  - keep existing public SBOM-facing contracts
- `DX.Comply.BuildEvidence.Intf.pas`
  - evidence enums, records, and interfaces
- `DX.Comply.BuildEvidence.Reader.pas`
  - build-evidence collection from `.dproj`, build side products, and IDE/CLI inputs
- `DX.Comply.UnitResolver.pas`
  - unit closure and representation resolution
- `DX.Comply.OriginClassifier.pas`
  - provenance grouping
- `DX.Comply.Evidence.Writer.pas`
  - sidecar manifest output

## Proposed Core Enums

### `TBuildEvidenceSourceKind`
Describes where a piece of evidence came from.

- `besProjectMetadata`
- `besCompilerCommandLine`
- `besCompilerResponseFile`
- `besCompileNotification`
- `besMapFile`
- `besDcuFile`
- `besDcpFile`
- `besBplFile`
- `besSearchPathFallback`
- `besManualOverride`

### `TUnitEvidenceKind`
Describes the representation actually used for a unit.

- `uekPas`
- `uekDcu`
- `uekDcp`
- `uekBpl`
- `uekUnknown`

### `TUnitOriginKind`
Describes the provenance group shown to the user.

- `uokEmbarcaderoRtl`
- `uokEmbarcaderoVcl`
- `uokEmbarcaderoFmx`
- `uokLocalProject`
- `uokThirdParty`
- `uokUnknown`

### `TResolutionConfidence`
Makes resolver certainty visible.

- `rcAuthoritative`
- `rcStrong`
- `rcHeuristic`
- `rcUnknown`

## Proposed Core Records

### `TBuildPathSet`
Normalized paths for the selected platform/configuration.

- `OutputDir`
- `DcuOutputDir`
- `DcpOutputDir`
- `BplOutputDir`
- `MapFilePath`
- `ResponseFilePath`

`MapFilePath` is important enough to be treated as a first-class build artefact path. In Deep-Evidence mode, the pipeline should prefer consuming a detailed `.map` file before falling back to weaker sources.

### `TBuildEvidenceItem`
Represents one concrete evidence artifact or input.

- `SourceKind: TBuildEvidenceSourceKind`
- `DisplayName: string`
- `FilePath: string`
- `PackageName: string`
- `UnitName: string`
- `Detail: string`

### `TBuildEvidence`
Normalized evidence bundle produced before unit resolution.

- `ProjectPath: string`
- `Platform: string`
- `Configuration: string`
- `Paths: TBuildPathSet`
- `SearchPaths: TList<string>`
- `UnitScopeNames: TList<string>`
- `RuntimePackages: TList<string>`
- `EvidenceItems: TList<TBuildEvidenceItem>`
- `Warnings: TList<string>`

### `TResolvedUnitInfo`
Final per-unit record used by hashing, classification, and evidence writing.

- `UnitName: string`
- `EvidenceKind: TUnitEvidenceKind`
- `OriginKind: TUnitOriginKind`
- `Confidence: TResolutionConfidence`
- `ResolvedPath: string`
- `ContainerPath: string`
- `PackageName: string`
- `PrimaryHashSha512: string`
- `SecondaryHashSha256: string`
- `EvidenceSources: TArray<TBuildEvidenceSourceKind>`
- `Warnings: TArray<string>`

### `TCompositionEvidence`
Top-level sidecar model.

- `ProjectName: string`
- `ProjectVersion: string`
- `Platform: string`
- `Configuration: string`
- `GeneratedAt: string`
- `Units: TList<TResolvedUnitInfo>`
- `Warnings: TList<string>`

## Proposed First Interfaces

### `IBuildEvidenceReader`
Responsibility: gather normalized build evidence.

Suggested methods:
- `function Read(const AProjectInfo: TProjectInfo): TBuildEvidence;`

Optional future extension:
- `function SupportsLiveIdeEvidence: Boolean;`

### `IUnitResolver`
Responsibility: compute direct + transitive unit closure and representation resolution.

Suggested methods:
- `function Resolve(const AProjectInfo: TProjectInfo; const ABuildEvidence: TBuildEvidence): TCompositionEvidence;`

Alternative split if the implementation grows:
- `ResolveUnits(...) : TList<TResolvedUnitInfo>`
- `BuildCompositionEvidence(...) : TCompositionEvidence`

### `IOriginClassifier`
Responsibility: assign a provenance group to one resolved unit.

Suggested methods:
- `function Classify(const AProjectInfo: TProjectInfo; const AResolvedUnit: TResolvedUnitInfo): TUnitOriginKind;`

### `IEvidenceWriter`
Responsibility: serialize the sidecar evidence manifest.

Suggested methods:
- `function Write(const AOutputPath: string; const AEvidence: TCompositionEvidence): Boolean;`

## Evidence Resolution Rules

### `.map`
Use as the primary **membership** source when a detailed map file is available.

- A detailed `.map` can prove that code from a unit ended up in the linked result.
- A `.map` does **not** by itself prove whether the unit originated from `.pas`, `.dcu`, `.dcp`, or `.bpl`.
- Therefore, `.map` should seed the unit set first, and representation/origin resolution should refine it afterwards.

### `.pas`
Use when:
- the active build inputs prove source compilation, or
- the unit resolves to source with stronger evidence than any compiled/package candidate.

### `.dcu`
Use when:
- the unit is satisfied by a concrete compiled unit in the effective search paths or output directories,
- and no stronger source-compilation proof overrides it.

### `.dcp`
Use when:
- package metadata is the strongest proof for unit membership,
- especially when the package identity is required but no individual `.dcu` is attributable.

### `.bpl`
Use when:
- runtime package/container provenance is what the build proves most directly.

### `unknown`
Use when:
- DX.Comply can name the unit but cannot safely prove the representation actually used.

## Integration With Current Code

### `TProjectInfo`
Already implemented additions:
- `SearchPaths: TList<string>`
- `UnitScopeNames: TList<string>`
- `DcuOutputDir: string`
- `DcpOutputDir: string`
- `BplOutputDir: string`
- `MapFilePath: string`
- `Warnings: TList<string>`

These additions keep `.dproj` parsing results reusable and avoid reparsing in later phases.

### `TDxComplyGenerator`
Current pipeline direction:
1. `IProjectScanner.Scan`
2. if Deep Evidence is enabled, optionally ensure an explicit build with detailed `.map` output
3. `IBuildEvidenceReader.Read`
4. use `.map`-driven membership seeding when available
5. `IUnitResolver.Resolve`
6. `IOriginClassifier.Classify`
7. `IHashService` for artefacts and unit evidence
8. `ISbomWriter.Write`
9. `IEvidenceWriter.Write`

### `TFileScanner`
Keep it limited to shipped artefacts. Unit resolution should not depend on a recursive directory scan of the build output alone.

## Completed Foundation Slices

The following foundation slices are already implemented:

1. `DX.Comply.BuildEvidence.Intf.pas`
2. `TProjectInfo` expansion for build/search-path metadata
3. `DX.Comply.BuildEvidence.Reader.pas`
4. dedicated `DX.Comply.MapFile.Reader.pas`
5. `.map`-seeded `DX.Comply.UnitResolver.pas`
6. first `DX.Comply.BuildOrchestrator.pas` slice

## Next Active Slices

The next implementation slices should focus on:

1. representation refinement for map-derived units
2. `OriginClassifier`
3. `EvidenceWriter`
4. Deep-Evidence CLI exposure

## Non-Goals For The First Slice
- Full parsing of every Delphi package format
- Online advisory correlation
- HTML reporting
- Replacing the existing artefact scan path for the release SBOM immediately

## Result
This design gives DX.Comply a clear next coding step: introduce the evidence contracts first, then move the existing engine from artefact-scan-driven orchestration toward a build-evidence-driven pipeline.

That transition has now started and the repository contains the first working
MAP-first and Build-Orchestrator foundation slices.