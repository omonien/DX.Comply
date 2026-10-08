/// <summary>
/// DX.Comply.Engine
/// Main facade for DX.Comply SBOM generation.
/// </summary>
///
/// <remarks>
/// This unit provides TDxComplyGenerator as the main entry point for SBOM generation:
/// - Coordinates ProjectScanner, FileScanner, HashService, and SbomWriter
/// - Provides a simple API for IDE and CLI consumers
///
/// Usage:
/// <code>
///   var Generator := TDxComplyGenerator.Create;
///   try
///     Generator.Generate('MyApp.dproj', 'bom.json', sfCycloneDxJson);
///   finally
///     Generator.Free;
///   end;
/// </code>
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Engine;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.DateUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  DX.Comply.Engine.Intf,
  DX.Comply.BuildEvidence.Intf,
  DX.Comply.BuildOrchestrator,
  DX.Comply.BuildEvidence.Reader,
  DX.Comply.UnitResolver,
  DX.Comply.ProjectScanner,
  DX.Comply.FileScanner,
  DX.Comply.HashService,
  DX.Comply.CycloneDx.Writer,
  DX.Comply.CycloneDx.XmlWriter,
  DX.Comply.Report.Intf,
  DX.Comply.Report.MarkdownWriter,
  DX.Comply.Report.HtmlWriter,
  DX.Comply.Spdx.Writer,
  DX.Comply.Schema.Validator;

type
  /// <summary>
  /// Fields of TSbomConfig that a caller set on purpose.
  /// GenerateFromConfig keeps these when a .dxcomply.json file is also loaded,
  /// so an explicit CLI option is not replaced by the file (issue #50).
  /// </summary>
  TSbomConfigOverride = (
    scoOutputPath,
    scoFormat,
    scoPlatform,
    scoConfiguration,
    scoProductName,
    scoProductVersion,
    scoSupplier,
    scoIncludePatterns,
    scoExcludePatterns,
    scoMapFileDir,
    scoIncludeCompositionEvidence,
    scoReport,
    scoScanDirs,
    scoScanTree
  );
  /// <summary>Set of TSbomConfig fields that were set explicitly.</summary>
  TSbomConfigOverrides = set of TSbomConfigOverride;

  /// <summary>
  /// Configuration for SBOM generation.
  /// </summary>
  TSbomConfig = record
    /// <summary>Output file path.</summary>
    OutputPath: string;
    /// <summary>SBOM format.</summary>
    Format: TSbomFormat;
    /// <summary>Include patterns (glob).</summary>
    IncludePatterns: TArray<string>;
    /// <summary>Exclude patterns (glob).</summary>
    ExcludePatterns: TArray<string>;
    /// <summary>Product name override.</summary>
    ProductName: string;
    /// <summary>Product version override.</summary>
    ProductVersion: string;
    /// <summary>Supplier name.</summary>
    Supplier: string;
    /// <summary>
    /// Optional component manifest (components.json). Empty means no enrichment.
    /// A relative path is resolved from the project directory.
    /// </summary>
    ManifestFile: string;
    /// <summary>
    /// True when ManifestFile was set by an explicit --manifest flag.
    /// That value wins over the manifest key in .dxcomply.json.
    /// </summary>
    ManifestFileExplicit: Boolean;
    /// <summary>Target platform.</summary>
    Platform: string;
    /// <summary>
    /// True when the caller set the platform with --platform or with
    /// platform in .dxcomply.json. The built-in Win32 default stays False.
    /// </summary>
    PlatformExplicit: Boolean;
    /// <summary>Build configuration.</summary>
    Configuration: string;
    /// <summary>
    /// True when the caller set the configuration with --config-name or with
    /// configuration in .dxcomply.json. The built-in Release default stays False.
    /// </summary>
    ConfigurationExplicit: Boolean;
    /// <summary>Controls whether Deep-Evidence builds are disabled, conditional, or forced.</summary>
    DeepEvidenceMode: TDeepEvidenceBuildMode;
    /// <summary>Optional Delphi major version to use for the Deep-Evidence build.</summary>
    DeepEvidenceDelphiVersion: Integer;
    /// <summary>Optional override path to DelphiBuildDPROJ.ps1.</summary>
    DeepEvidenceBuildScriptPath: string;
    /// <summary>Continue SBOM generation when the Deep-Evidence build fails.</summary>
    ContinueOnDeepEvidenceBuildFailure: Boolean;
    /// <summary>Emit a warning when no composition units could be resolved.</summary>
    WarnOnEmptyCompositionEvidence: Boolean;
    /// <summary>Optional human-readable companion report settings.</summary>
    HumanReadableReport: THumanReadableReportConfig;
    /// <summary>Optional override directory for the MAP file location.</summary>
    MapFileDir: string;
    /// <summary>
    /// When False, composition-evidence units (PAS/DCU) are omitted from the
    /// SBOM output. Useful for generating a binary-only SBOM.
    /// Default is True (evidence included).
    /// </summary>
    IncludeCompositionEvidence: Boolean;
    /// <summary>
    /// When True, and OutputPath was not set explicitly, append the platform
    /// and configuration to the output filename (issue #25). Applied after a
    /// config file is merged so the file's output, platform, and configName
    /// are the values that get decorated.
    /// </summary>
    IncludePlatformInOutput: Boolean;
    /// <summary>
    /// Which fields were set explicitly by the caller. Empty means every field
    /// is still a default and may be replaced by .dxcomply.json.
    /// </summary>
    ExplicitOverrides: TSbomConfigOverrides;
    /// <summary>
    /// Extra directories or globs to scan for binaries (CLI --scan-dir,
    /// config scanDirs). Each entry is non-recursive unless it contains **.
    /// Relative entries are resolved from the project directory.
    /// </summary>
    ScanDirs: TArray<string>;
    /// <summary>
    /// When True, recursively scan the project output directory the way older
    /// versions did. Deprecated and kept for one release. Default is False.
    /// </summary>
    ScanTree: Boolean;
    /// <summary>
    /// Optional Delphi 7 installation directory for legacy .dpr/.dpk/.bdsproj
    /// scans. Empty uses the Borland registry key and the DELPHI variable.
    /// </summary>
    Delphi7Root: string;
    /// <summary>Creates a new TSbomConfig with default values.</summary>
    class function Default: TSbomConfig; static;
    /// <summary>
    /// Appends the platform and configuration to a filename.
    /// Both values are reduced to letters, digits, hyphen and underscore
    /// before they are interpolated.
    /// </summary>
    class function DecorateOutputFileName(const AOutputPath, APlatform,
      AConfiguration: string): string; static;
  end;

  /// <summary>
  /// Event type for progress notifications.
  /// </summary>
  /// <summary>
  /// Compatible with anonymous closures, plain procedures, and method pointers.
  /// </summary>
  TProgressEvent = reference to procedure(const AMessage: string; const AProgress: Integer);

  /// <summary>
  /// Main facade for SBOM generation.
  /// </summary>
  TDxComplyGenerator = class
  private
    FProjectScanner: IProjectScanner;
    FBuildEvidenceReader: IBuildEvidenceReader;
    FBuildOrchestrator: IBuildOrchestrator;
    FUnitResolver: IUnitResolver;
    FFileScanner: IFileScanner;
    FHashService: IHashService;
    FSbomWriter: ISbomWriter;
    FConfig: TSbomConfig;
    FOnProgress: TProgressEvent;
    procedure DoProgress(const AMessage: string; const AProgress: Integer);
    function MergeFileConfig(const ACaller, AFile: TSbomConfig): TSbomConfig;
    function CreateWriter(AFormat: TSbomFormat): ISbomWriter;
    function CreateReportWriter(AFormat: THumanReadableReportFormat): IHumanReadableReportWriter;
    function BuildMetadata(const AConfig: TSbomConfig; const AProjectInfo: TProjectInfo;
      const ABuildEvidence: TBuildEvidence; const ACompositionEvidence: TCompositionEvidence;
      const AWarnings: TList<string>;
      const ADeepEvidenceBuildResult: TDeepEvidenceBuildResult): TSbomMetadata;
    function BuildHumanReadableReportData(const ASbomOutputPath: string; ASbomFormat: TSbomFormat;
      const AMetadata: TSbomMetadata; const AProjectInfo: TProjectInfo;
      const ABuildEvidence: TBuildEvidence; const ACompositionEvidence: TCompositionEvidence;
      const AArtefacts: TArtefactList; const AWarnings: TList<string>;
      const ADeepEvidenceBuildResult: TDeepEvidenceBuildResult;
      const AValidationResult: TValidationResult): TComplianceReportData;
    function BuildDeepEvidenceOptions: TDeepEvidenceBuildOptions;
    function BuildEmptyCompositionWarning(const AProjectInfo: TProjectInfo;
      const ABuildEvidence: TBuildEvidence): string;
    function EnsureDeepEvidenceBuild(const AProjectInfo: TProjectInfo): TDeepEvidenceBuildResult;
    function GenerateHumanReadableReports(const AData: TComplianceReportData;
      out AGeneratedReportPaths: TArray<string>): Boolean;
    function ReadBuildEvidence(const AProjectInfo: TProjectInfo): TBuildEvidence;
    procedure ReportWarnings(const AWarnings, AReportedWarnings: TList<string>;
      const AProgress: Integer);
    function ResolveReportOutputBasePath(const ASbomOutputPath: string): string;
    function ResolveReportOutputPath(const AOutputBasePath: string;
      AFormat: THumanReadableReportFormat): string;
    function ResolveCompositionEvidence(const AProjectInfo: TProjectInfo;
      const ABuildEvidence: TBuildEvidence): TCompositionEvidence;
    procedure AddCompositionEvidenceToArtefacts(
      const ACompositionEvidence: TCompositionEvidence;
      const AArtefacts: TArtefactList);
    procedure AddRuntimePackagesToArtefacts(
      const AProjectInfo: TProjectInfo;
      const AArtefacts: TArtefactList);
    procedure AddExternalDllReferencesToArtefacts(
      const AProjectInfo: TProjectInfo;
      const ACompositionEvidence: TCompositionEvidence;
      const AArtefacts: TArtefactList);
    /// <summary>
    /// Lists the named project output, binaries in its directory, and any
    /// extra scan directories. ScanTree restores the old recursive walk.
    /// </summary>
    function CollectBuildArtefacts(const AProjectInfo: TProjectInfo): TArtefactList;
    /// <summary>
    /// Appends artefacts whose full path is not already in the target list.
    /// </summary>
    procedure MergeArtefacts(const ATarget, ASource: TArtefactList);
    /// <summary>
    /// Copies include/exclude warnings from the most recent file scan.
    /// </summary>
    procedure RememberPatternWarnings(const AWarnings: TList<string>);
  public
    /// <summary>
    /// Scans the supplied .pas files for external DLL references. String
    /// literals in 'external' or LoadLibrary/GetModuleHandle calls are taken
    /// as-is. Identifier forms (external DLLName, LoadLibrary(DLLName)) are
    /// resolved against const declarations. {$I}/{$INCLUDE} files are read
    /// from the including unit's directory and then from ASearchPaths.
    /// When one const has several values (typical {$IFDEF} branches), every
    /// value is returned and the matching AConditional entry is True.
    /// Names are lower-cased and de-duplicated. Public for testability.
    /// </summary>
    class function ScanPasFilesForDllReferences(
      const APasFilePaths, ASearchPaths: TArray<string>;
      out AConditional: TArray<Boolean>): TArray<string>; overload; static;
    /// <summary>
    /// Same scan with no extra search paths. Conditional flags are discarded.
    /// </summary>
    class function ScanPasFilesForDllReferences(
      const APasFilePaths: TArray<string>): TArray<string>; overload; static;
    /// <summary>
    /// Creates a new TDxComplyGenerator instance.
    /// </summary>
    constructor Create; overload;
    /// <summary>
    /// Creates a new TDxComplyGenerator with custom configuration.
    /// </summary>
    constructor Create(const AConfig: TSbomConfig); overload;
    /// <summary>
    /// Destroys the TDxComplyGenerator instance.
    /// </summary>
    destructor Destroy; override;
    /// <summary>
    /// Generates an SBOM for the specified project.
    /// </summary>
    /// <param name="AProjectPath">Path to the .dproj file.</param>
    /// <param name="AOutputPath">Output file path (optional, uses config if empty).</param>
    /// <param name="AFormat">SBOM format (optional, uses config if default).</param>
    /// <returns>True if generation succeeded.</returns>
    function Generate(const AProjectPath: string;
      const AOutputPath: string = '';
      AFormat: TSbomFormat = sfCycloneDxJson): Boolean;
    /// <summary>
    /// Reads a .dxcomply.json file. A missing file returns
    /// TSbomConfig.Default. Does not modify this generator.
    /// </summary>
    function LoadConfig(const AConfigPath: string): TSbomConfig;
    /// <summary>
    /// Generates an SBOM using a configuration file.
    /// File values replace built-in defaults. Fields listed in
    /// Config.ExplicitOverrides keep the caller's value (issue #50).
    /// </summary>
    function GenerateFromConfig(const AProjectPath, AConfigPath: string): Boolean;
    /// <summary>
    /// Validates a project file.
    /// </summary>
    function ValidateProject(const AProjectPath: string): Boolean;
    /// <summary>
    /// Validates a generated SBOM file against the schema.
    /// </summary>
    function ValidateSbom(const AFilePath: string): TValidationResult;
    /// <summary>
    /// Progress notification event.
    /// </summary>
    property OnProgress: TProgressEvent read FOnProgress write FOnProgress;
    /// <summary>
    /// Current configuration.
    /// </summary>
    property Config: TSbomConfig read FConfig write FConfig;
  end;

implementation

uses
  DX.Comply.ComponentManifest,
  DX.Comply.LegacyProject,
  DX.Comply.Report.Support,
  DX.Comply.VersionInfo;

{ TSbomConfig }

class function TSbomConfig.Default: TSbomConfig;
begin
  Result.OutputPath := 'bom.json';
  Result.Format := sfCycloneDxJson;
  Result.Platform := 'Win32';
  Result.PlatformExplicit := False;
  Result.Configuration := 'Release';
  Result.ConfigurationExplicit := False;
  Result.DeepEvidenceMode := debWhenMapMissing;
  Result.DeepEvidenceDelphiVersion := 0;
  Result.DeepEvidenceBuildScriptPath := '';
  Result.ContinueOnDeepEvidenceBuildFailure := True;
  Result.WarnOnEmptyCompositionEvidence := False;
  Result.HumanReadableReport := THumanReadableReportConfig.Default;
  Result.ProductName := '';
  Result.ProductVersion := '';
  Result.Supplier := '';
  Result.ManifestFile := '';
  Result.ManifestFileExplicit := False;
  SetLength(Result.IncludePatterns, 0);
  SetLength(Result.ExcludePatterns, 0);
  Result.IncludeCompositionEvidence := True;
  Result.IncludePlatformInOutput := False;
  Result.ExplicitOverrides := [];
  Result.MapFileDir := '';
  Result.ScanTree := False;
  SetLength(Result.ScanDirs, 0);
  Result.Delphi7Root := '';
end;


class function TSbomConfig.DecorateOutputFileName(const AOutputPath, APlatform,
  AConfiguration: string): string;

  function SanitizeSegment(const AValue: string): string;
  var
    LChar: Char;
  begin
    // Same whitelist as TCliOptions.SanitizeForFilename.
    Result := '';
    for LChar in AValue do
      if CharInSet(LChar, ['A'..'Z', 'a'..'z', '0'..'9', '-', '_']) then
        Result := Result + LChar;
  end;

var
  LDir, LName, LExt, LSafePlatform, LSafeConfig: string;
begin
  if AOutputPath = '' then
    Exit('');
  LDir := ExtractFilePath(AOutputPath);
  LExt := ExtractFileExt(AOutputPath);
  LName := ChangeFileExt(ExtractFileName(AOutputPath), '');
  LSafePlatform := SanitizeSegment(APlatform);
  LSafeConfig := SanitizeSegment(AConfiguration);
  Result := LDir + LName + '.' + LSafePlatform + '.' + LSafeConfig + LExt;

end;


{ TDxComplyGenerator }

constructor TDxComplyGenerator.Create;
begin
  inherited Create;
  FConfig := TSbomConfig.Default;
  FProjectScanner := TProjectScanner.Create;
  FBuildEvidenceReader := TBuildEvidenceReader.Create;
  FBuildOrchestrator := TBuildOrchestrator.Create;
  FHashService := THashService.Create;
  FUnitResolver := TUnitResolver.Create(FHashService);
  FFileScanner := TFileScanner.Create(FHashService);
end;

constructor TDxComplyGenerator.Create(const AConfig: TSbomConfig);
begin
  Create;
  FConfig := AConfig;
end;

destructor TDxComplyGenerator.Destroy;
begin
  FProjectScanner := nil;
  FBuildEvidenceReader := nil;
  FBuildOrchestrator := nil;
  FUnitResolver := nil;
  FFileScanner := nil;
  FHashService := nil;
  FSbomWriter := nil;
  inherited;
end;

function TDxComplyGenerator.ReadBuildEvidence(const AProjectInfo: TProjectInfo): TBuildEvidence;
begin
  if Assigned(FBuildEvidenceReader) then
    Result := FBuildEvidenceReader.Read(AProjectInfo)
  else
    Result := TBuildEvidence.Create;
end;

function TDxComplyGenerator.BuildDeepEvidenceOptions: TDeepEvidenceBuildOptions;
begin
  Result := TDeepEvidenceBuildOptions.Default;
  Result.Mode := FConfig.DeepEvidenceMode;
  Result.DelphiVersion := FConfig.DeepEvidenceDelphiVersion;
  Result.BuildScriptPathOverride := FConfig.DeepEvidenceBuildScriptPath;
end;

function TDxComplyGenerator.BuildHumanReadableReportData(const ASbomOutputPath: string;
  ASbomFormat: TSbomFormat; const AMetadata: TSbomMetadata;
  const AProjectInfo: TProjectInfo; const ABuildEvidence: TBuildEvidence;
  const ACompositionEvidence: TCompositionEvidence; const AArtefacts: TArtefactList;
  const AWarnings: TList<string>; const ADeepEvidenceBuildResult: TDeepEvidenceBuildResult;
  const AValidationResult: TValidationResult): TComplianceReportData;
begin
  Result := Default(TComplianceReportData);
  Result.SbomOutputPath := ASbomOutputPath;
  Result.SbomFormat := ASbomFormat;
  Result.Metadata := AMetadata;
  Result.ProjectInfo := AProjectInfo;
  Result.BuildEvidence := ABuildEvidence;
  Result.CompositionEvidence := ACompositionEvidence;
  Result.Artefacts := AArtefacts;
  Result.Warnings := AWarnings;
  Result.ValidationResult := AValidationResult;
  Result.CompositionEvidenceIncluded := FConfig.IncludeCompositionEvidence;
end;

function TDxComplyGenerator.BuildEmptyCompositionWarning(const AProjectInfo: TProjectInfo;
  const ABuildEvidence: TBuildEvidence): string;
var
  LEvidenceItem: TBuildEvidenceItem;
  LHasMapFileEvidence: Boolean;
  LHasMapUnitEvidence: Boolean;
begin
  LHasMapFileEvidence := False;
  LHasMapUnitEvidence := False;

  for LEvidenceItem in ABuildEvidence.EvidenceItems do
  begin
    if LEvidenceItem.SourceKind <> besMapFile then
      Continue;

    LHasMapFileEvidence := True;
    if Trim(LEvidenceItem.UnitName) <> '' then
    begin
      LHasMapUnitEvidence := True;
      Break;
    end;
  end;

  if LHasMapUnitEvidence then
    Exit('No composition units were resolved although map evidence was present. The generated SBOM may be incomplete.');

  if LHasMapFileEvidence then
    Exit('No composition units were resolved. The detailed MAP file did not expose any unit entries that could be transformed into composition evidence.');

  Result := 'No composition units were resolved. The generated SBOM contains artefact-level evidence only because no detailed MAP evidence was available.';
  if AProjectInfo.MapFilePath <> '' then
    Result := Result + ' Expected MAP file: ' + AProjectInfo.MapFilePath;
end;

function TDxComplyGenerator.EnsureDeepEvidenceBuild(
  const AProjectInfo: TProjectInfo): TDeepEvidenceBuildResult;
begin
  if Assigned(FBuildOrchestrator) then
    Result := FBuildOrchestrator.EnsureDeepEvidenceBuild(AProjectInfo,
      BuildDeepEvidenceOptions)
  else
  begin
    Result := Default(TDeepEvidenceBuildResult);
    Result.Success := True;
    Result.Message := 'No build orchestrator assigned.';
  end;
end;

procedure TDxComplyGenerator.ReportWarnings(const AWarnings,
  AReportedWarnings: TList<string>; const AProgress: Integer);
var
  LWarning: string;
begin
  if not Assigned(AWarnings) or not Assigned(AReportedWarnings) then
    Exit;

  for LWarning in AWarnings do
  begin
    if Trim(LWarning) = '' then
      Continue;
    if AReportedWarnings.Contains(LWarning) then
      Continue;

    AReportedWarnings.Add(LWarning);
    DoProgress('Warning: ' + LWarning, AProgress);
  end;
end;

function TDxComplyGenerator.ResolveCompositionEvidence(const AProjectInfo: TProjectInfo;
  const ABuildEvidence: TBuildEvidence): TCompositionEvidence;
begin
  if Assigned(FUnitResolver) then
    Result := FUnitResolver.Resolve(AProjectInfo, ABuildEvidence)
  else
    Result := TCompositionEvidence.Create;
end;

procedure TDxComplyGenerator.AddCompositionEvidenceToArtefacts(
  const ACompositionEvidence: TCompositionEvidence;
  const AArtefacts: TArtefactList);
var
  LArtefact: TArtefactInfo;
  LResolvedUnit: TResolvedUnitInfo;
begin
  for LResolvedUnit in ACompositionEvidence.Units do
  begin
    if LResolvedUnit.ResolvedPath = '' then
      Continue;

    LArtefact := Default(TArtefactInfo);
    LArtefact.FilePath := LResolvedUnit.ResolvedPath;
    LArtefact.RelativePath := TPath.GetFileName(LResolvedUnit.ResolvedPath);
    LArtefact.Hash := LResolvedUnit.SecondaryHashSha256;

    if TFile.Exists(LResolvedUnit.ResolvedPath) then
      LArtefact.FileSize := TFile.GetSize(LResolvedUnit.ResolvedPath)
    else
      LArtefact.FileSize := -1;

    LArtefact.ArtefactType := 'unit-evidence';
    LArtefact.Origin := UnitOriginKindToString(LResolvedUnit.OriginKind);
    LArtefact.Evidence := UnitEvidenceKindToString(LResolvedUnit.EvidenceKind);
    LArtefact.Confidence := ResolutionConfidenceToString(LResolvedUnit.Confidence);

    AArtefacts.Add(LArtefact);
  end;
end;

procedure TDxComplyGenerator.AddRuntimePackagesToArtefacts(
  const AProjectInfo: TProjectInfo;
  const AArtefacts: TArtefactList);
var
  LArtefact: TArtefactInfo;
  LPackageName: string;
  LBplFileName: string;
begin
  if not Assigned(AProjectInfo.RuntimePackages) then
    Exit;

  for LPackageName in AProjectInfo.RuntimePackages do
  begin
    if Trim(LPackageName) = '' then
      Continue;

    if AProjectInfo.DllSuffix <> '' then
      LBplFileName := LPackageName + AProjectInfo.DllSuffix + '.bpl'
    else
      LBplFileName := LPackageName + '.bpl';

    LArtefact := Default(TArtefactInfo);
    LArtefact.FilePath := '';
    LArtefact.RelativePath := LBplFileName;
    LArtefact.FileSize := -1;
    LArtefact.Hash := '';
    LArtefact.ArtefactType := 'runtime-package';
    LArtefact.Origin := '';
    LArtefact.Evidence := 'BPL';
    LArtefact.Confidence := 'Declared';

    AArtefacts.Add(LArtefact);
  end;
end;

procedure TDxComplyGenerator.AddExternalDllReferencesToArtefacts(
  const AProjectInfo: TProjectInfo;
  const ACompositionEvidence: TCompositionEvidence;
  const AArtefacts: TArtefactList);
var
  LArtefact: TArtefactInfo;
  LPasFiles: TList<string>;
  LDllNames: TArray<string>;
  LConditional: TArray<Boolean>;
  LSearchPaths: TArray<string>;
  LDllName, LFilePath: string;
  LResolvedUnit: TResolvedUnitInfo;
  I: Integer;
begin
  LPasFiles := TList<string>.Create;
  try
    // Collect all .pas files from explicit unit references
    if Assigned(AProjectInfo.ExplicitUnitReferences) then
      for I := 0 to AProjectInfo.ExplicitUnitReferences.Count - 1 do
      begin
        LFilePath := AProjectInfo.ExplicitUnitReferences[I].FilePath;
        if (LFilePath <> '') and SameText(TPath.GetExtension(LFilePath), '.pas')
          and TFile.Exists(LFilePath) and not LPasFiles.Contains(LFilePath) then
          LPasFiles.Add(LFilePath);
      end;

    // Also include main source file (.dpr/.dpk)
    if (AProjectInfo.MainSourcePath <> '') and TFile.Exists(AProjectInfo.MainSourcePath)
      and not LPasFiles.Contains(AProjectInfo.MainSourcePath) then
      LPasFiles.Add(AProjectInfo.MainSourcePath);

    // Include all .pas files from composition evidence.  Units that are only
    // reachable through uses-clause traversal (and therefore not in the project
    // manager's DCCReference list) may also carry external/LoadLibrary
    // declarations.  Issue #23.
    if Assigned(ACompositionEvidence.Units) then
      for LResolvedUnit in ACompositionEvidence.Units do
      begin
        LFilePath := LResolvedUnit.ResolvedPath;
        if (LFilePath <> '') and SameText(TPath.GetExtension(LFilePath), '.pas')
          and TFile.Exists(LFilePath) and not LPasFiles.Contains(LFilePath) then
          LPasFiles.Add(LFilePath);
      end;

    SetLength(LSearchPaths, 0);
    if Assigned(AProjectInfo.SearchPaths) then
    begin
      SetLength(LSearchPaths, AProjectInfo.SearchPaths.Count);
      for I := 0 to AProjectInfo.SearchPaths.Count - 1 do
        LSearchPaths[I] := AProjectInfo.SearchPaths[I];
    end;

    // The DLL file itself is often not in the build output. Record the
    // reference anyway: empty hash, size -1. Issue #45.
    LDllNames := ScanPasFilesForDllReferences(LPasFiles.ToArray, LSearchPaths,
      LConditional);

    for I := 0 to High(LDllNames) do
    begin
      LDllName := LDllNames[I];
      LArtefact := Default(TArtefactInfo);
      LArtefact.FilePath := '';
      LArtefact.RelativePath := LDllName;
      LArtefact.FileSize := -1;
      LArtefact.Hash := '';
      LArtefact.ArtefactType := 'external-reference';
      LArtefact.Origin := '';
      LArtefact.Evidence := TPath.GetExtension(LDllName).ToUpper.TrimLeft(['.']);
      LArtefact.Confidence := 'Source-scan';
      if I < Length(LConditional) then
        LArtefact.Conditional := LConditional[I];

      AArtefacts.Add(LArtefact);
    end;
  finally
    LPasFiles.Free;
  end;
end;

class function TDxComplyGenerator.ScanPasFilesForDllReferences(
  const APasFilePaths: TArray<string>): TArray<string>;
var
  LConditional: TArray<Boolean>;
  LSearchPaths: TArray<string>;
begin
  SetLength(LSearchPaths, 0);
  Result := ScanPasFilesForDllReferences(APasFilePaths, LSearchPaths, LConditional);
end;

class function TDxComplyGenerator.ScanPasFilesForDllReferences(
  const APasFilePaths, ASearchPaths: TArray<string>;
  out AConditional: TArray<Boolean>): TArray<string>;
var
  LDllNames: TList<string>;
  LConditionalMap: TDictionary<string, Boolean>;
  LConstMap: TDictionary<string, TList<string>>;
  LGlobalConstMap: TDictionary<string, TList<string>>;
  LExpandedFiles: TObjectList<TStringList>;
  LUnitNames: TList<string>;
  LRegExExternal, LRegExLoadLib, LRegExLoadLibIdent, LRegExConstDll: TRegEx;
  LRegExExternalIdent, LRegExInclude: TRegEx;
  LRegExMatch: TMatch;
  LMatches: TMatchCollection;
  LFilePath, LLine: string;
  K: Integer;

  procedure AddDllName(const AName: string; AConditional: Boolean);
  var
    LKey: string;
    LWasConditional: Boolean;
  begin
    LKey := LowerCase(AName);
    if LKey = '' then
      Exit;
    if not LDllNames.Contains(LKey) then
      LDllNames.Add(LKey);
    // A literal or a single const value is a definite reference and
    // clears an earlier conditional flag for the same file name.
    if LConditionalMap.TryGetValue(LKey, LWasConditional) then
    begin
      if not AConditional then
        LConditionalMap.AddOrSetValue(LKey, False);
    end
    else
      LConditionalMap.Add(LKey, AConditional);
  end;

  function UnitNameOf(const AFilePath: string): string;
  begin
    Result := LowerCase(TPath.GetFileNameWithoutExtension(AFilePath));
  end;

  procedure RememberConst(const AMap: TDictionary<string, TList<string>>;
    const AKey, AValue: string);
  var
    LValues: TList<string>;
  begin
    if (AKey = '') or (AValue = '') then
      Exit;
    if not AMap.TryGetValue(AKey, LValues) then
    begin
      LValues := TList<string>.Create;
      AMap.Add(AKey, LValues);
    end;
    // Keep every assignment. {$IFDEF} branches often declare the same
    // const twice, and dropping either name hides a DLL the program
    // may load. Callers that define the const locally still see only
    // their own values, because the unit-scoped map is consulted first.
    if LValues.IndexOf(AValue) < 0 then
      LValues.Add(AValue);
  end;

  procedure AddResolvedNames(const AValues: TList<string>; AConditional: Boolean);
  var
    LValue: string;
  begin
    for LValue in AValues do
      AddDllName(LValue, AConditional);
  end;

  procedure ResolveIdent(const AUnitName, AIdent: string);
  var
    LValues: TList<string>;
    LLookupKey: string;
  begin
    if AIdent = '' then
      Exit;
    // Already qualified (Other.IDENT): use as-is. Otherwise look up
    // within the current unit first.
    if Pos('.', AIdent) > 0 then
      LLookupKey := AIdent
    else
      LLookupKey := AUnitName + '.' + AIdent;
    if LConstMap.TryGetValue(LLookupKey, LValues) then
      AddResolvedNames(LValues, LValues.Count > 1)
    else if (Pos('.', AIdent) = 0) and
            LGlobalConstMap.TryGetValue(AIdent, LValues) then
      // Project-wide fallback for consts declared in a separate unit
      // (OpenSSL_Consts.pas) and used from a sibling wrapper. Issue #24.
      // More than one value means the branches were not narrowed, so each
      // candidate is marked conditional.
      AddResolvedNames(LValues, LValues.Count > 1);
  end;

  function ResolveIncludePath(const AFromFile, AIncName: string): string;
  var
    LDir: string;
    LCandidate: string;
  begin
    Result := '';
    if AIncName = '' then
      Exit;
    if not TPath.IsRelativePath(AIncName) then
    begin
      if TFile.Exists(AIncName) then
        Result := AIncName;
      Exit;
    end;

    // The including file's own directory wins, then the project search path.
    LCandidate := TPath.Combine(TPath.GetDirectoryName(AFromFile), AIncName);
    if TFile.Exists(LCandidate) then
      Exit(LCandidate);

    for LDir in ASearchPaths do
    begin
      if Trim(LDir) = '' then
        Continue;
      LCandidate := TPath.Combine(LDir, AIncName);
      if TFile.Exists(LCandidate) then
        Exit(LCandidate);
    end;
  end;

  function IncludeFileName(const AMatch: TMatch): string;
  var
    G: Integer;
  begin
    Result := '';
    for G := 1 to AMatch.Groups.Count - 1 do
      if AMatch.Groups[G].Success and (AMatch.Groups[G].Value <> '') then
        Exit(AMatch.Groups[G].Value);
  end;

  procedure LoadExpanded(const APath: string; ADest: TStrings;
    ASeen: TDictionary<string, Boolean>; ADepth: Integer);
  var
    LRaw: TStringList;
    LIndex: Integer;
    LWork, LIncName, LResolved, LSeenKey: string;
    LIncMatch: TMatch;
  begin
    if (ADepth > 16) or (APath = '') then
      Exit;
    try
      LSeenKey := LowerCase(TPath.GetFullPath(APath));
    except
      Exit;
    end;
    if ASeen.ContainsKey(LSeenKey) then
      Exit;
    ASeen.Add(LSeenKey, True);

    LRaw := TStringList.Create;
    try
      try
        LRaw.LoadFromFile(APath, TEncoding.UTF8);
      except
        try
          LRaw.LoadFromFile(APath);
        except
          Exit;
        end;
      end;

      for LIndex := 0 to LRaw.Count - 1 do
      begin
        LWork := LRaw[LIndex];
        // {$I+}/{$I-} are IO-check switches, not file includes. The
        // pattern requires whitespace after I or INCLUDE, so those
        // switches stay in the line and are ignored by the DLL regexes.
        while True do
        begin
          LIncMatch := LRegExInclude.Match(LWork);
          if not LIncMatch.Success then
            Break;
          LIncName := IncludeFileName(LIncMatch);
          LResolved := ResolveIncludePath(APath, LIncName);
          LWork := LWork.Substring(0, LIncMatch.Index) +
            LWork.Substring(LIncMatch.Index + LIncMatch.Length);
          if LResolved <> '' then
            LoadExpanded(LResolved, ADest, ASeen, ADepth + 1);
        end;
        if Trim(LWork) <> '' then
          ADest.Add(LWork);
      end;
    finally
      LRaw.Free;
    end;
  end;

  procedure FreeConstMap(AMap: TDictionary<string, TList<string>>);
  var
    LValues: TList<string>;
  begin
    if not Assigned(AMap) then
      Exit;
    for LValues in AMap.Values do
      LValues.Free;
    AMap.Free;
  end;

  procedure CollectLiteralsAndConsts(const ALines: TStrings; const AUnitName: string);
  var
    LIndex, LMatchIndex: Integer;
  begin
    for LIndex := 0 to ALines.Count - 1 do
    begin
      LLine := ALines[LIndex];

      LMatches := LRegExExternal.Matches(LLine);
      for LMatchIndex := 0 to LMatches.Count - 1 do
        AddDllName(LMatches[LMatchIndex].Groups[1].Value, False);

      LMatches := LRegExLoadLib.Matches(LLine);
      for LMatchIndex := 0 to LMatches.Count - 1 do
        AddDllName(LMatches[LMatchIndex].Groups[1].Value, False);

      LRegExMatch := LRegExConstDll.Match(LLine);
      if LRegExMatch.Success then
      begin
        RememberConst(LConstMap,
          AUnitName + '.' + LowerCase(LRegExMatch.Groups[1].Value),
          LRegExMatch.Groups[2].Value);
        RememberConst(LGlobalConstMap,
          LowerCase(LRegExMatch.Groups[1].Value),
          LRegExMatch.Groups[2].Value);
      end;
    end;
  end;

  procedure ResolveIdentifierUses(const ALines: TStrings; const AUnitName: string);
  var
    LIndex, LMatchIndex: Integer;
  begin
    for LIndex := 0 to ALines.Count - 1 do
    begin
      LLine := ALines[LIndex];

      LMatches := LRegExLoadLibIdent.Matches(LLine);
      for LMatchIndex := 0 to LMatches.Count - 1 do
        ResolveIdent(AUnitName, LowerCase(LMatches[LMatchIndex].Groups[1].Value));

      // external DLLName (identifier, not a string literal). String
      // literals are collected in the first pass and do not match here
      // because the next token is a quote.
      LMatches := LRegExExternalIdent.Matches(LLine);
      for LMatchIndex := 0 to LMatches.Count - 1 do
        ResolveIdent(AUnitName, LowerCase(LMatches[LMatchIndex].Groups[1].Value));
    end;
  end;

var
  LExpanded: TStringList;
  LSeen: TDictionary<string, Boolean>;
  I: Integer;
  LFlag: Boolean;
begin
  SetLength(AConditional, 0);
  LDllNames := TList<string>.Create;
  LConditionalMap := TDictionary<string, Boolean>.Create;
  // "unitname.const_name" -> every file name assigned to that const.
  // Scoped per unit so the same identifier in two units does not collide.
  LConstMap := TDictionary<string, TList<string>>.Create;
  // Unqualified const name -> file names. Fallback when the calling unit
  // does not declare the identifier itself. Issue #24.
  LGlobalConstMap := TDictionary<string, TList<string>>.Create;
  LExpandedFiles := TObjectList<TStringList>.Create(True);
  LUnitNames := TList<string>.Create;
  try
    // Patterns:
    //   external 'filename.dll'
    //   external DLLName
    //   LoadLibrary('filename.dll') / LoadLibraryEx / SafeLoadLibrary /
    //     GetModuleHandle('filename.dll') / LoadPackage, plus the same
    //     calls with an identifier argument
    //   const NAME = 'filename.dll';
    //   {$I 'file.inc'} / {$INCLUDE file.inc} / (*$I 'file.inc'*)
    LRegExExternal := TRegEx.Create(
      'external\s+''([^'']+\.(dll|bpl))''', [roIgnoreCase]);
    LRegExExternalIdent := TRegEx.Create(
      'external\s+([A-Za-z_][A-Za-z0-9_\.]*)', [roIgnoreCase]);
    LRegExLoadLib := TRegEx.Create(
      '(?:LoadLibrary|LoadLibraryEx|LoadLibraryA|LoadLibraryW|SafeLoadLibrary|GetModuleHandle|GetModuleHandleA|GetModuleHandleW|LoadPackage)\s*\(\s*''([^'']+\.(dll|bpl))''',
      [roIgnoreCase]);
    LRegExLoadLibIdent := TRegEx.Create(
      '(?:LoadLibrary|LoadLibraryEx|LoadLibraryA|LoadLibraryW|SafeLoadLibrary|GetModuleHandle|GetModuleHandleA|GetModuleHandleW|LoadPackage)\s*\(\s*([A-Za-z_][A-Za-z0-9_\.]*)\s*[,)]',
      [roIgnoreCase]);
    // Only match real const declarations: identifier starts the line
    // (after whitespace), optional ': type', '=', single-quoted file name,
    // then ';'. Comparisons like `if X = 'foo.dll' then` do not end in
    // ';' on the comparison, so they will not match.
    LRegExConstDll := TRegEx.Create(
      '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*[A-Za-z_][A-Za-z0-9_]*\s*)?=\s*''([^'']+\.(?:dll|bpl))''\s*;',
      [roIgnoreCase]);
    LRegExInclude := TRegEx.Create(
      '\{\$\s*I(?:NCLUDE)?\s+(?:''([^'']+)''|"([^"]+)"|(\S+?))\s*\}' +
      '|\(\*\$\s*I(?:NCLUDE)?\s+(?:''([^'']+)''|"([^"]+)"|(\S+?))\s*\*\)',
      [roIgnoreCase]);

    for LFilePath in APasFilePaths do
    begin
      LExpanded := TStringList.Create;
      LExpandedFiles.Add(LExpanded);
      LUnitNames.Add(UnitNameOf(LFilePath));
      LSeen := TDictionary<string, Boolean>.Create;
      try
        LoadExpanded(LFilePath, LExpanded, LSeen, 0);
      finally
        LSeen.Free;
      end;
    end;

    // First pass: literals and the const map, so identifier uses (including
    // ones that arrived via an include) can be resolved afterwards.
    for K := 0 to LExpandedFiles.Count - 1 do
      CollectLiteralsAndConsts(LExpandedFiles[K], LUnitNames[K]);

    for K := 0 to LExpandedFiles.Count - 1 do
      ResolveIdentifierUses(LExpandedFiles[K], LUnitNames[K]);

    Result := LDllNames.ToArray;
    SetLength(AConditional, LDllNames.Count);
    for I := 0 to LDllNames.Count - 1 do
    begin
      if not LConditionalMap.TryGetValue(LDllNames[I], LFlag) then
        LFlag := False;
      AConditional[I] := LFlag;
    end;
  finally
    LUnitNames.Free;
    LExpandedFiles.Free;
    FreeConstMap(LGlobalConstMap);
    FreeConstMap(LConstMap);
    LConditionalMap.Free;
    LDllNames.Free;
  end;
end;

procedure TDxComplyGenerator.DoProgress(const AMessage: string; const AProgress: Integer);
begin
  if Assigned(FOnProgress) then
    FOnProgress(AMessage, AProgress);
end;

function TDxComplyGenerator.CreateWriter(AFormat: TSbomFormat): ISbomWriter;
begin
  case AFormat of
    sfCycloneDxJson:
      Result := TCycloneDxJsonWriter.Create;
    sfCycloneDxXml:
      Result := TCycloneDxXmlWriter.Create;
    sfSpdxJson:
      Result := TSpdxJsonWriter.Create;
  else
    Result := TCycloneDxJsonWriter.Create;
  end;
end;

function TDxComplyGenerator.CreateReportWriter(
  AFormat: THumanReadableReportFormat): IHumanReadableReportWriter;
begin
  case AFormat of
    hrfMarkdown:
      Result := TMarkdownReportWriter.Create;
    hrfHtml:
      Result := THtmlReportWriter.Create;
  else
    Result := TMarkdownReportWriter.Create;
  end;
end;

function TDxComplyGenerator.LoadConfig(const AConfigPath: string): TSbomConfig;
var
  LRoot: TJSONValue;
  LJson: TJSONObject;
  LContent: TStringList;
  LArray: TJSONArray;
  LDeepEvidence: TJSONObject;
  LFormatStr: string;
  LModeStr: string;
  LProduct: TJSONObject;
  LReport: TJSONObject;
  LReportFormatStr: string;
  LWarnings: TJSONObject;
  LManifestValue: TJSONValue;
  LText: string;
  I: Integer;
begin
  Result := TSbomConfig.Default;

  if not TFile.Exists(AConfigPath) then
    Exit;

  LContent := TStringList.Create;
  try
    LContent.LoadFromFile(AConfigPath, TEncoding.UTF8);
    // Parse into TJSONValue first. Casting with "as TJSONObject" before the
    // try leaks the value when the root is an array or a string.
    LRoot := TJSONObject.ParseJSONValue(LContent.Text);
    if LRoot = nil then
      Exit;
    try
      if LRoot is TJSONObject then
      begin
        LJson := TJSONObject(LRoot);
        // Output path
        if LJson.GetValue('output') <> nil then
          Result.OutputPath := LJson.GetValue<string>('output');

        // Format
        if LJson.GetValue('format') <> nil then
        begin
          LFormatStr := LowerCase(LJson.GetValue<string>('format'));
          if LFormatStr = 'cyclonedx-json' then
            Result.Format := sfCycloneDxJson
          else if LFormatStr = 'cyclonedx-xml' then
            Result.Format := sfCycloneDxXml
          else if LFormatStr = 'spdx-json' then
            Result.Format := sfSpdxJson;
        end;

        // Target platform. Empty values keep the default.
        // A non-empty value is explicit, not the built-in Win32 default.
        if LJson.GetValue('platform') <> nil then
        begin
          LText := Trim(LJson.GetValue<string>('platform'));
          if LText <> '' then
          begin
            Result.Platform := LText;
            Result.PlatformExplicit := True;
          end;
        end;

        // Build configuration. CLI flag is --config-name (issue #50).
        // configuration is the other name. configName wins when both are set.
        if LJson.GetValue('configName') <> nil then
        begin
          LText := Trim(LJson.GetValue<string>('configName'));
          if LText <> '' then
          begin
            Result.Configuration := LText;
            Result.ConfigurationExplicit := True;
          end;
        end
        else if LJson.GetValue('configuration') <> nil then
        begin
          LText := Trim(LJson.GetValue<string>('configuration'));
          if LText <> '' then
          begin
            Result.Configuration := LText;
            Result.ConfigurationExplicit := True;
          end;
        end;

        // Include patterns
        if LJson.GetValue('include') is TJSONArray then
        begin
          LArray := LJson.GetValue('include') as TJSONArray;
          SetLength(Result.IncludePatterns, LArray.Count);
          for I := 0 to LArray.Count - 1 do
            Result.IncludePatterns[I] := LArray.Items[I].Value;
        end;

        // Exclude patterns
        if LJson.GetValue('exclude') is TJSONArray then
        begin
          LArray := LJson.GetValue('exclude') as TJSONArray;
          SetLength(Result.ExcludePatterns, LArray.Count);
          for I := 0 to LArray.Count - 1 do
            Result.ExcludePatterns[I] := LArray.Items[I].Value;
        end;

        // Product info
        if LJson.GetValue('product') is TJSONObject then
        begin
          LProduct := TJSONObject(LJson.GetValue('product'));
          if LProduct.GetValue('name') <> nil then
            Result.ProductName := LProduct.GetValue<string>('name');
          if LProduct.GetValue('version') <> nil then
            Result.ProductVersion := LProduct.GetValue<string>('version');
          if LProduct.GetValue('supplier') <> nil then
            Result.Supplier := LProduct.GetValue<string>('supplier');
        end;

        // Deep Evidence
        if LJson.GetValue('deepEvidence') is TJSONObject then
        begin
          LDeepEvidence := LJson.GetValue('deepEvidence') as TJSONObject;
          if LDeepEvidence.GetValue('mode') <> nil then
          begin
            LModeStr := LowerCase(LDeepEvidence.GetValue<string>('mode'));
            if LModeStr = 'always' then
              Result.DeepEvidenceMode := debAlways
            else if (LModeStr = 'missing') or (LModeStr = 'when-missing') then
              Result.DeepEvidenceMode := debWhenMapMissing
            else
              Result.DeepEvidenceMode := debWhenMapMissing;
          end;
          // deepEvidence.build used to be read here, but both branches stored
          // debWhenMapMissing, so the flag could not turn the build off and
          // it overwrote an explicit mode. The CLI does not compile the
          // project. Use deepEvidence.mode (always | when-missing) instead.
          if LDeepEvidence.GetValue('delphiVersion') <> nil then
            Result.DeepEvidenceDelphiVersion := LDeepEvidence.GetValue<Integer>('delphiVersion');
          if LDeepEvidence.GetValue('buildScriptPath') <> nil then
            Result.DeepEvidenceBuildScriptPath := LDeepEvidence.GetValue<string>('buildScriptPath');
          if LDeepEvidence.GetValue('continueOnBuildFailure') <> nil then
            Result.ContinueOnDeepEvidenceBuildFailure :=
              LDeepEvidence.GetValue<Boolean>('continueOnBuildFailure');
        end;

        if LJson.GetValue('warnings') is TJSONObject then
        begin
          LWarnings := LJson.GetValue('warnings') as TJSONObject;
          if LWarnings.GetValue('warnOnEmptyCompositionEvidence') <> nil then
            Result.WarnOnEmptyCompositionEvidence :=
              LWarnings.GetValue<Boolean>('warnOnEmptyCompositionEvidence');
        end;

        if LJson.GetValue('report') is TJSONObject then
        begin
          LReport := LJson.GetValue('report') as TJSONObject;
          if LReport.GetValue('enabled') <> nil then
            Result.HumanReadableReport.Enabled := LReport.GetValue<Boolean>('enabled');
          if LReport.GetValue('format') <> nil then
          begin
            LReportFormatStr := LowerCase(LReport.GetValue<string>('format'));
            if LReportFormatStr = 'html' then
              Result.HumanReadableReport.Format := hrfHtml
            else if LReportFormatStr = 'both' then
              Result.HumanReadableReport.Format := hrfBoth
            else
              Result.HumanReadableReport.Format := hrfMarkdown;
          end;
          if LReport.GetValue('output') <> nil then
            Result.HumanReadableReport.OutputBasePath := LReport.GetValue<string>('output');
          if LReport.GetValue('includeWarnings') <> nil then
            Result.HumanReadableReport.IncludeWarnings := LReport.GetValue<Boolean>('includeWarnings');
          if LReport.GetValue('includeCompositionEvidence') <> nil then
            Result.HumanReadableReport.IncludeCompositionEvidence :=
              LReport.GetValue<Boolean>('includeCompositionEvidence');
          if LReport.GetValue('includeBuildEvidence') <> nil then
            Result.HumanReadableReport.IncludeBuildEvidence :=
              LReport.GetValue<Boolean>('includeBuildEvidence');
        end;

        // MAP file directory override
        if LJson.GetValue('mapDir') <> nil then
          Result.MapFileDir := LJson.GetValue<string>('mapDir');

        // Delphi 7 install override for legacy .dpr/.dpk/.bdsproj scans.
        if LJson.GetValue('delphi7Root') <> nil then
          Result.Delphi7Root := LJson.GetValue<string>('delphi7Root');

        // Composition evidence inclusion
        if LJson.GetValue('includeCompositionEvidence') <> nil then
          Result.IncludeCompositionEvidence :=
            LJson.GetValue<Boolean>('includeCompositionEvidence');

        if LJson.GetValue('scanDirs') is TJSONArray then
        begin
          LArray := LJson.GetValue('scanDirs') as TJSONArray;
          SetLength(Result.ScanDirs, LArray.Count);
          for I := 0 to LArray.Count - 1 do
            Result.ScanDirs[I] := LArray.Items[I].Value;
        end;

        if LJson.GetValue('scanTree') <> nil then
          Result.ScanTree := LJson.GetValue<Boolean>('scanTree');

        // Component manifest. A non-string value is ignored here; the IDE
        // reader reports that case. Relative paths stay relative until
        // generation, which resolves them from the project directory.
        if LJson.GetValue('manifest') <> nil then
        begin
          LManifestValue := LJson.GetValue('manifest');
          if (LManifestValue is TJSONString) or (LManifestValue is TJSONNumber) then
            Result.ManifestFile := Trim(LManifestValue.Value);
        end;
      end;
    finally
      LRoot.Free;
    end;
  finally
    LContent.Free;
  end;
end;

function TDxComplyGenerator.BuildMetadata(const AConfig: TSbomConfig;
  const AProjectInfo: TProjectInfo; const ABuildEvidence: TBuildEvidence;
  const ACompositionEvidence: TCompositionEvidence; const AWarnings: TList<string>;
  const ADeepEvidenceBuildResult: TDeepEvidenceBuildResult): TSbomMetadata;
var
  LBomProperties: TList<TSbomProperty>;
  LComponentProperties: TList<TSbomProperty>;

  const
    cPropertyNamespace = 'net.developer-experts.dx-comply';

  function PropertyName(const AGroup, AName: string): string;
  begin
    Result := cPropertyNamespace + ':' + AGroup + '.' + AName;
  end;

  procedure AddBomProperty(const AName, AValue: string);
  begin
    if (Trim(AName) = '') or (Trim(AValue) = '') then
      Exit;
    LBomProperties.Add(TSbomProperty.Create(AName, AValue));
  end;

  procedure AddComponentProperty(const AName, AValue: string);
  begin
    if (Trim(AName) = '') or (Trim(AValue) = '') then
      Exit;
    LComponentProperties.Add(TSbomProperty.Create(AName, AValue));
  end;

  function BoolToMetadataValue(const AValue: Boolean): string;
  begin
    if AValue then
      Result := 'true'
    else
      Result := 'false';
  end;

  function DcuModeToMetadataValue: string;
  begin
    if AProjectInfo.UsesDebugDCUs then
      Result := 'debug'
    else
      Result := 'release';
  end;

  function EffectiveMapFilePath: string;
  begin
    Result := Trim(ADeepEvidenceBuildResult.MapFilePath);
    if Result <> '' then
      Exit;

    Result := Trim(ABuildEvidence.Paths.MapFilePath);
    if Result <> '' then
      Exit;

    Result := Trim(AProjectInfo.MapFilePath);
  end;

  procedure AddConsolidatedUnitEvidenceProperties;
  begin
    AddComponentProperty(PropertyName('unit-evidence', 'count'),
      IntToStr(ACompositionEvidence.Units.Count));
  end;
begin
  Result.ProductName := AConfig.ProductName;
  Result.ProductVersion := AConfig.ProductVersion;
  Result.Supplier := AConfig.Supplier;
  Result.SupplierUrl := '';
  Result.ComponentManifestJson := '';
  Result.Timestamp := DateToISO8601(Now, False);
  Result.ToolName := 'DX.Comply';
  Result.ToolVersion := GetDxComplyToolVersion;
  LBomProperties := TList<TSbomProperty>.Create;
  LComponentProperties := TList<TSbomProperty>.Create;
  try
    AddBomProperty(PropertyName('document', 'profile'), 'build-evidence');
    AddBomProperty(PropertyName('assessment', 'warning-count'), IntToStr(AWarnings.Count));

    AddComponentProperty(PropertyName('build', 'map-file'), EffectiveMapFilePath);
    AddComponentProperty(PropertyName('build', 'platform'), AProjectInfo.Platform);
    AddComponentProperty(PropertyName('build', 'configuration'), AProjectInfo.Configuration);
    AddComponentProperty(PropertyName('build', 'dcu-mode'), DcuModeToMetadataValue);
    AddComponentProperty(PropertyName('build', 'output-dir'), ABuildEvidence.Paths.OutputDir);
    AddComponentProperty(PropertyName('build', 'dcu-output-dir'), ABuildEvidence.Paths.DcuOutputDir);
    AddComponentProperty(PropertyName('build', 'dcp-output-dir'), ABuildEvidence.Paths.DcpOutputDir);
    AddComponentProperty(PropertyName('build', 'bpl-output-dir'), ABuildEvidence.Paths.BplOutputDir);
    AddComponentProperty(PropertyName('build', 'response-file'), ABuildEvidence.Paths.ResponseFilePath);
    AddComponentProperty(PropertyName('build', 'evidence-item-count'),
      IntToStr(ABuildEvidence.EvidenceItems.Count));
    AddComponentProperty(PropertyName('build', 'search-path-count'),
      IntToStr(ABuildEvidence.SearchPaths.Count));
    AddComponentProperty(PropertyName('build', 'conditional-defines'),
      AProjectInfo.ConditionalDefines);
    AddComponentProperty(PropertyName('composition', 'resolved-unit-count'),
      IntToStr(ACompositionEvidence.Units.Count));
    AddConsolidatedUnitEvidenceProperties;
    AddComponentProperty(PropertyName('toolchain', 'product'), AProjectInfo.Toolchain.ProductName);
    AddComponentProperty(PropertyName('toolchain', 'version'), AProjectInfo.Toolchain.Version);
    AddComponentProperty(PropertyName('toolchain', 'build-version'), AProjectInfo.Toolchain.BuildVersion);
    AddComponentProperty(PropertyName('toolchain', 'root-dir'), AProjectInfo.Toolchain.RootDir);

    Result.Properties := LBomProperties.ToArray;
    Result.ComponentProperties := LComponentProperties.ToArray;
  finally
    LComponentProperties.Free;
    LBomProperties.Free;
  end;
end;

function TDxComplyGenerator.GenerateHumanReadableReports(const AData: TComplianceReportData;
  out AGeneratedReportPaths: TArray<string>): Boolean;
var
  LOutputBasePath: string;
  LOutputPath: string;
  LPaths: TList<string>;
  LWriter: IHumanReadableReportWriter;
  procedure GenerateOne(AFormat: THumanReadableReportFormat);
  begin
    LWriter := CreateReportWriter(AFormat);
    LOutputPath := ResolveReportOutputPath(LOutputBasePath, AFormat);
    DoProgress('Generating human-readable report (' +
      HumanReadableReportFormatToString(AFormat) + ')...', 92);
    if not LWriter.Write(LOutputPath, AData, FConfig.HumanReadableReport) then
      raise Exception.Create('Failed to write human-readable report: ' + LOutputPath);

    LPaths.Add(LOutputPath);
    DoProgress('Human-readable report generated: ' + LOutputPath, 96);
  end;
begin
  SetLength(AGeneratedReportPaths, 0);
  if not FConfig.HumanReadableReport.Enabled then
    Exit(True);

  LOutputBasePath := ResolveReportOutputBasePath(AData.SbomOutputPath);
  LPaths := TList<string>.Create;
  try
    case FConfig.HumanReadableReport.Format of
      hrfMarkdown:
        GenerateOne(hrfMarkdown);
      hrfHtml:
        GenerateOne(hrfHtml);
      hrfBoth:
      begin
        GenerateOne(hrfMarkdown);
        GenerateOne(hrfHtml);
      end;
    end;
    AGeneratedReportPaths := LPaths.ToArray;
    Result := True;
  finally
    LPaths.Free;
  end;
end;

procedure TDxComplyGenerator.RememberPatternWarnings(const AWarnings: TList<string>);
var
  LScanner: TFileScanner;
  LWarning: string;
begin
  if not Assigned(AWarnings) then
    Exit;
  if not ((FFileScanner as TObject) is TFileScanner) then
    Exit;

  LScanner := TFileScanner(FFileScanner as TObject);
  for LWarning in LScanner.PatternWarnings do
    if AWarnings.IndexOf(LWarning) < 0 then
      AWarnings.Add(LWarning);
end;

procedure TDxComplyGenerator.MergeArtefacts(const ATarget, ASource: TArtefactList);
var
  LArtefact: TArtefactInfo;
  LExisting: TArtefactInfo;
  I: Integer;
  LAlreadyListed: Boolean;
begin
  if not Assigned(ATarget) or not Assigned(ASource) then
    Exit;

  for LArtefact in ASource do
  begin
    LAlreadyListed := False;
    if LArtefact.FilePath <> '' then
      for I := 0 to ATarget.Count - 1 do
      begin
        LExisting := ATarget[I];
        if SameText(LExisting.FilePath, LArtefact.FilePath) then
        begin
          LAlreadyListed := True;
          Break;
        end;
      end;
    if not LAlreadyListed then
      ATarget.Add(LArtefact);
  end;
end;

function TDxComplyGenerator.CollectBuildArtefacts(
  const AProjectInfo: TProjectInfo): TArtefactList;
var
  LArtefact: TArtefactInfo;
  LOutputFile: string;
  LScanRoot: string;
  LScanned: TArtefactList;
  LScanDir: string;
  LWarnings: TList<string>;
  LWarning: string;
begin
  Result := TArtefactList.Create;
  LWarnings := TList<string>.Create;
  try
    try
      // The binary the .dproj names is always a candidate, including when the
      // file has not been built yet. CollectFile hashes it when it is on disk.
      // A later directory walk sees the same path; MergeArtefacts keeps one entry.
      if AProjectInfo.OutputFilePath <> '' then
      begin
        LOutputFile := AProjectInfo.OutputFilePath;
        try
          LOutputFile := TPath.GetFullPath(LOutputFile);
        except
          on E: EInOutArgumentException do
            LOutputFile := AProjectInfo.OutputFilePath;
        end;
        if FFileScanner.CollectFile(LOutputFile,
          TPath.GetFileName(LOutputFile),
          FConfig.IncludePatterns, FConfig.ExcludePatterns, LArtefact) then
          Result.Add(LArtefact);
        RememberPatternWarnings(LWarnings);
      end;

      if FConfig.ScanTree then
      begin
        // Previous releases walked OutputDir with soAllDirectories, which
        // pulled in setup\, tools\, and old build folders whenever that
        // directory fell back to the project root. Kept for one release.
        DoProgress('Warning: scanTree is deprecated and will be removed in a ' +
          'future release. The output directory is scanned recursively. ' +
          'Use scanDirs to add binaries that are staged somewhere else.', 30);
        LScanRoot := AProjectInfo.OutputDir;
      end
      else if AProjectInfo.ArtefactOutputDir <> '' then
        LScanRoot := AProjectInfo.ArtefactOutputDir
      else
        LScanRoot := AProjectInfo.OutputDir;

      if (LScanRoot <> '') and not TDirectory.Exists(LScanRoot) then
        DoProgress('Warning: Output directory not found: ' + LScanRoot, 29);

      LScanned := FFileScanner.Scan(LScanRoot, FConfig.IncludePatterns,
        FConfig.ExcludePatterns, FConfig.ScanTree);
      try
        MergeArtefacts(Result, LScanned);
      finally
        LScanned.Free;
      end;
      RememberPatternWarnings(LWarnings);

      for LScanDir in FConfig.ScanDirs do
      begin
        if Trim(LScanDir) = '' then
          Continue;
        LScanned := FFileScanner.ScanLocation(LScanDir, AProjectInfo.ProjectDir,
          FConfig.IncludePatterns, FConfig.ExcludePatterns);
        try
          MergeArtefacts(Result, LScanned);
        finally
          LScanned.Free;
        end;
        RememberPatternWarnings(LWarnings);
      end;

      for LWarning in LWarnings do
        DoProgress('Warning: ' + LWarning, 30);
    except
      Result.Free;
      raise;
    end;
  finally
    LWarnings.Free;
  end;
end;

function TDxComplyGenerator.Generate(const AProjectPath, AOutputPath: string;
  AFormat: TSbomFormat): Boolean;
var
  LDeepEvidenceBuildResult: TDeepEvidenceBuildResult;
  LProjectInfo: TProjectInfo;
  LBuildEvidence: TBuildEvidence;
  LCompositionEvidence: TCompositionEvidence;
  LArtefacts: TArtefactList;
  LMetadata: TSbomMetadata;
  LOutputPath: string;
  LFormat: TSbomFormat;
  LGeneratedReportPaths: TArray<string>;
  LReportedWarnings: TList<string>;
  LReportData: TComplianceReportData;
  LValidation: TValidationResult;
  LManifest: TComponentManifest;
  LManifestJson: string;
  LManifestPath: string;
  LManifestError: string;
  LDormantWarnings: TArray<string>;
  LWarningIndex: Integer;
begin
  Result := False;

  // Validate project
  if not FProjectScanner.Validate(AProjectPath) then
  begin
    DoProgress('Error: Invalid project file: ' + AProjectPath, -1);
    Exit;
  end;

  DoProgress('Scanning project...', 10);

  // Scan project. Initialize the record so the outer finally can safely call Free.
  LProjectInfo := Default(TProjectInfo);
  LBuildEvidence := Default(TBuildEvidence);
  LCompositionEvidence := Default(TCompositionEvidence);
  LDeepEvidenceBuildResult := Default(TDeepEvidenceBuildResult);
  LValidation := TValidationResult.CreateValid;
  LReportedWarnings := TList<string>.Create;
  LManifest := Default(TComponentManifest);
  LManifestJson := '';
  try
    FProjectScanner.SetDelphi7Root(FConfig.Delphi7Root);
    FProjectScanner.SetExplicitTargetRequest(FConfig.PlatformExplicit,
      FConfig.ConfigurationExplicit);
    LProjectInfo := FProjectScanner.Scan(AProjectPath, FConfig.Platform, FConfig.Configuration);

    // Apply MapFileDir override. Legacy projects look next to the output
    // binary unless the caller points at another directory.
    if FConfig.MapFileDir <> '' then
      LProjectInfo.MapFilePath := TPath.Combine(FConfig.MapFileDir,
        LProjectInfo.ProjectName + LProjectInfo.EffectiveMapSuffix + '.map');
  except
    on E: Exception do
    begin
      DoProgress('Error: Failed to read project file: ' + E.Message, -1);
      LReportedWarnings.Free;
      Exit;
    end;
  end;

  try
    ReportWarnings(LProjectInfo.Warnings, LReportedWarnings, 12);

    // Legacy projects are not compiled here. The MAP file must already sit
    // next to the output binary (or in --map-dir).
    if LProjectInfo.IsLegacyProject and
       ((Trim(LProjectInfo.MapFilePath) = '') or not TFile.Exists(LProjectInfo.MapFilePath)) then
    begin
      DoProgress('Error: ' + LegacyMapFileMissingMessage(LProjectInfo.MapFilePath), -1);
      Exit(False);
    end;

    if Trim(FConfig.ManifestFile) <> '' then
    begin
      LManifestPath := ResolveManifestPath(LProjectInfo.ProjectDir, FConfig.ManifestFile);
      if not TryLoadComponentManifest(LManifestPath, LManifest, LManifestJson, LManifestError) then
      begin
        DoProgress('Error: Invalid component manifest "' + LManifestPath + '": ' +
          LManifestError, -1);
        Exit(False);
      end;
      for LWarningIndex := 0 to High(LManifest.Warnings) do
        DoProgress('Warning: ' + LManifestPath + ': ' + LManifest.Warnings[LWarningIndex], 13);
    end;

    DoProgress('Ensuring MAP file...', 15);
    if LProjectInfo.IsLegacyProject then
    begin
      LDeepEvidenceBuildResult := Default(TDeepEvidenceBuildResult);
      LDeepEvidenceBuildResult.Success := True;
      LDeepEvidenceBuildResult.Executed := False;
      LDeepEvidenceBuildResult.Message :=
        'Legacy project: DX.Comply does not compile it. Using the MAP file from your build.';
      DoProgress(LDeepEvidenceBuildResult.Message, 18);
    end
    else
    try
      LDeepEvidenceBuildResult := EnsureDeepEvidenceBuild(LProjectInfo);
    except
      on E: Exception do
      begin
        LDeepEvidenceBuildResult := Default(TDeepEvidenceBuildResult);
        LDeepEvidenceBuildResult.Success := False;
        LDeepEvidenceBuildResult.Message := 'Deep-Evidence build failed: ' + E.Message;
      end;
    end;
    if not LDeepEvidenceBuildResult.Success then
    begin
      // When ContinueOnDeepEvidenceBuildFailure is set (the default), the
      // Deep-Evidence build is best-effort: the SBOM is still produced from
      // whatever MAP file is already present. Reporting the failure as
      // [ERROR] confused users who saw "Error: …" followed by a successful
      // "SBOM generated" line (issues #29 and #31). Demote the message to a
      // warning in that case and clarify that SBOM generation continues.
      if FConfig.ContinueOnDeepEvidenceBuildFailure then
      begin
        DoProgress('Warning: Skipping optional Deep-Evidence rebuild. ' +
          LDeepEvidenceBuildResult.Message, 18);
        if LDeepEvidenceBuildResult.CommandLine <> '' then
          DoProgress('Hint: Deep-Evidence command was: ' +
            LDeepEvidenceBuildResult.CommandLine, 18);
        if LDeepEvidenceBuildResult.Output <> '' then
          DoProgress('Hint: Deep-Evidence build output: ' +
            LDeepEvidenceBuildResult.Output, 18);
        DoProgress('Continuing SBOM generation with the existing MAP file (if any). ' +
          'See the log output above for details.', 18);
      end
      else
      begin
        DoProgress('Error: ' + LDeepEvidenceBuildResult.Message, -1);
        if LDeepEvidenceBuildResult.CommandLine <> '' then
          DoProgress('Command: ' + LDeepEvidenceBuildResult.CommandLine, -1);
        if LDeepEvidenceBuildResult.Output <> '' then
          DoProgress('Build output: ' + LDeepEvidenceBuildResult.Output, -1);
        Exit;
      end;
    end
    else if LDeepEvidenceBuildResult.Executed then
      DoProgress('MAP build completed.', 18)
    else
      DoProgress(LDeepEvidenceBuildResult.Message, 18);

    DoProgress('Preparing build evidence...', 20);
    LBuildEvidence := ReadBuildEvidence(LProjectInfo);
    DoProgress(Format('Collected %d build evidence item(s)',
      [LBuildEvidence.EvidenceItems.Count]), 25);
    ReportWarnings(LBuildEvidence.Warnings, LReportedWarnings, 26);

    DoProgress('Resolving composition evidence...', 28);
    LCompositionEvidence := ResolveCompositionEvidence(LProjectInfo, LBuildEvidence);
    DoProgress(Format('Resolved %d composition unit(s)',
      [LCompositionEvidence.Units.Count]), 29);
    ReportWarnings(LCompositionEvidence.Warnings, LReportedWarnings, 29);
    if FConfig.WarnOnEmptyCompositionEvidence and (LCompositionEvidence.Units.Count = 0) then
      DoProgress('Warning: ' + BuildEmptyCompositionWarning(LProjectInfo, LBuildEvidence), 29);

    DoProgress('Scanning build output...', 30);

    LArtefacts := CollectBuildArtefacts(LProjectInfo);
    try
      DoProgress(Format('Found %d artefacts', [LArtefacts.Count]), 50);

      // Determine output path
      if AOutputPath <> '' then
        LOutputPath := AOutputPath
      else
        LOutputPath := FConfig.OutputPath;

      // Make output path absolute if relative
      if TPath.IsRelativePath(LOutputPath) then
        LOutputPath := TPath.Combine(LProjectInfo.ProjectDir, LOutputPath);

      // Determine format
      if AFormat <> sfCycloneDxJson then
        LFormat := AFormat
      else
        LFormat := FConfig.Format;

      DoProgress('Collecting dependencies...', 60);
      AddRuntimePackagesToArtefacts(LProjectInfo, LArtefacts);
      AddExternalDllReferencesToArtefacts(LProjectInfo, LCompositionEvidence, LArtefacts);

      DoProgress('Generating SBOM...', 70);

      if FConfig.IncludeCompositionEvidence then
        AddCompositionEvidenceToArtefacts(LCompositionEvidence, LArtefacts);

      // Create writer and generate SBOM
      FSbomWriter := CreateWriter(LFormat);
      LMetadata := BuildMetadata(FConfig, LProjectInfo, LBuildEvidence,
        LCompositionEvidence, LReportedWarnings, LDeepEvidenceBuildResult);

      // Override metadata with project info if not specified
      if LMetadata.ProductName = '' then
        LMetadata.ProductName := LProjectInfo.ProjectName;
      if LMetadata.ProductVersion = '' then
        LMetadata.ProductVersion := LProjectInfo.Version;
      if LMetadata.Supplier = '' then
        LMetadata.Supplier := LProjectInfo.CompanyName;

      if LManifest.Loaded then
      begin
        LDormantWarnings := DormantComponentWarnings(LManifest,
          BuildManifestPlan(LManifest, LArtefacts));
        for LWarningIndex := 0 to High(LDormantWarnings) do
          DoProgress('Warning: ' + LManifestPath + ': ' + LDormantWarnings[LWarningIndex], 68);
        ApplyManifestPublisher(LManifest, LMetadata);
        LMetadata.ComponentManifestJson := LManifestJson;
      end;

      Result := FSbomWriter.Write(LOutputPath, LMetadata, LArtefacts, LProjectInfo);

      if Result then
      begin
        DoProgress('Running structural check...', 90);
        LValidation := ValidateSbom(LOutputPath);

        LReportData := BuildHumanReadableReportData(LOutputPath, LFormat, LMetadata,
          LProjectInfo, LBuildEvidence, LCompositionEvidence, LArtefacts,
          LReportedWarnings, LDeepEvidenceBuildResult, LValidation);
        if not GenerateHumanReadableReports(LReportData, LGeneratedReportPaths) then
        begin
          DoProgress('Error: Failed to generate the configured human-readable report.', -1);
          Exit(False);
        end;

        if LValidation.IsValid then
        begin
          if Length(LGeneratedReportPaths) > 0 then
            DoProgress(Format('SBOM and %d human-readable report(s) generated. Structural check passed: %s',
              [Length(LGeneratedReportPaths), LOutputPath]), 100)
          else
            DoProgress(Format('SBOM generated. Structural check passed: %s', [LOutputPath]), 100);
        end
        else
        begin
          if Length(LGeneratedReportPaths) > 0 then
            DoProgress(Format('SBOM and human-readable report(s) generated: %s (structural check did not pass)',
              [LOutputPath]), 95)
          else
            DoProgress(Format('SBOM generated: %s (structural check did not pass)', [LOutputPath]), 95);
          var LErr: string;
          for LErr in LValidation.Errors do
            DoProgress('Structural check error: ' + LErr, -1);
          var LWarn: string;
          for LWarn in LValidation.Warnings do
            DoProgress('Structural check warning: ' + LWarn, 95);
        end;
      end
      else
        DoProgress('Error: Failed to write SBOM', -1);

    finally
      LArtefacts.Free;
    end;
  finally
    LReportedWarnings.Free;
    LCompositionEvidence.Free;
    LBuildEvidence.Free;
    LProjectInfo.Free;
  end;
end;

function TDxComplyGenerator.MergeFileConfig(const ACaller, AFile: TSbomConfig): TSbomConfig;
begin
  // Precedence (issue #50):
  // 1. Built-in defaults, already applied by LoadConfig / TSbomConfig.Default.
  // 2. Keys present in the config file (AFile).
  // 3. Caller fields listed in ExplicitOverrides. An explicit CLI option wins.
  // Fields the caller left at the default are not treated as overrides.
  Result := AFile;

  if scoOutputPath in ACaller.ExplicitOverrides then
    Result.OutputPath := ACaller.OutputPath;
  if scoFormat in ACaller.ExplicitOverrides then
    Result.Format := ACaller.Format;
  if scoPlatform in ACaller.ExplicitOverrides then
    Result.Platform := ACaller.Platform;
  if scoConfiguration in ACaller.ExplicitOverrides then
    Result.Configuration := ACaller.Configuration;
  if scoProductName in ACaller.ExplicitOverrides then
    Result.ProductName := ACaller.ProductName;
  if scoProductVersion in ACaller.ExplicitOverrides then
    Result.ProductVersion := ACaller.ProductVersion;
  if scoSupplier in ACaller.ExplicitOverrides then
    Result.Supplier := ACaller.Supplier;
  if scoIncludePatterns in ACaller.ExplicitOverrides then
    Result.IncludePatterns := ACaller.IncludePatterns;
  if scoExcludePatterns in ACaller.ExplicitOverrides then
    Result.ExcludePatterns := ACaller.ExcludePatterns;
  if scoMapFileDir in ACaller.ExplicitOverrides then
    Result.MapFileDir := ACaller.MapFileDir;
  if scoIncludeCompositionEvidence in ACaller.ExplicitOverrides then
    Result.IncludeCompositionEvidence := ACaller.IncludeCompositionEvidence;
  if scoReport in ACaller.ExplicitOverrides then
  begin
    // Only the switch and the format come from the CLI. The file keeps its
    // report output path and include flags, which the CLI cannot set.
    Result.HumanReadableReport.Enabled := ACaller.HumanReadableReport.Enabled;
    Result.HumanReadableReport.Format := ACaller.HumanReadableReport.Format;
  end;
  if scoScanDirs in ACaller.ExplicitOverrides then
    Result.ScanDirs := ACaller.ScanDirs;
  if scoScanTree in ACaller.ExplicitOverrides then
    Result.ScanTree := ACaller.ScanTree;

  Result.IncludePlatformInOutput := ACaller.IncludePlatformInOutput;
  Result.ExplicitOverrides := ACaller.ExplicitOverrides;

  if Result.IncludePlatformInOutput and
     not (scoOutputPath in ACaller.ExplicitOverrides) and
     (Result.OutputPath <> '') then
    Result.OutputPath := TSbomConfig.DecorateOutputFileName(
      Result.OutputPath, Result.Platform, Result.Configuration);
end;

function TDxComplyGenerator.GenerateFromConfig(const AProjectPath, AConfigPath: string): Boolean;
var
  LCliConfig: TSbomConfig;
begin
  LCliConfig := FConfig;
  FConfig := MergeFileConfig(LCliConfig, LoadConfig(AConfigPath));
  if (FConfig.Delphi7Root = '') and (LCliConfig.Delphi7Root <> '') then
    FConfig.Delphi7Root := LCliConfig.Delphi7Root;
  if LCliConfig.PlatformExplicit then
    FConfig.PlatformExplicit := True;
  if LCliConfig.ConfigurationExplicit then
    FConfig.ConfigurationExplicit := True;
  if LCliConfig.ManifestFileExplicit then
  begin
    FConfig.ManifestFile := LCliConfig.ManifestFile;
    FConfig.ManifestFileExplicit := True;
  end;
  Result := Generate(AProjectPath);
end;

function TDxComplyGenerator.ValidateProject(const AProjectPath: string): Boolean;
begin
  Result := FProjectScanner.Validate(AProjectPath);
end;

function TDxComplyGenerator.ResolveReportOutputBasePath(
  const ASbomOutputPath: string): string;
begin
  Result := Trim(FConfig.HumanReadableReport.OutputBasePath);
  if Result = '' then
    Exit(TPath.Combine(TPath.GetDirectoryName(ASbomOutputPath),
      TPath.GetFileNameWithoutExtension(ASbomOutputPath) + '.report'));

  if TPath.IsRelativePath(Result) then
    Result := TPath.Combine(TPath.GetDirectoryName(ASbomOutputPath), Result);

  if Result.EndsWith('.md', True) then
    Exit(TPath.ChangeExtension(Result, ''));
  if Result.EndsWith('.html', True) then
    Exit(TPath.ChangeExtension(Result, ''));
end;

function TDxComplyGenerator.ResolveReportOutputPath(const AOutputBasePath: string;
  AFormat: THumanReadableReportFormat): string;
begin
  Result := AOutputBasePath;
  case AFormat of
    hrfMarkdown:
      Result := Result + '.md';
    hrfHtml:
      Result := Result + '.html';
  end;
end;

function TDxComplyGenerator.ValidateSbom(const AFilePath: string): TValidationResult;
var
  LContent: TStringList;
  LValidator: TSbomValidator;
begin
  Result := TValidationResult.CreateValid;
  if not TFile.Exists(AFilePath) then
  begin
    SetLength(Result.Errors, 1);
    Result.Errors[0] := 'File not found: ' + AFilePath;
    Result.IsValid := False;
    Exit;
  end;

  LContent := TStringList.Create;
  try
    LContent.LoadFromFile(AFilePath, TEncoding.UTF8);
    LValidator := TSbomValidator.Create;
    try
      Result := LValidator.ValidateAuto(LContent.Text);
    finally
      LValidator.Free;
    end;
  finally
    LContent.Free;
  end;
end;

end.
