# DX.Comply

[![Delphi Supported Versions](https://img.shields.io/badge/Delphi-11%20|%2012%20|%2013-blue?logo=delphi)](https://www.embarcadero.com/products/delphi)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![CycloneDX](https://img.shields.io/badge/SBOM-CycloneDX%201.5-informational?logo=owasp)](https://cyclonedx.org/)
[![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey?logo=windows)](https://www.microsoft.com/windows)
[![EU CRA](https://img.shields.io/badge/EU%20CRA-2024%2F2847-orange)](https://eur-lex.europa.eu/eli/reg/2024/2847/oj/eng)

**Write a Software Bill of Materials from a Delphi build.**

> DX.Comply lists the units, packages and DLL names it can see in the build, with a hash where it could open the file. That component list is a starting point for the SBOM part of EU Cyber Resilience Act technical documentation (Annex I Part II, Annex VII). It does not make a product compliant, and it does not produce the rest of the technical file.

---

## Why DX.Comply?

The EU **Cyber Resilience Act (CRA)**, Regulation (EU) 2024/2847, requires manufacturers to keep technical documentation for products with digital elements. That file includes a machine-readable Software Bill of Materials (SBOM). The regulation applies in full from **11 December 2027**.

DX.Comply produces build evidence and that component list from a RAD Studio project, together with optional HTML and Markdown reports.

**You generate it. You archive it. You never have to submit it anywhere.**

> **SBOM** = a structured component list for a piece of software. DX.Comply fills it from the build: unit names, package names and DLL names, plus a SHA-256 hash when the file could be opened.

---

## Screenshots

*Generating an SBOM for the Embarcadero AlienInvasion sample project:*

| Build Confirmation | Progress and MAP Build | HTML SBOM Report |
|:---:|:---:|:---:|
| ![Build Confirmation](docs/Screenshot.png) | ![Progress](docs/Screenshot2.png) | ![Report](docs/Screenshot3.png) |

---

## SBOM Output Example

> **See it for yourself:** [Full example SBOM (JSON)](docs/examples/AlienInvasion.bom.json) and [full example HTML report](docs/examples/AlienInvasion.bom.report.html), generated from the Embarcadero *AlienInvasion* sample project.

DX.Comply writes **CycloneDX 1.5** JSON by default. Each linked unit is a `library` component, with a SHA-256 hash when the file could be opened, and with an origin classification:

```json
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.5",
  "metadata": {
    "component": {
      "type": "application",
      "name": "AlienInvasion",
      "version": "1.0.0.0"
    }
  },
  "components": [
    {
      "type": "application",
      "name": "AlienInvasion.exe",
      "hashes": [
        { "alg": "SHA-256", "content": "d0be8d3ad469b93c...f6cee44" }
      ]
    },
    {
      "type": "library",
      "name": "System.SysUtils.dcu",
      "hashes": [
        { "alg": "SHA-256", "content": "a1c9f3e7b2d4..." }
      ],
      "properties": [
        { "name": "net.developer-experts.dx-comply:origin", "value": "Embarcadero RTL" },
        { "name": "net.developer-experts.dx-comply:evidence", "value": "DCU" },
        { "name": "net.developer-experts.dx-comply:confidence", "value": "Strong" }
      ]
    }
  ]
}
```

---

## Installation

### Installer (Delphi 13)

The installer in the current release is built for Delphi 13 (RAD Studio 37.0). Run it from the [Releases](https://github.com/omonien/DX.Comply/releases) page. It registers the IDE plugin for Delphi 13 and copies the command line tool onto the machine.

The command line tool does not use the IDE and does not compile the project. It reads a `.dproj`, `.dpk`, or `.groupproj`, or a Delphi 7 `.dpr` with its `.dof` and `.cfg`, together with a detailed MAP file from a build. That MAP file can come from an older Delphi.

### Manual

1. Open `DX.Comply.groupproj` in RAD Studio.
2. Build and install the `DX.Comply.IDE` design-time package.
3. Optionally build the `DX.Comply.CLI` console application for command-line / CI use.

---

## Quick Start

### Option A: RAD Studio IDE (recommended)

1. Install the `DX.Comply.IDE` design-time package.
2. **Open your project** in RAD Studio.
3. Choose **Project > DX.Comply > Generate SBOM...** from the main menu.
4. In the confirmation dialog, **select the build configuration** to use for MAP generation (the active IDE configuration is pre-selected). DX.Comply compiles the project via OTA with detailed MAP output, scans all evidence, and produces the SBOM.
5. Done. Your `bom.json`, `bom.report.html`, and `bom.report.md` are in your project folder.

### Option B: Command line / CI

The CLI tool expects an existing detailed MAP file. Build your project first with `DCC_MapFile=3`, then run:

```bash
dxcomply --project=MyApp.dproj --format=cyclonedx-json --output=bom.json --no-pause
```

If the MAP file is in a non-standard directory, use `--map-dir`:

```bash
dxcomply --project=MyApp.dproj --map-dir=build/Win32/Release --output=bom.json --no-pause
```

To also generate the HTML/Markdown companion report from the CLI (the report ships disabled by default), pass `--report`:

```bash
dxcomply --project=MyApp.dproj --report=html --no-pause          # HTML only
dxcomply --project=MyApp.dproj --report=both --no-pause          # HTML + Markdown
dxcomply --project=MyApp.dproj --report --no-pause               # same as --report=both
```

When building the same project for several targets, append the platform/configuration to the default filename so subsequent runs don't overwrite each other:

```bash
dxcomply --project=MyApp.dproj --platform=Win64 --config-name=Release \
         --include-platform-in-output --no-pause
# -> bom.Win64.Release.json (+ bom.Win64.Release.report.html if --report is set)
```

Run `dxcomply --help` for the full list of switches. See [docs/CI-Integration.md](docs/CI-Integration.md) for GitHub Actions / GitLab CI examples.

### Option C: Older Delphi, with a detailed MAP file

The command line tool can write an SBOM for a project that was built with an older Delphi when the build produced a **detailed MAP file**.

1. In the IDE that builds the project, set **Map file** to **Detailed**.
2. Build the project. This produces a `.map` file.
3. Run the CLI against the project file. Delphi 2007 and later use a `.dproj`, `.dpk`, or `.groupproj`. A Delphi 7 project is the `.dpr` together with its `.dof` and `.cfg`, or the `.dpk` when a package has no `.dproj`. Delphi 2005 and 2006 can use the `.bdsproj`. If a `.dproj` is also present, pass the `.dproj`.

```bash
dxcomply --project=MyApp.dpr --output=bom.json --no-pause
```

The CLI reads the sibling `.dof` and `.cfg`. When both files define a setting, the `.dof` value is used. These projects have one Win32 option set, so `--platform` and `--config-name` are not applied. The built-in Win32 and Release defaults are not reported. A platform or configuration you set on the command line or in `.dxcomply.json` is reported and ignored. A blank package output directory uses the registry value `Package DPL Output` when Delphi 7's `RootDir` was found, and the project directory otherwise. The `.map` file must sit next to the output binary. If it is missing, the CLI stops. Library units come from a Delphi 7 install when `Software\Borland\Delphi\7.0` is in the registry. The scan still runs when that install is missing; pass `--delphi7-root` or set `delphi7Root` in `.dxcomply.json`. For a `.dproj`, if the MAP file is not in the output directory taken from the project, pass `--map-dir`.

> **Tip:** You can automate this with a **Post-Build Event** in a dedicated build configuration. Create a configuration named e.g. `SBOM` that enables detailed MAP output and runs `dxcomply` as a post-build step. This way, a single build generates both your application and its SBOM.

See [docs/LegacySupport.md](docs/LegacySupport.md) for details.

---

## What DX.Comply analyses

DX.Comply always performs a **Deep-Evidence analysis** based on the compiler-generated MAP file. This approach identifies linked units (PAS/DCU) with dependency resolution, SHA-256 hashes where the file could be opened, and origin classification. Whether the MAP file is generated by the IDE plugin or provided for CLI usage makes no difference to the analysis quality.

| Evidence source | Details |
|---|---|
| **Project metadata** | Name, version, platform, configuration, DllSuffix |
| **MAP file analysis** | Extracts linked units from segment entries and line-number sections |
| **Unit resolution** | Resolves each unit to its source/DCU/BPL file with a SHA-256 hash when the file could be opened |
| **Origin classification** | Classifies each unit as Embarcadero RTL, VCL, FMX, Local project, or Third party |
| **Build artefacts** | The exe, dll, or bpl named by the project, plus other `.exe`, `.dll`, `.bpl`, and `.dcp` files in that output directory. SHA-256 is recorded when the file could be opened |
| **Compiler evidence** | Parses `.cfg` and `.rsp` files for effective search paths and unit scopes |

---

## Output formats

DX.Comply produces **one machine-readable SBOM** and, if you ask for them, one or two **human-readable reports** next to it. The SBOM is the machine-readable file. The reports are for people.

### SBOM formats (machine-readable, pick one via `--format`)

| Format | Version | Description |
|---|---|---|
| **CycloneDX JSON** | 1.5 | Default. A common SBOM format for tooling |
| **CycloneDX XML** | 1.5 | XML variant for XML-based toolchains |
| **SPDX JSON** | 2.3 | SPDX 2.3 JSON |

### Human-readable companion reports (optional, opt-in via `--report=<format>`)

| Report | Description |
|---|---|
| **HTML** | SBOM report with unit evidence, artefacts, and the result of the internal structural check. Pass `--report=html` |
| **Markdown** | Shorter companion for review and archival. Pass `--report=markdown` |

`--report=both` (or bare `--report`) emits both. `--report=none` keeps companion reports off (the default).

After it writes a file, DX.Comply runs its own structural check of required fields and value shapes. That check is not a validation against an official schema.

CycloneDX JSON from the example in this repository passes [`check-jsonschema`](https://github.com/python-jsonschema/check-jsonschema) against the [official CycloneDX 1.5 JSON schema](http://cyclonedx.org/schema/bom-1.5.schema.json). SPDX JSON and CycloneDX XML are not checked against official schemas inside the tool.

### Further SBOM fields (roadmap)

[BSI TR-03183-2](https://www.bsi.bund.de/dok/TR-03183-en) v2.1.0 asks for more than DX.Comply writes today, including CycloneDX 1.6 or later, SHA-512 hashes, a licence and a supplier on each component, and recursive dependencies. Matching that profile is on the roadmap. DX.Comply does not yet fully meet it.

---

## Which binaries are listed

The SBOM lists the binary the `.dproj` builds (exe, dll, or bpl, including `DllSuffix` and the active configuration/platform output path). If that file is on disk it is hashed. Other `.exe`, `.dll`, `.bpl`, and `.dcp` files in the same output directory are listed too, for example a plugin DLL next to the exe.

Subfolders are not walked. `setup\`, `tools\`, and old build directories stay out of the SBOM, so the document is smaller than in previous versions: unrelated binaries are no longer listed. Runtime packages from the project, and DLLs referenced in source, are still listed even when those files were not found by the scan.

Pass `--scan-dir=<path>` (repeatable) or set `scanDirs` when you stage extra binaries on purpose. Each entry is scanned non-recursively. If the value contains `**`, subdirectories are included. A relative path is resolved from the project directory.

```bash
dxcomply --project=MyApp.dproj --scan-dir=redist --scan-dir=plugins\** --no-pause
```

`--scan-tree` (or `"scanTree": true`) restores the previous recursive walk of the output directory. It is deprecated and will be removed in a future release. Prefer `--scan-dir`.

`include` and `exclude` still filter what was scanned. Patterns match the path relative to the directory being scanned. `*.dll` matches a DLL next to the exe. Patterns such as `build/**` matter when the scanned directory itself contains a `build` folder, which is the case for `--scan-tree` when the project has no output directory, and for a `--scan-dir` value that contains `**`.

## Configuration

Add a `.dxcomply.json` to your project folder and pass `--ci` so the CLI loads it:

```json
{
  "output": "bom.json",
  "format": "cyclonedx-json",
  "platform": "Win32",
  "configName": "Release",
  "include": ["build/**"],
  "exclude": ["build/**/Debug/**", "**/*.dcu"],
  "scanDirs": ["redist"],
  "manifest": "components.json",
  "product": {
    "name": "My Application",
    "version": "2.1.0",
    "supplier": "Acme GmbH"
  },
  "report": {
    "enabled": true,
    "format": "both"
  }
}
```

`configName` is the build configuration (the same value as `--config-name`). `platform` matches `--platform`. Use these when the project is not built as `Release|Win32`.

`scanDirs` lists extra directories of binaries. Each entry is scanned non-recursively unless the value contains `**`. `"scanTree": true` restores the old recursive walk of the output directory. That switch is deprecated.

When `--ci` is set and the file exists, values are merged in this order:

1. Built-in defaults (`Release`, `Win32`, `cyclonedx-json`, `bom.json`).
2. Keys present in `.dxcomply.json`.
3. Command-line options you actually pass. Those win over the file.

An option you leave off the command line does not override the file, even though that option has a default. `dxcomply --ci --config-name=Debug` uses Debug even when the file says `"configName": "Release"`. `dxcomply --ci` with no `--config-name` uses the file's `configName`, or `Release` when the key is absent. The same rule applies to `--platform`, `--format`, `--output`, `--product`, `--version`, `--supplier`, `--report`, `--include`, `--exclude`, `--map-dir`, `--manifest`, and `--no-composition-evidence`.

If you pass `--include` or `--exclude`, that list replaces the file's list. `--report` overrides the file's enabled flag and format, and leaves the file's report output path as it is.

Without `--ci`, the file is not read. `--config=<path>` only chooses which file `--ci` loads (the default path is `.dxcomply.json`).

`deepEvidence.mode` may be `always` or `when-missing`. The old `deepEvidence.build` boolean is ignored.


## Component manifest

An optional components file adds one library component for each matched row and fills in supplier, licence, version, type, and package URL. The format is the DelphiSBOM schema 1.0, so a file written for that tool works here unchanged. A sample is in [docs/samples/components.sample.json](docs/samples/components.sample.json).

```bash
dxcomply --project=MyApp.dproj --manifest=components.json --no-pause
```

The same path can live in `.dxcomply.json` as `"manifest"`. A relative path is resolved from the project directory. Without `--ci`, the CLI does not read `.dxcomply.json`, so pass `--manifest` on the command line. With `--ci`, the file supplies `manifest` unless you also pass `--manifest`. The flag wins. The IDE expert reads the same key from the project folder and has no extra options field.

The units come from the MAP file, including a Delphi 7 `.dpr` with its `.dof` and `.cfg`. Each row matches those units by `units_exact` and/or `units_prefix` (case-insensitive). The unit name is tried as written and again with one known scope prefix removed (`System.`, `Vcl.`, `Winapi.`, and the other Delphi scopes). An exact hit beats `own_code_units`, those beat a prefix, and a library prefix beats `own_code_prefixes`. The first matching row wins inside one rule kind.

`own_code_units` and `own_code_prefixes` mark the project's own units. Those units stay in the evidence. They are not dropped, and they are not attributed to a third-party library. Unmatched units stay as they are: one component each, linked from the program that was built.

A matched unit stays as its own evidence component (hash, origin, `file:` package URL). The SBOM adds one library component for the row (`name`, `version`, `type`, supplier and author from `vendor`, optional `vendor_url`). The program that was built depends on that library, and the library depends on the matched units. Other binaries stay linked from that program. This is written for CycloneDX JSON, CycloneDX XML, and SPDX 2.3 JSON.

`licence` (British spelling) is an SPDX identifier such as `MIT` (written as `license.id`), an SPDX expression such as `MPL-1.1 OR LGPL-2.1-or-later` (written as `expression`), or any other text such as `Commercial` or `Proprietary` (written as `license.name`). `licence_url` is optional and is omitted for expressions. `license` and `license_url` are accepted as aliases. `type` is `library`, `framework`, or `application`.

There is no required `purl` field. When it is absent, DX.Comply writes `pkg:delphi/<name>@<version>` with the name and version percent-encoded. `pkg:delphi` is not a registered package-url type. Scanned files keep the existing `file:` locator. Set `purl` on a row when you want a different locator.

A file that cannot be read (missing, not JSON, or not an object or array) stops generation. The message names the file and the reason. Missing fields, a short prefix, or an unrecognised licence name are warnings, and the SBOM is still written. A row with match rules that hits no unit is reported as a warning. The root `supplier` is the application publisher. It is used only when `--supplier` and `product.supplier` are both empty.


---

## The EU Cyber Resilience Act: what you need to know

**Regulation (EU) 2024/2847** entered into force on **10 December 2024**. If you place software on the EU market, you must:

- Document software components in your product (SBOM)
- Manage and disclose vulnerabilities
- Provide security updates throughout the support lifecycle

| Date | Milestone |
|---|---|
| **11 Sep 2026** | Vulnerability and incident reporting obligations begin |
| **11 Dec 2027** | Full CRA compliance mandatory for all products on the EU market |

### What counts as a valid SBOM?

The CRA requires (Annex I, Part II):
- Machine-readable format (CycloneDX or SPDX)
- Coverage of at least top-level dependencies
- One SBOM per software version

**You do NOT submit the SBOM anywhere.** You generate it per release, archive it, and make it available only if a market surveillance authority formally requests it.

> DX.Comply lists the units, packages and DLL names it can see from the build, with hashes where it could open the file. A components file can fill supplier, version and licence on the libraries it matches. Units that do not match a row still have none of those. You still need the rest of the CRA technical file: the vulnerability handling process, the disclosure policy, how updates are delivered, and the risk assessment. Vulnerability management and incident reporting are outside the scope of this tool.

---

## What to do with your SBOM

1. **Archive it with each release.** Store `bom.json` alongside your release artefacts.
2. **Retain for at least 10 years.** CRA Article 13 requires this.
3. **Be ready to hand it over if asked.** Market surveillance authorities can request it (Article 52).
4. **Sharing with customers is optional.** That choice is yours (Annex II, Part I, point 9).

---

## Requirements

| Mode | Requirement |
|---|---|
| **IDE plugin** | Release installer: Delphi 13. The design-time package is the IDE integration. |
| **CLI tool** | Windows executable. Needs a `.dproj`, `.dpk`, `.groupproj`, or a Delphi 7 `.dpr` with `.dof` and `.cfg`, and a detailed MAP file. It does not compile the project. |
| **Platform** | Windows build host |

No internet connection is required. All processing is local.

---

## Documentation

| Document | Description |
|---|---|
| [Architecture](docs/Architecture.md) | Engine pipeline, component overview, unit origin classification |
| [CI Integration](docs/CI-Integration.md) | Command-line usage, GitHub Actions examples, CI configuration |
| [Legacy Support](docs/LegacySupport.md) | MAP files from older Delphi versions, and which project files the CLI accepts |
| [Example SBOM (JSON)](docs/examples/AlienInvasion.bom.json) | Full CycloneDX 1.5 SBOM generated from the AlienInvasion sample |
| [Component manifest sample](docs/samples/components.sample.json) | Optional components.json (supplier, licence, version, type, package URL) |
| [Example HTML Report](docs/examples/AlienInvasion.bom.report.html) | Human-readable SBOM report for the same project |

---

## License

Open source under the [MIT License](LICENSE).
Copyright 2026 Olaf Monien.

---

## Official sources

| Source | Link |
|---|---|
| Regulation (EU) 2024/2847: full text | [EUR-Lex](https://eur-lex.europa.eu/eli/reg/2024/2847/oj/eng) |
| EC Digital Strategy: CRA overview | [EC](https://digital-strategy.ec.europa.eu/en/policies/cyber-resilience-act) |
| ENISA: SBOM Landscape Analysis | [ENISA](https://www.enisa.europa.eu/publications/sbom-analysis) |
| BSI TR-03183-2: Software Bill of Materials | [BSI](https://www.bsi.bund.de/dok/TR-03183-en) |

---

DX.Comply is developed by **Olaf Monien** as part of the [DX component suite](https://github.com/omonien).
