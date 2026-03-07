/// <summary>
/// DX.Comply.BuildEvidence.Intf
/// Core contracts for build-evidence-driven unit resolution.
/// </summary>
///
/// <remarks>
/// This unit defines the internal evidence model used to describe:
/// - where build evidence came from
/// - how units were resolved
/// - how certain DX.Comply is about each resolution
///
/// The contracts are intentionally separate from the public SBOM facade so the
/// evidence pipeline can evolve without destabilising the engine entry point.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.BuildEvidence.Intf;

interface

uses
  System.Generics.Collections,
  DX.Comply.Engine.Intf;

type
  /// <summary>
  /// Describes the source from which a piece of build evidence was obtained.
  /// </summary>
  TBuildEvidenceSourceKind = (
    besProjectMetadata,
    besCompilerCommandLine,
    besCompilerResponseFile,
    besCompileNotification,
    besMapFile,
    besDcuFile,
    besDcpFile,
    besBplFile,
    besSearchPathFallback,
    besManualOverride
  );

  /// <summary>
  /// Describes the representation actually used for a resolved unit.
  /// </summary>
  TUnitEvidenceKind = (
    uekPas,
    uekDcu,
    uekDcp,
    uekBpl,
    uekUnknown
  );

  /// <summary>
  /// Groups a resolved unit by provenance.
  /// </summary>
  TUnitOriginKind = (
    uokEmbarcaderoRtl,
    uokEmbarcaderoVcl,
    uokEmbarcaderoFmx,
    uokLocalProject,
    uokThirdParty,
    uokUnknown
  );

  /// <summary>
  /// Expresses how certain the resolver is about a unit result.
  /// </summary>
  TResolutionConfidence = (
    rcAuthoritative,
    rcStrong,
    rcHeuristic,
    rcUnknown
  );

  /// <summary>
  /// Normalized path set for the selected platform and configuration.
  /// </summary>
  TBuildPathSet = record
    OutputDir: string;
    DcuOutputDir: string;
    DcpOutputDir: string;
    BplOutputDir: string;
    MapFilePath: string;
    ResponseFilePath: string;
  end;

  /// <summary>
  /// Represents a single evidence item gathered from the build context.
  /// </summary>
  TBuildEvidenceItem = record
    SourceKind: TBuildEvidenceSourceKind;
    DisplayName: string;
    FilePath: string;
    PackageName: string;
    UnitName: string;
    Detail: string;
  end;

  /// <summary>
  /// List of normalized build evidence items.
  /// </summary>
  TBuildEvidenceItemList = TList<TBuildEvidenceItem>;

  /// <summary>
  /// Final resolved unit information used by classification and evidence writing.
  /// </summary>
  TResolvedUnitInfo = record
    UnitName: string;
    EvidenceKind: TUnitEvidenceKind;
    OriginKind: TUnitOriginKind;
    Confidence: TResolutionConfidence;
    ResolvedPath: string;
    ContainerPath: string;
    PackageName: string;
    PrimaryHashSha512: string;
    SecondaryHashSha256: string;
    EvidenceSources: TArray<TBuildEvidenceSourceKind>;
    Warnings: TArray<string>;
  end;

  /// <summary>
  /// List of resolved units.
  /// </summary>
  TResolvedUnitList = TList<TResolvedUnitInfo>;

  /// <summary>
  /// Normalized evidence bundle produced before unit resolution.
  /// </summary>
  TBuildEvidence = record
    ProjectPath: string;
    Platform: string;
    Configuration: string;
    Paths: TBuildPathSet;
    SearchPaths: TList<string>;
    UnitScopeNames: TList<string>;
    RuntimePackages: TList<string>;
    EvidenceItems: TBuildEvidenceItemList;
    Warnings: TList<string>;
    /// <summary>Initializes the record with owned list instances.</summary>
    class function Create: TBuildEvidence; static;
    /// <summary>Frees owned list instances.</summary>
    procedure Free;
  end;

  /// <summary>
  /// Top-level evidence model written to the sidecar manifest.
  /// </summary>
  TCompositionEvidence = record
    ProjectName: string;
    ProjectVersion: string;
    Platform: string;
    Configuration: string;
    GeneratedAt: string;
    Units: TResolvedUnitList;
    Warnings: TList<string>;
    /// <summary>Initializes the record with owned list instances.</summary>
    class function Create: TCompositionEvidence; static;
    /// <summary>Frees owned list instances.</summary>
    procedure Free;
  end;

  /// <summary>
  /// Reads normalized build evidence for a selected project build.
  /// </summary>
  IBuildEvidenceReader = interface
    ['{2E1D65A3-5C18-4B8A-A220-7C5F5A5D9401}']
    /// <summary>
    /// Reads build evidence for the provided project metadata.
    /// </summary>
    function Read(const AProjectInfo: TProjectInfo): TBuildEvidence;
  end;

  /// <summary>
  /// Resolves the direct and transitive unit closure for a selected build.
  /// </summary>
  IUnitResolver = interface
    ['{7A50D5E2-391D-43F8-8A7F-6602A6B8E1B2}']
    /// <summary>
    /// Resolves composition evidence from project metadata and normalized build evidence.
    /// </summary>
    function Resolve(const AProjectInfo: TProjectInfo;
      const ABuildEvidence: TBuildEvidence): TCompositionEvidence;
  end;

  /// <summary>
  /// Classifies one resolved unit into a provenance group.
  /// </summary>
  IOriginClassifier = interface
    ['{22F9AE44-8CA4-46B0-B4A0-47F5955AE4C8}']
    /// <summary>
    /// Classifies the origin of the specified resolved unit.
    /// </summary>
    function Classify(const AProjectInfo: TProjectInfo;
      const AResolvedUnit: TResolvedUnitInfo): TUnitOriginKind;
  end;

  /// <summary>
  /// Writes the Delphi-specific evidence sidecar.
  /// </summary>
  IEvidenceWriter = interface
    ['{C0C124B1-F2A6-4FCE-BB91-A7D514BFF2CC}']
    /// <summary>
    /// Writes the evidence document to the specified output file.
    /// </summary>
    function Write(const AOutputPath: string;
      const AEvidence: TCompositionEvidence): Boolean;
  end;

implementation

{ TBuildEvidence }

class function TBuildEvidence.Create: TBuildEvidence;
begin
  Result := Default(TBuildEvidence);
  Result.SearchPaths := TList<string>.Create;
  Result.UnitScopeNames := TList<string>.Create;
  Result.RuntimePackages := TList<string>.Create;
  Result.EvidenceItems := TBuildEvidenceItemList.Create;
  Result.Warnings := TList<string>.Create;
end;

procedure TBuildEvidence.Free;
begin
  if Assigned(SearchPaths) then
  begin
    SearchPaths.Free;
    SearchPaths := nil;
  end;

  if Assigned(UnitScopeNames) then
  begin
    UnitScopeNames.Free;
    UnitScopeNames := nil;
  end;

  if Assigned(RuntimePackages) then
  begin
    RuntimePackages.Free;
    RuntimePackages := nil;
  end;

  if Assigned(EvidenceItems) then
  begin
    EvidenceItems.Free;
    EvidenceItems := nil;
  end;

  if Assigned(Warnings) then
  begin
    Warnings.Free;
    Warnings := nil;
  end;
end;

{ TCompositionEvidence }

class function TCompositionEvidence.Create: TCompositionEvidence;
begin
  Result := Default(TCompositionEvidence);
  Result.Units := TResolvedUnitList.Create;
  Result.Warnings := TList<string>.Create;
end;

procedure TCompositionEvidence.Free;
begin
  if Assigned(Units) then
  begin
    Units.Free;
    Units := nil;
  end;

  if Assigned(Warnings) then
  begin
    Warnings.Free;
    Warnings := nil;
  end;
end;

end.