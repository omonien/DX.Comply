/// <summary>
/// DX.Comply.FileScanner
/// Scans build output directories for artefacts.
/// </summary>
///
/// <remarks>
/// This unit provides TFileScanner which discovers build artefacts:
/// - Recursively scans output directories
/// - Applies include/exclude glob patterns
/// - Identifies shipped artefact types (exe, dll, bpl, dcp)
/// - Computes file sizes
///
/// Hash computation is delegated to IHashService.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.FileScanner;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Types,
  System.Generics.Collections,
  System.RegularExpressions,
  DX.Comply.Engine.Intf;

type
  /// <summary>
  /// Implementation of IFileScanner for scanning build output directories.
  /// </summary>
  TFileScanner = class(TInterfacedObject, IFileScanner)
  private
    const
      /// <summary>Default shipped file extensions to include.</summary>
      cDefaultExtensions: array[0..3] of string = (
        '.exe', '.dll', '.bpl', '.dcp'
      );
  private
    FHashService: IHashService;
    FIncludePatterns: TArray<string>;
    FExcludePatterns: TArray<string>;
    /// <summary>Cache of compiled regexes keyed by the regex string — avoids recompilation.</summary>
    FRegexCache: TDictionary<string, TRegEx>;
    function MatchesPattern(const APath: string; const APatterns: TArray<string>): Boolean;
    function IsIncluded(const APath: string): Boolean;
    function IsExcluded(const APath: string): Boolean;
    function GlobToRegex(const AGlob: string): string;
    function GetCachedRegex(const ARegexPattern: string): TRegEx;
  public
    /// <summary>
    /// Creates a new TFileScanner instance.
    /// </summary>
    /// <param name="AHashService">Hash service for computing file hashes.</param>
    constructor Create(const AHashService: IHashService); overload;
    /// <summary>
    /// Creates a new TFileScanner instance without hash computation.
    /// </summary>
    constructor Create; overload;
    /// <summary>
    /// Destroys the TFileScanner instance.
    /// </summary>
    destructor Destroy; override;
    // IFileScanner
    function Scan(const ADirectory: string;
      const AIncludePatterns, AExcludePatterns: TArray<string>): TArtefactList;
    function GetArtefactType(const AFilePath: string): string;
  end;

implementation

{ TFileScanner }

constructor TFileScanner.Create(const AHashService: IHashService);
begin
  inherited Create;
  FHashService := AHashService;
  FRegexCache := TDictionary<string, TRegEx>.Create;
end;

constructor TFileScanner.Create;
begin
  Create(nil);
end;

destructor TFileScanner.Destroy;
begin
  FHashService := nil;
  FRegexCache.Free;
  inherited;
end;

function TFileScanner.GetCachedRegex(const ARegexPattern: string): TRegEx;
var
  LRegex: TRegEx;
begin
  if not FRegexCache.TryGetValue(ARegexPattern, LRegex) then
  begin
    LRegex := TRegEx.Create(ARegexPattern, [roIgnoreCase]);
    FRegexCache.Add(ARegexPattern, LRegex);
  end;
  Result := LRegex;
end;

function TFileScanner.GlobToRegex(const AGlob: string): string;
var
  LResult: string;
  I: Integer;
begin
  // Convert glob pattern to regex
  LResult := '^';
  for I := 1 to Length(AGlob) do
  begin
    case AGlob[I] of
      '*': LResult := LResult + '.*';
      '?': LResult := LResult + '.';
      '.', '^', '$', '+', '(', ')', '[', ']', '{', '}', '|', '\':
        LResult := LResult + '\' + AGlob[I];
    else
      LResult := LResult + AGlob[I];
    end;
  end;
  LResult := LResult + '$';
  Result := LResult;
end;

function TFileScanner.MatchesPattern(const APath: string; const APatterns: TArray<string>): Boolean;
var
  LPattern, LNormalizedPattern, LRegex: string;
  I: Integer;
begin
  Result := False;
  for I := 0 to High(APatterns) do
  begin
    LPattern := APatterns[I];
    // Handle directory separators
    LNormalizedPattern := StringReplace(LPattern, '/', '\', [rfReplaceAll]);
    LRegex := GlobToRegex(LNormalizedPattern);
    // Make pattern match anywhere in path if it doesn't start with explicit path
    if (Pos('\', LNormalizedPattern) = 0) and (Pos('/', LPattern) = 0) then
      LRegex := '.*' + LRegex;
    try
      if GetCachedRegex(LRegex).IsMatch(APath) then
      begin
        Result := True;
        Exit;
      end;
    except
      // Invalid pattern — skip silently
    end;
  end;
end;

function TFileScanner.IsIncluded(const APath: string): Boolean;
var
  LExt, LFileExt: string;
  I: Integer;
begin
  // If no include patterns specified, use default extensions
  if Length(FIncludePatterns) = 0 then
  begin
    LFileExt := LowerCase(TPath.GetExtension(APath));
    for I := 0 to High(cDefaultExtensions) do
    begin
      LExt := cDefaultExtensions[I];
      if LFileExt = LExt then
      begin
        Result := True;
        Exit;
      end;
    end;
    Result := False;
  end
  else
    Result := MatchesPattern(APath, FIncludePatterns);
end;

function TFileScanner.IsExcluded(const APath: string): Boolean;
begin
  Result := MatchesPattern(APath, FExcludePatterns);
end;

function TFileScanner.Scan(const ADirectory: string;
  const AIncludePatterns, AExcludePatterns: TArray<string>): TArtefactList;
var
  LFiles: TStringDynArray;
  LFile: string;
  LArtefact: TArtefactInfo;
  LBaseDir: string;
begin
  Result := TArtefactList.Create;

  FIncludePatterns := AIncludePatterns;
  FExcludePatterns := AExcludePatterns;
  LBaseDir := TPath.GetFullPath(ADirectory);

  if not TDirectory.Exists(LBaseDir) then
    Exit;

  // Recursively find all files
  LFiles := TDirectory.GetFiles(LBaseDir, '*', TSearchOption.soAllDirectories);

  for LFile in LFiles do
  begin
    // Skip if excluded
    if IsExcluded(LFile) then
      Continue;

    // Skip if not included
    if not IsIncluded(LFile) then
      Continue;

    // Create artefact info
    LArtefact := Default(TArtefactInfo);
    LArtefact.FilePath := LFile;
    LArtefact.RelativePath := LFile.Remove(0, Length(LBaseDir) + 1);
    LArtefact.ArtefactType := GetArtefactType(LFile);

    try
      LArtefact.FileSize := TFile.GetSize(LFile);

      // Compute hash if hash service is available
      if Assigned(FHashService) then
        LArtefact.Hash := FHashService.ComputeSha256(LFile)
      else
        LArtefact.Hash := '';
    except
      // File might be locked or inaccessible
      LArtefact.FileSize := -1;
      LArtefact.Hash := '';
    end;

    Result.Add(LArtefact);
  end;
end;

function TFileScanner.GetArtefactType(const AFilePath: string): string;
var
  LExt: string;
begin
  LExt := LowerCase(TPath.GetExtension(AFilePath));
  if LExt = '.exe' then
    Result := 'application'
  else if LExt = '.dll' then
    Result := 'library'
  else if LExt = '.bpl' then
    Result := 'package'
  else if LExt = '.dcp' then
    Result := 'dcu-package'
  else if LExt = '.res' then
    Result := 'resource'
  else if LExt = '.rsm' then
    Result := 'map-symbol'
  else if LExt = '.map' then
    Result := 'map'
  else if LExt = '.tvsconfig' then
    Result := 'config'
  else
    Result := 'unknown';
end;

end.
