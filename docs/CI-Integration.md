# DX.Comply — CI/CD Integration Guide

## Overview

The `dxcomply` CLI can be dropped into any Windows build pipeline that produces
Delphi build artefacts. It reads a `.dproj` file (or a `.dxcomply.json`
configuration file in CI mode), combines project metadata with build evidence,
scans the build output directory, hashes every artefact, and writes a
standards-compliant SBOM.

Current Deep-Evidence status:

- the engine can consume MAP-derived evidence when a detailed Delphi `.map` file exists
- Deep-Evidence mode can be enabled through `.dxcomply.json`
- the engine can try to trigger an explicit build before evidence collection
- CLI-specific Deep-Evidence switches are not exposed yet; use the config file for now

The `--no-pause` flag suppresses the interactive "Press Enter to quit" prompt
and is **required** in all automated pipeline steps.

---

## GitHub Actions

### Basic SBOM generation

```yaml
- name: Generate SBOM
  run: dxcomply --project=src/MyApp.dproj --format=cyclonedx-json --output=bom.json --no-pause

- name: Upload SBOM artifact
  uses: actions/upload-artifact@v4
  with:
    name: sbom-${{ github.ref_name }}
    path: bom.json
```

### Full CI workflow with long-term retention (CRA-ready)

```yaml
name: Build and Generate SBOM

on:
  push:
    tags: ['v*']

jobs:
  build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build project
        run: msbuild src/MyApp.dproj /p:Config=Release /p:Platform=Win32

      - name: Generate SBOM
        run: >
          dxcomply
          --project=src/MyApp.dproj
          --format=cyclonedx-json
          --output=bom-${{ github.ref_name }}.json
          --no-pause

      - name: Upload SBOM
        uses: actions/upload-artifact@v4
        with:
          name: sbom
          path: bom-*.json
          retention-days: 3650  # 10 years — required by CRA Article 13
```

---

## GitLab CI

```yaml
generate-sbom:
  stage: compliance
  script:
    - >
      dxcomply
      --project=src/MyApp.dproj
      --format=cyclonedx-json
      --output=bom.json
      --no-pause
  artifacts:
    paths:
      - bom.json
    expire_in: never  # Keep for CRA compliance (10 years)
```

---

## Using a `.dxcomply.json` configuration file

For projects where the same settings are reused across branches or pipelines,
store the configuration in `.dxcomply.json` at the repository root.

**`.dxcomply.json`**

```json
{
  "output": "bom.json",
  "format": "cyclonedx-json",
  "include": ["build/**"],
  "exclude": [
    "build/**/Debug/**",
    "**/*.dcu"
  ],
  "deepEvidence": {
    "build": true,
    "delphiVersion": 13
  },
  "product": {
    "name": "My Application",
    "version": "2.1.0",
    "supplier": "My Company GmbH"
  }
}
```

Then invoke in CI mode — the config file drives all settings:

```
dxcomply --project=src/MyApp.dproj --ci --config=.dxcomply.json --no-pause
```

When `--ci` is given and the config file exists, `GenerateFromConfig` is called
instead of `Generate`, so command-line format/output flags are ignored in favour
of the file contents.

### Deep Evidence in CI

When `deepEvidence.build` is set to `true`, DX.Comply will try to run the shared
`build/DelphiBuildDPROJ.ps1` script before collecting evidence. This currently
requires:

- a Windows runner
- a Delphi installation visible to the build script
- permission to run the PowerShell build helper

If the runner does not have Delphi installed, the Deep-Evidence build step will
fail before evidence collection. In that environment, either disable
`deepEvidence.build` or provide an existing detailed `.map` file as part of the
build output.

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0    | SBOM generated successfully |
| 1    | Generation failed (see console output for details) |
| 2    | Invalid or missing arguments |

Pipeline steps should check the exit code and fail the job on non-zero values:

```yaml
- name: Generate SBOM
  run: dxcomply --project=src/MyApp.dproj --output=bom.json --no-pause
  # GitHub Actions fails the step automatically on non-zero exit code
```

---

## CRA Compliance Notes

The EU Cyber Resilience Act (CRA, Article 13) requires manufacturers to maintain
an SBOM for every released product version for **at least 10 years**.

Practical checklist:

- Generate an SBOM for **every release build** (tag-triggered pipeline).
- Store `bom.json` alongside the release artefacts in long-term storage.
- Set artifact `retention-days: 3650` (GitHub Actions) or `expire_in: never`
  (GitLab CI).
- Use CycloneDX JSON (`--format=cyclonedx-json`) — it is the format required by
  most EU conformity assessment toolchains.
- Archive the SBOM together with the installer or package so they remain
  associated even if the CI system is replaced.
