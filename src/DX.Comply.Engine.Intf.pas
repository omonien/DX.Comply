/// <summary>
/// DX.Comply.Engine.Intf
/// Core interfaces for DX.Comply SBOM generation engine.
/// </summary>
///
/// <remarks>
/// This unit defines the core interfaces used throughout DX.Comply:
/// - IProjectScanner: Scans and parses .dproj files
/// - IFileScanner: Scans build output directories
/// - IHashService: Computes cryptographic hashes
/// - ISbomWriter: Writes SBOM documents in various formats
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Engine.Intf;

interface

uses
  System.Generics.Collections;

type
  /// <summary>
  /// Represents a single file artefact discovered during scanning.
  /// </summary>
  TArtefactInfo = record
    /// <summary>Full path to the file.</summary>
    FilePath: string;
    /// <summary>Relative path from the project root.</summary>
    RelativePath: string;
    /// <summary>File size in bytes.</summary>
    FileSize: Int64;
    /// <summary>SHA-256 hash as hexadecimal string.</summary>
    Hash: string;
    /// <summary>Artefact type (exe, dll, bpl, dcp, resource, unit-evidence).</summary>
    ArtefactType: string;
    /// <summary>Unit origin label for composition evidence (e.g. Embarcadero RTL).</summary>
    Origin: string;
    /// <summary>Evidence kind label for composition evidence (e.g. DCU, PAS).</summary>
    Evidence: string;
    /// <summary>Resolution confidence label for composition evidence (e.g. Strong).</summary>
    Confidence: string;
    /// <summary>
    /// True when the file name is one of several {$IFDEF} candidates and the
    /// active compiler define was not applied. Writers emit this as
    /// net.developer-experts.dx-comply:conditional.
    /// </summary>
    Conditional: Boolean;
  end;

  /// <summary>
  /// List of artefacts discovered during scanning.
  /// </summary>
  TArtefactList = TList<TArtefactInfo>;

  /// <summary>
  /// Explicit unit reference declared by the project model or main source file.
  /// </summary>
  TProjectUnitReference = record
    /// <summary>Fully qualified unit name.</summary>
    UnitName: string;
    /// <summary>Resolved file path of the referenced unit.</summary>
    FilePath: string;
    /// <summary>Metadata source that declared the reference.</summary>
    Source: string;
  end;

  /// <summary>
  /// List of explicit project unit references.
  /// </summary>
  TProjectUnitReferenceList = TList<TProjectUnitReference>;

  /// <summary>
  /// Resolved Delphi toolchain metadata for the current project scan.
  /// </summary>
  TDelphiToolchainInfo = record
    /// <summary>Toolchain product/vendor label.</summary>
    ProductName: string;
    /// <summary>Delphi product version, for example 37.0.</summary>
    Version: string;
    /// <summary>Build version taken from the installed IDE binary.</summary>
    BuildVersion: string;
    /// <summary>Root directory of the detected Delphi installation.</summary>
    RootDir: string;
  end;

  /// <summary>
  /// Project metadata extracted from .dproj file.
  /// </summary>
  TProjectInfo = record
    /// <summary>Project name (without extension).</summary>
    ProjectName: string;
    /// <summary>Full path to the .dproj file.</summary>
    ProjectPath: string;
    /// <summary>Project directory (containing folder).</summary>
    ProjectDir: string;
    /// <summary>Main project source file (.dpr / .dpk) if it could be resolved.</summary>
    MainSourcePath: string;
    /// <summary>Target platform (Win32, Win64, etc.).</summary>
    Platform: string;
    /// <summary>Build configuration (Debug, Release).</summary>
    Configuration: string;
    /// <summary>True when the selected build is configured to use Delphi debug DCUs.</summary>
    UsesDebugDCUs: Boolean;
    /// <summary>Output directory for build artefacts.</summary>
    OutputDir: string;
    /// <summary>
    /// Directory that contains the binary this project builds (exe, dll, or bpl).
    /// Sibling binaries are scanned here. For a package this is the BPL output
    /// directory when one is set, which can differ from OutputDir.
    /// </summary>
    ArtefactOutputDir: string;
    /// <summary>
    /// Full path of the exe, dll, or bpl the .dproj names for the active
    /// configuration and platform, including DllSuffix. Empty when that name
    /// cannot be resolved.
    /// </summary>
    OutputFilePath: string;
    /// <summary>Output directory for generated package binaries (.bpl).</summary>
    BplOutputDir: string;
    /// <summary>Output directory for generated package metadata (.dcp).</summary>
    DcpOutputDir: string;
    /// <summary>Output directory for generated compiled units (.dcu).</summary>
    DcuOutputDir: string;
    /// <summary>DllSuffix / LibSuffix appended to package output file names (BPL, DCP, MAP).</summary>
    DllSuffix: string;
    /// <summary>Expected or resolved map file path for the selected build.</summary>
    MapFilePath: string;
    /// <summary>Project version (if specified).</summary>
    Version: string;
    /// <summary>
    /// True when the project file is a pre-MSBuild Delphi project
    /// (.dpr, .dpk, or .bdsproj). Those projects have one Win32 option set.
    /// </summary>
    IsLegacyProject: Boolean;
    /// <summary>
    /// CompanyName from legacy version info. The engine uses this as the
    /// SBOM supplier when the configuration does not set one.
    /// </summary>
    CompanyName: string;
    /// <summary>
    /// Conditional symbols from a legacy .dof or .cfg, separated by semicolons.
    /// Empty for .dproj projects.
    /// </summary>
    ConditionalDefines: string;
    /// <summary>Effective unit search paths for the selected platform/configuration.</summary>
    SearchPaths: TList<string>;
    /// <summary>Project-local unit search paths derived from the .dproj file.</summary>
    ProjectSearchPaths: TList<string>;
    /// <summary>Global Delphi library/source search roots in effective resolution order.</summary>
    GlobalSearchPaths: TList<string>;
    /// <summary>Resolved unit scope names for the selected platform/configuration.</summary>
    UnitScopeNames: TList<string>;
    /// <summary>List of runtime package dependencies.</summary>
    RuntimePackages: TList<string>;
    /// <summary>Explicit unit references declared by the project metadata.</summary>
    ExplicitUnitReferences: TProjectUnitReferenceList;
    /// <summary>Detected Delphi toolchain metadata.</summary>
    Toolchain: TDelphiToolchainInfo;
    /// <summary>Warnings collected while scanning the project metadata.</summary>
    Warnings: TList<string>;
    /// <summary>Initializes the record with a new TList instance.</summary>
    class function Create: TProjectInfo; static;
    /// <summary>Frees internal resources. Call this when done with the record.</summary>
    procedure Free;
    /// <summary>Returns True when the project is a package (.dpk), False for applications (.dpr).</summary>
    function IsPackage: Boolean;
    /// <summary>Returns the effective suffix for MAP file names (DllSuffix for packages, empty for applications).</summary>
    function EffectiveMapSuffix: string;
  end;

  /// <summary>
  /// SBOM metadata for the generated document.
  /// </summary>
  TSbomProperty = record
    /// <summary>Property name written into the SBOM.</summary>
    Name: string;
    /// <summary>Property value written into the SBOM.</summary>
    Value: string;
    /// <summary>Creates one SBOM metadata property entry.</summary>
    class function Create(const AName, AValue: string): TSbomProperty; static;
  end;

  /// <summary>
  /// SBOM metadata for the generated document.
  /// </summary>
  TSbomMetadata = record
    /// <summary>Product name.</summary>
    ProductName: string;
    /// <summary>Product version.</summary>
    ProductVersion: string;
    /// <summary>Supplier/manufacturer name.</summary>
    Supplier: string;
    /// <summary>Timestamp of SBOM generation (ISO 8601).</summary>
    Timestamp: string;
    /// <summary>Tool name that generated the SBOM.</summary>
    ToolName: string;
    /// <summary>Tool version.</summary>
    ToolVersion: string;
    /// <summary>Additional DX.Comply BOM metadata properties for the formal SBOM.</summary>
    Properties: TArray<TSbomProperty>;
    /// <summary>Additional DX.Comply component properties for metadata.component.</summary>
    ComponentProperties: TArray<TSbomProperty>;
  end;

  /// <summary>
  /// Supported SBOM output formats.
  /// </summary>
  TSbomFormat = (
    /// <summary>CycloneDX JSON format.</summary>
    sfCycloneDxJson,
    /// <summary>CycloneDX XML format.</summary>
    sfCycloneDxXml,
    /// <summary>SPDX JSON format.</summary>
    sfSpdxJson
  );

  /// <summary>
  /// Interface for scanning .dproj project files.
  /// </summary>
  IProjectScanner = interface
    ['{A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D}']
    /// <summary>
    /// Scans the specified .dproj file and extracts project metadata.
    /// </summary>
    /// <param name="AProjectPath">Full path to the .dproj file.</param>
    /// <param name="APlatform">Target platform (Win32, Win64, etc.).</param>
    /// <param name="AConfiguration">Build configuration (Debug, Release).</param>
    /// <returns>TProjectInfo with extracted metadata.</returns>
    function Scan(const AProjectPath, APlatform, AConfiguration: string): TProjectInfo;
    /// <summary>
    /// Validates that the project file exists and has a supported extension.
    /// </summary>
    function Validate(const AProjectPath: string): Boolean;
    /// <summary>
    /// Optional Delphi 7 installation directory. Used when a .dpr, .dpk, or
    /// .bdsproj is scanned. Empty means registry and the DELPHI environment
    /// variable. A missing install does not fail the scan.
    /// </summary>
    procedure SetDelphi7Root(const ARoot: string);
    /// <summary>
    /// Records whether the caller set --platform and --config-name (or the
    /// matching .dxcomply.json keys). Legacy scans warn only when a flag is
    /// True and the value is not the single Win32 / Default option set.
    /// </summary>
    procedure SetExplicitTargetRequest(APlatformExplicit,
      AConfigurationExplicit: Boolean);
  end;

  /// <summary>
  /// Interface for scanning build output directories.
  /// </summary>
  IFileScanner = interface
    ['{B2C3D4E5-F6A7-4B5C-9D0E-1F2A3B4C5D6E}']
    /// <summary>
    /// Scans the specified directory for build artefacts.
    /// </summary>
    /// <param name="ADirectory">Directory to scan.</param>
    /// <param name="AIncludePatterns">Glob patterns for files to include.</param>
    /// <param name="AExcludePatterns">Glob patterns for files to exclude.</param>
    /// <param name="ARecursive">
    /// When True, subdirectories are walked as well. The default is False:
    /// only files directly in ADirectory are considered.
    /// </param>
    /// <returns>TArtefactList with discovered files.</returns>
    function Scan(const ADirectory: string;
      const AIncludePatterns, AExcludePatterns: TArray<string>;
      ARecursive: Boolean = False): TArtefactList;
    /// <summary>
    /// Scans one extra location from --scan-dir or scanDirs.
    /// A plain directory is not recursive. A value that contains ** walks
    /// subdirectories. ABaseDir resolves a relative location.
    /// </summary>
    function ScanLocation(const ALocation, ABaseDir: string;
      const AIncludePatterns, AExcludePatterns: TArray<string>): TArtefactList;
    /// <summary>
    /// Builds an artefact for one file when it passes include/exclude.
    /// A missing file is still returned so the named project output can be
    /// listed before it has been built. Hash and size are set only when the
    /// file exists.
    /// </summary>
    function CollectFile(const AFilePath, ARelativePath: string;
      const AIncludePatterns, AExcludePatterns: TArray<string>;
      out AArtefact: TArtefactInfo): Boolean;
    /// <summary>
    /// Determines the artefact type based on file extension.
    /// </summary>
    function GetArtefactType(const AFilePath: string): string;
  end;

  /// <summary>
  /// Interface for computing cryptographic hashes.
  /// </summary>
  IHashService = interface
    ['{C3D4E5F6-A7B8-4C5D-0E1F-2A3B4C5D6E7F}']
    /// <summary>
    /// Computes SHA-256 hash of the specified file.
    /// </summary>
    /// <param name="AFilePath">Full path to the file.</param>
    /// <returns>Hexadecimal string representation of the hash.</returns>
    function ComputeSha256(const AFilePath: string): string;
    /// <summary>
    /// Computes SHA-512 hash of the specified file.
    /// </summary>
    /// <param name="AFilePath">Full path to the file.</param>
    /// <returns>Hexadecimal string representation of the hash.</returns>
    function ComputeSha512(const AFilePath: string): string;
  end;

  /// <summary>
  /// Interface for writing SBOM documents.
  /// </summary>
  ISbomWriter = interface
    ['{D4E5F6A7-B8C9-4D5E-1F2A-3B4C5D6E7F8A}']
    /// <summary>
    /// Writes the SBOM document to the specified file.
    /// </summary>
    /// <param name="AOutputPath">Output file path.</param>
    /// <param name="AMetadata">SBOM metadata.</param>
    /// <param name="AArtefacts">List of artefacts to include.</param>
    /// <param name="AProjectInfo">Project information.</param>
    /// <returns>True if writing succeeded.</returns>
    function Write(const AOutputPath: string;
      const AMetadata: TSbomMetadata;
      const AArtefacts: TArtefactList;
      const AProjectInfo: TProjectInfo): Boolean;
    /// <summary>
    /// Returns the supported SBOM format.
    /// </summary>
    function GetFormat: TSbomFormat;
    /// <summary>
    /// Validates the generated SBOM against the schema.
    /// </summary>
    function Validate(const AContent: string): Boolean;
  end;

/// <summary>
/// Index of the built exe, dll or bpl inside AArtefacts, or -1 when the
/// list has no deliverable. An exe is preferred over a dll or bpl, and a
/// file whose name matches AProjectName is preferred over other files of
/// the same kind. Runtime packages and source-scanned DLL references are
/// not deliverables.
/// </summary>
function FindDeliverableTargetIndex(const AArtefacts: TArtefactList;
  const AProjectName: string): Integer;

/// <summary>
/// Grouping order for a dependency edge: 0 runtime package, 1 external
/// DLL reference, 2 linked unit, 3 any other artefact.
/// </summary>
function ArtefactDependencyGroup(const AArtefact: TArtefactInfo): Integer;

implementation

uses
  System.IOUtils,
  System.SysUtils;

{ TSbomProperty }

class function TSbomProperty.Create(const AName, AValue: string): TSbomProperty;
begin
  Result.Name := AName;
  Result.Value := AValue;
end;

{ TProjectInfo }

class function TProjectInfo.Create: TProjectInfo;
begin
  Result := Default(TProjectInfo);
  Result.SearchPaths := TList<string>.Create;
  Result.ProjectSearchPaths := TList<string>.Create;
  Result.GlobalSearchPaths := TList<string>.Create;
  Result.UnitScopeNames := TList<string>.Create;
  Result.RuntimePackages := TList<string>.Create;
  Result.ExplicitUnitReferences := TProjectUnitReferenceList.Create;
  Result.Warnings := TList<string>.Create;
end;

procedure TProjectInfo.Free;
begin
  if Assigned(SearchPaths) then
  begin
    SearchPaths.Free;
    SearchPaths := nil;
  end;

  if Assigned(ProjectSearchPaths) then
  begin
    ProjectSearchPaths.Free;
    ProjectSearchPaths := nil;
  end;

  if Assigned(GlobalSearchPaths) then
  begin
    GlobalSearchPaths.Free;
    GlobalSearchPaths := nil;
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

  if Assigned(ExplicitUnitReferences) then
  begin
    ExplicitUnitReferences.Free;
    ExplicitUnitReferences := nil;
  end;

  if Assigned(Warnings) then
  begin
    Warnings.Free;
    Warnings := nil;
  end;
end;

function TProjectInfo.IsPackage: Boolean;
begin
  Result := (MainSourcePath <> '') and
    SameText(TPath.GetExtension(MainSourcePath), '.dpk');
end;

function TProjectInfo.EffectiveMapSuffix: string;
begin
  if IsPackage then
    Result := DllSuffix
  else
    Result := '';
end;

function TargetKindScore(const AArtefactType: string): Integer;
begin
  if SameText(AArtefactType, 'application') then
    Result := 300
  else if SameText(AArtefactType, 'package') then
    Result := 200
  else if SameText(AArtefactType, 'library') then
    Result := 100
  else
    Result := -1;
end;

function FindDeliverableTargetIndex(const AArtefacts: TArtefactList;
  const AProjectName: string): Integer;
var
  I: Integer;
  LScore: Integer;
  LBest: Integer;
  LName: string;
begin
  Result := -1;
  LBest := -1;
  if not Assigned(AArtefacts) then
    Exit;

  for I := 0 to AArtefacts.Count - 1 do
  begin
    LScore := TargetKindScore(AArtefacts[I].ArtefactType);
    if LScore < 0 then
      Continue;

    LName := TPath.GetFileNameWithoutExtension(AArtefacts[I].RelativePath);
    if (AProjectName <> '') and SameText(LName, AProjectName) then
      Inc(LScore, 10);

    if LScore > LBest then
    begin
      LBest := LScore;
      Result := I;
    end;
  end;
end;

function ArtefactDependencyGroup(const AArtefact: TArtefactInfo): Integer;
begin
  if SameText(AArtefact.ArtefactType, 'runtime-package') then
    Result := 0
  else if SameText(AArtefact.ArtefactType, 'external-reference') then
    Result := 1
  else if SameText(AArtefact.ArtefactType, 'unit-evidence') then
    Result := 2
  else
    Result := 3;
end;

end.
