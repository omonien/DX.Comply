# Changelog

Released notes for shipped versions are in `docs/releases/`.

## [Unreleased]

### Fixed

- The version of a binary in the SBOM and in the HTML and Markdown reports is the numeric file version (a.b.c.d from the fixed file info). The FileVersion string, then the ProductVersion string, is used only when that fixed file info is absent. A string such as "6, 10, 5, 0" no longer replaces 6.10.5.0 (#188).
