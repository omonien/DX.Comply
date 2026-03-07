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
  DX.Comply.BuildEvidence.Reader,
  DX.Comply.ProjectScanner,
  DX.Comply.FileScanner,
  DX.Comply.HashService,
  DX.Comply.CycloneDx.Writer,
  DX.Comply.CycloneDx.XmlWriter,
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
    FFileScanner: IFileScanner;
    FHashService: IHashService;
    FSbomWriter: ISbomWriter;
    FConfig: TSbomConfig;
    FOnProgress: TProgressEvent;
    procedure DoProgress(const AMessage: string; const AProgress: Integer);
    function LoadConfig(const AConfigPath: string): TSbomConfig;
    function CreateWriter(AFormat: TSbomFormat): ISbomWriter;
    function BuildMetadata(const AConfig: TSbomConfig): TSbomMetadata;
    function ReadBuildEvidence(const AProjectInfo: TProjectInfo): TBuildEvidence;
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

{ TSbomConfig }

class function TSbomConfig.Default: TSbomConfig;
begin
  Result.OutputPath := 'bom.json';
  Result.Format := sfCycloneDxJson;
  Result.Platform := 'Win32';
  Result.Configuration := 'Release';
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
  FHashService := THashService.Create;
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

function TDxComplyGenerator.LoadConfig(const AConfigPath: string): TSbomConfig;
var
  LJson: TJSONObject;
  LContent: TStringList;
  LArray: TJSONArray;
  LFormatStr: string;
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
          var LProduct := LJson.GetValue('product') as TJSONObject;
          if LProduct.GetValue('name') <> nil then
            Result.ProductName := LProduct.GetValue<string>('name');
          if LProduct.GetValue('version') <> nil then
            Result.ProductVersion := LProduct.GetValue<string>('version');
          if LProduct.GetValue('supplier') <> nil then
            Result.Supplier := LProduct.GetValue<string>('supplier');
        end;
      end;
    finally
      LJson.Free;
    end;
  finally
    LContent.Free;
  end;
end;

function TDxComplyGenerator.BuildMetadata(const AConfig: TSbomConfig): TSbomMetadata;
begin
  Result.ProductName := AConfig.ProductName;
  Result.ProductVersion := AConfig.ProductVersion;
  Result.Supplier := AConfig.Supplier;
  Result.Timestamp := DateToISO8601(Now, False);
  Result.ToolName := 'DX.Comply';
  Result.ToolVersion := '1.0.0';
end;

function TDxComplyGenerator.Generate(const AProjectPath, AOutputPath: string;
  AFormat: TSbomFormat): Boolean;
var
  LProjectInfo: TProjectInfo;
  LBuildEvidence: TBuildEvidence;
  LArtefacts: TArtefactList;
  LMetadata: TSbomMetadata;
  LOutputPath: string;
  LFormat: TSbomFormat;
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
  try
    LProjectInfo := FProjectScanner.Scan(AProjectPath, FConfig.Platform, FConfig.Configuration);
  except
    on E: Exception do
    begin
      DoProgress('Error: Failed to read project file: ' + E.Message, -1);
      Exit;
    end;
  end;

  try
    DoProgress('Preparing build evidence...', 20);
    LBuildEvidence := ReadBuildEvidence(LProjectInfo);
    DoProgress(Format('Collected %d build evidence item(s)',
      [LBuildEvidence.EvidenceItems.Count]), 25);

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

      // Create writer and generate SBOM
      FSbomWriter := CreateWriter(LFormat);
      LMetadata := BuildMetadata(FConfig);

      // Override metadata with project info if not specified
      if LMetadata.ProductName = '' then
        LMetadata.ProductName := LProjectInfo.ProjectName;
      if LMetadata.ProductVersion = '' then
        LMetadata.ProductVersion := LProjectInfo.Version;

      Result := FSbomWriter.Write(LOutputPath, LMetadata, LArtefacts, LProjectInfo);

      if Result then
      begin
        DoProgress('Validating SBOM...', 90);
        // Post-write schema validation
        var LValidation := ValidateSbom(LOutputPath);
        if LValidation.IsValid then
          DoProgress(Format('SBOM generated and validated: %s', [LOutputPath]), 100)
        else
        begin
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
