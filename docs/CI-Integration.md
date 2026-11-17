# DX.Comply: CI/CD Integration Guide

## Overview

The `dxcomply` CLI can be dropped into any Windows build pipeline that produces
Delphi build artefacts. It reads a `.dproj` file (or a `.dxcomply.json`
configuration file in CI mode), combines project metadata with build evidence,
lists the binary the project builds and the other binaries in that output
directory, hashes the files it can open, and writes a
CycloneDX or SPDX SBOM. Subfolders such as `setup\` or `tools\` are not
walked.

The CLI reads a detailed MAP file for the configuration and platform you pass
(`Release` and `Win32` when you pass neither). When that file is missing, the
default deep evidence mode `when-missing` builds the project with MSBuild
(`build/DelphiBuildDPROJ.ps1`, property `DCC_MapFile=3`) and prints a warning
that names the missing MAP file, the configuration, and the platform.
`--no-build`, or `"noBuild": true` in `.dxcomply.json`, stops that run with
exit code 1 instead of compiling. A pipeline that already built the project
should pass `--no-build` together with the same `--config-name` and
`--platform`. With `--ci`, the flag wins over `noBuild` in the file. A Delphi
7 project is not compiled.

`dxcomply.exe` is not installed by GetIt. Copy it from the release ZIP or the
installer `bin` folder, or build `src/CLI/dxcomply.dproj`, and call that
executable from the pipeline.

The `--no-pause` flag suppresses the interactive "Press Enter to quit" prompt
and is **required** in all automated pipeline steps.

`--cpe=<cpe>` sets `product.cpe` (a CPE 2.3 formatted string or a CPE 2.2 URI)
on the product and on the built program. `--cpe-lookup` searches the NVD CPE
API for the configured vendor and product and prints the matches. It does not
write an SBOM. `--cpe-dictionary` writes a CPE Dictionary 2.3 file and a mail
text next to the SBOM after generation and does not call the NVD. DX.Comply
does not send that message. The optional NVD API key is `--nvd-api-key`, then
the environment variable `NVD_API_KEY`, then
`HKCU\Software\Developer Experts\DX.Comply\NIST` value `ApiKey`. It is not read
from `.dxcomply.json` and it is not printed. The log names only the source.

The default output directory comes from `DCC_ExeOutput`, then the BPL, DCP, and
DCU output paths in the `.dproj`. `$(Platform)` and `$(Config)` are expanded.
For 32-bit Android the platform folder is `Android`, so a default layout is
`Android\Release\libMyApp.so` and `Android\Release\libMyApp.so.map`.
`--platform=Android32` maps to that folder. Android64 stays `Android64`.
Pass `--platform=Android` or `--platform=Android64` with the configuration
you built. When those output settings are absent and the platform folder is
already on disk, that folder is used. Otherwise the project directory is used.

If the MAP file is not located in the default output directory derived from the
`.dproj`, use `--map-dir` to point `dxcomply` at the correct directory:

```cmd
dxcomply --project=src\MyApp.dproj --map-dir=build\Win32\Release --output=bom.json --no-pause
```

This is also supported in `.dxcomply.json` via the `mapDir` key.

## Output folders

A clean setup gives every project its own output folder and assembles the install folder in the installer, so this situation does not arise. Each project then has one output directory of its own, and the SBOM lists that project's executable and the DLLs that belong next to it.

An existing setup may still build several projects into one folder, for example an install folder. DX.Comply scans that folder flat. Every `.exe`, `.dll`, `.bpl`, and `.dcp` in the folder is listed, so the SBOM of one tool also contains the executables and DLLs of the others. Subfolders are not walked. `scanDirs` adds a directory you stage on purpose. It does not separate those projects. When the output folder contains more than one `.exe`, DX.Comply writes one info line that names those executables and points at this section. The line is information. It does not change which files are listed. An include list does not hide the line, because the line names the executables in the folder.

For that existing setup, limit the scan with an include list. An include list replaces the default extensions. Add each DLL you still need with another `--include`:

```cmd
dxcomply --project=src\MyTool.dproj --include=MyTool.exe --include=MyTool.dll --no-pause
```

`--include=MyTool.exe` keeps that executable and drops the other default extensions, including other executables in the same folder. Do not use `--exclude=*.exe`. An exclude list only removes matches. It does not replace the default extensions, so other projects' DLLs stay in the SBOM, and `--exclude=*.exe` also drops the executable you wanted to keep.

The same list in `.dxcomply.json` is the `include` array. `dxcomply.exe` reads that file when you pass `--ci`:

```json
{
  "include": ["MyTool.exe", "MyTool.dll"]
}
```

```cmd
dxcomply --project=src\MyTool.dproj --ci --no-pause
```

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
          retention-days: 3653  # 10 years including leap days, CRA Article 13(13)
```

GitHub caps `retention-days` at the repository limit: 90 days for a public
repository, at most 400 days for a private one. A higher value is cut to that
limit with a warning. The artifact therefore does not cover the 10 years on its
own. Also attach the SBOM to the GitHub release, or copy it to your long-term
archive.

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
  "matchPrefixes": "corroborated",
  "noBuild": true,
  "product": {
    "name": "My Application",
    "version": "2.1.0",
    "supplier": "My Company GmbH",
    "cpe": "cpe:2.3:a:example:my_application:2.1.0:*:*:*:*:*:*:*"
  }
}
```

`"noBuild": true` is the same as `--no-build`. With `--ci`, `--no-build=false` wins over the file.

`scanDirs` entries are extra directories of binaries you stage on purpose.
Each one is scanned non-recursively unless the value contains `**`.
`"scanTree": true` restores the old recursive walk of the output directory.
That switch is deprecated and will be removed in the next release.

`include` and `exclude` still filter the files that were scanned. With
`scanTree`, or a `scanDirs` value that contains `**`, patterns are relative
to the scanned directory. A shared output folder is covered in
[Output folders](#output-folders). An include list replaces the default
extensions. Do not use `--exclude=*.exe` for that case.

`configName` selects the build configuration used to read the `.dproj` (Debug, Release, or a custom name). `platform` selects the target. Both match the CLI flags `--config-name` and `--platform`.

Then invoke in CI mode:

```
dxcomply --project=src/MyApp.dproj --ci --config=.dxcomply.json --no-pause
```

`dxcomply.exe` looks for a relative `--config` path, including the default `.dxcomply.json`, in the current directory first. If that file is not there and `--project` is set, it looks in the project folder. An absolute `--config` path is used as given. The folder that contains `dxcomply.exe` is not searched. When `--ci` is set and no file is found, `dxcomply.exe` prints a warning that lists the paths it tried and then continues. That warning does not change the exit code. `--strict` still exits with code 3 only when a CRA/BSI warning was raised.

A batch file often starts in a working directory that is not the project folder. Begin the batch file with:

```
cd /d %~dp0
```

That sets the working directory to the folder that contains the batch file, so a relative `.dxcomply.json` next to the batch file is found on the first check. With `--project` pointing at the `.dproj`, `dxcomply.exe` also finds a config file in the project folder when the working directory is somewhere else.

When `--ci` is given and the config file exists, DX.Comply loads that file and then applies the options you actually passed on the command line. Precedence is:

1. Built-in defaults.
2. Values from `.dxcomply.json`.
3. Command-line options that appear in the invocation. These win.

A default you did not pass does not override the file. `dxcomply --ci --config-name=Debug` keeps Debug even if the file says `"configName": "Release"`. `dxcomply --ci --platform=Win64` keeps the file's `configName` and replaces only the platform. The same rule applies to `--no-build`: `dxcomply --ci --no-build=false` keeps the build enabled even when the file says `"noBuild": true`. Without `--ci`, the file is not read. `--config` only changes the path used together with `--ci`, using the lookup order above.

The line printed after a successful run is the output path after that merge, including a `configName` or `platform` taken from the file.

`report.content` (or `--report-content`) chooses the parts of the HTML and Markdown reports: `all` (the default), `overview` for the origin summary, licences and third-party units without manifest, or `units` for the unit list with SHA-256 hashes. The SBOM stays complete either way.

`manifest` is an optional components file (see the README section "Component manifest"). A relative path is resolved from the project directory. `--manifest` wins over the file. A missing or invalid file fails the run and names the path and the reason. The same file is used for a Delphi 7 `.dpr`: matching uses the units from the MAP file. Folder entries inside the file (`units_folder`, `own_code_folders`) are resolved from the directory of that file. `$(name)` in those fields is expanded first. `--define:name=value` (also `--define=name=value` and `--define name=value`) sets a name, and `defines` in this file does the same. A name on the command line wins. `$(env.NAME)` reads the environment when that full name is not defined. An unknown name fails the run. A folder that is not on disk is a warning, and the rule is still applied. Prefer `units_folder` or `units_exact` over a short `units_prefix`. A prefix with no dot is not applied unless `match.prefixes` in the components file, or `matchPrefixes` here, is `legacy`. `--match-prefixes` wins over `matchPrefixes`, and `matchPrefixes` wins over the components file. `legacy` is for this release. A prefix never reassigns a unit in an Embarcadero product path.

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

When the MAP file for the selected configuration and platform is missing, the
CLI builds the project itself. The default `deepEvidence.mode` is
`when-missing`. `always` builds even when that MAP file is already on disk.
The build is a nested MSBuild. The CLI prints a warning first. The warning
names the missing MAP file, the configuration, and the platform. Without
`--config-name` the CLI looks for the Release MAP file.

To get full unit-level evidence from your own build step, include the
`DCC_MapFile=3` MSBuild property, then tell the CLI not to build again:

```cmd
msbuild src\MyApp.dproj /p:Config=Release /p:Platform=Win32 /p:DCC_MapFile=3
dxcomply --project=src\MyApp.dproj --config-name=Release --platform=Win32 --no-build --no-pause
```

A post-build event should pass the configuration and platform of the build
that is running:

```cmd
call sbom.bat "$(PROJECTPATH)" $(Config) $(Platform)
```

`sbom.bat`:

```bat
@echo off
dxcomply --project=%1 --config-name=%2 --platform=%3 --no-build --no-pause
```

Add `--map-dir` when the MAP file is not in the output directory the project
records.

If you use `.dxcomply.json`, `deepEvidence.build` is ignored. Set
`deepEvidence.mode` to `always` or `when-missing`. `"noBuild": true` is the
file form of `--no-build`. With `--ci`, the flag wins. When `--no-build` stops
a build that would otherwise run, the exit code is 1. A Delphi 7 project is
not compiled. The MAP file from that build must already exist.

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0    | SBOM generated successfully |
| 1    | Generation failed (see console output for details). `--no-build`, or `"noBuild": true`, uses this code when a build would otherwise run. The message names the MAP file, the configuration, and the platform. |
| 2    | Invalid or missing arguments |
| 3    | SBOM generated, but `--strict` (or `"strict": true`) is set and at least one CRA/BSI warning was raised |

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

The tool's own check of the written file is structural. The checked-in example
is `docs/examples/ConwaysLifeFMX.cdx.json`, CycloneDX 1.6, from ConwaysLifeFMX
in https://github.com/Embarcadero/RADStudio13Demos.git, project
`Object Pascal/RTL/Parallel Library/FMX/ConwaysLifeFMX.dproj`, built
Release/Win32 with a map file. It replaces the earlier AlienInvasion example.
SPDX JSON and CycloneDX XML are not checked against official schemas inside
the tool.

BSI TR-03183-2 version 2.1.0 asks for CycloneDX 1.6 or later, or SPDX 3.0.1
or later. CycloneDX output is 1.6. SPDX output is 2.3 by default, and
3.0.1 with `dxcomply.exe --spdx-version=3.0.1`. The CLI writes SHA-512 next to SHA-256, and on a deployable file it
also writes that SHA-512 as an external reference of type distribution. It
writes the file name and the executable, archive, and structured properties
when the component has a file name. Pass `--sbom-creator` with an email
address or an http(s) URL when you want that contact in the document. A
component manifest supplies licence, version, creator, and, when the row
sets it, copyright for third-party libraries. The dependency list is the
grouped graph of the built program, plus direct uses edges where the Pascal
source was read. The program lists runtime packages, external DLLs, and the
units that no other unit uses. A uses B and B uses C writes those two edges,
and the program depends on A. CycloneDX compositions say which of those sets
are complete. A unit with no source stays incomplete. See
[BSI-TR-03183-2.md](BSI-TR-03183-2.md). This output is not a certification.

Practical checklist:

- Generate an SBOM for **every release build** (tag-triggered pipeline).
- Store `bom.json` alongside the release artefacts in long-term storage.
- Set artifact `retention-days: 3653` (GitHub Actions, capped at the repository
  limit, see above) or `expire_in: never` (GitLab CI). 3653 days are 10 years
  including leap days.
- CycloneDX JSON (`--format=cyclonedx-json`) is the default format.
- Archive the SBOM together with the installer or package so they remain
  associated even if the CI system is replaced.
- Vulnerability management and incident reporting are outside the scope of this tool.
