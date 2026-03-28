/// <summary>
/// DX.Comply.UnitResolver
/// First-pass implementation of composition evidence resolution.
/// </summary>
///
/// <remarks>
/// This resolver intentionally keeps the first slice small. It builds the
/// composition evidence envelope, propagates metadata and warnings, and leaves
/// the unit list empty until the actual unit-closure logic is implemented.
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
  DX.Comply.Engine.Intf,
  DX.Comply.BuildEvidence.Intf;

type
  /// <summary>
  /// Implementation of IUnitResolver for the first composition evidence slice.
  /// </summary>
  TUnitResolver = class(TInterfacedObject, IUnitResolver)
  private
    FHashService: IHashService;
    FRecursiveSearchCache: TDictionary<string, string>;
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

implementation

uses
  System.IOUtils,
  System.DateUtils,
  System.StrUtils,
  System.SysUtils,
  DX.Comply.UsesClauseParser;

constructor TUnitResolver.Create;
begin
  inherited Create;
  FRecursiveSearchCache := TDictionary<string, string>.Create;
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

destructor TUnitResolver.Destroy;
begin
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
  if Assigned(AProjectInfo.ProjectSearchPaths) then
    for LSearchPath in AProjectInfo.ProjectSearchPaths do
      if (Trim(LSearchPath) <> '') and
         IsPathUnderDirectory(AResolvedPath, LSearchPath) then
        Exit(uokLocalProject);

  if IsPathUnderDirectory(AResolvedPath, AProjectInfo.Toolchain.RootDir) then
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

function TUnitResolver.IsPathUnderDirectory(const APath, ABaseDirectory: string): Boolean;
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
    ACompositionEvidence.Units.Add(LResolvedUnit);
  end;
end;

function TUnitResolver.ResolveUnitBySearchPaths(const AProjectInfo: TProjectInfo;
  const ABuildEvidence: TBuildEvidence; const AUnitName: string;
  AEvidenceSource: TBuildEvidenceSourceKind): TResolvedUnitInfo;
var
  LCandidateFileNames: TArray<string>;
  LDirectSearchPaths: TList<string>;
  LExplicitReference: TProjectUnitReference;
  LResolvedPath: string;
  LUsedFallbackName: Boolean;
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
      if IsPathUnderDirectory(Result.ResolvedPath, ABuildEvidence.Paths.OutputDir) or
         IsPathUnderDirectory(Result.ResolvedPath, ABuildEvidence.Paths.DcuOutputDir) or
         IsPathUnderDirectory(Result.ResolvedPath, ABuildEvidence.Paths.DcpOutputDir) or
         IsPathUnderDirectory(Result.ResolvedPath, ABuildEvidence.Paths.BplOutputDir) then
        Result.OriginKind := uokLocalProject;
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
    ABuildEvidence.UnitScopeNames);

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
    ACompositionEvidence.Units.Add(LResolvedUnit);
  end;
end;

function TUnitResolver.Resolve(const AProjectInfo: TProjectInfo;
  const ABuildEvidence: TBuildEvidence): TCompositionEvidence;
var
  LHasMapEvidence: Boolean;
begin
  Result := TCompositionEvidence.Create;
  Result.ProjectName := AProjectInfo.ProjectName;
  Result.ProjectVersion := AProjectInfo.Version;
  Result.Platform := AProjectInfo.Platform;
  Result.Configuration := AProjectInfo.Configuration;
  Result.GeneratedAt := DateToISO8601(Now, False);
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