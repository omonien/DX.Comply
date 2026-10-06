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

| Build Confirmation | Progress & MAP Build | HTML Compliance Report |
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

## Installation

### Installer (Delphi 13)

Run the Inno Setup installer from the [Releases](https://github.com/omonien/DX.Comply/releases) page. It registers the IDE plugin and CLI tool automatically.

### Manual

1. Open `DX.Comply.groupproj` in RAD Studio.
2. Build and install the `DX.Comply.IDE` design-time package.
3. Optionally build the `DX.Comply.CLI` console application for command-line / CI use.

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

DX.Comply always performs a **Deep-Evidence analysis** based on the compiler-generated MAP file. This approach identifies every linked unit (PAS/DCU) with full dependency resolution, SHA-256 hashes, and origin classification. Whether the MAP file is generated automatically by the IDE plugin or provided manually for CLI usage makes no difference to the analysis quality.

| Evidence source | Details |
|---|---|
| **Project metadata** | Name, version, platform, configuration, DllSuffix |
| **MAP file analysis** | Extracts all linked units from segment entries and line-number sections |
| **Unit resolution** | Resolves each unit to its source/DCU/BPL file with SHA-256 hash |
| **Origin classification** | Classifies each unit as Embarcadero RTL, VCL, FMX, Local project, or Third party |
| **Build artefacts** | The exe, dll, or bpl named by the project (SHA-256 when the file exists), plus other `.exe`, `.dll`, `.bpl`, and `.dcp` files in that output directory |
| **Compiler evidence** | Parses `.cfg` and `.rsp` files for effective search paths and unit scopes |

---

## Output formats

DX.Comply produces **one machine-readable SBOM** plus, optionally, one or two **human-readable companion reports** alongside it. The SBOM and the reports are distinct outputs — the SBOM is what auditors and compliance toolchains consume; the reports are for humans.

### SBOM formats (machine-readable, pick one via `--format`)

| Format | Version | Description |
|---|---|---|
| **CycloneDX JSON** | 1.5 | Default — standard SBOM format for audits and tooling |
| **CycloneDX XML** | 1.5 | XML variant for XML-based toolchains |
| **SPDX JSON** | 2.3 | Linux Foundation ecosystem |

### Human-readable companion reports (optional, opt-in via `--report=<format>`)

| Report | Description |
|---|---|
| **HTML** | Compliance report with unit evidence, artefacts, and schema-validation status — pass `--report=html` |
| **Markdown** | Lightweight companion suitable for code review and archival — pass `--report=markdown` |

`--report=both` (or bare `--report`) emits both. `--report=none` keeps companion reports off (the default).

All generated SBOMs are validated against the official schema before being written to disk. CycloneDX JSON output passes [`check-jsonschema`](https://github.com/python-jsonschema/check-jsonschema) validation against the [official CycloneDX 1.5 JSON schema](http://cyclonedx.org/schema/bom-1.5.schema.json).

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

Add a `.dxcomply.json` to your project folder:

```json
{
  "output": "bom.json",
  "format": "cyclonedx-json",
  "exclude": ["**/*.dcu"],
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

With `--scan-tree`, or a `scanDirs` entry that contains `**`, the same include/exclude globs as before still apply relative to the scanned directory:

```json
"include": ["build/**"],
"exclude": ["build/**/Debug/**", "**/*.dcu"]
```

## Component manifest

An optional components file groups matched units under one library and fills in supplier, licence, version, type, and package URL. The format is the DelphiSBOM schema 1.0, so a file written for that tool works here unchanged. A sample is in [docs/samples/components.sample.json](docs/samples/components.sample.json).

```bash
dxcomply --project=MyApp.dproj --manifest=components.json --no-pause
```

The same path can live in `.dxcomply.json` as `"manifest"`. A relative path is resolved from the project directory. Without `--ci`, the CLI does not read `.dxcomply.json`, which is the same rule as the other settings, so pass `--manifest` on the command line. With `--ci`, the file supplies `manifest` unless you also pass `--manifest`: the flag wins. The IDE expert reads the same key from the project folder and has no extra options field.

Each row matches units by `units_exact` and/or `units_prefix` (case-insensitive). The unit name is tried as written and again with one known scope prefix removed (`System.`, `Vcl.`, `Winapi.`, and the other Delphi scopes). An exact hit beats `own_code_units`, those beat a prefix, and a library prefix beats `own_code_prefixes`. The first matching row wins inside one rule kind.

`own_code_units` and `own_code_prefixes` mark the project's own units. Those units stay in the evidence. They are not dropped, and they are not attributed to a third-party library. Unmatched units stay as they do today: one component each, linked from the application.

A matched unit stays as its own evidence component (hash, origin, `file:` package URL). The SBOM adds one library component for the row (`name`, `version`, `type`, supplier and author from `vendor`, optional `vendor_url`). The application depends on that library, and the library depends on the matched units. This is written for CycloneDX JSON, CycloneDX XML, and SPDX 2.3 JSON.

`licence` (British spelling) is an SPDX identifier such as `MIT` (emitted as `license.id`), an SPDX expression such as `MPL-1.1 OR LGPL-2.1-or-later` (emitted as `expression`), or any other text such as `Commercial` (emitted as `license.name`). `licence_url` is optional and is omitted for expressions. `license` and `license_url` are accepted as aliases. `type` is `library`, `framework`, or `application`.

There is no required `purl` field. When it is absent, DX.Comply writes `pkg:delphi/<name>@<version>` with the name and version percent-encoded. `pkg:delphi` is not a registered package-url type. Scanned files keep the existing `file:` locator. Set `purl` on a row when you want a different locator.

A file that cannot be read (missing, not JSON, or not an object or array) stops generation. The message names the file and the reason. Missing fields, a short prefix, or an unrecognised licence name are warnings, and the SBOM is still written. A row with match rules that hits no unit is reported as a warning. The root `supplier` is the application publisher. It is used only when `--supplier` or `product.supplier` was not already set.

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
| [Component manifest sample](docs/samples/components.sample.json) | Optional components.json (supplier, licence, version, type, PURL) |
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