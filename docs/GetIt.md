# GetIt install and uninstall

GetIt installs the DX.Comply IDE plugin from the release ZIP. The GetIt package definition is maintained by Embarcadero, not in this repository. It copies the ZIP to

```
%USERPROFILE%\Documents\Embarcadero\Studio\37.0\CatalogRepository\DXComply-13\<version>
```

and adds folders of that copy, for example `lib`, `src` and `assets`, to the Delphi library path and browsing path.

## Hint H2675 after an uninstall

If the CatalogRepository copy is removed but the path entries stay, every compile in any project shows hints like:

```
[dcc32 Hint] H2675 Directory not found: C:\Users\<user>\Documents\Embarcadero\Studio\37.0\CatalogRepository\DXComply-13\1.0.1\lib
```

The entries are written and removed by GetIt. DX.Comply does not add them. The hints are harmless, but you can remove the entries.

### Remove the entries in the IDE

1. Open **Tools > Options > Language > Delphi > Library**.
2. Select a platform, for example **Windows 32-bit**.
3. Open **Library path**, remove every entry that contains `CatalogRepository\DXComply-`, and confirm.
4. Do the same for **Browsing path** and **Debug DCU path**.
5. Repeat for each platform that shows the hints, for example **Windows 64-bit**.

### Remove the entries in the registry

Close RAD Studio first. The IDE writes these values back when it closes.

Key, one per platform (`Win32`, `Win64`, and so on):

```
HKEY_CURRENT_USER\Software\Embarcadero\BDS\37.0\Library\<platform>
```

Values: `Search Path`, `Browsing Path`, `Debug DCU Path`. Each is a list separated by semicolons. Remove the entries that contain `CatalogRepository\DXComply-` and point to a folder that no longer exists. An entry can also be written as `$(BDSCatalogRepository)\DXComply-13\1.0.1\lib`.

### The Delphi 13 installer cleans up

Starting with the next release, the Delphi 13 installer (`DX.Comply.D13.Setup.exe`) removes these entries when it installs and when it is uninstalled. It removes only entries under a `DXComply-*` folder of the CatalogRepository whose folder does not exist, so an installed GetIt copy is not affected. Close RAD Studio before you run the installer or the uninstaller.
