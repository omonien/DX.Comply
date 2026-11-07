/// <summary>
/// DX.Comply.IDE.ExpectedMapFile
/// Resolves the MAP file the IDE build confirmation dialog shows.
/// </summary>
///
/// <remarks>
/// The dialog and the Deep-Evidence build must name the same file. This unit
/// asks TProjectScanner for that path, so a custom output directory and
/// $(Platform) / $(Config) are expanded the same way SBOM generation expands
/// them. The missing-file flag uses the path that scan returned.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.IDE.ExpectedMapFile;

interface

type
  /// <summary>
  /// MAP file expected for one configuration and platform.
  /// </summary>
  TExpectedMapFileState = record
    /// <summary>Absolute path generation will read. Empty when it cannot be resolved.</summary>
    Path: string;
    /// <summary>True when Path is set and that file is not on disk yet.</summary>
    Missing: Boolean;
  end;

/// <summary>
/// Resolves the MAP file for AProjectPath built as APlatform / AConfiguration.
/// Empty AProjectPath returns an empty path and Missing = False.
/// </summary>
function ResolveExpectedMapFileState(const AProjectPath, APlatform,
  AConfiguration: string): TExpectedMapFileState;

/// <summary>
/// Short note shown when the expected MAP file is not on disk. Empty when
/// the file is present or the path could not be resolved.
/// </summary>
function ExpectedMapFileMissingHint(const AState: TExpectedMapFileState): string;

const
  /// <summary>
  /// Hint for an expected MAP file that is not on disk yet (issue #153).
  /// </summary>
  scExpectedMapFileMissing =
    'MAP file not found. The Deep-Evidence build will write it.';

implementation

uses
  System.IOUtils,
  System.SysUtils,
  DX.Comply.Engine.Intf,
  DX.Comply.ProjectScanner;

function ResolveExpectedMapFileState(const AProjectPath, APlatform,
  AConfiguration: string): TExpectedMapFileState;
var
  LProjectInfo: TProjectInfo;
  LScanner: IProjectScanner;
begin
  Result.Path := '';
  Result.Missing := False;
  if Trim(AProjectPath) = '' then
    Exit;

  // Same scan SBOM generation uses for this platform and configuration.
  LScanner := TProjectScanner.Create;
  LProjectInfo := LScanner.Scan(AProjectPath, APlatform, AConfiguration);
  try
    Result.Path := LProjectInfo.MapFilePath;
    Result.Missing := (Result.Path <> '') and not TFile.Exists(Result.Path);
  finally
    LProjectInfo.Free;
  end;
end;

function ExpectedMapFileMissingHint(const AState: TExpectedMapFileState): string;
begin
  if AState.Missing then
    Result := scExpectedMapFileMissing
  else
    Result := '';
end;

end.
