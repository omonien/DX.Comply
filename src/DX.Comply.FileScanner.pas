/// <summary>
/// DX.Comply.FileScanner
/// Scans build output directories for artefacts.
/// </summary>
///
/// <remarks>
/// This unit provides TFileScanner which discovers build artefacts:
/// - Scans a single output directory (subdirectories only when requested)
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
    /// <summary>Cache of compiled regexes keyed by the regex string. Avoids recompilation.</summary>
    FRegexCache: TDictionary<string, TRegEx>;
    /// <summary>Patterns that could not be compiled during the last Scan.</summary>
    FPatternWarnings: TList<string>;
    function MatchesPattern(const APath: string; const APatterns: TArray<string>): Boolean;
    function IsIncluded(const APath: string): Boolean;
    function IsExcluded(const APath: string): Boolean;
    function GlobToRegex(const AGlob: string): string;
    function GetCachedRegex(const ARegexPattern: string): TRegEx;
    function NormalizeMatchPath(const APath: string): string;
    procedure AddPatternWarning(const APattern, AReason: string);
    procedure PreparePatterns(const APatterns: TArray<string>);
    function IsCompilableGlob(const AGlob: string): Boolean;
    procedure BeginFilter(const AIncludePatterns, AExcludePatterns: TArray<string>);
    function IsUniversalScanPattern(const APattern: string): Boolean;
    procedure ParseScanLocation(const ALocation: string;
      out ARoot, ARequirePattern: string; out ARecursive: Boolean);
    function RelativePathFromRoot(const AFilePath, ARoot: string): string;
    function ScanPrepared(const ADirectory: string; ARecursive: Boolean;
      const ARequirePattern: string): TArtefactList;
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
      const AIncludePatterns, AExcludePatterns: TArray<string>;
      ARecursive: Boolean = False): TArtefactList;
    function ScanLocation(const ALocation, ABaseDir: string;
      const AIncludePatterns, AExcludePatterns: TArray<string>): TArtefactList;
    function CollectFile(const AFilePath, ARelativePath: string;
      const AIncludePatterns, AExcludePatterns: TArray<string>;
      out AArtefact: TArtefactInfo): Boolean;
    function GetArtefactType(const AFilePath: string): string;
    /// <summary>
    /// Warnings from include/exclude patterns that could not be compiled
    /// during the most recent Scan. Empty when every pattern was usable.
    /// </summary>
    function PatternWarnings: TArray<string>;
  end;

implementation

{ TFileScanner }

constructor TFileScanner.Create(const AHashService: IHashService);
begin
  inherited Create;
  FHashService := AHashService;
  FRegexCache := TDictionary<string, TRegEx>.Create;
  FPatternWarnings := TList<string>.Create;
end;

constructor TFileScanner.Create;
begin
  Create(nil);
end;

destructor TFileScanner.Destroy;
begin
  FHashService := nil;
  FRegexCache.Free;
  FPatternWarnings.Free;
  inherited;
end;

function TFileScanner.PatternWarnings: TArray<string>;
begin
  if FPatternWarnings = nil then
    SetLength(Result, 0)
  else
    Result := FPatternWarnings.ToArray;
end;

function TFileScanner.NormalizeMatchPath(const APath: string): string;
begin
  Result := StringReplace(APath, '\', '/', [rfReplaceAll]);
end;

procedure TFileScanner.AddPatternWarning(const APattern, AReason: string);
var
  LMessage: string;
begin
  LMessage := 'Invalid include/exclude pattern "' + APattern + '": ' + AReason;
  if (FPatternWarnings <> nil) and (FPatternWarnings.IndexOf(LMessage) < 0) then
    FPatternWarnings.Add(LMessage);
end;

function TFileScanner.IsCompilableGlob(const AGlob: string): Boolean;
var
  I: Integer;
begin
  Result := True;
  for I := 1 to Length(AGlob) do
    if Ord(AGlob[I]) < 32 then
    begin
      AddPatternWarning(AGlob, 'pattern contains a control character');
      Exit(False);
    end;
end;

procedure TFileScanner.PreparePatterns(const APatterns: TArray<string>);
var
  LPattern: string;
begin
  for LPattern in APatterns do
  begin
    if Trim(LPattern) = '' then
      Continue;
    if not IsCompilableGlob(LPattern) then
      Continue;
    try
      GetCachedRegex(GlobToRegex(LPattern));
    except
      on E: Exception do
        AddPatternWarning(LPattern, E.Message);
    end;
  end;
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
  LGlob: string;
  LResult: string;
  I: Integer;

  procedure AppendLiteral(const AChar: Char);
  begin
    case AChar of
      '.', '^', '$', '+', '(', ')', '[', ']', '{', '}', '|', '\':
        LResult := LResult + '\' + AChar;
    else
      LResult := LResult + AChar;
    end;
  end;

begin
  // Match the path relative to the scan root. '/' and '\' are the same,
  // '*' stays inside one directory, and '**' crosses directories.
  LGlob := StringReplace(AGlob, '\', '/', [rfReplaceAll]);
  LResult := '^';
  I := 1;
  while I <= Length(LGlob) do
  begin
    if (LGlob[I] = '*') and (I < Length(LGlob)) and (LGlob[I + 1] = '*') then
    begin
      Inc(I, 2);
      if (I <= Length(LGlob)) and (LGlob[I] = '/') then
      begin
        Inc(I);
        LResult := LResult + '(?:.*/)?';
      end
      else
        LResult := LResult + '.*';
    end
    else if LGlob[I] = '*' then
    begin
      LResult := LResult + '[^/]*';
      Inc(I);
    end
    else if LGlob[I] = '?' then
    begin
      LResult := LResult + '[^/]';
      Inc(I);
    end
    else
    begin
      AppendLiteral(LGlob[I]);
      Inc(I);
    end;
  end;
  Result := LResult + '$';
end;

function TFileScanner.MatchesPattern(const APath: string; const APatterns: TArray<string>): Boolean;
var
  LPattern, LRegex: string;
  I: Integer;
begin
  Result := False;
  for I := 0 to High(APatterns) do
  begin
    LPattern := APatterns[I];
    if Trim(LPattern) = '' then
      Continue;
    if not IsCompilableGlob(LPattern) then
      Continue;
    try
      LRegex := GlobToRegex(LPattern);
      if GetCachedRegex(LRegex).IsMatch(NormalizeMatchPath(APath)) then
        Exit(True);
    except
      on E: Exception do
        AddPatternWarning(LPattern, E.Message);
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
    Result := MatchesPattern(NormalizeMatchPath(APath), FIncludePatterns);
end;

function TFileScanner.IsExcluded(const APath: string): Boolean;
begin
  Result := MatchesPattern(NormalizeMatchPath(APath), FExcludePatterns);
end;

procedure TFileScanner.BeginFilter(const AIncludePatterns, AExcludePatterns: TArray<string>);
begin
  FIncludePatterns := AIncludePatterns;
  FExcludePatterns := AExcludePatterns;
  if FPatternWarnings <> nil then
    FPatternWarnings.Clear;
  PreparePatterns(FIncludePatterns);
  PreparePatterns(FExcludePatterns);
end;

function TFileScanner.IsUniversalScanPattern(const APattern: string): Boolean;
var
  LPattern: string;
begin
  LPattern := StringReplace(Trim(APattern), '\', '/', [rfReplaceAll]);
  Result := (LPattern = '') or (LPattern = '*') or (LPattern = '**') or
    (LPattern = '**/*');
end;

procedure TFileScanner.ParseScanLocation(const ALocation: string;
  out ARoot, ARequirePattern: string; out ARecursive: Boolean);
var
  LSpec: string;
  LNorm: string;
  LPrefix: string;
  LGlobPos: Integer;
  LSlash: Integer;
  I: Integer;
begin
  ARoot := '';
  ARequirePattern := '';
  ARecursive := False;

  LSpec := Trim(ALocation);
  if LSpec = '' then
    Exit;

  // A trailing separator is not part of the pattern. Keep a drive root intact.
  while (Length(LSpec) > 1) and
        ((LSpec[Length(LSpec)] = '\') or (LSpec[Length(LSpec)] = '/')) do
  begin
    if (Length(LSpec) = 3) and (LSpec[2] = ':') then
      Break;
    Delete(LSpec, Length(LSpec), 1);
  end;

  LNorm := StringReplace(LSpec, '\', '/', [rfReplaceAll]);
  LGlobPos := 0;
  for I := 1 to Length(LNorm) do
    if (LNorm[I] = '*') or (LNorm[I] = '?') then
    begin
      LGlobPos := I;
      Break;
    end;

  if LGlobPos = 0 then
  begin
    ARoot := StringReplace(LNorm, '/', '\', [rfReplaceAll]);
    Exit;
  end;

  ARecursive := Pos('**', LNorm) > 0;
  LPrefix := Copy(LNorm, 1, LGlobPos - 1);
  LSlash := LastDelimiter('/', LPrefix);
  if LSlash <= 0 then
  begin
    ARoot := '';
    ARequirePattern := LNorm;
  end
  else
  begin
    ARoot := StringReplace(Copy(LNorm, 1, LSlash - 1), '/', '\', [rfReplaceAll]);
    ARequirePattern := Copy(LNorm, LSlash + 1, MaxInt);
  end;
end;

function TFileScanner.RelativePathFromRoot(const AFilePath, ARoot: string): string;
begin
  if (ARoot <> '') and AFilePath.StartsWith(ARoot, True) and
     (Length(AFilePath) >= Length(ARoot)) then
    Result := AFilePath.Substring(Length(ARoot))
  else
    Result := AFilePath;

  if (Result <> '') and ((Result[1] = '\') or (Result[1] = '/')) then
    Result := Result.Substring(1);
end;

function TFileScanner.ScanPrepared(const ADirectory: string; ARecursive: Boolean;
  const ARequirePattern: string): TArtefactList;
var
  LFiles: TStringDynArray;
  LFile: string;
  LArtefact: TArtefactInfo;
  LBaseDir: string;
  LSearchOption: TSearchOption;
begin
  Result := TArtefactList.Create;

  // An empty or syntactically invalid directory path must never crash the
  // scan. TPath.GetFullPath raises EInOutArgumentException ("Invalid characters
  // in path") on an empty string or on illegal path characters, for example when
  // a project's output directory could not be resolved from the .dproj and an
  // empty or unresolved path is passed in (issue #47). Treat any such path like a
  // missing directory: return the empty artefact list and let SBOM generation
  // continue.
  if Trim(ADirectory) = '' then
    Exit;

  try
    LBaseDir := TPath.GetFullPath(ADirectory);
  except
    on E: EInOutArgumentException do
      Exit;
  end;

  if not TDirectory.Exists(LBaseDir) then
    Exit;

  // The default walk stays in this directory. Subfolders such as setup\ or
  // an old build tree are a different product and were drowning the SBOM
  // (issue #38). ARecursive is the deprecated --scan-tree path, and a
  // scan-dir value that contains **.
  if ARecursive then
    LSearchOption := TSearchOption.soAllDirectories
  else
    LSearchOption := TSearchOption.soTopDirectoryOnly;

  LFiles := TDirectory.GetFiles(LBaseDir, '*', LSearchOption);

  for LFile in LFiles do
  begin
    LArtefact := Default(TArtefactInfo);
    LArtefact.FilePath := LFile;
    LArtefact.RelativePath := RelativePathFromRoot(LFile, LBaseDir);

    // Include/exclude globs are matched against the path relative to the
    // scan root, so a pattern such as build/** does not depend on the
    // absolute prefix of the project directory.
    if not IsUniversalScanPattern(ARequirePattern) and
       not MatchesPattern(LArtefact.RelativePath, [ARequirePattern]) then
      Continue;
    if IsExcluded(LArtefact.RelativePath) then
      Continue;
    if not IsIncluded(LArtefact.RelativePath) then
      Continue;
    LArtefact.ArtefactType := GetArtefactType(LFile);

    try
      LArtefact.FileSize := TFile.GetSize(LFile);

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

function TFileScanner.Scan(const ADirectory: string;
  const AIncludePatterns, AExcludePatterns: TArray<string>;
  ARecursive: Boolean): TArtefactList;
begin
  BeginFilter(AIncludePatterns, AExcludePatterns);
  Result := ScanPrepared(ADirectory, ARecursive, '');
end;

function TFileScanner.ScanLocation(const ALocation, ABaseDir: string;
  const AIncludePatterns, AExcludePatterns: TArray<string>): TArtefactList;
var
  LRoot: string;
  LRequirePattern: string;
  LRecursive: Boolean;
  LFullRoot: string;
begin
  BeginFilter(AIncludePatterns, AExcludePatterns);
  ParseScanLocation(ALocation, LRoot, LRequirePattern, LRecursive);
  if Trim(ALocation) = '' then
    Exit(TArtefactList.Create);

  if LRoot = '' then
    LFullRoot := ABaseDir
  else if (ABaseDir <> '') and TPath.IsRelativePath(LRoot) then
    LFullRoot := TPath.Combine(ABaseDir, LRoot)
  else
    LFullRoot := LRoot;

  Result := ScanPrepared(LFullRoot, LRecursive, LRequirePattern);
end;

function TFileScanner.CollectFile(const AFilePath, ARelativePath: string;
  const AIncludePatterns, AExcludePatterns: TArray<string>;
  out AArtefact: TArtefactInfo): Boolean;
begin
  Result := False;
  AArtefact := Default(TArtefactInfo);
  BeginFilter(AIncludePatterns, AExcludePatterns);

  if Trim(AFilePath) = '' then
    Exit;
  if IsExcluded(ARelativePath) then
    Exit;
  if not IsIncluded(ARelativePath) then
    Exit;

  AArtefact.FilePath := AFilePath;
  AArtefact.RelativePath := ARelativePath;
  AArtefact.ArtefactType := GetArtefactType(AFilePath);
  AArtefact.FileSize := -1;
  AArtefact.Hash := '';

  // The project output is part of the SBOM even when the binary has not
  // been built yet. Hash and size are filled in only when the file is there.
  if TFile.Exists(AFilePath) then
  begin
    try
      AArtefact.FileSize := TFile.GetSize(AFilePath);
      if Assigned(FHashService) then
        AArtefact.Hash := FHashService.ComputeSha256(AFilePath);
    except
      AArtefact.FileSize := -1;
      AArtefact.Hash := '';
    end;
  end;
  Result := True;
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
