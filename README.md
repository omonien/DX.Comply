# DX.Comply

[![Delphi Supported Versions](https://img.shields.io/badge/Delphi-11%20|%2012%20|%2013-blue?logo=delphi)](https://www.embarcadero.com/products/delphi)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![CycloneDX](https://img.shields.io/badge/SBOM-CycloneDX%201.5-informational?logo=owasp)](https://cyclonedx.org/)
[![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey?logo=windows)](https://www.microsoft.com/windows)
[![EU CRA](https://img.shields.io/badge/EU%20CRA-2024%2F2847-orange)](https://eur-lex.europa.eu/eli/reg/2024/2847/oj/eng)

**Generate Software Bills of Materials for your Delphi projects — with one click.**

> Built for Delphi developers. Designed for compliance. Ready for the EU Cyber Resilience Act.

---

## Why DX.Comply?

The EU **Cyber Resilience Act (CRA)** requires software vendors to document what is inside their products. Full compliance is mandatory by **December 2027**.

DX.Comply generates that documentation — a *Software Bill of Materials* (SBOM) — directly from your RAD Studio project in one click, together with human-readable HTML and Markdown reports for audit and review workflows.

**You generate it. You archive it. You never have to submit it anywhere.**

> **SBOM** = a structured list of every component, file, and dependency in your software, including versions and checksums. Think of it as the ingredient list on a food label — for your application.

---

## Screenshots

*Generating an SBOM for the Embarcadero AlienInvasion sample project:*

| Build Confirmation | Progress & Deep-Evidence Build | HTML Compliance Report |
|:---:|:---:|:---:|
| ![Build Confirmation](docs/Screenshot.png) | ![Progress](docs/Screenshot2.png) | ![Report](docs/Screenshot3.png) |

---

## SBOM Output Example

> **See it for yourself:** [Full example SBOM (JSON)](docs/examples/AlienInvasion.bom.json) · [Full example HTML report](docs/examples/AlienInvasion.bom.report.html) — generated from the Embarcadero *AlienInvasion* sample project.

DX.Comply produces standards-compliant **CycloneDX 1.5** SBOMs. Each linked unit is emitted as a `library` component with SHA-256 hash and origin classification:

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

## Quick Start

### Option A — RAD Studio IDE (recommended)

1. Install the `DX.Comply.IDE` design-time package.
2. **Open your project** in RAD Studio.
3. Choose **Project > DX.Comply > Generate documentation...** from the main menu.
4. In the confirmation dialog, **select the build configuration** to use for MAP generation (the active IDE configuration is pre-selected). DX.Comply compiles the project via OTA with detailed MAP output, scans all evidence, and produces the SBOM.
5. Done. Your `bom.json`, `bom.report.html`, and `bom.report.md` are in your project folder.

### Option B — Command line / CI

The CLI tool expects an existing detailed MAP file. Build your project first with `DCC_MapFile=3`, then run:

```bash
dxcomply --project=MyApp.dproj --format=cyclonedx-json --output=bom.json --no-pause
```

See [docs/CI-Integration.md](docs/CI-Integration.md) for GitHub Actions examples and CI configuration.

### Option C — Legacy Delphi (Delphi 7 and older)

DX.Comply can generate SBOMs for projects built with any Delphi version — including Delphi 7 — as long as a **detailed MAP file** is available. No IDE plugin is required.

1. Open your project in the legacy Delphi IDE.
2. Go to **Project > Options > Linker** and set **Map file** to **Detailed**.
3. Build your project — this produces a `.map` file in the output directory.
4. Run the CLI tool against the `.dproj` (or `.dof` for very old versions):

```bash
dxcomply --project=MyApp.dproj --output=bom.json --no-pause
```

> **Tip:** You can automate this with a **Post-Build Event** in a dedicated build configuration. Create a configuration named e.g. `SBOM` that enables detailed MAP output and runs `dxcomply` as a post-build step. This way, a single build generates both your application and its SBOM.

See [docs/LegacySupport.md](docs/LegacySupport.md) for details.

---

## What DX.Comply analyses

| Evidence source | Details |
|---|---|
| **Project metadata** | Name, version, platform, configuration, DllSuffix |
| **Deep-Evidence build** | IDE plugin: compiles via OTA with `DCC_MapFile=3`; CLI: expects a pre-built MAP file |
| **MAP file analysis** | Extracts all linked units from segment entries and line-number sections |
| **Unit resolution** | Resolves each unit to its source/DCU/BPL file with SHA-256 hash |
| **Origin classification** | Classifies each unit as Embarcadero RTL, VCL, FMX, Local project, or Third party |
| **Build artefacts** | Scans output directory for `.exe`, `.dll`, `.bpl`, `.dcp` with SHA-256 fingerprints |
| **Compiler evidence** | Parses `.cfg` and `.rsp` files for effective search paths and unit scopes |

---

## Output formats

| Format | Version | Description |
|---|---|---|
| **CycloneDX JSON** | 1.5 | Default — standard SBOM format for audits and tooling |
| **CycloneDX XML** | 1.5 | XML variant for XML-based toolchains |
| **SPDX JSON** | 2.3 | Linux Foundation ecosystem |
| **HTML Report** | — | Human-readable compliance report with unit evidence, artefacts, validation |
| **Markdown Report** | — | Lightweight companion for code review and archival |

All generated SBOMs are validated against the official schema before being written to disk. CycloneDX JSON output passes [`check-jsonschema`](https://github.com/python-jsonschema/check-jsonschema) validation against the [official CycloneDX 1.5 JSON schema](http://cyclonedx.org/schema/bom-1.5.schema.json).

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

## The EU Cyber Resilience Act — what you need to know

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

> DX.Comply handles the SBOM obligation. Other CRA requirements (secure-by-design, vulnerability management, incident reporting) are outside its scope.

---

## What to do with your SBOM

1. **Archive it with each release** — store `bom.json` alongside your release artefacts.
2. **Retain for at least 10 years** — required by CRA Article 13.
3. **Be ready to hand it over if asked** — market surveillance authorities can request it (Article 52).
4. **Sharing with customers is optional** — your choice (Annex II, Part I, point 9).

---

## Requirements

| Mode | Requirement |
|---|---|
| **IDE plugin** | RAD Studio / Delphi 11 Alexandria or newer |
| **CLI tool** | Any Delphi version (requires a pre-built detailed MAP file) |
| **Platform** | Windows build host |

No internet connection required — all processing is local.

---

## Documentation

| Document | Description |
|---|---|
| [Architecture](docs/Architecture.md) | Engine pipeline, component overview, unit origin classification |
| [CI Integration](docs/CI-Integration.md) | Command-line usage, GitHub Actions examples, CI configuration |
| [Legacy Support](docs/LegacySupport.md) | Using DX.Comply with Delphi 7 and other legacy versions |
| [Example SBOM (JSON)](docs/examples/AlienInvasion.bom.json) | Full CycloneDX 1.5 SBOM generated from the AlienInvasion sample |
| [Example HTML Report](docs/examples/AlienInvasion.bom.report.html) | Human-readable compliance report for the same project |

---

## License

Open source under the [MIT License](LICENSE).
Copyright 2026 Olaf Monien.

---

## Official EU Sources

| Source | Link |
|---|---|
| Regulation (EU) 2024/2847 — full text | [EUR-Lex](https://eur-lex.europa.eu/eli/reg/2024/2847/oj/eng) |
| EC Digital Strategy — CRA overview | [EC](https://digital-strategy.ec.europa.eu/en/policies/cyber-resilience-act) |
| ENISA — SBOM Landscape Analysis | [ENISA](https://www.enisa.europa.eu/publications/sbom-analysis) |

---

DX.Comply is developed by **Olaf Monien** as part of the [DX component suite](https://github.com/omonien).