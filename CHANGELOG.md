# Changelog

Released notes for shipped versions are in `docs/releases/`.

## [Unreleased]

### Added

- When an output folder contains more than one executable, DX.Comply writes one info line that names them and points at the Output folders section. The SBOM is unchanged. The docs say first that each project should have its own output folder, and then show `--include=MyTool.exe` for an existing shared folder (#189).
- The command line tool builds a `.dproj`, `.dpk`, or `.groupproj` when the MAP file for the selected configuration and platform is missing. The default deep evidence mode is `when-missing`. Before that build it prints a warning that names the missing MAP file, the configuration, and the platform. `--no-build`, or `"noBuild": true` in `.dxcomply.json`, stops the run with exit code 1 and names the same MAP file, configuration, and platform. With `--ci`, the flag wins over the file. A Delphi 7 project is not compiled. A post-build event should pass the active configuration and platform (#187).
- The product, the project's own binary, and units marked as own code (`own_code_units`, `own_code_prefixes`, `own_code_folders`) take their copyright notice from `LegalCopyright` in the version resource of the built binary. A non-empty top-level `copyright` value in `.dxcomply.json` wins over that resource, including in library mode. The HTML and Markdown Copyright cells use the same notice. When both are empty, CycloneDX still omits `copyright`, SPDX 2.3 keeps `copyrightText` as `NOASSERTION`, and SPDX 3.0.1 omits `software_copyrightText`. A component manifest row keeps its own `copyright` on that library. There is no command-line flag. The IDE project options and the SBOM header dialog do not edit this key (#190).

### Fixed

- The version of a binary in the SBOM and in the HTML and Markdown reports is the numeric file version (a.b.c.d from the fixed file info). The FileVersion string, then the ProductVersion string, is used only when that fixed file info is absent. A string such as "6, 10, 5, 0" no longer replaces 6.10.5.0 (#188).
