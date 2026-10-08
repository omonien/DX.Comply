# DX.Comply: CI/CD Integration Guide

## Overview

The `dxcomply` CLI can be dropped into any Windows build pipeline that produces
Delphi build artefacts. It reads a `.dproj` file (or a `.dxcomply.json`
configuration file in CI mode), combines project metadata with build evidence,
lists the binary the project builds and the other binaries in that output
directory, hashes the files it can open, and writes a
CycloneDX or SPDX SBOM. Subfolders such as `setup\` or `tools\` are not
walked.

The CLI tool expects an existing detailed MAP file. It does **not** compile your
project. Your pipeline must build the project with `DCC_MapFile=3` before
running `dxcomply`. This keeps the CLI lightweight and avoids any dependency on
build scripts or Delphi installations beyond what your pipeline already provides.

`dxcomply.exe` is not installed by GetIt. Copy it from the release ZIP or the
installer `bin` folder, or build `src/CLI/DX.Comply.CLI.dproj`, and call that
executable from the pipeline.

The `--no-pause` flag suppresses the interactive "Press Enter to quit" prompt
and is **required** in all automated pipeline steps.

If the MAP file is not located in the default output directory derived from the
`.dproj`, use `--map-dir` to point `dxcomply` at the correct directory:

```cmd
dxcomply --project=src\MyApp.dproj --map-dir=build\Win32\Release --output=bom.json --no-pause
```

This is also supported in `.dxcomply.json` via the `mapDir` key.

---

## GitHub Actions

### Basic SBOM generation

```yaml
- name: Build with detailed MAP
  run: msbuild src/MyApp.dproj /p:Config=Release /p:Platform=Win32 /p:DCC_MapFile=3

- name: Generate SBOM
  run: dxcomply --project=src/MyApp.dproj --format=cyclonedx-json --output=bom.json --no-pause

- name: Upload SBOM artifact
  uses: actions/upload-artifact@v4
  with:
    name: sbom-${{ github.ref_name }}
    path: bom.json
```

### Full CI workflow with long-term retention

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

      - name: Build project with detailed MAP
        run: msbuild src/MyApp.dproj /p:Config=Release /p:Platform=Win32 /p:DCC_MapFile=3

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
          retention-days: 3650  # 10 years, the retention period in CRA Article 13
```

---

## GitLab CI

```yaml
generate-sbom:
  stage: compliance
  script:
    - msbuild src/MyApp.dproj /p:Config=Release /p:Platform=Win32 /p:DCC_MapFile=3
    - >
      dxcomply
      --project=src/MyApp.dproj
      --format=cyclonedx-json
      --output=bom.json
      --no-pause
  artifacts:
    paths:
      - bom.json
    expire_in: never  # Keep the SBOM with the release (CRA Article 13: at least 10 years)
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
  "platform": "Win32",
  "configName": "Release",
  "include": ["build/**"],
  "exclude": [
    "build/**/Debug/**",
    "**/*.dcu"
  ],
  "scanDirs": ["redist"],
  "manifest": "components.json",
  "product": {
    "name": "My Application",
    "version": "2.1.0",
    "supplier": "My Company GmbH"
  }
}
```

`scanDirs` entries are extra directories of binaries you stage on purpose.
Each one is scanned non-recursively unless the value contains `**`.
`"scanTree": true` restores the old recursive walk of the output directory.
That switch is deprecated and will be removed in a future release.

`include` and `exclude` still filter the files that were scanned. With
`scanTree`, or a `scanDirs` value that contains `**`, patterns are relative
to the scanned directory.

`configName` selects the build configuration used to read the `.dproj` (Debug, Release, or a custom name). `platform` selects the target. Both match the CLI flags `--config-name` and `--platform`.

Then invoke in CI mode:

```
dxcomply --project=src/MyApp.dproj --ci --config=.dxcomply.json --no-pause
```

When `--ci` is given and the config file exists, DX.Comply loads that file and then applies the options you actually passed on the command line. Precedence is:

1. Built-in defaults.
2. Values from `.dxcomply.json`.
3. Command-line options that appear in the invocation. These win.

A default you did not pass does not override the file. `dxcomply --ci --config-name=Debug` keeps Debug even if the file says `"configName": "Release"`. `dxcomply --ci --platform=Win64` keeps the file's `configName` and replaces only the platform. Without `--ci`, the file is not read. `--config` only changes the path used together with `--ci`.

The line printed after a successful run is the output path after that merge, including a `configName` or `platform` taken from the file.

`manifest` is an optional components file (see the README section "Component manifest"). A relative path is resolved from the project directory. `--manifest` wins over the file. A missing or invalid file fails the run and names the path and the reason. The same file is used for a Delphi 7 `.dpr`: matching uses the units from the MAP file.

### Multi-platform builds

When the same project is built for several targets in one pipeline (e.g. Win32
and Win64), each invocation of `dxcomply` will by default write to the same
`bom.json` and overwrite the previous run. Use `--include-platform-in-output`
to append `<Platform>.<Config>` to the default base filename. Explicit
`--output` paths are never decorated:

```yaml
- name: Generate SBOM (Win32)
  run: >
    dxcomply
    --project=src/MyApp.dproj
    --platform=Win32 --config-name=Release
    --include-platform-in-output
    --report=html
    --no-pause
  # -> bom.Win32.Release.json + bom.Win32.Release.report.html

- name: Generate SBOM (Win64)
  run: >
    dxcomply
    --project=src/MyApp.dproj
    --platform=Win64 --config-name=Release
    --include-platform-in-output
    --report=html
    --no-pause
  # -> bom.Win64.Release.json + bom.Win64.Release.report.html
```

### Deep Evidence in CI

The CLI tool does not compile your project. It relies on the MAP file that your
build step produces. To get full unit-level evidence, ensure your build step
includes the `DCC_MapFile=3` MSBuild property:

```cmd
msbuild src\MyApp.dproj /p:Config=Release /p:Platform=Win32 /p:DCC_MapFile=3
```

If you use `.dxcomply.json`, `deepEvidence.build` is ignored. Set
`deepEvidence.mode` to `always` or `when-missing` instead. The CLI still does
not compile the project: the MAP file must already exist before `dxcomply` runs.

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

## CRA notes

The EU Cyber Resilience Act (CRA, Article 13) requires manufacturers to keep
technical documentation, including an SBOM, for **at least 10 years**. The SBOM
from DX.Comply is build evidence and a component list. It is a starting point
for that part of the file. It does not make a product compliant.

The tool's own check of the written file is structural. The checked-in
`docs/examples/AlienInvasion.bom.json` is a CycloneDX 1.5 document from an
earlier AlienInvasion run. It was not regenerated as 1.6. The reference sample
is now ConwaysLifeFMX from https://github.com/Embarcadero/RADStudio13Demos.git,
project `Object Pascal/RTL/Parallel Library/FMX/ConwaysLifeFMX.dproj`, built
Release/Win32 with a map file. The example SBOM is regenerated from that demo
and will replace `docs/examples/AlienInvasion.bom.json` as
`docs/examples/ConwaysLifeFMX.cdx.json`. That file is not committed yet.
SPDX JSON and CycloneDX XML are not checked against official schemas inside
the tool.

BSI TR-03183-2 version 2.1.0 asks for CycloneDX 1.6 or later, or SPDX 3.0.1
or later. CycloneDX output is 1.6. SPDX stays at 2.3. SPDX 3.0.1 is out of
scope. The CLI writes SHA-512 next to SHA-256, and on a deployable file it
also writes that SHA-512 as an external reference of type distribution. It
writes the file name and the executable, archive, and structured properties
when the component has a file name. Pass `--sbom-creator` with an email
address or an http(s) URL when you want that contact in the document. A
component manifest supplies licence, version, and creator for third-party
libraries. The dependency list is the grouped graph of the built program,
plus direct uses edges where the Pascal source was read. CycloneDX
compositions say which of those sets are complete. A unit with no source
stays incomplete. See
[BSI-TR-03183-2.md](BSI-TR-03183-2.md). This output is not a certification.

Practical checklist:

- Generate an SBOM for **every release build** (tag-triggered pipeline).
- Store `bom.json` alongside the release artefacts in long-term storage.
- Set artifact `retention-days: 3650` (GitHub Actions) or `expire_in: never`
  (GitLab CI).
- CycloneDX JSON (`--format=cyclonedx-json`) is the default format.
- Archive the SBOM together with the installer or package so they remain
  associated even if the CI system is replaced.
- Vulnerability management and incident reporting are outside the scope of this tool.
