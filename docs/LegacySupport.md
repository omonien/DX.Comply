# DX.Comply — Legacy Delphi Support

## Overview

DX.Comply can generate SBOMs for projects built with **any Delphi version** — including Delphi 7, 2007, 2010, XE, and beyond. The IDE plugin requires Delphi 11+, but the CLI tool works with any Delphi version as long as a **detailed MAP file** is available.

The key insight: the MAP file contains a complete list of every unit linked into the executable. DX.Comply extracts this information and transforms it into a standards-compliant SBOM.

---

## How It Works

### IDE Plugin (Delphi 11+)

The IDE plugin compiles the project automatically via the OTA (Open Tools API) with `DCC_MapFile=3` to produce a detailed MAP file. No manual steps are needed.

### CLI Tool (Any Delphi Version)

The CLI tool expects the MAP file to already exist. You compile the project yourself (either interactively or in a CI pipeline), then run `dxcomply` to generate the SBOM from the build output.

---

## Step-by-Step: Legacy Delphi (Delphi 7 / 2007 / 2010)

### 1. Enable Detailed MAP File Output

**Delphi 7 / 2005 / 2006 / 2007:**
- Open **Project > Options > Linker**
- Set **Map file** to **Detailed**
- Click OK

**Delphi 2009 / 2010 / XE / XE2+:**
- Open **Project > Options > Delphi Compiler > Linking**
- Set **Map file** to **Detailed**

### 2. Build Your Project

Build the project as usual. The compiler produces a `.map` file alongside the executable in the output directory.

### 3. Run the CLI Tool

```bash
dxcomply --project=MyApp.dproj --output=bom.json --no-pause
```

The SBOM lists the program or package that was built, plus other binaries in that output directory. Installers and helper tools in subfolders are left out, so the document stays smaller. If the `.dproj` has no output directory, only binaries in the project directory itself are listed. Use `--scan-dir` for anything you stage on purpose. `--scan-tree` restores the old recursive listing and is deprecated.

For very old projects that use `.dof` instead of `.dproj`, you can point `--project` at the `.dproj` if one exists, or at the `.dpr` file. DX.Comply will locate the MAP file based on the output directory conventions.

---

## Automating with Post-Build Events

You can fully automate SBOM generation by adding a Post-Build Event to a dedicated build configuration.

### Creating an SBOM Build Configuration

1. In the Delphi IDE, open **Project > Options > Build Configurations**
2. Create a new configuration named `SBOM` (based on `Release`)
3. In this configuration:
   - Set **Map file** to **Detailed** (Linker settings)
   - Add a Post-Build Event:

```bash
dxcomply --project="$(PROJECTPATH)" --output="$(OUTPUTDIR)bom.json" --no-pause
```

4. When you build with the `SBOM` configuration, both the application and its SBOM are generated in one step.

### CI Pipeline Example

In a CI/CD pipeline, compile the project with detailed MAP output first, then run `dxcomply`:

```yaml
# GitHub Actions example
- name: Build with detailed MAP
  run: >
    msbuild src/MyApp.dproj
    /p:Config=Release
    /p:Platform=Win32
    /p:DCC_MapFile=3

- name: Generate SBOM
  run: >
    dxcomply
    --project=src/MyApp.dproj
    --format=cyclonedx-json
    --output=bom.json
    --no-pause
```

The critical part is `/p:DCC_MapFile=3` — this tells MSBuild to produce the detailed MAP file that DX.Comply needs for full unit-level evidence.

---

## MAP File Directory Override

If the MAP file is not in the default output directory that DX.Comply derives from the `.dproj`, you can specify the directory explicitly:

```bash
dxcomply --project=MyApp.dproj --map-dir=C:\builds\output --output=bom.json --no-pause
```

This is particularly useful for legacy projects where output paths are configured outside the `.dproj` or when the MAP file is generated in a non-standard location.

---

## AnyCPU Platform Support

Some legacy Delphi 2007 projects use `AnyCPU` instead of `Win32` as the platform identifier in their `.dproj` condition attributes. DX.Comply automatically falls back to `AnyCPU` when no matching `$(Configuration)|$(Platform)` property group is found for `Win32`, so these projects work without any manual adjustment.

---

## Encoding Considerations

- **Delphi 7** writes MAP files in **ANSI** encoding (Windows-1252 / ISO-8859-1).
- **Delphi 2009+** writes MAP files in **UTF-8**.
- DX.Comply handles both encodings automatically.

## Unit Naming

- **Delphi 7** uses flat unit names without namespace prefixes (e.g., `SysUtils` instead of `System.SysUtils`).
- DX.Comply handles both naming conventions and classifies units correctly regardless of the Delphi version that produced the MAP file.

---

## Supported Scenarios

| Scenario | IDE Plugin | CLI Tool |
|---|:---:|:---:|
| Delphi 13 / 12 / 11 | Yes | Yes |
| Delphi XE – 10.4 | — | Yes |
| Delphi 2009 / 2010 | — | Yes |
| Delphi 7 / 2005 / 2006 / 2007 | — | Yes |
| CI/CD pipeline (no IDE) | — | Yes |
| Cross-version build server | — | Yes |
