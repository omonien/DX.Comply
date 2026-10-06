# Locating the repository from tests

`RepoRoot` in `DX.Comply.Tests.Paths` returns the DX.Comply checkout used by the integration tests. A valid root is a directory that contains both `src\DX.Comply.Engine.dproj` and `README.md`.

The search stops at the first match:

1. Environment variable `DXCOMPLY_REPO_ROOT`, when that value is the repository root. A relative value is resolved from the process current directory.
2. Ancestor folders of the test executable (`ExtractFilePath(ParamStr(0))`). This is the layout used by a local `build\Win32\Debug` (or `build\Win64\Release`) output.
3. Ancestor folders of the process current directory.
4. The file `dxcomply-repo-root.txt` in the same directory as the executable. The first line is the repository root, or a path inside the checkout such as a `.dproj`. A path inside the checkout is walked upward. Delphi cannot embed the compiling source directory, so the build server writes this file when the executable is not inside the checkout.
5. Sibling checkout layout. From the executable directory, walk upward to the first folder that contains `sources`. That folder is used only when exactly one `sources\*\src\DX.Comply.Engine.dproj` exists, and that checkout also contains `README.md`.

On the Delphi build server the executable is `builds\<id>\bin\DX.Comply.Tests.exe` and the git checkout is `sources\<name>\`. Step 2 does not see that checkout. Step 3 works when the current directory is the checkout. Step 5 works when `builds` and `sources` share a parent and only one checkout is present. Step 4 works when the server writes `dxcomply-repo-root.txt` next to the executable.

If every step fails, `RepoRoot` raises an exception that names each place that was searched.

`DX.Comply.IDE.PathSupport` uses the same order, starting from the loaded module rather than `ParamStr(0)`. That is what lets `LoadDXComplyReadmeMarkdown` find `README.md` when the test executable sits outside the checkout.
