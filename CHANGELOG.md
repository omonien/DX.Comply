# Changelog

Released notes for shipped versions are in `docs/releases/`.

## [Unreleased]

### Added

- When an output folder contains more than one executable, DX.Comply writes one info line that names them and points at the Output folders section. The SBOM is unchanged. The docs say first that each project should have its own output folder, and then show `--include=MyTool.exe` for an existing shared folder (#189).

### Fixed

- The version of a binary in the SBOM and in the HTML and Markdown reports is the numeric file version (a.b.c.d from the fixed file info). The FileVersion string, then the ProductVersion string, is used only when that fixed file info is absent. A string such as "6, 10, 5, 0" no longer replaces 6.10.5.0 (#188).
