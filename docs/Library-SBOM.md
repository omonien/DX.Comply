# Library SBOM

DX.Comply has two modes. Pick the one that matches what you ship.

## Build mode (default)

You ship a program, a DLL, or a runtime package. DX.Comply reads the `.dproj`, the MAP file, the DCUs, and the output directory of one build. The SBOM describes that build: the binary, the runtime packages it loads, the DLLs it references, and the units that were linked into it.

```cmd
dxcomply --project=MyApp.dproj --config=Release --platform=Win64 --no-pause
```

## Library mode (`--library`)

You ship source code: a component set, a library on GitHub, a ZIP for GetIt. Your customer compiles it. There is no binary of yours, so build evidence would describe your own test build, not the release.

Library mode describes the source release:

| Part | Content |
|---|---|
| Root component | Type `library`, name, version, licence, supplier, supplier URL, package URL |
| File components | One per shipped source file, type `file`, relative path, SHA-256, SHA-512 |
| Required packages | One per name in the `.dpk` requires clause. `rtl`, `vcl`, and `fmx` are `framework` with the Delphi version |
| Compositions | Files complete when every file was hashed. Required packages complete when a requires clause was read, otherwise `unknown` |
| Property | `net.developer-experts.dx-comply:document.profile` = `library-source` |

### Which files are listed

- `--project` with a `.dpk`: the package file and every unit in the contains clause that has an `in` path, plus a `.dfm` or `.fmx` next to it.
- `--project` with a `.dpr`: the program file and every uses entry that has an `in` path. RTL and search path units have no path and are not listed.
- `--project` with a `.dproj`: the `.dpk` or `.dpr` named as MainSource. Name and version come from the project version info.
- `--source-dir=<dir>`: every `.pas`, `.inc`, `.dpk`, `.dpr`, `.dproj`, `.dfm`, `.fmx`, `.res`, `.dcr`, and `.rc` file under the directory, recursively. Repeat the option for more directories. A relative path is resolved from the project directory. `include` and `exclude` patterns apply.

Both sets are merged. A file appears once. `{$I}` directives are not followed, so pass `--source-dir` when the release contains include files.

### Version and package URL

`--version` overrides the project version. Set it when the version info still says 1.0.0.0, which also raises a CRA warning. `--purl` sets the package URL. Without it, `--repo-url=https://github.com/<owner>/<repo>` gives `pkg:github/<owner>/<repo>@<version>`. Other hosts get no derived purl.

### Example

```cmd
dxcomply --library --project=Source\DEC60.dproj --source-dir=Source --version=6.4.1 ^
  --purl=pkg:github/MHumm/DelphiEncryptionCompendium@V6.4.1 --licence=Apache-2.0 ^
  --supplier="Team DEC" --supplier-url=https://github.com/MHumm/DelphiEncryptionCompendium ^
  --sbom-creator=markus.humm@gmail.com --report=html --no-pause
```

### Config file

```json
{
  "library": true,
  "sourceDirs": ["Source"],
  "product": {
    "version": "6.4.1",
    "licence": "Apache-2.0",
    "repoUrl": "https://github.com/MHumm/DelphiEncryptionCompendium"
  }
}
```

The file is read with `--ci`. With `library` set in the file, `--project` may be left out when `sourceDirs` is set.

### What library mode does not do

It does not compile, read MAP files, or hash binaries. It does not resolve third party units that the library uses from the search path. It does not follow `{$I}` directives or `{$IFDEF}` branches. A customer who builds a product with the library still runs build mode on that product.
