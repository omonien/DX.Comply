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

**Regulation (EU) 2024/2847** (Cyber Resilience Act) entered into force on **10 December 2024**. If you place software or hardware with a digital component on the EU market — as an ISV, product company, or enterprise — you will be required to:

- document the software components in your product (**SBOM** — see below)
- manage and disclose vulnerabilities
- provide security updates throughout the support lifecycle

**Key dates:**
- **11 September 2026** — Vulnerability and incident reporting obligations begin (Article 14). Applies to all products already on the market.
- **11 December 2027** — Full CRA application date (Article 71). All products placed on the EU market must fully comply.

**DX.Comply handles the SBOM part.** The CRA requires manufacturers to identify and document software components — at minimum all top-level dependencies (Annex I, Part II, point 1). DX.Comply generates a machine-readable, standards-compliant *Software Bill of Materials* directly from your Delphi project — suitable for audits, customers, and regulatory submissions.

> **SBOM** (Software Bill of Materials) is simply a structured list of every component, file, and dependency in your software, including their versions and checksums. Think of it as the ingredient list on a food label — for your application.

---

## What exactly must I do? (CRA compliance at a glance)

The CRA applies to you if you place software products on the EU market — regardless of where you or your company is based. "Placing on the market" means selling, distributing, or otherwise making your product available to users in the EU.

Here is a plain-language overview of what the CRA requires from software manufacturers:

| # | Obligation | What it means in practice | DX.Comply |
|---|---|---|:---:|
| 1 | Secure-by-design | Build security into your development process from the start (threat modelling, secure defaults, least privilege) | — |
| 2 | SBOM | Generate and keep a machine-readable list of all software components shipped with your product | ✔️ |
| 3 | Vulnerability handling | Track known vulnerabilities in your components; patch and communicate them proactively | — |
| 4 | Incident reporting | Report actively exploited vulnerabilities to ENISA within 24 hours — **mandatory from 11 September 2026** (Article 14) | — |
| 5 | Technical documentation | Prepare and retain all compliance documentation for at least **10 years** (Article 13) | partial ¹ |
| 6 | Conformity assessment | For higher-risk products: formal third-party audit and CE marking | — |

> ¹ DX.Comply generates the SBOM artefact. Archiving and versioning it is your responsibility.

### The SBOM obligation — key clarifications

**You do NOT submit the SBOM anywhere.**

There is no EU portal, no registration process, and no proactive submission required. The SBOM is part of your *technical documentation* — you generate it per release, keep it, and make it available only in two situations:

- **To market surveillance authorities** — only if they formally request it (Article 52). This is an inspection right, not a submission requirement.
- **To end users / customers** — entirely **optional** (Annex II, Part I, point 9). If you choose to share it, you must document where it can be accessed.

### What counts as a valid SBOM?

The CRA requires (Annex I, Part II, point 1):

- Machine-readable format
- A commonly-used format — CycloneDX and SPDX are both accepted
- Coverage of at least the **top-level (direct) dependencies** of your product

Germany's Federal Office for Information Security (BSI) has published the first national technical interpretation: **BSI TR-03183-2** (v2.1, August 2025). It specifies:

- Format: **CycloneDX 1.6+** or **SPDX 3.0.1+** (JSON or XML)
- Checksums: **SHA-512** per component
- One SBOM per software version; no vulnerability data inside the SBOM (use CSAF/VEX for that)

> **Note:** BSI TR-03183-2 is Germany's national interpretation of the CRA SBOM requirement. The EU Commission may issue implementing acts that supersede or align national guidelines. DX.Comply tracks these developments.

### What DX.Comply covers

DX.Comply handles **obligation #2** — generating a standards-compliant SBOM directly from your Delphi/RAD Studio project. All other obligations (secure-by-design, vulnerability management, incident reporting, CE marking) are outside its scope.

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
├── bom.json          ← your SBOM, ready to archive with this release
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

### What to do with your SBOM

Once generated, there is no submission process — you simply keep it. Here is what you should do:

1. **Archive it with each release.**
   Store `bom.json` alongside your release artefacts (installer, binaries, changelog). Name it clearly, e.g. `bom-v2.1.0.json`. One SBOM per shipped version.

2. **Keep it for at least 10 years.**
   The CRA requires technical documentation — including the SBOM — to be retained for at least 10 years after a product version is placed on the market (Article 13). A release archive folder or a document management system both work fine.

3. **Be ready to hand it over if asked.**
   Market surveillance authorities can formally request your technical documentation (Article 52). This is rare and requires a reasoned request — but you should be able to produce the SBOM for any released version within a reasonable time.

4. **Sharing with customers is your choice.**
   The CRA does not require you to publish or hand the SBOM to end users. If you do choose to share it (e.g. in a trust portal or on your website), you must document where it can be accessed (Annex II, Part I, point 9).

> **In short:** Generate → archive → retain. That is all the CRA asks of you on the SBOM front.

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

## Official EU Sources

All CRA compliance claims in this project are based on the following official EU publications:

| Source | Link |
|--------|------|
| Regulation (EU) 2024/2847 — full text (EUR-Lex) | https://eur-lex.europa.eu/eli/reg/2024/2847/oj/eng |
| EC Digital Strategy — CRA overview | https://digital-strategy.ec.europa.eu/en/policies/cyber-resilience-act |
| ENISA — SBOM Landscape Analysis | https://www.enisa.europa.eu/publications/sbom-analysis |

---

## About

DX.Comply is developed by **Olaf Monien** as part of the [DX component suite](https://github.com/omonien).
Copyright © 2026 Olaf Monien.

