# DX.Comply: Delphi Coding Style Guide

## Source
Derived from the [omonien/DelphiStandards](https://github.com/omonien/DelphiStandards) style guide.

## File Format
- `.pas` files: **UTF-8 with BOM**, CRLF line endings
- `.dfm`/`.fmx`: Delphi codepoint syntax for non-ASCII (`#1234`)

## Naming Conventions

### Units
- Dot-notation hierarchy: `DX.Comply.Engine`, `DX.Comply.IDE.Wizard`
- Forms: `.Form.pas`, Data Modules: `.DM.pas`

### Types
| Type | Prefix | Example |
|---|---|---|
| Class | `T` | `TProjectScanner` |
| Interface | `I` | `IHashService` |
| Record | `T` | `TArtefactInfo` |
| Exception | `E` | `EInvalidOperation` |
| Enum | `T` | `TSbomFormat` |

### Variables
| Scope | Prefix | Example |
|---|---|---|
| Local | `L` | `LProjectInfo` |
| Field | `F` | `FHashService` |
| Global | `G` | `GWizardIndex` |
| Loop counter | none | `i`, `j` |

### Constants
| Kind | Prefix | Example |
|---|---|---|
| General | `c` | `cBufferSize` |
| String | `sc` | `scErrorMessage` |
| Resource strings | `rs` | `rsWelcomeText` |

### Parameters: prefix `A` (`AFilePath`, `AFormat`)
### Components: type as prefix (`ButtonLogin`, `EditUserName`)

## Methods
- PascalCase
- Procedures: verb prefix (`SaveDocument`, `ValidateInput`)
- Functions: `Get`/`Is`/`Can` prefix (`GetUserName`, `IsValid`)

## Comments & Docs
- XML doc comments (`/// <summary>`) on all public types and methods
- Comments explain WHY, not WHAT
- No trivial comments

## Unit Header
Every unit must begin with an XML doc header:
```pascal
/// <summary>Unit.Name: Short description</summary>
/// <remarks>Detailed description</remarks>
/// <copyright>Copyright © YYYY Olaf Monien, MIT License</copyright>

unit Unit.Name;
```
