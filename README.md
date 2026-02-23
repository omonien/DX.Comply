# DX.Comply

**Generate software manifests for your Delphi projects — with one click.**

> Built for Delphi developers. Designed for compliance. Ready for the EU Cyber Resilience Act.

---

## The problem, in plain language

When you ship software to customers or the market, regulations increasingly require you to answer a simple question:
**"What exactly is inside your product?"**

This means: Which files does your application consist of? Which third-party packages, libraries, or components does it use? What versions? With which cryptographic fingerprints?

Manually maintaining such a list is tedious and error-prone — especially across releases. **DX.Comply automates this entirely**, directly from your RAD Studio project.

---

## The EU Cyber Resilience Act (CRA) — what it means for you

The EU Cyber Resilience Act (CRA) is now in force. Most obligations apply from **late 2027**. If you sell software or hardware with a digital component in the EU — as an ISV, product company, or enterprise — you will be required to:

- document the software components in your product (**SBOM**)
- manage and disclose vulnerabilities
- provide security updates throughout the support lifecycle

**DX.Comply handles the SBOM part.** It generates a machine-readable, standards-compliant *Software Bill of Materials* directly from your Delphi project — suitable for audits, customers, and regulatory submissions.

> **SBOM** (Software Bill of Materials) is simply a structured list of every component, file, and dependency in your software, including their versions and checksums. Think of it as the ingredient list on a food label — for your application.

---

## Quick Start

### Option A — RAD Studio IDE (recommended)

Get your first SBOM in under a minute:

1. **Open your project** in RAD Studio as usual.
2. **Build your project** at least once so the output artefacts exist.
3. In the main menu, choose **Project → Generate SBOM (DX.Comply)**.
4. A dialog opens — select your output format (start with **CycloneDX JSON**) and confirm.
5. Done. Your `bom.json` is in your project folder.

```
MyApp/
├── MyApp.dproj
├── bom.json          ← your SBOM, ready to submit or archive
└── ...
```

The IDE message window shows a log of what was scanned and any warnings.

---

### Option B — Command line / CI/CD

Install the `dxcomply` CLI and integrate it into your build pipeline:

```bash
# Generate a CycloneDX JSON SBOM
dxcomply --project=MyApp.dproj --format=cyclonedx-json --output=bom.json

# Use a project config file
dxcomply --ci --config=.dxcomply.json
```

**GitHub Actions example:**
```yaml
- name: Generate SBOM
  run: dxcomply --project=src/MyApp.dproj --format=cyclonedx-json --output=bom.json

- name: Upload SBOM
  uses: actions/upload-artifact@v4
  with:
    name: sbom
    path: bom.json
```

---

## What DX.Comply analyses

For each build, DX.Comply scans your project and output directory and records:

| What                        | Details                                      |
|-----------------------------|----------------------------------------------|
| Project metadata            | Name, version, platform, configuration       |
| Build artefacts             | `.exe`, `.dll`, `.bpl`, `.dcp`, resources    |
| Third-party packages        | Runtime packages, detected library paths     |
| Cryptographic fingerprints  | SHA-256 hash for every file                  |
| Dependency graph            | Basic component relationships                |

---

## Configuration

Add a `.dxcomply.json` to your project folder to control the scan:

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
  }
}
```

---

## Output formats

| Format            | Version | Use case                                      | Available in    |
|-------------------|---------|-----------------------------------------------|-----------------|
| CycloneDX JSON    | 1.5     | Default — audits, tools, CRA submissions      | Community + Pro |
| CycloneDX XML     | 1.5     | XML-based toolchains                          | Community + Pro |
| SPDX JSON         | 2.3     | Linux Foundation ecosystem, some EU portals   | Pro             |

All generated SBOMs are validated against the official schema before being written to disk.

---

## Features

| Feature                         | Community (MIT) | Pro |
|---------------------------------|:--------------:|:---:|
| RAD Studio IDE integration      | ✔️             | ✔️  |
| CLI (`dxcomply`)                | ✔️             | ✔️  |
| CycloneDX JSON + XML            | ✔️             | ✔️  |
| SHA-256 artefact fingerprints   | ✔️             | ✔️  |
| SPDX JSON export                | —              | ✔️  |
| SBOM diff between releases      | —              | ✔️  |
| HTML compliance report          | —              | ✔️  |
| Policy checks (allow/deny)      | —              | ✔️  |
| CVE feed integration            | —              | ✔️  |
| Enterprise templates            | —              | ✔️  |
| Priority support                | —              | ✔️  |

---

## Requirements

- **RAD Studio / Delphi 11 Alexandria** or newer (for IDE plugin)
- **Windows** (build host); CLI output consumed on any platform
- No internet connection required — all processing is local

---

## Roadmap

| Version | Highlights                                              | Status   |
|---------|---------------------------------------------------------|----------|
| v1.0    | IDE plugin, CLI, CycloneDX JSON/XML, artefact scan     | In development |
| v1.1    | SPDX export, HTML report, SBOM diff                    | Planned  |
| v2.0    | CVE feed integration, licence heuristics, policy checks | Planned  |

---

## License

The **Community edition** is open source under the [MIT License](LICENSE).  
The **Pro edition** is available as a commercial subscription.

---

## About

DX.Comply is developed by **Olaf Monien** as part of the [DX component suite](https://github.com/omonien).  
Copyright © 2026 Olaf Monien.

