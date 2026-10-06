# DX.Comply: Legacy Delphi Support

## Overview

The release installer is built for Delphi 13 and registers the IDE plugin there. The command line tool is separate. It does not compile the project. It reads a `.dproj`, `.dpk`, or `.groupproj` and a detailed MAP file, so the Delphi version that wrote the MAP file does not have to be Delphi 13.

The MAP file lists the units linked into the executable. DX.Comply turns that list into a CycloneDX or SPDX SBOM, with a hash where it could open the file.

---

## How It Works

### IDE plugin

The release installer registers the IDE plugin for Delphi 13. In that IDE, the plugin compiles the project via the OTA (Open Tools API) with `DCC_MapFile=3` to produce a detailed MAP file.

### CLI tool

The CLI tool expects the MAP file to already exist, and `--project` must be a `.dproj`, `.dpk`, or `.groupproj`. You compile the project yourself (either interactively or in a CI pipeline), then run `dxcomply` to generate the SBOM from the build output.

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

The SBOM lists the program or package that was built, plus other binaries in that output directory. Installers and helper tools in subfolders are not included. If the `.dproj` has no output directory, only binaries in the project directory itself are listed. Use `--scan-dir` for binaries you stage on purpose. `--scan-tree` restores the old recursive listing and is deprecated.

`--project` does not accept a `.dpr` or a `.dof`. Delphi 7, 2005, and 2006 projects are often only those files. If a `.dproj` exists for the same project, pass that path. When the MAP file is not in the output directory taken from the `.dproj`, pass `--map-dir`.

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

The critical part is `/p:DCC_MapFile=3`. This tells MSBuild to produce the detailed MAP file that DX.Comply needs for unit-level evidence.

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
| Delphi XE to 10.4 | No | Yes |
| Delphi 2009 / 2010 | No | Yes |
| Delphi 2007 (has a `.dproj`) | No | Yes |
| Delphi 7 / 2005 / 2006 | No | Only with a `.dproj`, `.dpk`, or `.groupproj` |
| CI/CD pipeline (no IDE) | No | Yes |
| Cross-version build server | No | Yes |
