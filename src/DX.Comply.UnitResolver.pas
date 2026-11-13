/// <summary>
/// DX.Comply.UnitResolver
/// First-pass implementation of composition evidence resolution.
/// </summary>
///
/// <remarks>
/// Resolves units from the MAP file, and from uses clauses when the MAP is
/// missing or the platform is not Win32 or Win64. A readable .pas is parsed
/// once. The uses-clause walk and CacheUsedUnits share that result, and the
/// SBOM writers read it from the resolved unit.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.UnitResolver;

interface

uses
  System.Generics.Defaults,
  System.Generics.Collections,
  DX.Comply.BuildEvidence.Intf,
  DX.Comply.ComponentManifest,
  DX.Comply.Engine.Intf;

type
  /// <summary>
  /// Implementation of IUnitResolver for the first composition evidence slice.
  /// </summary>
  TUnitResolver = class(TInterfacedObject, IUnitResolver)
  private
    FHashService: IHashService;
    FRecursiveSearchCache: TDictionary<string, string>;
    /// <summary>
    /// Uses names already parsed for a .pas, keyed by the full path in
    /// lower case. The uses-clause walk fills it. CacheUsedUnits reads it.
    /// </summary>
    FUsesClauseCache: TDictionary<string, TArray<string>>;
    /// <summary>
    /// Copies unique warning entries from the source list into the target list.
    /// </summary>
    procedure CopyUniqueWarnings(const ASource, ATarget: TList<string>);
    /// <summary>
    /// Adds unique map-derived units to the composition evidence result.
    /// </summary>
    procedure AddMapDerivedUnits(const AProjectInfo: TProjectInfo;
      const ABuildEvidence: TBuildEvidence;
      var ACompositionEvidence: TCompositionEvidence);
    /// <summary>
    /// Builds candidate filenames for a unit name.
    /// </summary>
    function BuildCandidateFileNames(const AUnitName: string): TArray<string>;
    /// <summary>
    /// Maps a resolved file path to the concrete evidence kind.
    /// </summary>
    function DetermineEvidenceKind(const AResolvedPath: string): TUnitEvidenceKind;
    /// <summary>
    /// Classifies the resolved unit origin by path and namespace.
    /// </summary>
    function DetermineOriginKind(const AProjectInfo: TProjectInfo;
      const AUnitName, AResolvedPath: string): TUnitOriginKind;
    /// <summary>
    /// Finds the first direct candidate inside the supplied search paths.
    /// </summary>
    function FindExistingDirectCandidate(const ASearchPaths: TList<string>;
      const ACandidateFileNames: TArray<string>; out AResolvedPath: string;
      out AUsedFallbackName: Boolean): Boolean;
    /// <summary>
    /// Finds the first recursive candidate inside the supplied search roots.
    /// </summary>
    function FindExistingRecursiveCandidate(const ASearchPaths: TList<string>;
      const ACandidateFileNames: TArray<string>; out AResolvedPath: string;
      out AUsedFallbackName: Boolean): Boolean;
    /// <summary>
    /// Infers the origin kind from the unit name namespace when no file can be resolved.
    /// </summary>
    function InferOriginFromUnitName(const AProjectInfo: TProjectInfo;
      const AUnitName: string): TUnitOriginKind;
    /// <summary>
    /// Returns True when APath is located below ABaseDirectory.
    /// </summary>
    function IsPathUnderDirectory(const APath, ABaseDirectory: string): Boolean;
    /// <summary>
    /// True when APath lies in a product source tree or a product lib folder
    /// below the Delphi root. Extras, a GetIt catalog repository, and any
    /// other folder under the install are not included.
    /// </summary>
    function IsEmbarcaderoShippedPath(const APath, ARootDir: string): Boolean;
    /// <summary>
    /// Finds AUnitName.pas in a build search path that is not an output
    /// folder. Used to classify a DCU found in the DCU output folder.
    /// </summary>
    function FindSourceOutsideOutputDirs(const ABuildEvidence: TBuildEvidence;
      const AUnitName: string; out ASourcePath: string): Boolean;
    /// <summary>
    /// Resolves a unit by searching build output, project and global paths.
    /// Shared resolution logic used by both MAP-derived and uses-clause-derived evidence.
    /// </summary>
    function ResolveUnitBySearchPaths(const AProjectInfo: TProjectInfo;
      const ABuildEvidence: TBuildEvidence; const AUnitName: string;
      AEvidenceSource: TBuildEvidenceSourceKind): TResolvedUnitInfo;
    /// <summary>
    /// Resolves one map-derived unit into richer composition evidence.
    /// </summary>
    function ResolveMapDerivedUnit(const AProjectInfo: TProjectInfo;
      const ABuildEvidence: TBuildEvidence; const AUnitName, AMapFilePath: string): TResolvedUnitInfo;
    /// <summary>
    /// Adds uses-clause-derived units as fallback for LLVM platforms or missing MAP evidence.
    /// </summary>
    procedure AddUsesClauseDerivedUnits(const AProjectInfo: TProjectInfo;
      const ABuildEvidence: TBuildEvidence;
      var ACompositionEvidence: TCompositionEvidence);
    /// <summary>
    /// Computes SHA-256 and SHA-512 hashes for the resolved file path.
    /// </summary>
    procedure ComputeHashes(var AResolvedUnit: TResolvedUnitInfo);
    /// <summary>
    /// Reads the uses clause of a resolved .pas once. A DCU is marked cached
    /// with an empty name list so writers do not open it.
    /// </summary>
    procedure CacheUsedUnits(var AResolvedUnit: TResolvedUnitInfo);
  public
    /// <summary>
    /// Returns True for classic-compiler platforms (Win32, Win64) that produce MAP files.
    /// Returns False for LLVM platforms (iOS, Android, macOS, Linux, WinARM64).
    /// </summary>
    class function IsClassicCompilerPlatform(const APlatform: string): Boolean;
    constructor Create; overload;
    constructor Create(const AHashService: IHashService); overload;
    destructor Destroy; override;
    /// <summary>
    /// Resolves the first-pass composition evidence envelope.
    /// </summary>
    function Resolve(const AProjectInfo: TProjectInfo;
      const ABuildEvidence: TBuildEvidence): TCompositionEvidence;
  end;

/// <summary>
/// A units_exact, units_prefix, or units_folder match names a third-party
/// library. That match wins over a Delphi-install location that classified
/// the unit as Embarcadero. The origin becomes Third party. A unit that
/// does not match, including a product RTL unit, is left as resolved.
/// </summary>
procedure ApplyManifestOverInstallOrigin(const AManifest: TComponentManifest;
  const AInstallRoot: string; const AUnits: TResolvedUnitList);

implementation

uses
  System.Classes,
  System.IOUtils,
  System.DateUtils,
  System.StrUtils,
  System.SysUtils,
  DX.Comply.UsesClauseParser;

constructor TUnitResolver.Create;
begin
  inherited Create;
  FRecursiveSearchCache := TDictionary<string, string>.Create;
  FUsesClauseCache := TDictionary<string, TArray<string>>.Create;
end;

constructor TUnitResolver.Create(const AHashService: IHashService);
begin
  Create;
  FHashService := AHashService;
end;

class function TUnitResolver.IsClassicCompilerPlatform(const APlatform: string): Boolean;
begin
  Result := SameText(APlatform, 'Win32') or SameText(APlatform, 'Win64');
end;

procedure TUnitResolver.ComputeHashes(var AResolvedUnit: TResolvedUnitInfo);
begin
  if not Assigned(FHashService) then
    Exit;
  if (AResolvedUnit.ResolvedPath = '') or not TFile.Exists(AResolvedUnit.ResolvedPath) then
    Exit;

  AResolvedUnit.SecondaryHashSha256 := FHashService.ComputeSha256(AResolvedUnit.ResolvedPath);
  AResolvedUnit.PrimaryHashSha512 := FHashService.ComputeSha512(AResolvedUnit.ResolvedPath);
end;

procedure TUnitResolver.CacheUsedUnits(var AResolvedUnit: TResolvedUnitInfo);
var
  LPath: string;
  LKey: string;
  LLines: TStringList;
  LText: string;
begin
  AResolvedUnit.UsesCached := True;
  AResolvedUnit.UsedUnitNames := nil;
  LPath := AResolvedUnit.ResolvedPath;
  if (LPath = '') or not SameText(TPath.GetExtension(LPath), '.pas') then
    Exit;
  if not TFile.Exists(LPath) then
    Exit;

  // The uses-clause walk already parsed this file. Reuse that list.
  LKey := LowerCase(TPath.GetFullPath(LPath));
  if Assigned(FUsesClauseCache) and FUsesClauseCache.TryGetValue(LKey,
    AResolvedUnit.UsedUnitNames) then
    Exit;

  LLines := TStringList.Create;
  try
    try
      LLines.LoadFromFile(LPath, TEncoding.UTF8);
    except
      try
        LLines.LoadFromFile(LPath);
      except
        // The writer may try once more. A failed read is not an empty clause.
        AResolvedUnit.UsesCached := False;
        Exit;
      end;
    end;
    LText := LLines.Text;
  finally
    LLines.Free;
  end;
  AResolvedUnit.UsedUnitNames := TUsesClauseParser.ExtractUsedUnits(LText);
  if Assigned(FUsesClauseCache) then
    FUsesClauseCache.AddOrSetValue(LKey, AResolvedUnit.UsedUnitNames);
end;

destructor TUnitResolver.Destroy;
begin
  FUsesClauseCache.Free;
  FRecursiveSearchCache.Free;
  inherited;
end;

procedure TUnitResolver.CopyUniqueWarnings(const ASource, ATarget: TList<string>);
var
  LWarning: string;
begin
  if not Assigned(ASource) or not Assigned(ATarget) then
    Exit;

  for LWarning in ASource do
  begin
    if not ATarget.Contains(LWarning) then
      ATarget.Add(LWarning);
  end;
end;

function TUnitResolver.BuildCandidateFileNames(const AUnitName: string): TArray<string>;
var
  LFileNames: TList<string>;
  LShortUnitName: string;
  procedure AddUniqueCandidate(const AFileName: string);
  begin
    if (Trim(AFileName) <> '') and not LFileNames.Contains(AFileName) then
      LFileNames.Add(AFileName);
  end;
begin
  LFileNames := TList<string>.Create;
  try
    AddUniqueCandidate(AUnitName + '.pas');
    AddUniqueCandidate(AUnitName + '.dcu');
    AddUniqueCandidate(AUnitName + '.dcp');
    AddUniqueCandidate(AUnitName + '.bpl');

    LShortUnitName := AUnitName;
    if Pos('.', LShortUnitName) > 0 then
      LShortUnitName := LShortUnitName.Split(['.'])[High(LShortUnitName.Split(['.']))];

    AddUniqueCandidate(LShortUnitName + '.pas');
    AddUniqueCandidate(LShortUnitName + '.dcu');
    AddUniqueCandidate(LShortUnitName + '.dcp');
    AddUniqueCandidate(LShortUnitName + '.bpl');
    Result := LFileNames.ToArray;
  finally
    LFileNames.Free;
  end;
end;

function TUnitResolver.DetermineEvidenceKind(const AResolvedPath: string): TUnitEvidenceKind;
begin
  if SameText(TPath.GetExtension(AResolvedPath), '.pas') then
    Exit(uekPas);
  if SameText(TPath.GetExtension(AResolvedPath), '.dcu') then
    Exit(uekDcu);
  if SameText(TPath.GetExtension(AResolvedPath), '.dcp') then
    Exit(uekDcp);
  if SameText(TPath.GetExtension(AResolvedPath), '.bpl') then
    Exit(uekBpl);

  Result := uekUnknown;
end;

function TUnitResolver.DetermineOriginKind(const AProjectInfo: TProjectInfo;
  const AUnitName, AResolvedPath: string): TUnitOriginKind;
var
  LSearchPath: string;
begin
  if Trim(AResolvedPath) = '' then
    Exit(uokUnknown);

  if IsPathUnderDirectory(AResolvedPath, AProjectInfo.ProjectDir) then
    Exit(uokLocalProject);

  // Units resolved from a path that is explicitly listed in the project's own
  // search paths belong to the project even when they live outside the project
  // directory (e.g. sibling directories such as ..\SharedUnits\).  Issue #22.
  // A search path inside the Delphi installation is a shared library folder,
  // not project code (issue #133).
  if Assigned(AProjectInfo.ProjectSearchPaths) then
    for LSearchPath in AProjectInfo.ProjectSearchPaths do
      if (Trim(LSearchPath) <> '') and
         IsPathUnderDirectory(AResolvedPath, LSearchPath) and
         not ((Trim(AProjectInfo.Toolchain.RootDir) <> '') and
              IsPathUnderDirectory(LSearchPath, AProjectInfo.Toolchain.RootDir)) then
        Exit(uokLocalProject);

  // Only product source trees and product lib folders count as Embarcadero.
  // Extras, a GetIt catalog repository, and a folder added under the
  // install are third-party code (issue #134).
  if IsEmbarcaderoShippedPath(AResolvedPath, AProjectInfo.Toolchain.RootDir) then
  begin
    if StartsText('Vcl.', AUnitName) or (Pos('\source\vcl\', LowerCase(AResolvedPath)) > 0) then
      Exit(uokEmbarcaderoVcl);
    if StartsText('Fmx.', AUnitName) or (Pos('\source\fmx\', LowerCase(AResolvedPath)) > 0) then
      Exit(uokEmbarcaderoFmx);
    Exit(uokEmbarcaderoRtl);
  end;

  Result := uokThirdParty;
end;

function TUnitResolver.FindExistingDirectCandidate(const ASearchPaths: TList<string>;
  const ACandidateFileNames: TArray<string>; out AResolvedPath: string;
  out AUsedFallbackName: Boolean): Boolean;
var
  I: Integer;
  LCandidatePath: string;
  LSearchPath: string;
begin
  Result := False;
  AResolvedPath := '';
  AUsedFallbackName := False;
  if not Assigned(ASearchPaths) then
    Exit;

  for LSearchPath in ASearchPaths do
  begin
    if Trim(LSearchPath) = '' then
      Continue;

    for I := 0 to High(ACandidateFileNames) do
    begin
      LCandidatePath := TPath.Combine(LSearchPath, ACandidateFileNames[I]);
      if not TFile.Exists(LCandidatePath) then
        Continue;

      AResolvedPath := TPath.GetFullPath(LCandidatePath);
      AUsedFallbackName := I >= 4;
      Exit(True);
    end;
  end;
end;

function TUnitResolver.FindExistingRecursiveCandidate(const ASearchPaths: TList<string>;
  const ACandidateFileNames: TArray<string>; out AResolvedPath: string;
  out AUsedFallbackName: Boolean): Boolean;
var
  I: Integer;
  LCacheKey: string;
  LFiles: TArray<string>;
  LSearchPath: string;
begin
  Result := False;
  AResolvedPath := '';
  AUsedFallbackName := False;
  if not Assigned(ASearchPaths) then
    Exit;

  for LSearchPath in ASearchPaths do
  begin
    if not TDirectory.Exists(LSearchPath) then
      Continue;

    for I := 0 to High(ACandidateFileNames) do
    begin
      LCacheKey := LowerCase(LSearchPath + '|' + ACandidateFileNames[I]);
      if FRecursiveSearchCache.TryGetValue(LCacheKey, AResolvedPath) then
      begin
        if AResolvedPath <> '' then
        begin
          AUsedFallbackName := I >= 4;
          Exit(True);
        end;
        Continue;
      end;

      LFiles := TDirectory.GetFiles(LSearchPath, ACandidateFileNames[I], TSearchOption.soAllDirectories);
      if Length(LFiles) = 0 then
      begin
        FRecursiveSearchCache.AddOrSetValue(LCacheKey, '');
        Continue;
      end;

      AResolvedPath := TPath.GetFullPath(LFiles[0]);
      FRecursiveSearchCache.AddOrSetValue(LCacheKey, AResolvedPath);
      AUsedFallbackName := I >= 4;
      Exit(True);
    end;
  end;
end;

function TUnitResolver.InferOriginFromUnitName(const AProjectInfo: TProjectInfo;
  const AUnitName: string): TUnitOriginKind;
begin
  if StartsText('Vcl.', AUnitName) or SameText(AUnitName, 'Vcl') then
    Exit(uokEmbarcaderoVcl);
  if StartsText('Fmx.', AUnitName) or SameText(AUnitName, 'Fmx') or StartsText('FMX.', AUnitName) then
    Exit(uokEmbarcaderoFmx);
  if StartsText('System.', AUnitName) or SameText(AUnitName, 'System') or
     SameText(AUnitName, 'SysInit') or
     StartsText('Winapi.', AUnitName) or
     StartsText('Posix.', AUnitName) or
     StartsText('Macapi.', AUnitName) or
     StartsText('iOSapi.', AUnitName) or
     StartsText('Androidapi.', AUnitName) or
     StartsText('Data.', AUnitName) or
     StartsText('Datasnap.', AUnitName) or
     StartsText('Xml.', AUnitName) or
     StartsText('Web.', AUnitName) or
     StartsText('Soap.', AUnitName) or
     StartsText('REST.', AUnitName) or
     StartsText('Net.', AUnitName) then
    Exit(uokEmbarcaderoRtl);

  Result := uokLocalProject;
end;

function PathIsUnderDirectory(const APath, ABaseDirectory: string): Boolean;
var
  LNormalizedBase: string;
  LNormalizedPath: string;
begin
  Result := False;
  if (Trim(APath) = '') or (Trim(ABaseDirectory) = '') then
    Exit;

  LNormalizedBase := IncludeTrailingPathDelimiter(LowerCase(TPath.GetFullPath(ABaseDirectory)));
  LNormalizedPath := LowerCase(TPath.GetFullPath(APath));
  Result := StartsText(LNormalizedBase, LNormalizedPath) or
    SameText(ExcludeTrailingPathDelimiter(LNormalizedBase), LNormalizedPath);
end;

function TUnitResolver.IsPathUnderDirectory(const APath, ABaseDirectory: string): Boolean;
begin
  Result := PathIsUnderDirectory(APath, ABaseDirectory);
end;

type
  TFirstSegment = record
    Name: string;
    HasMore: Boolean;
  end;

function FirstPathSegment(const APath, ABaseDirectory: string): TFirstSegment;
var
  LBase: string;
  LPath: string;
  LRest: string;
  LSlash: Integer;
begin
  Result.Name := '';
  Result.HasMore := False;
  if not PathIsUnderDirectory(APath, ABaseDirectory) then
    Exit;

  LBase := ExcludeTrailingPathDelimiter(LowerCase(TPath.GetFullPath(ABaseDirectory)));
  LPath := LowerCase(TPath.GetFullPath(APath));
  if NativeInt(Length(LPath)) <= NativeInt(Length(LBase)) then
    Exit;

  LRest := Copy(LPath, Length(LBase) + 1, MaxInt);
  if StartsText('\', LRest) or StartsText('/', LRest) then
    LRest := Copy(LRest, 2, MaxInt);
  if NativeInt(Length(LRest)) = 0 then
    Exit;

  LSlash := Pos('\', LRest);
  if LSlash = 0 then
    LSlash := Pos('/', LRest);
  if LSlash = 0 then
    Result.Name := LRest
  else
  begin
    Result.Name := Copy(LRest, 1, LSlash - 1);
    Result.HasMore := NativeInt(Length(LRest)) > NativeInt(LSlash);
  end;
end;

function IsReleaseOrDebugFolder(const AName: string): Boolean;
begin
  Result := SameText(AName, 'release') or SameText(AName, 'debug');
end;

function IsDelphiLibPlatform(const AName: string): Boolean;
const
  cPlatforms: array[0..21] of string = (
    'win32', 'win64', 'win64x', 'winarm64',
    'linux32', 'linux64', 'linuxarm64',
    'osx32', 'osx64', 'osxarm64', 'macos64', 'macosarm64',
    'android', 'android32', 'android64',
    'iosdevice', 'iosdevice32', 'iosdevice64',
    'iossim32', 'iossim64', 'iossimarm64', 'iossimulator');
var
  i: Integer;
begin
  Result := False;
  for i := Low(cPlatforms) to High(cPlatforms) do
    if SameText(AName, cPlatforms[i]) then
      Exit(True);
end;

function IsEmbarcaderoSourcePath(const APath, ARootDir: string): Boolean;
const
  // First-level folders of the product source tree. A library copied into
  // source\, or installed under Extras or CatalogRepository, is not here.
  cSourceFolders: array[0..23] of string = (
    'rtl', 'vcl', 'fmx', 'data', 'databinding', 'dataexplorer',
    'dunit', 'dunitx', 'experts', 'flatbox2d', 'ibx',
    'indy', 'indy10', 'indyimpl', 'internet', 'property editors',
    'soap', 'tethering', 'toolsapi', 'visualizers', 'xml',
    'db', 'websnap', 'clx');
var
  i: Integer;
  LFolder: TFirstSegment;
  LSource: string;
begin
  Result := False;
  LSource := TPath.Combine(ARootDir, 'source');
  if not PathIsUnderDirectory(APath, LSource) then
    Exit;
  LFolder := FirstPathSegment(APath, LSource);
  if LFolder.Name = '' then
    Exit;
  for i := Low(cSourceFolders) to High(cSourceFolders) do
    if SameText(LFolder.Name, cSourceFolders[i]) then
      Exit(True);
end;

function IsEmbarcaderoLibPath(const APath, ARootDir: string): Boolean;
var
  LFirst: TFirstSegment;
  LLib: string;
  LSecond: TFirstSegment;
begin
  // Product DCUs live in lib\<platform>\release, lib\<platform>\debug,
  // directly in lib\<platform>, or (older installs) directly in lib.
  // lib\<package>\... is a library added under the install.
  Result := False;
  LLib := TPath.Combine(ARootDir, 'lib');
  if not PathIsUnderDirectory(APath, LLib) then
    Exit;

  LFirst := FirstPathSegment(APath, LLib);
  if LFirst.Name = '' then
    Exit;
  if not LFirst.HasMore then
    Exit(True);
  if IsReleaseOrDebugFolder(LFirst.Name) then
    Exit(True);

  // release and debug count only under a product platform folder.
  // lib\SomeLibrary\release is a folder added under the install.
  LSecond := FirstPathSegment(APath, TPath.Combine(LLib, LFirst.Name));
  if not IsDelphiLibPlatform(LFirst.Name) then
    Exit;
  if IsReleaseOrDebugFolder(LSecond.Name) then
    Exit(True);
  if not LSecond.HasMore then
    Exit(True);
end;

function TUnitResolver.IsEmbarcaderoShippedPath(const APath, ARootDir: string): Boolean;
begin
  Result := IsEmbarcaderoSourcePath(APath, ARootDir) or
    IsEmbarcaderoLibPath(APath, ARootDir);
end;

function ManifestSourcePath(const AUnit: TResolvedUnitInfo): string;
begin
  // Same path the manifest folder rule uses: the recorded source, or the
  // resolved .pas. A DCU in the output folder has no folder match without
  // a source path.
  Result := Trim(AUnit.SourcePath);
  if Result <> '' then
    Exit;
  if SameText(TPath.GetExtension(AUnit.ResolvedPath), '.pas') then
    Result := AUnit.ResolvedPath;
end;

function InstallLocationPath(const AUnit: TResolvedUnitInfo): string;
begin
  Result := Trim(AUnit.SourcePath);
  if Result = '' then
    Result := AUnit.ResolvedPath;
end;

procedure ApplyManifestOverInstallOrigin(const AManifest: TComponentManifest;
  const AInstallRoot: string; const AUnits: TResolvedUnitList);
var
  i: Integer;
  LLocation: string;
  LMatch: TManifestMatch;
  LUnit: TResolvedUnitInfo;
begin
  if not AManifest.Loaded or not Assigned(AUnits) then
    Exit;
  if Trim(AInstallRoot) = '' then
    Exit;

  for i := 0 to AUnits.Count - 1 do
  begin
    LUnit := AUnits[i];
    if not (LUnit.OriginKind in [uokEmbarcaderoRtl, uokEmbarcaderoVcl,
      uokEmbarcaderoFmx]) then
      Continue;

    LLocation := InstallLocationPath(LUnit);
    if not PathIsUnderDirectory(LLocation, AInstallRoot) and
      not PathIsUnderDirectory(LUnit.ResolvedPath, AInstallRoot) then
      Continue;

    LMatch := MatchManifestUnit(AManifest, LUnit.UnitName,
      ManifestSourcePath(LUnit));
    if LMatch.Kind <> mmLibrary then
      Continue;

    LUnit.OriginKind := uokThirdParty;
    AUnits[i] := LUnit;
  end;
end;

procedure TUnitResolver.AddMapDerivedUnits(const AProjectInfo: TProjectInfo;
  const ABuildEvidence: TBuildEvidence;
  var ACompositionEvidence: TCompositionEvidence);
var
  LEvidenceItem: TBuildEvidenceItem;
  LExistingResolvedUnit: TResolvedUnitInfo;
  LIsDuplicate: Boolean;
  LResolvedUnit: TResolvedUnitInfo;
begin
  for LEvidenceItem in ABuildEvidence.EvidenceItems do
  begin
    if (LEvidenceItem.SourceKind <> besMapFile) or (Trim(LEvidenceItem.UnitName) = '') then
      Continue;

    LIsDuplicate := False;
    for LExistingResolvedUnit in ACompositionEvidence.Units do
    begin
      if SameText(LExistingResolvedUnit.UnitName, LEvidenceItem.UnitName) then
      begin
        LIsDuplicate := True;
        Break;
      end;
    end;

    if LIsDuplicate then
      Continue;

    LResolvedUnit := ResolveMapDerivedUnit(AProjectInfo,
      ABuildEvidence, LEvidenceItem.UnitName, LEvidenceItem.FilePath);
    ComputeHashes(LResolvedUnit);
    CacheUsedUnits(LResolvedUnit);
    ACompositionEvidence.Units.Add(LResolvedUnit);
  end;
end;

function TUnitResolver.FindSourceOutsideOutputDirs(const ABuildEvidence: TBuildEvidence;
  const AUnitName: string; out ASourcePath: string): Boolean;
var
  LCandidate: string;
  LSearchPath: string;
begin
  Result := False;
  ASourcePath := '';
  for LSearchPath in ABuildEvidence.SearchPaths do
  begin
    if Trim(LSearchPath) = '' then
      Continue;
    if IsPathUnderDirectory(LSearchPath, ABuildEvidence.Paths.OutputDir) or
       IsPathUnderDirectory(LSearchPath, ABuildEvidence.Paths.DcuOutputDir) or
       IsPathUnderDirectory(LSearchPath, ABuildEvidence.Paths.DcpOutputDir) or
       IsPathUnderDirectory(LSearchPath, ABuildEvidence.Paths.BplOutputDir) then
      Continue;
    LCandidate := TPath.Combine(LSearchPath, AUnitName + '.pas');
    if TFile.Exists(LCandidate) then
    begin
      ASourcePath := TPath.GetFullPath(LCandidate);
      Exit(True);
    end;
  end;
end;

function TUnitResolver.ResolveUnitBySearchPaths(const AProjectInfo: TProjectInfo;
  const ABuildEvidence: TBuildEvidence; const AUnitName: string;
  AEvidenceSource: TBuildEvidenceSourceKind): TResolvedUnitInfo;
var
  LCandidateFileNames: TArray<string>;
  LDirectSearchPaths: TList<string>;
  LExplicitReference: TProjectUnitReference;
  LPasPath: string;
  LResolvedPath: string;
  LSourcePath: string;
  LUsedFallbackName: Boolean;

  function IsOutputPath(const APath: string): Boolean;
  begin
    Result := IsPathUnderDirectory(APath, ABuildEvidence.Paths.OutputDir) or
      IsPathUnderDirectory(APath, ABuildEvidence.Paths.DcuOutputDir) or
      IsPathUnderDirectory(APath, ABuildEvidence.Paths.DcpOutputDir) or
      IsPathUnderDirectory(APath, ABuildEvidence.Paths.BplOutputDir);
  end;

  // Folder rules in the component manifest need the package directory, not
  // the DCU the compiler wrote into the project output folder.
  procedure RememberSourcePath(const APasPath: string);
  begin
    if SameText(TPath.GetExtension(Result.ResolvedPath), '.pas') then
      Result.SourcePath := Result.ResolvedPath
    else if APasPath <> '' then
      Result.SourcePath := APasPath
    else if (Result.ResolvedPath <> '') and not IsOutputPath(Result.ResolvedPath) then
      Result.SourcePath := Result.ResolvedPath;
  end;

begin
  Result := Default(TResolvedUnitInfo);
  Result.UnitName := AUnitName;
  Result.Confidence := rcStrong;
  Result.EvidenceSources := [AEvidenceSource];
  LCandidateFileNames := BuildCandidateFileNames(AUnitName);

  for LExplicitReference in AProjectInfo.ExplicitUnitReferences do
  begin
    if not SameText(LExplicitReference.UnitName, AUnitName) then
      Continue;
    if not TFile.Exists(LExplicitReference.FilePath) then
      Continue;

    Result.ResolvedPath := TPath.GetFullPath(LExplicitReference.FilePath);
    Result.EvidenceKind := DetermineEvidenceKind(Result.ResolvedPath);
    Result.OriginKind := DetermineOriginKind(AProjectInfo, AUnitName, Result.ResolvedPath);
    Result.Confidence := rcAuthoritative;
    Result.EvidenceSources := [AEvidenceSource, besProjectMetadata];
    RememberSourcePath('');
    Exit;
  end;

  LDirectSearchPaths := TList<string>.Create;
  try
    if ABuildEvidence.Paths.OutputDir <> '' then
      LDirectSearchPaths.Add(ABuildEvidence.Paths.OutputDir);
    if ABuildEvidence.Paths.DcuOutputDir <> '' then
      LDirectSearchPaths.Add(ABuildEvidence.Paths.DcuOutputDir);
    if ABuildEvidence.Paths.DcpOutputDir <> '' then
      LDirectSearchPaths.Add(ABuildEvidence.Paths.DcpOutputDir);
    if ABuildEvidence.Paths.BplOutputDir <> '' then
      LDirectSearchPaths.Add(ABuildEvidence.Paths.BplOutputDir);
    for LResolvedPath in ABuildEvidence.SearchPaths do
      if not LDirectSearchPaths.Contains(LResolvedPath) then
        LDirectSearchPaths.Add(LResolvedPath);

    if FindExistingDirectCandidate(LDirectSearchPaths, LCandidateFileNames,
      LResolvedPath, LUsedFallbackName) then
    begin
      Result.ResolvedPath := LResolvedPath;
      Result.EvidenceKind := DetermineEvidenceKind(Result.ResolvedPath);
      Result.OriginKind := DetermineOriginKind(AProjectInfo, AUnitName, Result.ResolvedPath);
      LPasPath := '';
      if IsOutputPath(Result.ResolvedPath) then
      begin
        // A DCU in the output folder was compiled from a source somewhere in
        // the search path. That source decides the origin, so a third-party
        // unit compiled into the project's DCU folder stays third party
        // (issue #133). Without a source the unit counts as project code.
        Result.OriginKind := uokLocalProject;
        if FindSourceOutsideOutputDirs(ABuildEvidence, AUnitName, LSourcePath) then
        begin
          Result.OriginKind := DetermineOriginKind(AProjectInfo, AUnitName, LSourcePath);
          LPasPath := LSourcePath;
        end;
      end;
      RememberSourcePath(LPasPath);
      if LUsedFallbackName then
        Result.Confidence := rcHeuristic
      else
        Result.Confidence := rcStrong;
      Result.EvidenceSources := [AEvidenceSource, besSearchPathFallback];
      Exit;
    end;

    if FindExistingRecursiveCandidate(AProjectInfo.GlobalSearchPaths, LCandidateFileNames,
      LResolvedPath, LUsedFallbackName) then
    begin
      Result.ResolvedPath := LResolvedPath;
      Result.EvidenceKind := DetermineEvidenceKind(Result.ResolvedPath);
      Result.OriginKind := DetermineOriginKind(AProjectInfo, AUnitName, Result.ResolvedPath);
      RememberSourcePath('');
      if LUsedFallbackName then
        Result.Confidence := rcHeuristic
      else
        Result.Confidence := rcStrong;
      Result.EvidenceSources := [AEvidenceSource, besSearchPathFallback];
      Exit;
    end;
  finally
    LDirectSearchPaths.Free;
  end;

  Result.EvidenceKind := uekUnknown;
  Result.OriginKind := InferOriginFromUnitName(AProjectInfo, AUnitName);
  Result.Confidence := rcHeuristic;
  SetLength(Result.Warnings, 1);
  Result.Warnings[0] := 'Could not resolve unit file on disk.';
end;

function TUnitResolver.ResolveMapDerivedUnit(const AProjectInfo: TProjectInfo;
  const ABuildEvidence: TBuildEvidence; const AUnitName, AMapFilePath: string): TResolvedUnitInfo;
begin
  Result := ResolveUnitBySearchPaths(AProjectInfo, ABuildEvidence, AUnitName, besMapFile);
  Result.ContainerPath := AMapFilePath;
  if (Result.ResolvedPath = '') and (Result.EvidenceKind = uekUnknown) then
  begin
    Result.EvidenceKind := uekMap;
    if Length(Result.Warnings) > 0 then
      Result.Warnings[0] := 'Could not resolve the unit beyond MAP-file membership.';
  end;
end;

procedure TUnitResolver.AddUsesClauseDerivedUnits(const AProjectInfo: TProjectInfo;
  const ABuildEvidence: TBuildEvidence;
  var ACompositionEvidence: TCompositionEvidence);
var
  LRootSourcePath: string;
  LDiscoveredUnits: TArray<string>;
  LUnitName: string;
  LExistingUnit: TResolvedUnitInfo;
  LIsDuplicate: Boolean;
  LResolvedUnit: TResolvedUnitInfo;
begin
  LRootSourcePath := ChangeFileExt(AProjectInfo.ProjectPath, '.dpr');
  if not TFile.Exists(LRootSourcePath) then
  begin
    LRootSourcePath := ChangeFileExt(AProjectInfo.ProjectPath, '.dpk');
    if not TFile.Exists(LRootSourcePath) then
      Exit;
  end;

  LDiscoveredUnits := TUsesClauseWalker.WalkDependencies(LRootSourcePath,
    ABuildEvidence.SearchPaths, AProjectInfo.GlobalSearchPaths,
    ABuildEvidence.UnitScopeNames, 100, FUsesClauseCache);

  for LUnitName in LDiscoveredUnits do
  begin
    LIsDuplicate := False;
    for LExistingUnit in ACompositionEvidence.Units do
    begin
      if SameText(LExistingUnit.UnitName, LUnitName) then
      begin
        LIsDuplicate := True;
        Break;
      end;
    end;

    if LIsDuplicate then
      Continue;

    LResolvedUnit := ResolveUnitBySearchPaths(AProjectInfo, ABuildEvidence,
      LUnitName, besUsesClause);
    ComputeHashes(LResolvedUnit);
    CacheUsedUnits(LResolvedUnit);
    ACompositionEvidence.Units.Add(LResolvedUnit);
  end;
end;

function TUnitResolver.Resolve(const AProjectInfo: TProjectInfo;
  const ABuildEvidence: TBuildEvidence): TCompositionEvidence;
var
  LHasMapEvidence: Boolean;
begin
  // A reused resolver must not keep uses names from an earlier project.
  if Assigned(FUsesClauseCache) then
    FUsesClauseCache.Clear;

  Result := TCompositionEvidence.Create;
  Result.ProjectName := AProjectInfo.ProjectName;
  Result.ProjectVersion := AProjectInfo.Version;
  Result.Platform := AProjectInfo.Platform;
  Result.Configuration := AProjectInfo.Configuration;
  Result.GeneratedAt := FormatUtcTimestamp('');
  Result.ToolchainProductName := AProjectInfo.Toolchain.ProductName;
  Result.ToolchainVersion := AProjectInfo.Toolchain.Version;
  Result.ToolchainBuildVersion := AProjectInfo.Toolchain.BuildVersion;
  Result.ToolchainRootDir := AProjectInfo.Toolchain.RootDir;

  CopyUniqueWarnings(AProjectInfo.Warnings, Result.Warnings);
  CopyUniqueWarnings(ABuildEvidence.Warnings, Result.Warnings);
  AddMapDerivedUnits(AProjectInfo, ABuildEvidence, Result);

  LHasMapEvidence := Result.Units.Count > 0;
  if not LHasMapEvidence or not IsClassicCompilerPlatform(AProjectInfo.Platform) then
    AddUsesClauseDerivedUnits(AProjectInfo, ABuildEvidence, Result);
end;

end.
