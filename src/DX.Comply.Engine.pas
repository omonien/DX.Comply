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
    /// <summary>Target platform.</summary>
    Platform: string;
    /// <summary>Build configuration.</summary>
    Configuration: string;
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
    /// <summary>Creates a new TSbomConfig with default values.</summary>
    class function Default: TSbomConfig; static;
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
    function LoadConfig(const AConfigPath: string): TSbomConfig;
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
  public
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
    /// Generates an SBOM using a configuration file.
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
  DX.Comply.Report.Support;

{ TSbomConfig }

class function TSbomConfig.Default: TSbomConfig;
begin
  Result.OutputPath := 'bom.json';
  Result.Format := sfCycloneDxJson;
  Result.Platform := 'Win32';
  Result.Configuration := 'Release';
  Result.DeepEvidenceMode := debDisabled;
  Result.DeepEvidenceDelphiVersion := 0;
  Result.DeepEvidenceBuildScriptPath := '';
  Result.ContinueOnDeepEvidenceBuildFailure := False;
  Result.WarnOnEmptyCompositionEvidence := False;
  Result.HumanReadableReport := THumanReadableReportConfig.Default;
  Result.ProductName := '';
  Result.ProductVersion := '';
  Result.Supplier := '';
  SetLength(Result.IncludePatterns, 0);
  SetLength(Result.ExcludePatterns, 0);
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
  Result.DeepEvidenceRequested := FConfig.DeepEvidenceMode <> debDisabled;
  Result.DeepEvidenceResult := ADeepEvidenceBuildResult;
  Result.ValidationResult := AValidationResult;
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
  I: Integer;
begin
  Result := TSbomConfig.Default;

  if not TFile.Exists(AConfigPath) then
    Exit;

  LContent := TStringList.Create;
  try
    LContent.LoadFromFile(AConfigPath, TEncoding.UTF8);
    LJson := TJSONObject.ParseJSONValue(LContent.Text) as TJSONObject;
    try
      if Assigned(LJson) then
      begin
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
        if LJson.GetValue('product') <> nil then
        begin
          LProduct := LJson.GetValue('product') as TJSONObject;
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
              Result.DeepEvidenceMode := debDisabled;
          end;
          if LDeepEvidence.GetValue('build') <> nil then
          begin
            if LDeepEvidence.GetValue<Boolean>('build') then
              Result.DeepEvidenceMode := debWhenMapMissing
            else
              Result.DeepEvidenceMode := debDisabled;
          end;
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
      end;
    finally
      LJson.Free;
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

  function DeepEvidenceModeToMetadataValue: string;
  begin
    case FConfig.DeepEvidenceMode of
      debAlways:
        Result := 'always';
      debWhenMapMissing:
        Result := 'when-map-missing';
    else
      Result := 'disabled';
    end;
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
  Result.Timestamp := DateToISO8601(Now, False);
  Result.ToolName := 'DX.Comply';
  Result.ToolVersion := '1.0.0';
  LBomProperties := TList<TSbomProperty>.Create;
  LComponentProperties := TList<TSbomProperty>.Create;
  try
    AddBomProperty(PropertyName('document', 'profile'), 'cra-compliance-assessment');
    AddBomProperty(PropertyName('deep-evidence', 'mode'), DeepEvidenceModeToMetadataValue);
    AddBomProperty(PropertyName('deep-evidence', 'requested'),
      BoolToMetadataValue(FConfig.DeepEvidenceMode <> debDisabled));
    AddBomProperty(PropertyName('deep-evidence', 'executed'),
      BoolToMetadataValue(ADeepEvidenceBuildResult.Executed));
    AddBomProperty(PropertyName('deep-evidence', 'success'),
      BoolToMetadataValue(ADeepEvidenceBuildResult.Success));
    AddBomProperty(PropertyName('deep-evidence', 'exit-code'),
      IntToStr(ADeepEvidenceBuildResult.ExitCode));
    AddBomProperty(PropertyName('deep-evidence', 'message'), ADeepEvidenceBuildResult.Message);
    AddBomProperty(PropertyName('deep-evidence', 'command-line'), ADeepEvidenceBuildResult.CommandLine);
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
begin
  Result := False;

  // Validate project
  if not FProjectScanner.Validate(AProjectPath) then
  begin
    DoProgress('Error: Invalid project file: ' + AProjectPath, -1);
    Exit;
  end;

  DoProgress('Scanning project...', 10);

  // Scan project — initialize record so the outer finally can safely call Free
  LProjectInfo := Default(TProjectInfo);
  LBuildEvidence := Default(TBuildEvidence);
  LCompositionEvidence := Default(TCompositionEvidence);
  LDeepEvidenceBuildResult := Default(TDeepEvidenceBuildResult);
  LValidation := TValidationResult.CreateValid;
  LReportedWarnings := TList<string>.Create;
  try
    LProjectInfo := FProjectScanner.Scan(AProjectPath, FConfig.Platform, FConfig.Configuration);
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

    if FConfig.DeepEvidenceMode <> debDisabled then
    begin
      DoProgress('Ensuring Deep-Evidence build...', 15);
      LDeepEvidenceBuildResult := EnsureDeepEvidenceBuild(LProjectInfo);
      if not LDeepEvidenceBuildResult.Success then
      begin
        DoProgress('Error: ' + LDeepEvidenceBuildResult.Message, -1);
        if LDeepEvidenceBuildResult.CommandLine <> '' then
          DoProgress('Command: ' + LDeepEvidenceBuildResult.CommandLine, -1);
        if LDeepEvidenceBuildResult.Output <> '' then
          DoProgress('Build output: ' + LDeepEvidenceBuildResult.Output, -1);
        if FConfig.ContinueOnDeepEvidenceBuildFailure then
          DoProgress('Warning: Continuing SBOM generation without rebuilt MAP evidence.', 18)
        else
          Exit;
      end;

      if LDeepEvidenceBuildResult.Success and LDeepEvidenceBuildResult.Executed then
        DoProgress('Deep-Evidence build completed.', 18)
      else if LDeepEvidenceBuildResult.Success then
        DoProgress(LDeepEvidenceBuildResult.Message, 18);
    end;

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

    // Warn if output directory doesn't exist (artefacts not yet built)
    if not TDirectory.Exists(LProjectInfo.OutputDir) then
      DoProgress('Warning: Output directory not found: ' + LProjectInfo.OutputDir, 29);

    // Scan artefacts
    LArtefacts := FFileScanner.Scan(LProjectInfo.OutputDir,
      FConfig.IncludePatterns, FConfig.ExcludePatterns);
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

      DoProgress('Generating SBOM...', 70);

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

      Result := FSbomWriter.Write(LOutputPath, LMetadata, LArtefacts, LProjectInfo);

      if Result then
      begin
        DoProgress('Validating SBOM...', 90);
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
            DoProgress(Format('SBOM and %d human-readable report(s) generated and validated: %s',
              [Length(LGeneratedReportPaths), LOutputPath]), 100)
          else
            DoProgress(Format('SBOM generated and validated: %s', [LOutputPath]), 100);
        end
        else
        begin
          if Length(LGeneratedReportPaths) > 0 then
            DoProgress(Format('SBOM and human-readable report(s) generated: %s (with validation warnings)',
              [LOutputPath]), 95)
          else
            DoProgress(Format('SBOM generated: %s (with validation warnings)', [LOutputPath]), 95);
          var LErr: string;
          for LErr in LValidation.Errors do
            DoProgress('Validation error: ' + LErr, -1);
          var LWarn: string;
          for LWarn in LValidation.Warnings do
            DoProgress('Validation warning: ' + LWarn, 95);
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

function TDxComplyGenerator.GenerateFromConfig(const AProjectPath, AConfigPath: string): Boolean;
begin
  FConfig := LoadConfig(AConfigPath);
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
