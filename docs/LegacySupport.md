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
dxcomply --project=MyApp.dpr --output=bom.json --no-pause
```

Delphi 2007 and later still use the `.dproj` (`dxcomply --project=MyApp.dproj`). Delphi 7 passes the `.dpr`, or the `.dpk` when a package has no `.dproj`. Delphi 2005 and 2006 can pass the `.bdsproj`. DX.Comply reads the main source name from a `.bdsproj` and then uses the sibling `.dof` and `.cfg`. It does not read build configurations stored inside the `.bdsproj`. If a `.dproj` is present, pass the `.dproj`.

The sibling `.dof` (INI) and `.cfg` (dcc32 response file) supply the output directory, search path, defines, runtime packages, and version info. When both files define a value, the `.dof` wins, including when the `.dof` value is empty. The `.cfg` is used only for settings the `.dof` does not define. `OutputDir` and `-E` are the exe/dll directory. `PackageDLLOutputDir` and `-LE` are the package directory. Runtime packages are listed only when the project is built with runtime packages: `UsePackages=1` uses `[Directories] Packages` (or `-LU` if that key is absent), `UsePackages=0` lists none, and a `.dof` that never mentions `UsePackages` uses `-LU`.

Delphi 7, 2005, and 2006 projects have a single Win32 option set. `--platform` and `--config-name` are reported and not applied. The recorded platform is Win32 and the configuration is Default.

The output name comes from the project file name. The extension comes from the first `program` (`.exe`), `library` (`.dll`), or `package` (`.bpl`) keyword in the source. `{$LIBSUFFIX '...'}` is appended to dll and bpl names. The MAP file DX.Comply reads is that binary's name with a `.map` extension, in the same directory. If it is missing, the CLI stops and tells you to set Project Options, Linker, Map file to Detailed, or to add `-GD` to the `.cfg`, then rebuild. `--map-dir` still overrides the directory.

`FileVersion` from `[Version Info Keys]` becomes the root component version (otherwise `MajorVer.MinorVer.Release.Build`). `CompanyName` becomes the supplier when `--supplier` and `product.supplier` are both empty. The root component name stays the project name.

Delphi 7 library units are looked up from `HKCU` or `HKLM\Software\Borland\Delphi\7.0` (`RootDir` and `Library\Search Path`), then from the `DELPHI` environment variable. The scan does not fail when Delphi 7 is not installed; those library units are simply not resolved from an install tree. Pass `--delphi7-root` or set `delphi7Root` in `.dxcomply.json` to point at a Delphi 7 tree. `$(DELPHI)` in the search path expands to that root.

A blank `PackageDLLOutputDir` is treated as the project directory. The Delphi 7 IDE would use its global package output directory instead. Set the directory in the `.dof` or `.cfg` when the BPL is built somewhere else.

The SBOM lists the program or package that was built, plus other binaries in that output directory. Installers and helper tools in subfolders are left out, so the document stays smaller. If the project has no output directory, only binaries in the project directory itself are listed. Use `--scan-dir` for anything you stage on purpose. `--scan-tree` restores the old recursive listing and is deprecated.

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
