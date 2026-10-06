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

The command line tool does not use the IDE and does not compile the project. It reads a `.dproj`, `.dpk`, or `.groupproj` together with a detailed MAP file from a build. That MAP file can come from an older Delphi, as long as `--project` is one of those three file types.

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

The command line tool can write an SBOM for a project that was built with an older Delphi when two things are true: the build produced a **detailed MAP file**, and `--project` points at a `.dproj`, `.dpk`, or `.groupproj`.

1. In the IDE that builds the project, set **Map file** to **Detailed**.
2. Build the project. This produces a `.map` file.
3. Run the CLI against the `.dproj`:

```bash
dxcomply --project=MyApp.dproj --output=bom.json --no-pause
```

If the MAP file is not in the output directory taken from the `.dproj`, pass `--map-dir`. A `.dpr` or `.dof` is not a valid `--project` file. Delphi 7 projects are often only those two files, so they are not accepted unless a `.dproj` (or `.dpk` or `.groupproj`) exists for the same project.

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
| **Build artefacts** | Scans the output directory for `.exe`, `.dll`, `.bpl`, `.dcp` and records SHA-256 fingerprints when the file could be opened |
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

## Configuration

Add a `.dxcomply.json` to your project folder:

```json
{
  "output": "bom.json",
  "format": "cyclonedx-json",
  "include": ["build/**"],
  "exclude": ["build/**/Debug/**", "**/*.dcu"],
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

> DX.Comply lists the units, packages and DLL names it can see from the build, with hashes where it could open the file. You still need a supplier, a version and a licence for third-party components (a manifest for that is planned; see issue #20), and the rest of the CRA technical file: the vulnerability handling process, the disclosure policy, how updates are delivered, and the risk assessment. Vulnerability management and incident reporting are outside the scope of this tool.

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
| **CLI tool** | Windows executable. Needs a `.dproj`, `.dpk`, or `.groupproj` and a detailed MAP file. It does not compile the project. |
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
