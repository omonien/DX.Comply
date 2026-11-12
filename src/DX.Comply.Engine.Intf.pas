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
    /// <summary>
    /// Pascal source of a unit-evidence artefact, when the resolver found
    /// one. Component-manifest folder rules use this path. Empty when the
    /// unit is known only by name, or only as a DCU in an output folder.
    /// </summary>
    SourcePath: string;
    /// <summary>
    /// MAP or project unit name. Prefix and exact rules use this when it is
    /// set. Empty means the file name of RelativePath without its extension.
    /// </summary>
    UnitName: string;
    /// <summary>Relative path from the project root.</summary>
    RelativePath: string;
    /// <summary>File size in bytes.</summary>
    FileSize: Int64;
    /// <summary>SHA-256 hash as hexadecimal string.</summary>
    Hash: string;
    /// <summary>
    /// SHA-512 hash as a hexadecimal string. Empty when the file could not
    /// be opened. Written next to Hash when it is present.
    /// </summary>
    HashSha512: string;
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
    /// <summary>
    /// Unit names from the interface and implementation uses clauses.
    /// Empty when the source was not read, or when the clause is empty.
    /// </summary>
    UsedUnitNames: TArray<string>;
    /// <summary>
    /// True when UsedUnitNames was filled from a .pas, including an empty
    /// clause, or when the resolver decided there is no Pascal source.
    /// False means the writer may read a .pas once.
    /// </summary>
    UsesCached: Boolean;
    /// <summary>
    /// Component name written into the SBOM. Empty means the file name of
    /// RelativePath, which is what build mode writes.
    /// </summary>
    ComponentName: string;
    /// <summary>
    /// Component version written into the SBOM. Empty means the writers omit
    /// the version. Build mode fills it from the product version, the file's
    /// version resource, or the file modification time (VersionFromFileDate).
    /// </summary>
    Version: string;
    /// <summary>
    /// True when Version is the last modification time of the file in UTC
    /// (RFC 3339), because the file has no version of its own. BSI TR-03183-2
    /// section 5.2.2 prescribes this fallback. Writers emit
    /// net.developer-experts.dx-comply:versionSource=file-modification-time.
    /// </summary>
    VersionFromFileDate: Boolean;
    /// <summary>
    /// True for a file of a library source release (library mode). Writers
    /// omit the version when Version is empty, write no file: purl, and add
    /// the relative path as net.developer-experts.dx-comply:relativePath.
    /// </summary>
    LibrarySourceFile: Boolean;
    /// <summary>
    /// Where a source-scanned DLL was found: explicit-path, output-directory,
    /// project-tree or system-directory. Empty when the file was not found
    /// or the artefact is not a DLL reference. Writers emit this as
    /// net.developer-experts.dx-comply:locationSource.
    /// </summary>
    LocationSource: string;
    /// <summary>
    /// Full path of a DLL that was found only in a Windows system
    /// directory. No hash is recorded for it, because the build machine's
    /// copy does not represent the target system. Writers emit this as
    /// net.developer-experts.dx-comply:location.
    /// </summary>
    Location: string;
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
  /// Kind of binary a Delphi project builds. The file name also depends on
  /// the target platform.
  /// </summary>
  TPrimaryOutputKind = (
    /// <summary>The scanner could not tell application, library, or package.</summary>
    pokUnknown,
    /// <summary>program or console application.</summary>
    pokApplication,
    /// <summary>library project.</summary>
    pokLibrary,
    /// <summary>package project.</summary>
    pokPackage
  );

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
    /// Full path of the binary the project builds for the active
    /// configuration and platform. Windows is .exe, .dll, or .bpl.
    /// Android is lib&lt;Project&gt;.so. Linux and macOS applications have
    /// no extension. DllSuffix is included for libraries and packages.
    /// Empty when that name cannot be resolved.
    /// </summary>
    OutputFilePath: string;
    /// <summary>
    /// Application, library, or package. Combined with Platform to build
    /// OutputFilePath. pokUnknown when the scanner could not tell.
    /// </summary>
    OutputKind: TPrimaryOutputKind;
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
    /// CompanyName from the project version info: VerInfo_Keys in a .dproj,
    /// or the legacy .dof / .cfg version info keys. The engine uses this as
    /// the SBOM supplier when the configuration does not set one.
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
    /// <summary>
    /// One progress line for an output directory whose path used
    /// $(ProductVersion) (or $(BDSVersion) / $(BDSVER)), or that still
    /// contained an unresolved $(...) token after expansion.
    /// Ordinary $(Platform) and $(Config) paths are not listed.
    /// The generator forwards each line as progress. The CLI prints
    /// progress lines only with --verbose.
    /// </summary>
    ProgressNotes: TList<string>;
    /// <summary>Initializes the record with a new TList instance.</summary>
    class function Create: TProjectInfo; static;
    /// <summary>Frees internal resources. Call this when done with the record.</summary>
    procedure Free;
    /// <summary>Returns True when the project is a package (.dpk), False for applications (.dpr).</summary>
    function IsPackage: Boolean;
    /// <summary>Returns the effective suffix for MAP file names (DllSuffix for packages, empty for applications).</summary>
    function EffectiveMapSuffix: string;
    /// <summary>
    /// True for Android, Android32, and Android64. Those targets emit
    /// a shared library named libProject.so.
    /// </summary>
    function IsAndroidPlatform: Boolean;
    /// <summary>
    /// MAP file name for this project. Desktop targets use ProjectName plus
    /// the package suffix and .map. Android targets use lib, that stem, and
    /// .so.map.
    /// </summary>
    function ExpectedMapFileName: string;
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
    /// <summary>
    /// Optional URL for the supplier. Written on metadata.component when set.
    /// </summary>
    SupplierUrl: string;
    /// <summary>
    /// Distribution licence of the primary component. An SPDX identifier,
    /// an SPDX expression, or a plain name. Empty means the writers omit it.
    /// </summary>
    Licence: string;
    /// <summary>
    /// Raw components.json text. Empty when no component manifest is in use.
    /// Writers read this to group matched units under library components.
    /// </summary>
    ComponentManifestJson: string;
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
    /// <summary>
    /// SBOM creator contact copied from the configuration. An email address
    /// or an http(s) URL. Empty means the writers omit the contact.
    /// </summary>
    SbomCreator: string;
    /// <summary>
    /// CycloneDX type of the root component. Empty means application, which
    /// is what build mode writes. Library mode sets library.
    /// </summary>
    ComponentType: string;
    /// <summary>
    /// Package URL of the root component. Empty means the writers omit it.
    /// </summary>
    Purl: string;
    /// <summary>
    /// When True, compositions describe the library source set instead of
    /// the uses graph.
    /// </summary>
    LibraryCompositions: Boolean;
    /// <summary>
    /// True when every scanned library file has a SHA-256 and a SHA-512.
    /// </summary>
    LibraryFilesComplete: Boolean;
    /// <summary>
    /// True when the requires names were read from a .dpk requires clause.
    /// </summary>
    LibraryRequiresDeclared: Boolean;
  end;

  /// <summary>
  /// Supported SBOM output formats.
  /// </summary>
  TSbomFormat = (
    /// <summary>CycloneDX JSON format.</summary>
    sfCycloneDxJson,
    /// <summary>CycloneDX XML format.</summary>
    sfCycloneDxXml,
    /// <summary>SPDX 2.3 JSON format.</summary>
    sfSpdxJson,
    /// <summary>SPDX 3.0.1 JSON-LD format (issue #108).</summary>
    sfSpdx3Json
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
    /// Optional BDS version, for example 23.0 or 23. It selects the Delphi
    /// install whose $(ProductVersion), library paths, and IDE environment
    /// variable overrides are used. Empty uses the BDS environment variable,
    /// then the newest installed Delphi.
    /// </summary>
    procedure SetBdsVersion(const AVersion: string);
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
    /// file exists. AKnownProjectOutput accepts a platform binary whose
    /// extension is not .exe, .dll, .bpl, or .dcp, such as libProject.so or
    /// an extensionless Linux executable, when no include patterns are set.
    /// Exclude patterns and an explicit include list still apply.
    /// </summary>
    function CollectFile(const AFilePath, ARelativePath: string;
      const AIncludePatterns, AExcludePatterns: TArray<string>;
      out AArtefact: TArtefactInfo; AKnownProjectOutput: Boolean = False): Boolean;
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
/// Index of the built program inside AArtefacts, or -1 when the list has
/// none. An exe is preferred over a dll or bpl. A file whose name is
/// AProjectName is preferred, including a lib or bpl prefix and a numeric
/// package suffix. AOutputFilePath wins when that file is in the list.
/// A binary is still a candidate when its artefact type is not application,
/// package, or library, so the project's own executable is not left as an
/// unlicensed component (issue #155). Runtime packages and unit evidence
/// are not deliverables. Pass an empty output path when it is unknown.
/// </summary>
function FindDeliverableTargetIndex(const AArtefacts: TArtefactList;
  const AProjectName: string; const AOutputFilePath: string = ''): Integer;

/// <summary>
/// True when AIndex is ADeliverableIndex, or when both artefacts share
/// that file name. A second copy of the project binary then carries the
/// same licence. The dependency root stays the single best index.
/// </summary>
function IsSameDeliverableFile(const AArtefacts: TArtefactList;
  AIndex, ADeliverableIndex: Integer): Boolean;

/// <summary>
/// Grouping order for a dependency edge: 0 runtime package, 1 external
/// DLL reference, 2 linked unit, 3 any other artefact.
/// </summary>
function ArtefactDependencyGroup(const AArtefact: TArtefactInfo): Integer;

/// <summary>
/// True when AValue is a single email address: one @, no whitespace, and a
/// dot in the domain. A URL is not an email.
/// </summary>
function IsBsiEmailAddress(const AValue: string): Boolean;

/// <summary>
/// True when AValue starts with http:// or https:// and has a remainder.
/// </summary>
function IsBsiHttpUrl(const AValue: string): Boolean;

/// <summary>
/// Returns email, url, or an empty string when AValue is neither.
/// </summary>
function BsiCreatorKind(const AValue: string): string;

/// <summary>
/// Parses YYYY-MM-DDThh:mm:ss with optional fractional seconds and an
/// optional Z or +hh:mm, +hhmm or +hh offset. A value without a zone is
/// read as UTC. AUtc is the UTC time. False when the text does not match.
/// </summary>
function TryParseUtcTimestamp(const ATimestamp: string; out AUtc: TDateTime): Boolean;

/// <summary>
/// ATimestamp converted to UTC as YYYY-MM-DDThh:mm:ssZ. An empty or
/// unreadable value gives the current UTC time. Used for CycloneDX
/// metadata.timestamp, SPDX creationInfo.created and the reports.
/// </summary>
function FormatUtcTimestamp(const ATimestamp: string): string;

const
  /// <summary>Property name that marks how a component version was found.</summary>
  cVersionSourceProperty = 'net.developer-experts.dx-comply:versionSource';
  /// <summary>Value of cVersionSourceProperty for the file date fallback.</summary>
  cVersionSourceFileDate = 'file-modification-time';

/// <summary>
/// AUtc formatted per RFC 3339 as YYYY-MM-DDThh:mm:ssZ. AUtc must already
/// be UTC.
/// </summary>
function FormatRfc3339Utc(const AUtc: TDateTime): string;

/// <summary>
/// True when AValue is empty, or an email address, or an http(s) URL.
/// </summary>
function IsAcceptableBsiCreator(const AValue: string): Boolean;

/// <summary>
/// File name without a directory. Slashes and backslashes both count as
/// separators. Empty when ARelativePath has no name.
/// </summary>
function BsiComponentFileName(const ARelativePath: string): string;

/// <summary>
/// Name written on a component. ComponentName when it is set, otherwise
/// the file name of RelativePath.
/// </summary>
function ArtefactComponentName(const AArtefact: TArtefactInfo): string;

/// <summary>
/// CycloneDX type of the root component. Empty metadata means application.
/// </summary>
function SbomRootComponentType(const AMetadata: TSbomMetadata): string;

/// <summary>
/// True for archive names used by TR-03183-2 section 8.1.6 and for a short
/// list of package archives (.tgz, .rar, .jar, .nupkg, .iso, .cab).
/// </summary>
function IsBsiArchiveFileName(const AFileName: string): Boolean;

/// <summary>
/// True for an application, library, package, or runtime package, and for a
/// file whose name ends in .exe, .dll, .bpl, .so, or .dylib.
/// </summary>
function IsBsiExecutableArtefact(const AArtefact: TArtefactInfo): Boolean;

/// <summary>TR value executable or non-executable.</summary>
function BsiExecutableValue(const AArtefact: TArtefactInfo): string;

/// <summary>TR value archive or no archive.</summary>
function BsiArchiveValue(const AFileName: string): string;

/// <summary>TR value structured or unstructured.</summary>
function BsiStructuredValue(const AFileName: string): string;

/// <summary>
/// SPDX 2.3 package comment carrying the three TR properties. Empty when
/// the artefact has no file name.
/// </summary>
function BsiPropertyComment(const AArtefact: TArtefactInfo): string;

/// <summary>
/// File name Delphi writes for this platform and project kind.
/// Android applications, libraries, and packages are lib&lt;Name&gt;.so.
/// Linux and macOS applications have no extension. Linux libraries are
/// lib&lt;Name&gt;.so and Linux packages are bpl&lt;Name&gt;.so. macOS
/// libraries are lib&lt;Name&gt;.dylib and macOS packages are
/// bpl&lt;Name&gt;.dylib. iOS device libraries and packages are static
/// lib&lt;Name&gt;.a. Windows stays .exe, .dll, and .bpl.
/// ADllSuffix is applied to libraries and packages only.
/// </summary>
function PrimaryOutputFileName(const APlatform, AProjectName, ADllSuffix: string;
  AKind: TPrimaryOutputKind): string;

/// <summary>
/// Delphi output folder for APlatform, and the suffix of Base_ and Cfg_N_
/// property groups. The 32-bit Android target is the platform Android.
/// Android32, Android32Arm, and AndroidArm are accepted and map to that folder.
/// Android64, Android64Arm, and AndroidARM64 stay Android64. Every other
/// name is the folder Delphi already uses (Win32, Win64, Win64x, OSX32,
/// OSX64, OSXARM64, iOSSimulator, iOSDevice32, iOSDevice64, iOSSimARM64,
/// Linux64, LinuxARM64).
/// </summary>
function PlatformOutputDirectoryName(const APlatform: string): string;

/// <summary>
/// Artefact type of the binary this project builds: application, library,
/// or package.
/// </summary>
function PrimaryOutputArtefactType(AKind: TPrimaryOutputKind): string;

implementation

uses
  System.IOUtils,
  System.SysUtils,
  System.StrUtils,
  System.DateUtils;

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
  Result.ProgressNotes := TList<string>.Create;
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

  if Assigned(ProgressNotes) then
  begin
    ProgressNotes.Free;
    ProgressNotes := nil;
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

function TProjectInfo.IsAndroidPlatform: Boolean;
begin
  // Android, Android32, and Android64 all emit lib<Project>.so. A prefix
  // keeps a later Android target on the same MAP name. Win32, Win64, iOS,
  // macOS, and Linux do not match.
  Result := StartsText('Android', Trim(Platform));
end;

function TProjectInfo.ExpectedMapFileName: string;
var
  LStem: string;
begin
  // Same stem as the desktop MAP. Android only changes the lib prefix and
  // the .so.map ending, because the linker keeps the .so in the file name
  // (issue #89). TPath.ChangeExtension would turn libProject.so into
  // libProject.map, which is not the file on disk.
  LStem := ProjectName + EffectiveMapSuffix;
  if IsAndroidPlatform then
  begin
    Result := 'lib' + LStem + '.so.map';
  end
  else
  begin
    Result := LStem + '.map';
  end;
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

function ArtefactFileName(const AArtefact: TArtefactInfo): string;
begin
  // Same last-segment rule as the SBOM file name, so '/' and '\' both match.
  Result := BsiComponentFileName(AArtefact.RelativePath);
  if Result = '' then
    Result := BsiComponentFileName(AArtefact.FilePath);
end;

function ArtefactStem(const AFileName: string): string;
var
  LDot: Integer;
begin
  LDot := LastDelimiter('.', AFileName);
  if LDot <= 1 then
    Result := AFileName
  else
    Result := Copy(AFileName, 1, LDot - 1);
end;

function ArtefactExtension(const AFileName: string): string;
var
  LDot: Integer;
begin
  LDot := LastDelimiter('.', AFileName);
  if LDot <= 1 then
    Result := ''
  else
    Result := Copy(AFileName, LDot, MaxInt);
end;

function IsAllDigits(const AValue: string): Boolean;
var
  LChar: Char;
begin
  Result := AValue <> '';
  for LChar in AValue do
    if not CharInSet(LChar, ['0'..'9']) then
      Exit(False);
end;

function StemMatchesProject(const AStem, AProjectName: string): Boolean;
var
  LStem: string;
  LRest: string;
begin
  Result := False;
  if (AStem = '') or (AProjectName = '') then
    Exit;
  if SameText(AStem, AProjectName) then
    Exit(True);

  // Android output is lib<Project>.so. Linux packages are bpl<Project>.so.
  // Strip that prefix only when the project name does not already use it.
  LStem := AStem;
  if not StartsText('lib', AProjectName) and StartsText('lib', LStem) and
    (Length(LStem) > 3) then
    LStem := Copy(LStem, 4, MaxInt)
  else if not StartsText('bpl', AProjectName) and StartsText('bpl', LStem) and
    (Length(LStem) > 3) then
    LStem := Copy(LStem, 4, MaxInt);

  if SameText(LStem, AProjectName) then
    Exit(True);

  // DllSuffix appends digits, for example MyPkg290.bpl for project MyPkg.
  if StartsText(AProjectName, LStem) and (Length(LStem) > Length(AProjectName)) then
  begin
    LRest := Copy(LStem, Length(AProjectName) + 1, MaxInt);
    Result := IsAllDigits(LRest);
  end;
end;

function IsShippableBinaryExtension(const AExtension: string): Boolean;
begin
  // An empty extension is a Linux or macOS application.
  Result := SameText(AExtension, '.exe') or SameText(AExtension, '.dll') or
    SameText(AExtension, '.bpl') or SameText(AExtension, '.so') or
    SameText(AExtension, '.dylib') or SameText(AExtension, '.a') or
    (AExtension = '');
end;

function ExtensionKindScore(const AExtension: string): Integer;
begin
  if SameText(AExtension, '.exe') or (AExtension = '') then
    Result := 300
  else if SameText(AExtension, '.bpl') then
    Result := 200
  else if SameText(AExtension, '.dll') or SameText(AExtension, '.so') or
    SameText(AExtension, '.dylib') or SameText(AExtension, '.a') then
    Result := 100
  else
    Result := -1;
end;

function IsBlockedDeliverableType(const AArtefactType: string): Boolean;
begin
  // Units, runtime packages, and framework packages are not the product
  // binary, even when a stem happens to match the project name.
  Result := SameText(AArtefactType, 'unit-evidence') or
    SameText(AArtefactType, 'runtime-package') or
    SameText(AArtefactType, 'framework') or
    SameText(AArtefactType, 'required-package');
end;

function OutputPathMatchScore(const AArtefact: TArtefactInfo;
  const AOutputFilePath: string): Integer;
var
  LOutputName: string;
  LFileName: string;
begin
  Result := -1;
  if AOutputFilePath = '' then
    Exit;
  // The path from the project file is the dependency root. Another copy
  // of that file name is still the product, but it ranks just below.
  if SameText(AArtefact.FilePath, AOutputFilePath) or
    SameText(AArtefact.RelativePath, AOutputFilePath) then
    Exit(1000);
  LOutputName := BsiComponentFileName(AOutputFilePath);
  if LOutputName = '' then
    Exit;
  LFileName := ArtefactFileName(AArtefact);
  if (LFileName <> '') and SameText(LFileName, LOutputName) then
    Result := 900;
end;

function DeliverableScore(const AArtefact: TArtefactInfo;
  const AProjectName, AOutputFilePath: string): Integer;
var
  LFileName: string;
  LStem: string;
  LExt: string;
  LTypeScore: Integer;
  LPathScore: Integer;
begin
  Result := -1;
  if IsBlockedDeliverableType(AArtefact.ArtefactType) then
    Exit;

  LFileName := ArtefactFileName(AArtefact);
  LStem := ArtefactStem(LFileName);
  LExt := ArtefactExtension(LFileName);

  LPathScore := OutputPathMatchScore(AArtefact, AOutputFilePath);
  if LPathScore >= 0 then
    Exit(LPathScore);

  LTypeScore := TargetKindScore(AArtefact.ArtefactType);
  if LTypeScore >= 0 then
    Result := LTypeScore
  else if StemMatchesProject(LStem, AProjectName) and
    IsShippableBinaryExtension(LExt) then
    Result := ExtensionKindScore(LExt)
  else
    Exit;

  if StemMatchesProject(LStem, AProjectName) then
    Inc(Result, 10);
end;

function FindDeliverableTargetIndex(const AArtefacts: TArtefactList;
  const AProjectName: string; const AOutputFilePath: string): Integer;
var
  I: Integer;
  LScore: Integer;
  LBest: Integer;
begin
  Result := -1;
  LBest := -1;
  if not Assigned(AArtefacts) then
    Exit;

  for I := 0 to AArtefacts.Count - 1 do
  begin
    LScore := DeliverableScore(AArtefacts[I], AProjectName, AOutputFilePath);
    if LScore > LBest then
    begin
      LBest := LScore;
      Result := I;
    end;
  end;
end;

function IsSameDeliverableFile(const AArtefacts: TArtefactList;
  AIndex, ADeliverableIndex: Integer): Boolean;
var
  LWinner: string;
  LName: string;
begin
  Result := False;
  if not Assigned(AArtefacts) or (ADeliverableIndex < 0) or
    (ADeliverableIndex >= AArtefacts.Count) or (AIndex < 0) or
    (AIndex >= AArtefacts.Count) then
    Exit;
  if AIndex = ADeliverableIndex then
    Exit(True);
  LWinner := ArtefactFileName(AArtefacts[ADeliverableIndex]);
  if LWinner = '' then
    Exit;
  LName := ArtefactFileName(AArtefacts[AIndex]);
  Result := (LName <> '') and SameText(LName, LWinner);
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

function HasWhitespace(const AValue: string): Boolean;
var
  LChar: Char;
begin
  Result := False;
  for LChar in AValue do
    if LChar <= ' ' then
      Exit(True);
end;

function IsBsiEmailAddress(const AValue: string): Boolean;
var
  LAt: Integer;
  LDomain: string;
begin
  Result := False;
  if (AValue = '') or HasWhitespace(AValue) or (Pos('://', AValue) > 0) then
    Exit;
  LAt := Pos('@', AValue);
  if (LAt <= 1) or (LAt <> LastDelimiter('@', AValue)) then
    Exit;
  LDomain := Copy(AValue, LAt + 1, MaxInt);
  if (LDomain = '') or (Pos('.', LDomain) = 0) then
    Exit;
  if LDomain.StartsWith('.') or LDomain.EndsWith('.') then
    Exit;
  Result := True;
end;

function IsBsiHttpUrl(const AValue: string): Boolean;
begin
  if AValue.StartsWith('https://', True) then
    Result := Length(AValue) > Length('https://')
  else if AValue.StartsWith('http://', True) then
    Result := Length(AValue) > Length('http://')
  else
    Result := False;
end;

function BsiCreatorKind(const AValue: string): string;
var
  LValue: string;
begin
  LValue := Trim(AValue);
  if IsBsiEmailAddress(LValue) then
    Result := 'email'
  else if IsBsiHttpUrl(LValue) then
    Result := 'url'
  else
    Result := '';
end;

function IsAcceptableBsiCreator(const AValue: string): Boolean;
begin
  Result := BsiCreatorKind(AValue) <> '';
  if not Result then
    Result := Trim(AValue) = '';
end;

function BsiComponentFileName(const ARelativePath: string): string;
var
  I: Integer;
  LPos: Integer;
begin
  // TPath.GetFileName follows the platform separator. Library paths use
  // '/', and a build path uses '\'. Take the last segment of either.
  LPos := 0;
  for I := 1 to Length(ARelativePath) do
    if (ARelativePath[I] = '\') or (ARelativePath[I] = '/') then
      LPos := I;
  if LPos = 0 then
    Result := ARelativePath
  else
    Result := Copy(ARelativePath, LPos + 1, MaxInt);
end;

function ArtefactComponentName(const AArtefact: TArtefactInfo): string;
begin
  Result := Trim(AArtefact.ComponentName);
  if Result = '' then
    Result := TPath.GetFileName(AArtefact.RelativePath);
end;

function SbomRootComponentType(const AMetadata: TSbomMetadata): string;
begin
  Result := Trim(AMetadata.ComponentType);
  if Result = '' then
    Result := 'application';
end;

function IsBsiArchiveFileName(const AFileName: string): Boolean;
var
  LName, LExt: string;
begin
  LName := LowerCase(AFileName);
  LExt := LowerCase(TPath.GetExtension(LName));
  Result := (LExt = '.zip') or (LExt = '.7z') or (LExt = '.tar') or
    (LExt = '.tgz') or (LExt = '.rar') or (LExt = '.jar') or
    (LExt = '.nupkg') or (LExt = '.iso') or (LExt = '.cab') or
    LName.EndsWith('.tar.gz') or LName.EndsWith('.tar.bz2');
end;

function PlatformOutputDirectoryName(const APlatform: string): string;
var
  LPlatform: string;
begin
  // $(Platform) in a .dproj is this folder. The TargetedPlatforms bit for
  // 32-bit Android is often called Android32, and that name is not a
  // directory. Android 64-bit already matches its folder.
  LPlatform := Trim(APlatform);
  if SameText(LPlatform, 'Android32') or SameText(LPlatform, 'Android32Arm') or
     SameText(LPlatform, 'AndroidArm') then
    Exit('Android');
  if SameText(LPlatform, 'Android64Arm') or SameText(LPlatform, 'AndroidARM64') then
    Exit('Android64');
  Result := LPlatform;
end;

function PlatformOutputFamily(const APlatform: string): string;
begin
  // Families follow the file names in RAD Studio's output tables:
  // Android lib*.so, Linux ELF / lib*.so / bpl*.so, macOS Mach-O /
  // lib*.dylib / bpl*.dylib, iOS device static lib*.a. Anything else,
  // including Win32, Win64, and Win64x, keeps the Windows names.
  var LPlatform := Trim(APlatform);
  if StartsText('Android', LPlatform) then
    Exit('Android');
  if StartsText('Linux', LPlatform) then
    Exit('Linux');
  if StartsText('OSX', LPlatform) or StartsText('macOS', LPlatform) then
    Exit('macOS');
  // iOSSimARM64 links like the device. The old iOSSimulator target follows
  // the macOS dynamic-library names.
  if StartsText('iOSDevice', LPlatform) or SameText(LPlatform, 'iOSSimARM64') then
    Exit('iOSDevice');
  if StartsText('iOS', LPlatform) then
    Exit('iOSSimulator');
  Result := 'Windows';
end;

function PrimaryOutputFileName(const APlatform, AProjectName, ADllSuffix: string;
  AKind: TPrimaryOutputKind): string;
begin
  Result := '';
  var LName := Trim(AProjectName);
  if LName = '' then
    Exit;

  var LKind := AKind;
  if LKind = pokUnknown then
    LKind := pokApplication;

  // Applications do not take DllSuffix. A library or package does.
  var LSuffix := '';
  if LKind <> pokApplication then
    LSuffix := ADllSuffix;

  var LFamily := PlatformOutputFamily(APlatform);
  if LFamily = 'Android' then
  begin
    // Applications are shared libraries too. Packages are named the same
    // way as the Android map stem lib<Name>.so (issue #89).
    Result := 'lib' + LName + LSuffix + '.so';
  end
  else if LFamily = 'Linux' then
  begin
    if LKind = pokPackage then
      Result := 'bpl' + LName + LSuffix + '.so'
    else if LKind = pokLibrary then
      Result := 'lib' + LName + LSuffix + '.so'
    else
      Result := LName;
  end
  else if LFamily = 'macOS' then
  begin
    if LKind = pokPackage then
      Result := 'bpl' + LName + LSuffix + '.dylib'
    else if LKind = pokLibrary then
      Result := 'lib' + LName + LSuffix + '.dylib'
    else
      Result := LName;
  end
  else if LFamily = 'iOSSimulator' then
  begin
    // The 32-bit simulator used the macOS dynamic-library layout.
    if LKind = pokPackage then
      Result := 'bpl' + LName + LSuffix + '.dylib'
    else if LKind = pokLibrary then
      Result := 'lib' + LName + LSuffix + '.dylib'
    else
      Result := LName;
  end
  else if LFamily = 'iOSDevice' then
  begin
    // Device targets have no shared libraries. The executable is a Mach-O
    // file with no extension. Libraries and packages are static archives.
    if LKind = pokApplication then
      Result := LName
    else
      Result := 'lib' + LName + LSuffix + '.a';
  end
  else if LKind = pokPackage then
    Result := LName + LSuffix + '.bpl'
  else if LKind = pokLibrary then
    Result := LName + LSuffix + '.dll'
  else
    Result := LName + '.exe';
end;

function PrimaryOutputArtefactType(AKind: TPrimaryOutputKind): string;
begin
  case AKind of
    pokLibrary:
      Result := 'library';
    pokPackage:
      Result := 'package';
  else
    Result := 'application';
  end;
end;

function IsBsiExecutableArtefact(const AArtefact: TArtefactInfo): Boolean;
var
  LExt: string;
begin
  if SameText(AArtefact.ArtefactType, 'application') or
     SameText(AArtefact.ArtefactType, 'library') or
     SameText(AArtefact.ArtefactType, 'package') or
     SameText(AArtefact.ArtefactType, 'runtime-package') then
    Exit(True);
  LExt := LowerCase(TPath.GetExtension(BsiComponentFileName(AArtefact.RelativePath)));
  // .so and .dylib are the non-Windows shared libraries. An extensionless
  // ELF or Mach-O executable is recognised by its artefact type above.
  Result := (LExt = '.exe') or (LExt = '.dll') or (LExt = '.bpl') or
    (LExt = '.so') or (LExt = '.dylib');
end;

function BsiExecutableValue(const AArtefact: TArtefactInfo): string;
begin
  if IsBsiExecutableArtefact(AArtefact) then
    Result := 'executable'
  else
    Result := 'non-executable';
end;

function BsiArchiveValue(const AFileName: string): string;
begin
  if IsBsiArchiveFileName(AFileName) then
    Result := 'archive'
  else
    Result := 'no archive';
end;

function BsiStructuredValue(const AFileName: string): string;
begin
  if IsBsiArchiveFileName(AFileName) then
    Result := 'structured'
  else
    Result := 'unstructured';
end;

function BsiPropertyComment(const AArtefact: TArtefactInfo): string;
var
  LFileName: string;
begin
  LFileName := BsiComponentFileName(AArtefact.RelativePath);
  if LFileName = '' then
    Exit('');
  Result := 'bsi:component:executable=' + BsiExecutableValue(AArtefact) + '; ' +
    'bsi:component:archive=' + BsiArchiveValue(LFileName) + '; ' +
    'bsi:component:structured=' + BsiStructuredValue(LFileName);
  if AArtefact.VersionFromFileDate then
  begin
    Result := Result + '; ' + cVersionSourceProperty + '=' + cVersionSourceFileDate;
  end;
end;

function TryParseUtcTimestamp(const ATimestamp: string;
  out AUtc: TDateTime): Boolean;
var
  LText: string;
  LYear, LMonth, LDay, LHour, LMinute, LSecond: Integer;
  LPos: Integer;
  LOffsetMinutes: Integer;
  LSign: Integer;
  LRemain: Integer;
  LOffHour: Integer;
  LOffMinute: Integer;
begin
  Result := False;
  AUtc := 0;
  LText := Trim(ATimestamp);
  // YYYY-MM-DDThh:mm:ss
  if Length(LText) < 19 then
    Exit;
  if (LText[5] <> '-') or (LText[8] <> '-') then
    Exit;
  if (LText[11] <> 'T') and (LText[11] <> 't') then
    Exit;
  if (LText[14] <> ':') or (LText[17] <> ':') then
    Exit;
  if not TryStrToInt(Copy(LText, 1, 4), LYear) then
    Exit;
  if not TryStrToInt(Copy(LText, 6, 2), LMonth) then
    Exit;
  if not TryStrToInt(Copy(LText, 9, 2), LDay) then
    Exit;
  if not TryStrToInt(Copy(LText, 12, 2), LHour) then
    Exit;
  if not TryStrToInt(Copy(LText, 15, 2), LMinute) then
    Exit;
  if not TryStrToInt(Copy(LText, 18, 2), LSecond) then
    Exit;
  if (LMonth < 1) or (LMonth > 12) or (LDay < 1) or (LDay > 31) or
     (LHour < 0) or (LHour > 23) or (LMinute < 0) or (LMinute > 59) or
     (LSecond < 0) or (LSecond > 59) then
    Exit;

  // Fractional seconds are dropped. The output has whole seconds.
  LPos := 20;
  if (LPos <= Length(LText)) and (LText[LPos] = '.') then
  begin
    Inc(LPos);
    while (LPos <= Length(LText)) and CharInSet(LText[LPos], ['0'..'9']) do
      Inc(LPos);
  end;

  LOffsetMinutes := 0;
  if LPos <= Length(LText) then
  begin
    if (LText[LPos] = 'Z') or (LText[LPos] = 'z') then
    begin
      if LPos <> Length(LText) then
        Exit;
    end
    else if (LText[LPos] = '+') or (LText[LPos] = '-') then
    begin
      if LText[LPos] = '+' then
        LSign := 1
      else
        LSign := -1;
      LRemain := Length(LText) - LPos;
      LOffHour := 0;
      LOffMinute := 0;
      if LRemain = 5 then
      begin
        // ±HH:MM
        if LText[LPos + 3] <> ':' then
          Exit;
        if not TryStrToInt(Copy(LText, LPos + 1, 2), LOffHour) then
          Exit;
        if not TryStrToInt(Copy(LText, LPos + 4, 2), LOffMinute) then
          Exit;
      end
      else if LRemain = 4 then
      begin
        // ±HHMM
        if not TryStrToInt(Copy(LText, LPos + 1, 2), LOffHour) then
          Exit;
        if not TryStrToInt(Copy(LText, LPos + 3, 2), LOffMinute) then
          Exit;
      end
      else if LRemain = 2 then
      begin
        // ±HH
        if not TryStrToInt(Copy(LText, LPos + 1, 2), LOffHour) then
          Exit;
      end
      else
        Exit;
      if (LOffHour < 0) or (LOffHour > 14) or (LOffMinute < 0) or (LOffMinute > 59) then
        Exit;
      LOffsetMinutes := LSign * ((LOffHour * 60) + LOffMinute);
    end
    else
      Exit;
  end;

  try
    // Offset is minutes east of UTC. UTC clock = local clock - offset.
    AUtc := IncMinute(EncodeDateTime(Word(LYear), Word(LMonth), Word(LDay),
      Word(LHour), Word(LMinute), Word(LSecond), 0), -LOffsetMinutes);
    Result := True;
  except
    Result := False;
  end;
end;

function FormatRfc3339Utc(const AUtc: TDateTime): string;
begin
  Result := FormatDateTime('yyyy-mm-dd''T''hh:nn:ss''Z''', AUtc, TFormatSettings.Invariant);
end;

function FormatUtcTimestamp(const ATimestamp: string): string;
var
  LUtc: TDateTime;
begin
  // SPDX 2.3 requires YYYY-MM-DDThh:mm:ssZ, and BSI TR-03183-2 recommends
  // UTC for every SBOM timestamp. DateToISO8601(..., False) emits a local
  // offset and fractional seconds. The invariant format settings keep the
  // colons when the user locale has another time separator.
  if not TryParseUtcTimestamp(ATimestamp, LUtc) then
    LUtc := TTimeZone.Local.ToUniversalTime(Now);
  Result := FormatDateTime('yyyy-mm-dd''T''hh:nn:ss''Z''', LUtc,
    TFormatSettings.Invariant);
end;

end.
