# DX.Comply: Architecture

## Overview

DX.Comply is structured as three deliverables that share a single core engine:

```
src/
  DX.Comply.Engine.dpk/.dproj    Runtime package (core engine, RTL-only)
  DX.Comply.IDE.dpk/.dproj       Design-time IDE package (VCL + ToolsAPI)
  dxcomply.dpr/.dproj             Console application (CLI)
```

The **Engine package** has no UI dependencies and can be consumed by both the IDE plugin and the CLI.

## Engine pipeline

Every SBOM generation follows the same pipeline, regardless of whether it was triggered from the IDE or the command line:

```
 .dproj ──► ProjectScanner ──► TProjectInfo
                                    │
                                    ▼
                            BuildOrchestrator
                          (optional MAP file build)
                                    │
                                    ▼
                          BuildEvidenceReader ──► TBuildEvidence
                          (MAP, CFG, RSP files)
                                    │
                                    ▼
                            UnitResolver ──► TCompositionEvidence
                          (search paths, hashes, origin classification)
                                    │
                                    ▼
                            FileScanner ──► TArtefactList
                          (named output, its directory, SHA-256)
                                    │
                                    ▼
                         ┌──────────┴──────────┐
                         │                     │
                   SbomWriter            ReportWriter
              (CycloneDX/SPDX)        (HTML + Markdown)
```

## Key components

| Unit | Responsibility |
|------|---------------|
| `DX.Comply.Engine.pas` | `TDxComplyGenerator` facade. Orchestrates the full pipeline |
| `DX.Comply.Engine.Intf.pas` | Shared types: `TProjectInfo`, `TArtefactInfo`, `TSbomMetadata` |
| `DX.Comply.ComponentManifest.pas` | Optional components.json: match units to libraries, licences, and package URLs |
| `DX.Comply.ProjectScanner.pas` | Regex-based `.dproj` parser. Extracts paths, toolchain, version, DllSuffix |
| `DX.Comply.BuildOrchestrator.pas` | Plan construction and script-based build execution (used by CLI fallback) |
| `DX.Comply.BuildEvidence.Reader.pas` | Reads MAP files, compiler CFG/RSP files; collects evidence items |
| `DX.Comply.MapFile.Reader.pas` | Extracts unit names from MAP segment entries (`M=Unit`) and line-number sections |
| `DX.Comply.UnitResolver.pas` | Resolves units to files, classifies origin (RTL/VCL/FMX/Local/ThirdParty), computes SHA-256/SHA-512 hashes |
| `DX.Comply.HashService.pas` | SHA-256 and SHA-512 via `System.Hash` |
| `DX.Comply.FileScanner.pas` | Lists the named project output and binaries in that directory |
| `DX.Comply.CycloneDx.Writer.pas` | CycloneDX 1.6 JSON output |
| `DX.Comply.CycloneDx.XmlWriter.pas` | CycloneDX 1.6 XML output |
| `DX.Comply.Spdx.Writer.pas` | SPDX 2.3 JSON output |
| `DX.Comply.Report.HtmlWriter.pas` | HTML companion report |
| `DX.Comply.Report.MarkdownWriter.pas` | Markdown companion report |
| `DX.Comply.Report.Intf.pas` | Report writer interface and shared report types |
| `DX.Comply.Report.Support.pas` | Common report helper functions (HTML escaping, formatting) |
| `DX.Comply.BuildEvidence.Intf.pas` | Build evidence types and interfaces |
| `DX.Comply.Schema.Validator.pas` | Post-generation structural check of the SBOM (not an official schema) |
| `DX.Comply.CLI.Options.pas` | CLI argument parser (`--project`, `--format`, `--map-dir`, etc.) |

## MAP file generation

DX.Comply always performs a **Deep-Evidence analysis**, using the compiler-generated MAP file to resolve linked units (PAS/DCU) with their dependencies, SHA-256 hashes where the file could be opened, and origin classification. The MAP file is the source of truth for dependency resolution.

When a MAP file does not yet exist, DX.Comply can optionally trigger a build with `DCC_MapFile=3` (detailed MAP) to generate one. This is an implementation detail. The analysis quality is the same regardless of how the MAP file was produced.

### IDE plugin

The IDE plugin compiles the project directly via the OTA (`IOTAProject.ProjectBuilder`). Before the build starts, a confirmation dialog lets the user choose which build configuration to use as the basis for MAP generation. The active IDE configuration is pre-selected. DX.Comply temporarily sets `DCC_MapFile=3`, builds the project, and restores the original setting afterwards. The selected configuration is also restored after the build completes.

### CLI tool

The CLI tool does **not** compile the project. It expects the MAP file to already exist, either from a prior build with `DCC_MapFile=3` in the IDE or via MSBuild in a CI pipeline. `--project` may be a `.dproj`, `.dpk`, or `.groupproj`. A Delphi 7 `.dpr` is also accepted when the sibling `.dof` and `.cfg` are present. A `.dof` alone is not a project file. This keeps the CLI independent of the IDE.

## Unit origin classification

Every unit found in the MAP file is classified by origin:

| Origin | Heuristic |
|--------|-----------|
| Embarcadero RTL | Resolved path under Delphi root, or namespace `System.*`, `Winapi.*`, `Data.*`, etc. |
| Embarcadero VCL | Namespace `Vcl.*` or resolved under `\source\vcl\` |
| Embarcadero FMX | Namespace `Fmx.*` or resolved under `\source\fmx\` |
| Local project | Resolved path under project directory, or no known Embarcadero namespace |
| Third party | Resolved path outside both project and Delphi root |

## SBOM output structure

Each resolved unit is emitted as a CycloneDX `component` with `type: "library"`, carrying:
- SHA-256 and SHA-512 hashes of the resolved file, when the file could be opened
- `bsi:component:filename`, `bsi:component:executable`, `bsi:component:archive`, and `bsi:component:structured` when the component has a file name
- `net.developer-experts.dx-comply:origin` property (e.g. "Embarcadero RTL")
- `net.developer-experts.dx-comply:evidence` property (e.g. "DCU", "PAS", "MAP")
- `net.developer-experts.dx-comply:confidence` property (e.g. "Strong", "Heuristic")

When `--manifest` or the `manifest` key points at a components file, matched units stay in the document and are linked from one library component (name, version, supplier, licence, package URL, type). The program that was built depends on that library. Own-code rules keep those units with the program. The units come from the MAP file, so a Delphi 7 `.dpr` uses the same list. Matching and licence classification live in `DX.Comply.ComponentManifest.pas`. The CycloneDX and SPDX writers call that unit.

CycloneDX 1.6 and SPDX 2.3 also carry the BSI TR-03183-2 fields DX.Comply can support from evidence. SHA-512 sits next to SHA-256, and a deployable file also carries that SHA-512 on an external reference of type distribution. The SBOM creator contact is written only from `sbomCreator` or `--sbom-creator`, as `metadata.manufacturer`. SPDX stays at 2.3. SPDX 3.0.1 is out of scope. Direct dependencies stay the grouped graph, and CycloneDX marks that graph incomplete. Details, including the fields that are left out, are in [BSI-TR-03183-2.md](BSI-TR-03183-2.md). This is not a certification against the technical guideline.

## Test suite

DUnitX tests cover the full pipeline. Run:

```
build\Win32\Debug\DX.Comply.Tests.exe --no-pause
```

## Dependencies

The engine package depends only on Delphi RTL units (`System.*`, `Winapi.Windows`). No third-party libraries are required at runtime. DUnitX is used for tests and linked as a git submodule under `libs/DUnitX`.
