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
    /// <summary>Artefact type (exe, dll, bpl, dcp, resource).</summary>
    ArtefactType: string;
  end;

  /// <summary>
  /// List of artefacts discovered during scanning.
  /// </summary>
  TArtefactList = TList<TArtefactInfo>;

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
    /// <summary>Target platform (Win32, Win64, etc.).</summary>
    Platform: string;
    /// <summary>Build configuration (Debug, Release).</summary>
    Configuration: string;
    /// <summary>Output directory for build artefacts.</summary>
    OutputDir: string;
    /// <summary>Output directory for generated package binaries (.bpl).</summary>
    BplOutputDir: string;
    /// <summary>Output directory for generated package metadata (.dcp).</summary>
    DcpOutputDir: string;
    /// <summary>Output directory for generated compiled units (.dcu).</summary>
    DcuOutputDir: string;
    /// <summary>Project version (if specified).</summary>
    Version: string;
    /// <summary>Resolved unit search paths for the selected platform/configuration.</summary>
    SearchPaths: TList<string>;
    /// <summary>Resolved unit scope names for the selected platform/configuration.</summary>
    UnitScopeNames: TList<string>;
    /// <summary>List of runtime package dependencies.</summary>
    RuntimePackages: TList<string>;
    /// <summary>Warnings collected while scanning the project metadata.</summary>
    Warnings: TList<string>;
    /// <summary>Initializes the record with a new TList instance.</summary>
    class function Create: TProjectInfo; static;
    /// <summary>Frees internal resources. Call this when done with the record.</summary>
    procedure Free;
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
    /// Validates that the .dproj file exists and is readable.
    /// </summary>
    function Validate(const AProjectPath: string): Boolean;
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
    /// <returns>TArtefactList with discovered files.</returns>
    function Scan(const ADirectory: string;
      const AIncludePatterns, AExcludePatterns: TArray<string>): TArtefactList;
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

implementation

{ TProjectInfo }

class function TProjectInfo.Create: TProjectInfo;
begin
  Result := Default(TProjectInfo);
  Result.SearchPaths := TList<string>.Create;
  Result.UnitScopeNames := TList<string>.Create;
  Result.RuntimePackages := TList<string>.Create;
  Result.Warnings := TList<string>.Create;
end;

procedure TProjectInfo.Free;
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

  if Assigned(Warnings) then
  begin
    Warnings.Free;
    Warnings := nil;
  end;
end;

end.
