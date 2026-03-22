# DX.Comply — Architecture

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
                          (optional Deep-Evidence build)
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
                          (output directory scan, SHA-256)
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
| `DX.Comply.Engine.pas` | `TDxComplyGenerator` facade — orchestrates the full pipeline |
| `DX.Comply.Engine.Intf.pas` | Shared types: `TProjectInfo`, `TArtefactInfo`, `TSbomMetadata` |
| `DX.Comply.ProjectScanner.pas` | Regex-based `.dproj` parser — extracts paths, toolchain, version, DllSuffix |
| `DX.Comply.BuildOrchestrator.pas` | Plan construction and script-based build execution (used by CLI fallback) |
| `DX.Comply.BuildEvidence.Reader.pas` | Reads MAP files, compiler CFG/RSP files; collects evidence items |
| `DX.Comply.MapFile.Reader.pas` | Extracts unit names from MAP segment entries (`M=Unit`) and line-number sections |
| `DX.Comply.UnitResolver.pas` | Resolves units to files, classifies origin (RTL/VCL/FMX/Local/ThirdParty), computes SHA-256/SHA-512 hashes |
| `DX.Comply.HashService.pas` | SHA-256 and SHA-512 via `System.Hash` |
| `DX.Comply.FileScanner.pas` | Scans build output directory for deliverable artefacts |
| `DX.Comply.CycloneDx.Writer.pas` | CycloneDX 1.5 JSON output |
| `DX.Comply.CycloneDx.XmlWriter.pas` | CycloneDX 1.5 XML output |
| `DX.Comply.Spdx.Writer.pas` | SPDX 2.3 JSON output |
| `DX.Comply.Report.HtmlWriter.pas` | HTML companion report |
| `DX.Comply.Report.MarkdownWriter.pas` | Markdown companion report |

## Deep-Evidence build

When enabled, DX.Comply triggers an explicit build of the target project with `DCC_MapFile=3` (detailed MAP) before collecting evidence. This ensures a MAP file exists even for projects that don't normally produce one.

### IDE plugin

The IDE plugin compiles the project directly via the OTA (`IOTAProject.ProjectBuilder`). Before the build starts, a confirmation dialog lets the user choose which build configuration to use as the basis for MAP generation. The active IDE configuration is pre-selected. DX.Comply temporarily sets `DCC_MapFile=3`, builds the project, and restores the original setting afterwards. The selected configuration is also restored after the build completes.

### CLI tool

The CLI tool does **not** compile the project. It expects the MAP file to already exist — either from a prior build with `DCC_MapFile=3` in the IDE or via MSBuild in a CI pipeline. This design keeps the CLI lightweight and enables support for legacy Delphi versions (including Delphi 7) where no IDE plugin is available.

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
- SHA-256 hash of the resolved file
- `net.developer-experts.dx-comply:origin` property (e.g. "Embarcadero RTL")
- `net.developer-experts.dx-comply:evidence` property (e.g. "DCU", "PAS", "MAP")
- `net.developer-experts.dx-comply:confidence` property (e.g. "Strong", "Heuristic")

## Test suite

172 DUnitX tests cover the full pipeline. Run:

```
build\Win32\Debug\DX.Comply.Tests.exe --no-pause
```

## Dependencies

The engine package depends only on Delphi RTL units (`System.*`, `Winapi.Windows`). No third-party libraries are required at runtime. DUnitX is used for tests and linked as a git submodule under `libs/DUnitX`.
