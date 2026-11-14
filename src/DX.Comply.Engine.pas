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
  DX.Comply.Spdx3.Writer,
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
    scoScanTree,
    scoSbomCreator,
    scoSupplierUrl,
    scoLicence,
    scoLibraryMode,
    scoSourceDirs,
    scoPurl,
    scoRepoUrl,
    scoStrictMode,
    scoSpdxVersion,
    scoReportContent,
    scoReportGroupByFolder,
    scoPrefixMatch
  );
  /// <summary>Set of TSbomConfig fields that were set explicitly.</summary>
  TSbomConfigOverrides = set of TSbomConfigOverride;

  /// <summary>
  /// Who runs the generator. Warnings that ask for missing data name the
  /// way to supply it in that context: command line flags and
  /// .dxcomply.json keys for the CLI, the SBOM header dialog for the IDE.
  /// </summary>
  TSbomWarningContext = (
    swcCli,
    swcIde
  );

  /// <summary>
  /// Configuration for SBOM generation.
  /// </summary>
  TSbomConfig = record
    /// <summary>Output file path.</summary>
    OutputPath: string;
    /// <summary>
    /// Optional directory for the SBOM and the reports that follow it
    /// (issue #146). Empty leaves OutputPath as the file path. A relative
    /// directory is resolved from the project directory. The CLI --output
    /// flag is a file path and is not placed in this directory.
    /// </summary>
    OutputDir: string;
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
    /// Optional supplier contact URL from --supplier-url or product.supplierUrl.
    /// Written as supplier.url. Empty means the writers omit the URL.
    /// An explicit value is not replaced by the component manifest.
    /// </summary>
    SupplierUrl: string;
    /// <summary>
    /// Distribution licence of the primary component, from --licence or
    /// product.licence. An SPDX identifier, an SPDX expression, or a plain
    /// name. Empty means the writers omit it.
    /// </summary>
    Licence: string;
    /// <summary>
    /// Optional SBOM creator contact from --sbom-creator or sbomCreator.
    /// An email address or an http(s) URL. Empty means the field is omitted.
    /// A company name is not accepted.
    /// </summary>
    SbomCreator: string;
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
    /// versions did. Deprecated. Will be removed in the next release.
    /// Default is False.
    /// </summary>
    ScanTree: Boolean;
    /// <summary>
    /// Optional Delphi 7 installation directory for legacy .dpr/.dpk/.bdsproj
    /// scans. Empty uses the Borland registry key and the DELPHI variable.
    /// </summary>
    Delphi7Root: string;
    /// <summary>
    /// Optional BDS version (for example 23.0) from --bds-version or
    /// bdsVersion. Empty uses BDS, then the newest installed Delphi.
    /// </summary>
    BdsVersion: string;
    /// <summary>
    /// When True, write an SBOM for a source release. There is no build,
    /// no MAP file, and no binary scan. Default is False (build mode).
    /// </summary>
    LibraryMode: Boolean;
    /// <summary>
    /// Directories walked for library source files. Relative paths are
    /// resolved from the project directory, or from the current directory
    /// when there is no project.
    /// </summary>
    SourceDirs: TArray<string>;
    /// <summary>
    /// Package URL of the root component. Empty means derive one from
    /// RepoUrl when that URL is a GitHub repository and a version is known.
    /// </summary>
    Purl: string;
    /// <summary>
    /// Repository URL. A https://github.com/owner/repo URL, with an optional
    /// trailing .git or slash, can supply the root purl.
    /// </summary>
    RepoUrl: string;
    /// <summary>
    /// Context the warning texts are written for. Default swcCli.
    /// </summary>
    WarningContext: TSbomWarningContext;
    /// <summary>
    /// --strict or the strict key: the CLI still writes the SBOM and report,
    /// then exits with code 3 when a CRA/BSI warning was raised (issue #111).
    /// </summary>
    StrictMode: Boolean;
    /// <summary>
    /// --spdx-version or the spdxVersion key: 3.0.1 selects the SPDX 3.0.1
    /// writer for --format=spdx-json. Empty or 2.3 keeps SPDX 2.3 (issue #108).
    /// </summary>
    SpdxVersion: string;
    /// <summary>
    /// --match-prefixes or the matchPrefixes key. corroborated or legacy.
    /// Empty means the components file decides. A missing match.prefixes
    /// in that file is corroborated.
    /// </summary>
    PrefixMatch: string;
    /// <summary>Creates a new TSbomConfig with default values.</summary>
    class function Default: TSbomConfig; static;
    /// <summary>
    /// Appends the platform and configuration to a filename.
    /// Both values are reduced to letters, digits, hyphen and underscore
    /// before they are interpolated.
    /// </summary>
    class function DecorateOutputFileName(const AOutputPath, APlatform,
      AConfiguration: string): string; static;
    /// <summary>
    /// Places a bare SBOM file name in AOutputDir when that directory is set
    /// and the file path was not passed explicitly (issue #146).
    /// </summary>
    /// <remarks>
    /// An explicit file path (CLI --output) is returned unchanged.
    /// An empty directory returns AOutputFile unchanged, so an existing
    /// "output": "bom.json" stays that file.
    /// A bare file name is combined with the directory. A file path that
    /// already contains a directory is left as it is.
    /// The result may still be relative.
    /// </remarks>
    class function ApplyOutputDirectory(const AOutputFile, AOutputDir: string;
      AOutputFileExplicit: Boolean): string; static;
    /// <summary>
    /// Directory used for the SBOM. A non-empty project-file value wins.
    /// Otherwise the IDE options value is used. Both empty means the
    /// caller keeps the project folder.
    /// </summary>
    class function ChooseOutputDirectory(const ASettingsDir,
      AFileDir: string): string; static;
    /// <summary>
    /// Resolves the SBOM file path: directory, explicit file, platform
    /// decoration, then the project directory for a relative result.
    /// </summary>
    class function ResolveSbomOutputPath(const AOutputFile, AOutputDir,
      AProjectDir, APlatform, AConfiguration: string;
      AOutputFileExplicit, AIncludePlatformInOutput: Boolean): string; static;
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
  /// <summary>
  /// Where ResolveExternalDllFile found a DLL named in source code.
  /// </summary>
  TDllLocationSource = (dlsNotFound, dlsExplicitPath, dlsOutputDirectory,
    dlsProjectTree, dlsSystemDirectory);

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
    /// <summary>
    /// Lower-case file name to full path for .dll and .bpl files under the
    /// project directory. Built once per project and output directory.
    /// </summary>
    FProjectBinaryIndex: TDictionary<string, string>;
    FProjectBinaryIndexKey: string;
    FCraWarnings: TArray<string>;
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
    function ResolveConfiguredOutputPath(const AOutputPath: string): string;
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
    /// Adds a DLL or BPL named in the output binary's import table when that
    /// file sits under the project tree and is not already listed. System
    /// directories are not used. The output directory scan already lists
    /// binaries that sit next to the program.
    /// </summary>
    procedure AddImportedBinariesToArtefacts(const AProjectInfo: TProjectInfo;
      const AArtefacts: TArtefactList);
    /// <summary>
    /// Fills size and hashes from APath. Reuses a hash already stored for
    /// the same path.
    /// </summary>
    procedure CaptureBinaryFile(var AArtefact: TArtefactInfo; const APath: string;
      const AArtefacts: TArtefactList);
    procedure ClearProjectBinaryIndex;
    /// <summary>
    /// ResolveExternalDllFile with the project-tree index cached for this
    /// generator, so one SBOM does not walk the project once per DLL.
    /// </summary>
    function ResolveKnownBinary(const ADllName, AOutputDir, AProjectDir,
      APlatform: string; const ASystemDirs: TArray<string>;
      out ASource: TDllLocationSource): string;
    /// <summary>
    /// Maps each .dll and .bpl file name under AProjectDir to the preferred
    /// full path. For a Windows APlatform a copy built for that platform
    /// wins over a copy built for another one, so lib\Win64\x.dll is taken
    /// for Win64 and lib\Win32\x.dll for Win32. Then Installer wins. The
    /// output directory and Windows system directories are omitted. The
    /// caller frees the dictionary.
    /// </summary>
    class function BuildProjectBinaryIndex(const AProjectDir,
      AOutputDir: string; const APlatform: string = ''): TDictionary<string, string>; static;
    class function ResolveExternalDllWithIndex(const ADllName, AOutputDir,
      AProjectDir: string; const ASystemDirs: TArray<string>;
      const AProjectBinaries: TDictionary<string, string>;
      out ASource: TDllLocationSource): string; static;
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
    /// <summary>
    /// Writes an SBOM for a library source release. Build mode is not used.
    /// </summary>
    function GenerateLibrary(const AProjectPath, AOutputPath: string;
      AFormat: TSbomFormat): Boolean;
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
    /// Finds the file of a DLL named in source code. The order is: the full
    /// path given in code, the application output directory, then the
    /// system directories in ASystemDirs. A name without an extension is
    /// also tried with .dll, the same as LoadLibrary does. Returns the full
    /// path, or an empty string with dlsNotFound. Does not search the
    /// project tree. Public for testability.
    /// </summary>
    class function ResolveExternalDllFile(const ADllName, AOutputDir: string;
      const ASystemDirs: TArray<string>;
      out ASource: TDllLocationSource): string; overload; static;
    /// <summary>
    /// Same search, plus a bounded walk under AProjectDir for a DLL or BPL
    /// that ships with the program but is not in the output directory. An
    /// Installer folder is preferred over another copy in the project.
    /// System32 and SysWOW64 are not walked. A hit there stays
    /// dlsSystemDirectory, with no hash. Public for testability.
    /// </summary>
    class function ResolveExternalDllFile(const ADllName, AOutputDir,
      AProjectDir: string; const ASystemDirs: TArray<string>;
      out ASource: TDllLocationSource): string; overload; static;
    /// <summary>
    /// Same search for a target platform. When the project tree holds one
    /// copy of the file per platform, the copy whose PE header names
    /// APlatform (Win32, Win64, Win64x, WinARM64EC) is returned. Public for
    /// testability.
    /// </summary>
    class function ResolveExternalDllFile(const ADllName, AOutputDir,
      AProjectDir, APlatform: string; const ASystemDirs: TArray<string>;
      out ASource: TDllLocationSource): string; overload; static;
    /// <summary>
    /// Windows system directory that holds DLLs for the target platform:
    /// SysWOW64 for Win32 on 64-bit Windows, System32 for Win64 (Sysnative
    /// when this process is 32-bit, so file system redirection does not
    /// apply). Empty for non-Windows targets.
    /// </summary>
    class function SystemDirectoriesForPlatform(
      const APlatform: string): TArray<string>; static;
    /// <summary>
    /// Text for the locationSource property, e.g. output-directory.
    /// </summary>
    class function DllLocationSourceText(
      ASource: TDllLocationSource): string; static;
    /// <summary>
    /// Creates a new TDxComplyGenerator instance.
    /// </summary>
    constructor Create; overload;
    /// <summary>
    /// Creates a new TDxComplyGenerator with custom configuration.
    /// </summary>
    constructor Create(const AConfig: TSbomConfig); overload;
    /// <summary>
    /// The artefacts the third-party supplier and licence check runs on.
    /// With composition evidence switched off the units are not in
    /// AArtefacts, so the resolved units are added here. That way --strict
    /// still fails on third-party units without a manifest row. The caller
    /// frees the list. Public for testability.
    /// </summary>
    function ThirdPartyCheckArtefacts(const ACompositionEvidence: TCompositionEvidence;
      const AArtefacts: TArtefactList): TArtefactList;
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
    /// Project file a build mode run uses. A .dpr with a .dproj of the same
    /// name in the same folder resolves to that .dproj and reports an
    /// "Info: " progress message. Any other path is returned unchanged.
    /// </summary>
    function ResolveProjectPath(const AProjectPath: string): string;
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
    /// <summary>
    /// CRA/BSI warnings of the last Generate or GenerateLibrary call: header
    /// gaps, a missing deployable, and third-party components without
    /// supplier or licence. --strict fails the CLI when this is not empty.
    /// </summary>
    property CraWarnings: TArray<string> read FCraWarnings;
  end;

/// <summary>
/// Build mode versions for files that have no version yet.
/// The file at AOwnOutputPath (the executable, DLL, or package the project
/// builds) and a .dcp get AVersion, the product version. When AVersion is
/// empty, that .exe, .dll, or .bpl still on disk gets its PE FileVersion
/// (or ProductVersion) so the report and CycloneDX stay aligned (issue #90).
/// Any other .exe, .dll, or .bpl found on disk gets the version from its own
/// version resource (issue #96). A .dcp is the project's own only when
/// AOwnOutputPath is a package whose name starts with the .dcp name; any
/// other .dcp is treated like a third-party file. A file that still has no
/// version and exists on disk gets its last modification time in UTC as an
/// RFC 3339 timestamp, with VersionFromFileDate set (BSI TR-03183-2 section
/// 5.2.2, issue #109). Unit evidence, requires packages and
/// library source files are left unchanged. A runtime package with no file is
/// left unchanged. A runtime package whose BPL was found is versioned from
/// that file.
/// </summary>
procedure ApplyProductVersionToBuildFiles(const AArtefacts: TArtefactList;
  const AVersion: string; const AOwnOutputPath: string = '');

implementation

uses
  System.Types,
  Winapi.Windows,
  DX.Comply.ComponentManifest,
  DX.Comply.CraChecks,
  DX.Comply.LegacyProject,
  DX.Comply.LibrarySource,
  DX.Comply.Report.Overview,
  DX.Comply.Report.Support,
  DX.Comply.VersionInfo;

{ TSbomConfig }

class function TSbomConfig.Default: TSbomConfig;
begin
  Result.OutputPath := 'bom.json';
  Result.OutputDir := '';
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
  Result.SupplierUrl := '';
  Result.Licence := '';
  Result.SbomCreator := '';
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
  Result.BdsVersion := '';
  Result.LibraryMode := False;
  SetLength(Result.SourceDirs, 0);
  Result.Purl := '';
  Result.RepoUrl := '';
  Result.WarningContext := swcCli;
  Result.StrictMode := False;
  Result.SpdxVersion := '';
  Result.PrefixMatch := '';
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

class function TSbomConfig.ApplyOutputDirectory(const AOutputFile,
  AOutputDir: string; AOutputFileExplicit: Boolean): string;
var
  LDir, LFile, LName: string;
begin
  // --output is a file path. The directory setting does not move it.
  if AOutputFileExplicit then
    Exit(AOutputFile);

  LDir := Trim(AOutputDir);
  if LDir = '' then
    Exit(AOutputFile);

  LFile := Trim(AOutputFile);
  // A path that already names a directory stays a file path. ExtractFilePath
  // only sees '\', so a forward slash such as "build/custom.json" has to be
  // checked as well. An absolute path stays as it is.
  if (LFile <> '') and
     ((not TPath.IsRelativePath(LFile)) or (Pos('/', LFile) > 0) or
      (Pos('\', LFile) > 0)) then
    Exit(AOutputFile);

  LName := LFile;
  if LName = '' then
    LName := 'bom.json';
  Result := TPath.Combine(LDir, LName);
end;

class function TSbomConfig.ChooseOutputDirectory(const ASettingsDir,
  AFileDir: string): string;
begin
  // The project file wins when it sets a directory, as report.groupByFolder does.
  Result := Trim(AFileDir);
  if Result = '' then
    Result := Trim(ASettingsDir);
end;

class function TSbomConfig.ResolveSbomOutputPath(const AOutputFile, AOutputDir,
  AProjectDir, APlatform, AConfiguration: string; AOutputFileExplicit,
  AIncludePlatformInOutput: Boolean): string;
begin
  Result := ApplyOutputDirectory(AOutputFile, AOutputDir, AOutputFileExplicit);
  if AIncludePlatformInOutput and not AOutputFileExplicit and (Result <> '') then
    Result := DecorateOutputFileName(Result, APlatform, AConfiguration);
  if (Result <> '') and (AProjectDir <> '') and TPath.IsRelativePath(Result) then
    Result := TPath.Combine(AProjectDir, Result);
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
  ClearProjectBinaryIndex;
  FProjectScanner := nil;
  FBuildEvidenceReader := nil;
  FBuildOrchestrator := nil;
  FUnitResolver := nil;
  FFileScanner := nil;
  FHashService := nil;
  FSbomWriter := nil;
  inherited;
end;

function TryFileDateVersion(const AFilePath: string; out AVersion: string): Boolean;
begin
  AVersion := '';
  Result := (AFilePath <> '') and TFile.Exists(AFilePath);
  if Result then
  begin
    AVersion := FormatRfc3339Utc(TFile.GetLastWriteTimeUtc(AFilePath));
  end;
end;

function IsOwnDcp(const ADcpPath, AOwnOutputPath: string): Boolean;
var
  LDcpStem, LOwnStem: string;
begin
  // Without a known output every .dcp keeps the product version, as before.
  if AOwnOutputPath = '' then
    Exit(True);
  if not SameText(TPath.GetExtension(AOwnOutputPath), '.bpl') then
    Exit(False);
  LDcpStem := TPath.GetFileNameWithoutExtension(ADcpPath);
  LOwnStem := TPath.GetFileNameWithoutExtension(AOwnOutputPath);
  // A package MyPkg with LibSuffix 290 builds MyPkg290.bpl and MyPkg.dcp.
  Result := (LDcpStem <> '') and SameText(Copy(LOwnStem, 1, Length(LDcpStem)), LDcpStem);
end;

procedure ApplyProductVersionToBuildFiles(const AArtefacts: TArtefactList;
  const AVersion: string; const AOwnOutputPath: string);
var
  I: Integer;
  LArtefact: TArtefactInfo;
  LType, LExt, LFileName, LDateVersion: string;
  LOwnOutput: Boolean;
begin
  if AArtefacts = nil then
    Exit;
  for I := 0 to AArtefacts.Count - 1 do
  begin
    LArtefact := AArtefacts[I];
    if LArtefact.LibrarySourceFile or (Trim(LArtefact.Version) <> '') or
       (LArtefact.RelativePath = '') then
      Continue;
    LType := LArtefact.ArtefactType;
    if (LType = 'unit-evidence') or (LType = 'framework') or
       (LType = 'required-package') then
      Continue;
    // Declared runtime packages have no file until one is found on disk.
    if (LType = 'runtime-package') and (LArtefact.FilePath = '') then
      Continue;

    if LArtefact.FilePath <> '' then
      LFileName := LArtefact.FilePath
    else
      LFileName := LArtefact.RelativePath;
    LExt := LowerCase(TPath.GetExtension(LFileName));
    LOwnOutput := (AOwnOutputPath <> '') and (LArtefact.FilePath <> '') and
      SameText(ExpandFileName(LArtefact.FilePath), ExpandFileName(AOwnOutputPath));

    // Only the binary this project builds, plus its .dcp, carries the product
    // version. Another .exe in the same directory is a third-party file
    // (issue #96), same as a DLL, .bpl or .dcp that the project did not build.
    if LOwnOutput or ((LType <> 'external-reference') and (LExt = '.dcp') and
       IsOwnDcp(LFileName, AOwnOutputPath)) then
    begin
      LArtefact.Version := Trim(AVersion);
      // Issue #90: when no product version was configured, still surface the
      // PE version resource for the project's own binary so the report and
      // CycloneDX stay aligned.
      if (LArtefact.Version = '') and (LArtefact.FilePath <> '') and
         ((LExt = '.exe') or (LExt = '.dll') or (LExt = '.bpl')) then
      begin
        LArtefact.Version := GetFileVersionText(LArtefact.FilePath);
      end;
    end
    else if (LExt = '.exe') or (LExt = '.dll') or (LExt = '.bpl') then
    begin
      // A third-party EXE, DLL, or package carries its own version, or none.
      // The project's own output was handled above via AOwnOutputPath.
      LArtefact.Version := GetFileVersionText(LArtefact.FilePath);
    end;
    // BSI TR-03183-2 5.2.2: without a version, use the file modification
    // time as an RFC 3339 timestamp. A DLL found only in a system directory
    // (Location set) does not represent the target system and stays empty.
    if (Trim(LArtefact.Version) = '') and (LArtefact.Location = '') and
       TryFileDateVersion(LArtefact.FilePath, LDateVersion) then
    begin
      LArtefact.Version := LDateVersion;
      LArtefact.VersionFromFileDate := True;
    end;
    AArtefacts[I] := LArtefact;
  end;
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
var
  LPlan: TDeepEvidenceBuildPlan;
begin
  LPlan := Default(TDeepEvidenceBuildPlan);
  Result := Default(TDeepEvidenceBuildResult);
  Result.MapFilePath := AProjectInfo.MapFilePath;
  if AProjectInfo.ProjectDir <> '' then
    Result.WorkingDirectory := AProjectInfo.ProjectDir
  else if AProjectInfo.ProjectPath <> '' then
    Result.WorkingDirectory := TPath.GetDirectoryName(AProjectInfo.ProjectPath);

  if not Assigned(FBuildOrchestrator) then
  begin
    Result.Success := True;
    Result.Message := 'No build orchestrator assigned.';
    Exit;
  end;

  // Create the plan before Execute so exception handlers can name project, MAP,
  // working directory and command without reading MAP contents (issue #89).
  try
    LPlan := FBuildOrchestrator.CreatePlan(AProjectInfo, BuildDeepEvidenceOptions);
    Result.CommandLine := LPlan.CommandLine;
    Result.MapFilePath := LPlan.ExpectedMapFilePath;
    Result.WorkingDirectory := LPlan.WorkingDirectory;
    Result := FBuildOrchestrator.ExecutePlan(LPlan);
  except
    on E: Exception do
    begin
      Result.Success := False;
      if LPlan.CommandLine <> '' then
        Result.CommandLine := LPlan.CommandLine;
      if LPlan.ExpectedMapFilePath <> '' then
        Result.MapFilePath := LPlan.ExpectedMapFilePath;
      if LPlan.WorkingDirectory <> '' then
        Result.WorkingDirectory := LPlan.WorkingDirectory;
      Result.Message := FormatDeepEvidenceFailureMessage(E.ClassName, E.Message,
        AProjectInfo.ProjectPath, Result.MapFilePath, Result.WorkingDirectory,
        Result.CommandLine);
    end;
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
    LArtefact.SourcePath := LResolvedUnit.SourcePath;
    LArtefact.UnitName := LResolvedUnit.UnitName;
    LArtefact.RelativePath := TPath.GetFileName(LResolvedUnit.ResolvedPath);
    LArtefact.Hash := LResolvedUnit.SecondaryHashSha256;
    LArtefact.HashSha512 := LResolvedUnit.PrimaryHashSha512;

    if TFile.Exists(LResolvedUnit.ResolvedPath) then
      LArtefact.FileSize := TFile.GetSize(LResolvedUnit.ResolvedPath)
    else
      LArtefact.FileSize := -1;

    LArtefact.ArtefactType := 'unit-evidence';
    LArtefact.Origin := UnitOriginKindToString(LResolvedUnit.OriginKind);
    LArtefact.Evidence := UnitEvidenceKindToString(LResolvedUnit.EvidenceKind);
    LArtefact.Confidence := ResolutionConfidenceToString(LResolvedUnit.Confidence);
    LArtefact.UsedUnitNames := LResolvedUnit.UsedUnitNames;
    LArtefact.UsesCached := LResolvedUnit.UsesCached;

    AArtefacts.Add(LArtefact);
  end;
end;

function TDxComplyGenerator.ThirdPartyCheckArtefacts(
  const ACompositionEvidence: TCompositionEvidence;
  const AArtefacts: TArtefactList): TArtefactList;
var
  LArtefact: TArtefactInfo;
begin
  Result := TArtefactList.Create;
  try
    if Assigned(AArtefacts) then
      for LArtefact in AArtefacts do
        Result.Add(LArtefact);
    // With composition evidence on, the units are already in AArtefacts.
    if (not FConfig.IncludeCompositionEvidence) and
      Assigned(ACompositionEvidence.Units) then
      AddCompositionEvidenceToArtefacts(ACompositionEvidence, Result);
  except
    Result.Free;
    raise;
  end;
end;

procedure TDxComplyGenerator.AddRuntimePackagesToArtefacts(
  const AProjectInfo: TProjectInfo;
  const AArtefacts: TArtefactList);
var
  LArtefact: TArtefactInfo;
  LPackageName: string;
  LBplFileName: string;
  LOutputDir: string;
  LResolved: string;
  LSystemDirs: TArray<string>;
  LSource: TDllLocationSource;
begin
  if not Assigned(AProjectInfo.RuntimePackages) then
    Exit;

  LOutputDir := AProjectInfo.ArtefactOutputDir;
  if LOutputDir = '' then
    LOutputDir := AProjectInfo.OutputDir;
  LSystemDirs := SystemDirectoriesForPlatform(AProjectInfo.Platform);

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
    LArtefact.HashSha512 := '';
    LArtefact.ArtefactType := 'runtime-package';
    LArtefact.Origin := '';
    LArtefact.Evidence := 'BPL';
    LArtefact.Confidence := 'Declared';

    // A BPL staged under the project is the copy that ships. A file found
    // only in a system directory is not hashed, same as an external DLL.
    LResolved := ResolveKnownBinary(LBplFileName, LOutputDir,
      AProjectInfo.ProjectDir, AProjectInfo.Platform, LSystemDirs, LSource);
    if LSource in [dlsExplicitPath, dlsOutputDirectory, dlsProjectTree] then
    begin
      LArtefact.LocationSource := DllLocationSourceText(LSource);
      CaptureBinaryFile(LArtefact, LResolved, AArtefacts);
    end;

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
  LOutputDir, LResolvedPath: string;
  LSystemDirs: TArray<string>;
  LSource: TDllLocationSource;
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

    // Issue #59: look for the file. A file next to the program, at a full
    // path given in code, or staged under the project (Installer and other
    // project folders) is what ships, so it gets size and hashes. A file
    // found only in a system directory is the build machine's copy, so only
    // its location is recorded.
    LOutputDir := AProjectInfo.ArtefactOutputDir;
    if LOutputDir = '' then
      LOutputDir := AProjectInfo.OutputDir;
    LSystemDirs := SystemDirectoriesForPlatform(AProjectInfo.Platform);

    for I := 0 to High(LDllNames) do
    begin
      LDllName := LDllNames[I];
      LArtefact := Default(TArtefactInfo);
      LArtefact.FilePath := '';
      LArtefact.RelativePath := LDllName;
      LArtefact.FileSize := -1;
      LArtefact.Hash := '';
      LArtefact.HashSha512 := '';
      LArtefact.ArtefactType := 'external-reference';
      LArtefact.Origin := '';
      LArtefact.Evidence := TPath.GetExtension(LDllName).ToUpper.TrimLeft(['.']);
      LArtefact.Confidence := 'Source-scan';
      if I < Length(LConditional) then
        LArtefact.Conditional := LConditional[I];

      LResolvedPath := ResolveKnownBinary(LDllName, LOutputDir,
        AProjectInfo.ProjectDir, AProjectInfo.Platform, LSystemDirs, LSource);
      case LSource of
        dlsExplicitPath, dlsOutputDirectory, dlsProjectTree:
          begin
            LArtefact.LocationSource := DllLocationSourceText(LSource);
            // The output directory scan may already have hashed this file.
            CaptureBinaryFile(LArtefact, LResolvedPath, AArtefacts);
          end;
        dlsSystemDirectory:
          begin
            LArtefact.LocationSource := DllLocationSourceText(LSource);
            LArtefact.Location := LResolvedPath;
          end;
      end;

      AArtefacts.Add(LArtefact);
    end;
  finally
    LPasFiles.Free;
  end;
end;

class function TDxComplyGenerator.DllLocationSourceText(
  ASource: TDllLocationSource): string;
begin
  case ASource of
    dlsExplicitPath:
      Result := 'explicit-path';
    dlsOutputDirectory:
      Result := 'output-directory';
    dlsProjectTree:
      Result := 'project-tree';
    dlsSystemDirectory:
      Result := 'system-directory';
  else
    Result := '';
  end;
end;

class function TDxComplyGenerator.SystemDirectoriesForPlatform(
  const APlatform: string): TArray<string>;
var
  LWindowsDir, LSysWow64: string;
begin
  SetLength(Result, 0);
  LWindowsDir := GetEnvironmentVariable('SystemRoot');
  if LWindowsDir = '' then
    LWindowsDir := GetEnvironmentVariable('windir');
  if LWindowsDir = '' then
    Exit;

  if SameText(APlatform, 'Win32') or (APlatform = '') then
  begin
    // A 32-bit program loads system DLLs from SysWOW64 on 64-bit Windows.
    // That path is not redirected, so it works from a 32-bit IDE too.
    LSysWow64 := TPath.Combine(LWindowsDir, 'SysWOW64');
    if TDirectory.Exists(LSysWow64) then
      Result := [LSysWow64]
    else
      Result := [TPath.Combine(LWindowsDir, 'System32')];
  end
  else if SameText(APlatform, 'Win64') or SameText(APlatform, 'Win64x') or
    SameText(APlatform, 'WinARM64EC') then
  begin
    // A 32-bit process sees SysWOW64 under System32. Sysnative is the
    // real System32 for such a process.
    if SizeOf(Pointer) = 4 then
      Result := [TPath.Combine(LWindowsDir, 'Sysnative')]
    else
      Result := [TPath.Combine(LWindowsDir, 'System32')];
  end;
end;

function SplitShippedPath(const APath: string): TArray<string>;
var
  LList: TList<string>;
  LNormalized, LPart: string;
  LParts: TArray<string>;
begin
  LList := TList<string>.Create;
  try
    LNormalized := StringReplace(APath, '/', '\', [rfReplaceAll]);
    LParts := LNormalized.Split(['\']);
    for LPart in LParts do
      if LPart <> '' then
        LList.Add(LPart);
    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;

function PathHasInstallerSegment(const APath: string): Boolean;
var
  LPart: string;
begin
  Result := False;
  for LPart in SplitShippedPath(APath) do
    if SameText(LPart, 'Installer') then
      Exit(True);
end;

function ShippedPathDepth(const APath: string): Integer;
begin
  // One segment is the file name. The rest are directories.
  Result := Length(SplitShippedPath(APath));
  if Result > 0 then
    Dec(Result);
end;

function CompareShippedPaths(const ALeft, ARight: string): Integer;
var
  LLeft, LRight: TArray<string>;
  I, LCount: Integer;
begin
  LLeft := SplitShippedPath(ALeft);
  LRight := SplitShippedPath(ARight);
  LCount := Length(LLeft);
  if Length(LRight) < LCount then
    LCount := Length(LRight);
  for I := 0 to LCount - 1 do
  begin
    Result := CompareText(LLeft[I], LRight[I]);
    if Result <> 0 then
      Exit;
  end;
  Result := Length(LLeft) - Length(LRight);
end;

function ReadPeMachine(const AFilePath: string): Word;
const
  cPeSignature = $00004550; // 'PE'#0#0
var
  LStream: TFileStream;
  LDosHeader: array[0..63] of Byte;
  LPeOffset, LSignature: Cardinal;
  LMachine: Word;
begin
  // The Machine field of the COFF header. 0 when the file is not a PE image
  // or cannot be read.
  Result := 0;
  try
    LStream := TFileStream.Create(AFilePath, fmOpenRead or fmShareDenyNone);
    try
      if LStream.Read(LDosHeader, SizeOf(LDosHeader)) <> SizeOf(LDosHeader) then
        Exit;
      if (LDosHeader[0] <> Ord('M')) or (LDosHeader[1] <> Ord('Z')) then
        Exit;
      Move(LDosHeader[$3C], LPeOffset, SizeOf(LPeOffset));
      if (LPeOffset = 0) or (Int64(LPeOffset) + 6 > LStream.Size) then
        Exit;
      LStream.Position := LPeOffset;
      if LStream.Read(LSignature, SizeOf(LSignature)) <> SizeOf(LSignature) then
        Exit;
      if LSignature <> cPeSignature then
        Exit;
      if LStream.Read(LMachine, SizeOf(LMachine)) <> SizeOf(LMachine) then
        Exit;
      Result := LMachine;
    finally
      LStream.Free;
    end;
  except
    on E: Exception do
      Result := 0;
  end;
end;

function ShippedBinaryPlatformRank(const AFilePath, APlatform: string): Integer;
const
  cMachineI386 = $014C;
  cMachineAmd64 = $8664;
  cMachineArm64 = $AA64;
var
  LMachine: Word;
begin
  // 0: PE image for the target platform. 1: PE image for another platform.
  // 2: not a PE image. Without a Windows target every file ranks 0, so the
  // order is the one used before the platform was considered.
  Result := 0;
  if not (SameText(APlatform, 'Win32') or SameText(APlatform, 'Win64') or
    SameText(APlatform, 'Win64x') or SameText(APlatform, 'WinARM64EC')) then
    Exit;
  LMachine := ReadPeMachine(AFilePath);
  if LMachine = 0 then
    Exit(2);
  if SameText(APlatform, 'Win32') then
  begin
    if LMachine <> cMachineI386 then
      Result := 1;
  end
  else if SameText(APlatform, 'WinARM64EC') then
  begin
    // An ARM64EC process loads ARM64EC and x64 images.
    if (LMachine <> cMachineArm64) and (LMachine <> cMachineAmd64) then
      Result := 1;
  end
  else if LMachine <> cMachineAmd64 then
    Result := 1;
end;

function PreferShippedBinary(const ACandidate, ACurrent: string): Boolean;
var
  LCandidateInstaller, LCurrentInstaller: Boolean;
begin
  // Installer is the staged layout. Dateien sorts before DateienKunde
  // because the comparison is by path segment, not by the '\' character.
  LCandidateInstaller := PathHasInstallerSegment(ACandidate);
  LCurrentInstaller := PathHasInstallerSegment(ACurrent);
  if LCandidateInstaller <> LCurrentInstaller then
    Exit(LCandidateInstaller);
  if ShippedPathDepth(ACandidate) <> ShippedPathDepth(ACurrent) then
    Exit(ShippedPathDepth(ACandidate) < ShippedPathDepth(ACurrent));
  Result := CompareShippedPaths(ACandidate, ACurrent) < 0;
end;

function IsWindowsSystemPath(const APath: string): Boolean;

  function MatchesSystemDir(const AFull, AWindows, AName: string): Boolean;
  var
    LSystem: string;
  begin
    LSystem := ExcludeTrailingPathDelimiter(TPath.Combine(AWindows, AName));
    Result := SameText(AFull, LSystem) or AFull.StartsWith(LSystem + '\', True);
  end;

var
  LWindows, LFull: string;
begin
  Result := False;
  if Trim(APath) = '' then
    Exit;
  LWindows := GetEnvironmentVariable('SystemRoot');
  if LWindows = '' then
    LWindows := GetEnvironmentVariable('windir');
  if LWindows = '' then
    Exit;
  try
    LFull := ExcludeTrailingPathDelimiter(TPath.GetFullPath(APath));
  except
    on E: EInOutArgumentException do
      Exit;
  end;
  Result := MatchesSystemDir(LFull, LWindows, 'System32') or
    MatchesSystemDir(LFull, LWindows, 'SysWOW64') or
    MatchesSystemDir(LFull, LWindows, 'Sysnative');
end;

function IsReparsePoint(const APath: string): Boolean;
var
  LAttrs: DWORD;
begin
  // A junction can point outside the project. Do not follow it.
  LAttrs := Winapi.Windows.GetFileAttributes(PChar(APath));
  Result := (LAttrs <> INVALID_FILE_ATTRIBUTES) and
    ((LAttrs and FILE_ATTRIBUTE_REPARSE_POINT) <> 0);
end;

function IsIgnoredProjectDir(const AName: string): Boolean;
begin
  Result := SameText(AName, '.git') or SameText(AName, '.svn') or
    SameText(AName, '.hg') or SameText(AName, '__history') or
    SameText(AName, '__recovery') or SameText(AName, '__astcache') or
    SameText(AName, 'node_modules') or SameText(AName, '.vs') or
    SameText(AName, '.idea');
end;

class function TDxComplyGenerator.BuildProjectBinaryIndex(const AProjectDir,
  AOutputDir: string; const APlatform: string): TDictionary<string, string>;
const
  cMaxProjectBinaryDepth = 6;
  cMaxProjectBinaryDirs = 500;
  cMaxInstallerDirs = 200;
var
  LRoot, LSkipOutput: string;
  LVisited, LInstallerVisited: Integer;
  LIndex: TDictionary<string, string>;
  LRanks: TDictionary<string, Integer>;

  function SameDir(const ALeft, ARight: string): Boolean;
  begin
    Result := (ALeft <> '') and (ARight <> '') and
      SameText(ExcludeTrailingPathDelimiter(ALeft),
        ExcludeTrailingPathDelimiter(ARight));
  end;

  function SafeDirectories(const ADir: string): TStringDynArray;
  begin
    try
      Result := TDirectory.GetDirectories(ADir);
    except
      on E: Exception do
        SetLength(Result, 0);
    end;
  end;

  procedure SortProjectDirs(var ADirs: TStringDynArray);
  var
    I, J: Integer;
    LSwap: string;

    function Rank(const APath: string): Integer;
    begin
      if SameText(TPath.GetFileName(APath), 'Installer') then
        Result := 0
      else
        Result := 1;
    end;

  begin
    for I := 0 to High(ADirs) - 1 do
      for J := I + 1 to High(ADirs) do
        if (Rank(ADirs[J]) < Rank(ADirs[I])) or
           ((Rank(ADirs[J]) = Rank(ADirs[I])) and
            (CompareText(ADirs[J], ADirs[I]) < 0)) then
        begin
          LSwap := ADirs[I];
          ADirs[I] := ADirs[J];
          ADirs[J] := LSwap;
        end;
  end;

  procedure ConsiderMatches(const ADir: string);
  const
    cMasks: array[0..1] of string = ('*.dll', '*.bpl');
  var
    LMask, LFile, LFull, LKey, LExisting: string;
    LFiles: TStringDynArray;
    LRank, LExistingRank: Integer;
  begin
    for LMask in cMasks do
    begin
      try
        LFiles := TDirectory.GetFiles(ADir, LMask);
      except
        on E: Exception do
          SetLength(LFiles, 0);
      end;
      for LFile in LFiles do
      begin
        try
          LFull := TPath.GetFullPath(LFile);
        except
          on E: EInOutArgumentException do
            Continue;
        end;
        if IsWindowsSystemPath(LFull) then
          Continue;
        LKey := LowerCase(TPath.GetFileName(LFull));
        if LKey = '' then
          Continue;
        // A copy for the target platform beats a copy for another one,
        // whatever the folder. Equal ranks keep the Installer, depth and
        // name order.
        LRank := ShippedBinaryPlatformRank(LFull, APlatform);
        if (not LIndex.TryGetValue(LKey, LExisting)) or
           (not LRanks.TryGetValue(LKey, LExistingRank)) or
           (LRank < LExistingRank) or
           ((LRank = LExistingRank) and PreferShippedBinary(LFull, LExisting)) then
        begin
          LIndex.AddOrSetValue(LKey, LFull);
          LRanks.AddOrSetValue(LKey, LRank);
        end;
      end;
    end;
  end;

  procedure Walk(const ADir: string; ADepth: Integer);
  var
    LSubs: TStringDynArray;
    LSub: string;
    LInstaller: Boolean;
  begin
    if (ADepth > cMaxProjectBinaryDepth) or IsWindowsSystemPath(ADir) or
       SameDir(ADir, LSkipOutput) or not TDirectory.Exists(ADir) then
      Exit;
    LInstaller := PathHasInstallerSegment(ADir);
    if LInstaller then
    begin
      if LInstallerVisited >= cMaxInstallerDirs then
        Exit;
      Inc(LInstallerVisited);
    end
    else
    begin
      if LVisited >= cMaxProjectBinaryDirs then
        Exit;
      Inc(LVisited);
    end;

    ConsiderMatches(ADir);
    if ADepth = cMaxProjectBinaryDepth then
      Exit;

    LSubs := SafeDirectories(ADir);
    SortProjectDirs(LSubs);
    for LSub in LSubs do
    begin
      if IsIgnoredProjectDir(TPath.GetFileName(LSub)) then
        Continue;
      if IsReparsePoint(LSub) then
        Continue;
      Walk(LSub, ADepth + 1);
    end;
  end;

begin
  LIndex := TDictionary<string, string>.Create;
  Result := LIndex;
  LVisited := 0;
  LInstallerVisited := 0;
  LSkipOutput := '';
  if Trim(AProjectDir) = '' then
    Exit;
  try
    LRoot := ExcludeTrailingPathDelimiter(TPath.GetFullPath(AProjectDir));
  except
    on E: EInOutArgumentException do
      Exit;
  end;
  if IsWindowsSystemPath(LRoot) or not TDirectory.Exists(LRoot) then
    Exit;

  // The output directory is searched on its own, and only at the top level.
  // Skipping it here keeps a nested copy inside that directory out of the
  // project-tree result. When the output directory is the project root,
  // subfolders such as Installer still have to be walked.
  if Trim(AOutputDir) <> '' then
    try
      LSkipOutput := ExcludeTrailingPathDelimiter(TPath.GetFullPath(AOutputDir));
      if SameDir(LSkipOutput, LRoot) then
        LSkipOutput := '';
    except
      on E: EInOutArgumentException do
        LSkipOutput := '';
    end;

  LRanks := TDictionary<string, Integer>.Create;
  try
    Walk(LRoot, 0);
  finally
    LRanks.Free;
  end;
end;

class function TDxComplyGenerator.ResolveExternalDllWithIndex(
  const ADllName, AOutputDir, AProjectDir: string;
  const ASystemDirs: TArray<string>;
  const AProjectBinaries: TDictionary<string, string>;
  out ASource: TDllLocationSource): string;
var
  LCandidates: TArray<string>;
  LName, LCandidate, LDir, LPath: string;
begin
  Result := '';
  ASource := dlsNotFound;
  LName := Trim(ADllName);
  if LName = '' then
    Exit;

  if TPath.GetExtension(LName) = '' then
    LCandidates := [LName, LName + '.dll']
  else
    LCandidates := [LName];

  // 1. Full path given in code.
  if TPath.IsPathRooted(LName) and (ExtractFileDrive(LName) <> '') then
  begin
    for LCandidate in LCandidates do
      if TFile.Exists(LCandidate) then
      begin
        ASource := dlsExplicitPath;
        Exit(TPath.GetFullPath(LCandidate));
      end;
    // Not there: look for the file name in the places below.
    if TPath.GetExtension(LName) = '' then
      LCandidates := [TPath.GetFileName(LName),
        TPath.GetFileName(LName) + '.dll']
    else
      LCandidates := [TPath.GetFileName(LName)];
  end;

  // 2. Application output directory.
  if (AOutputDir <> '') and TDirectory.Exists(AOutputDir) then
    for LCandidate in LCandidates do
    begin
      LPath := TPath.Combine(AOutputDir, LCandidate);
      if TFile.Exists(LPath) then
      begin
        ASource := dlsOutputDirectory;
        Exit(TPath.GetFullPath(LPath));
      end;
    end;

  // 3. Known file under the project tree. Installer is preferred. This does
  // not add unrelated binaries; the caller already has the file name.
  if (AProjectDir <> '') and not IsWindowsSystemPath(AProjectDir) then
    for LCandidate in LCandidates do
    begin
      if ((Pos('\', LCandidate) > 0) or (Pos('/', LCandidate) > 0)) and
         not TPath.IsPathRooted(LCandidate) then
      begin
        LPath := TPath.Combine(AProjectDir, LCandidate);
        if TFile.Exists(LPath) and not IsWindowsSystemPath(LPath) then
        begin
          ASource := dlsProjectTree;
          Exit(TPath.GetFullPath(LPath));
        end;
      end;
      if (AProjectBinaries <> nil) and
         AProjectBinaries.TryGetValue(LowerCase(TPath.GetFileName(LCandidate)),
           LPath) and (LPath <> '') and TFile.Exists(LPath) and
         not IsWindowsSystemPath(LPath) then
      begin
        ASource := dlsProjectTree;
        Exit(LPath);
      end;
    end;

  // 4. Windows system directory for the target bitness. Only a plain file
  // name is looked up there, and only its location is recorded by the caller.
  for LDir in ASystemDirs do
    for LCandidate in LCandidates do
    begin
      if TPath.GetFileName(LCandidate) <> LCandidate then
        Continue;
      LPath := TPath.Combine(LDir, LCandidate);
      if TFile.Exists(LPath) then
      begin
        ASource := dlsSystemDirectory;
        // Report the directory under the name the target program sees.
        Result := StringReplace(TPath.GetFullPath(LPath), '\Sysnative\',
          '\System32\', [rfIgnoreCase]);
        Exit;
      end;
    end;
end;

class function TDxComplyGenerator.ResolveExternalDllFile(const ADllName,
  AOutputDir: string; const ASystemDirs: TArray<string>;
  out ASource: TDllLocationSource): string;
begin
  Result := ResolveExternalDllWithIndex(ADllName, AOutputDir, '', ASystemDirs,
    nil, ASource);
end;

class function TDxComplyGenerator.ResolveExternalDllFile(const ADllName,
  AOutputDir, AProjectDir: string; const ASystemDirs: TArray<string>;
  out ASource: TDllLocationSource): string;
var
  LIndex: TDictionary<string, string>;
begin
  LIndex := BuildProjectBinaryIndex(AProjectDir, AOutputDir);
  try
    Result := ResolveExternalDllWithIndex(ADllName, AOutputDir, AProjectDir,
      ASystemDirs, LIndex, ASource);
  finally
    LIndex.Free;
  end;
end;

class function TDxComplyGenerator.ResolveExternalDllFile(const ADllName,
  AOutputDir, AProjectDir, APlatform: string; const ASystemDirs: TArray<string>;
  out ASource: TDllLocationSource): string;
var
  LIndex: TDictionary<string, string>;
begin
  LIndex := BuildProjectBinaryIndex(AProjectDir, AOutputDir, APlatform);
  try
    Result := ResolveExternalDllWithIndex(ADllName, AOutputDir, AProjectDir,
      ASystemDirs, LIndex, ASource);
  finally
    LIndex.Free;
  end;
end;

procedure TDxComplyGenerator.ClearProjectBinaryIndex;
begin
  FreeAndNil(FProjectBinaryIndex);
  FProjectBinaryIndexKey := '';
end;

function TDxComplyGenerator.ResolveKnownBinary(const ADllName, AOutputDir,
  AProjectDir, APlatform: string; const ASystemDirs: TArray<string>;
  out ASource: TDllLocationSource): string;
var
  LKey: string;
  LFresh: TDictionary<string, string>;
begin
  LKey := LowerCase(AProjectDir) + '|' + LowerCase(AOutputDir) + '|' +
    LowerCase(APlatform);
  if not SameText(FProjectBinaryIndexKey, LKey) then
  begin
    LFresh := BuildProjectBinaryIndex(AProjectDir, AOutputDir, APlatform);
    FProjectBinaryIndex.Free;
    FProjectBinaryIndex := LFresh;
    FProjectBinaryIndexKey := LKey;
  end;
  Result := ResolveExternalDllWithIndex(ADllName, AOutputDir, AProjectDir,
    ASystemDirs, FProjectBinaryIndex, ASource);
end;

procedure TDxComplyGenerator.CaptureBinaryFile(var AArtefact: TArtefactInfo;
  const APath: string; const AArtefacts: TArtefactList);
var
  LExisting: TArtefactInfo;
begin
  AArtefact.FilePath := APath;
  if Assigned(AArtefacts) then
    for LExisting in AArtefacts do
      if SameText(LExisting.FilePath, APath) and (LExisting.Hash <> '') then
      begin
        AArtefact.FileSize := LExisting.FileSize;
        AArtefact.Hash := LExisting.Hash;
        AArtefact.HashSha512 := LExisting.HashSha512;
        Exit;
      end;
  try
    AArtefact.FileSize := TFile.GetSize(APath);
    if Assigned(FHashService) then
    begin
      AArtefact.Hash := FHashService.ComputeSha256(APath);
      AArtefact.HashSha512 := FHashService.ComputeSha512(APath);
    end
    else
    begin
      AArtefact.Hash := '';
      AArtefact.HashSha512 := '';
    end;
  except
    on E: Exception do
    begin
      AArtefact.FileSize := -1;
      AArtefact.Hash := '';
      AArtefact.HashSha512 := '';
    end;
  end;
end;

procedure TDxComplyGenerator.AddImportedBinariesToArtefacts(
  const AProjectInfo: TProjectInfo; const AArtefacts: TArtefactList);
var
  LNames: TArray<string>;
  LName, LExt, LOutputDir, LResolved: string;
  LSystemDirs: TArray<string>;
  LSource: TDllLocationSource;
  LArtefact: TArtefactInfo;

  function ListsFile(const AFileName: string): Boolean;
  var
    LListed: TArtefactInfo;
    LCurrent: string;
  begin
    Result := False;
    for LListed in AArtefacts do
    begin
      if LListed.FilePath <> '' then
        LCurrent := TPath.GetFileName(LListed.FilePath)
      else
        LCurrent := TPath.GetFileName(LListed.RelativePath);
      if SameText(LCurrent, TPath.GetFileName(AFileName)) then
        Exit(True);
    end;
  end;

begin
  if not Assigned(AArtefacts) or (AProjectInfo.OutputFilePath = '') then
    Exit;
  if not TryReadPeImportNames(AProjectInfo.OutputFilePath, LNames) then
    Exit;

  LOutputDir := AProjectInfo.ArtefactOutputDir;
  if LOutputDir = '' then
    LOutputDir := AProjectInfo.OutputDir;
  LSystemDirs := SystemDirectoriesForPlatform(AProjectInfo.Platform);

  for LName in LNames do
  begin
    LExt := LowerCase(TPath.GetExtension(LName));
    if (LExt <> '.dll') and (LExt <> '.bpl') then
      Continue;
    if ListsFile(LName) then
      Continue;
    LResolved := ResolveKnownBinary(LName, LOutputDir, AProjectInfo.ProjectDir,
      AProjectInfo.Platform, LSystemDirs, LSource);
    // The output directory is already scanned. A system DLL stays out.
    if LSource <> dlsProjectTree then
      Continue;

    LArtefact := Default(TArtefactInfo);
    LArtefact.RelativePath := TPath.GetFileName(LName);
    LArtefact.FileSize := -1;
    LArtefact.LocationSource := DllLocationSourceText(LSource);
    if LExt = '.bpl' then
      LArtefact.ArtefactType := 'package'
    else
      LArtefact.ArtefactType := 'library';
    CaptureBinaryFile(LArtefact, LResolved, AArtefacts);
    AArtefacts.Add(LArtefact);
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
    sfSpdx3Json:
      Result := TSpdx3JsonWriter.Create;
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
  LSupplierValue: TJSONValue;
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
        // outputDir is a directory. It does not replace an "output" file path.
        if LJson.GetValue('outputDir') <> nil then
          Result.OutputDir := Trim(LJson.GetValue<string>('outputDir'));

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
          // A supplier name can contain "&". TJSONString.Value is the text the
          // parser stored. The generic string reader is not used for this field.
          LSupplierValue := LProduct.GetValue('supplier');
          if LSupplierValue <> nil then
          begin
            if LSupplierValue is TJSONString then
              Result.Supplier := TJSONString(LSupplierValue).Value
            else
              Result.Supplier := LProduct.GetValue<string>('supplier');
          end;
          if LProduct.GetValue('supplierUrl') <> nil then
            Result.SupplierUrl := Trim(LProduct.GetValue<string>('supplierUrl'));
          if LProduct.GetValue('licence') <> nil then
            Result.Licence := Trim(LProduct.GetValue<string>('licence'));
          if LProduct.GetValue('purl') <> nil then
            Result.Purl := Trim(LProduct.GetValue<string>('purl'));
          if LProduct.GetValue('repoUrl') <> nil then
            Result.RepoUrl := Trim(LProduct.GetValue<string>('repoUrl'));
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
          // Issue #126: all (default), overview or units. Like format, an
          // unknown value keeps the default.
          if LReport.GetValue('content') <> nil then
            TryParseReportContent(LReport.GetValue<string>('content'),
              Result.HumanReadableReport.Content);
          // Issue #132: group third-party units without manifest by folder.
          if LReport.GetValue('groupByFolder') <> nil then
            Result.HumanReadableReport.GroupByFolder :=
              LReport.GetValue<Boolean>('groupByFolder');
        end;

        // MAP file directory override
        if LJson.GetValue('mapDir') <> nil then
          Result.MapFileDir := LJson.GetValue<string>('mapDir');

        // Delphi 7 install override for legacy .dpr/.dpk/.bdsproj scans.
        if LJson.GetValue('delphi7Root') <> nil then
          Result.Delphi7Root := LJson.GetValue<string>('delphi7Root');

        // Delphi version whose paths and IDE overrides are used.
        if LJson.GetValue('bdsVersion') <> nil then
          Result.BdsVersion := LJson.GetValue<string>('bdsVersion');

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

        if LJson.GetValue('library') <> nil then
          Result.LibraryMode := LJson.GetValue<Boolean>('library');

        if LJson.GetValue('strict') <> nil then
        begin
          Result.StrictMode := LJson.GetValue<Boolean>('strict');
        end;

        // Issue #108: "spdxVersion": "3.0.1" selects SPDX 3.0.1 for spdx-json.
        if LJson.GetValue('spdxVersion') <> nil then
        begin
          Result.SpdxVersion := Trim(LJson.GetValue<string>('spdxVersion'));
          // The CLI rejects an unknown --spdx-version. The file key keeps the
          // run going, so it says which version is written instead.
          if not IsSupportedSpdxVersion(Result.SpdxVersion) then
            DoProgress('Warning: spdxVersion "' + Result.SpdxVersion + '" in ' +
              TPath.GetFileName(AConfigPath) + ' is not supported. Use "2.3" or "3.0.1". ' +
              'SPDX output is written as 2.3.', 5);
          Result.Format := ApplySpdxVersion(Result.Format, Result.SpdxVersion);
        end;

        if LJson.GetValue('sourceDirs') is TJSONArray then
        begin
          LArray := LJson.GetValue('sourceDirs') as TJSONArray;
          SetLength(Result.SourceDirs, LArray.Count);
          for I := 0 to LArray.Count - 1 do
            Result.SourceDirs[I] := LArray.Items[I].Value;
        end;

        // Component manifest. A non-string value is ignored here; the IDE
        // reader reports that case. Relative paths stay relative until
        // generation, which resolves them from the project directory.
        if LJson.GetValue('manifest') <> nil then
        begin
          LManifestValue := LJson.GetValue('manifest');
          if (LManifestValue is TJSONString) or (LManifestValue is TJSONNumber) then
            Result.ManifestFile := Trim(LManifestValue.Value);
        end;

        // match.prefixes for this run. The components file is the default.
        // corroborated or legacy. Anything else is ignored here and the
        // file's own value is kept. The CLI rejects an unknown flag value.
        if LJson.GetValue('matchPrefixes') <> nil then
        begin
          LText := Trim(LJson.GetValue<string>('matchPrefixes'));
          if SameText(LText, 'legacy') or SameText(LText, 'corroborated') then
            Result.PrefixMatch := LowerCase(LText)
          else if LText <> '' then
            DoProgress('Warning: matchPrefixes "' + LText + '" in ' +
              TPath.GetFileName(AConfigPath) +
              ' is not corroborated or legacy. The components file is used.', 5);
        end;

        // SBOM creator contact. An empty value is ignored. A non-empty value
        // that is neither an email nor an http(s) URL is kept so Generate
        // can reject it instead of dropping it.
        if LJson.GetValue('sbomCreator') <> nil then
        begin
          LText := Trim(LJson.GetValue<string>('sbomCreator'));
          if LText <> '' then
            Result.SbomCreator := LText;
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
  Result.SbomCreator := Trim(AConfig.SbomCreator);
  // Build mode keeps the root component as an application and uses the
  // uses-graph compositions. These fields stay clear so a library run
  // cannot leak into a later build through an unassigned record.
  Result.ComponentType := '';
  Result.Purl := '';
  Result.LibraryCompositions := False;
  Result.LibraryFilesComplete := False;
  Result.LibraryRequiresDeclared := False;
  Result.SupplierUrl := Trim(AConfig.SupplierUrl);
  Result.Licence := Trim(AConfig.Licence);
  Result.ComponentManifestJson := '';
  Result.Timestamp := FormatUtcTimestamp('');
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
          FConfig.IncludePatterns, FConfig.ExcludePatterns, LArtefact, True) then
        begin
          // .so is both an Android application and a Linux library. The
          // project kind, not the extension, decides the artefact type.
          if AProjectInfo.OutputKind <> pokUnknown then
            LArtefact.ArtefactType := PrimaryOutputArtefactType(AProjectInfo.OutputKind);
          Result.Add(LArtefact);
        end;
        RememberPatternWarnings(LWarnings);
      end;

      if FConfig.ScanTree then
      begin
        // Previous releases walked OutputDir with soAllDirectories, which
        // pulled in setup\, tools\, and old build folders whenever that
        // directory fell back to the project root.
        DoProgress('Warning: scanTree is deprecated and will be removed in the next ' +
          'release. The output directory is scanned recursively. ' +
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

function TDxComplyGenerator.GenerateLibrary(const AProjectPath, AOutputPath: string;
  AFormat: TSbomFormat): Boolean;
var
  LProjectInfo: TProjectInfo;
  LBuildEvidence: TBuildEvidence;
  LCompositionEvidence: TCompositionEvidence;
  LArtefacts: TArtefactList;
  LMetadata: TSbomMetadata;
  LReportedWarnings: TList<string>;
  LValidation: TValidationResult;
  LCraWarnings: TList<string>;
  LGeneratedReportPaths: TArray<string>;
  LReportData: TComplianceReportData;
  LSourceDirs: TArray<string>;
  LFiles: TArray<TLibrarySourceFile>;
  LRequires: TArray<string>;
  LCollectWarnings: TArray<string>;
  LProjectPath: string;
  LExt: string;
  LDir: string;
  LCommonRoot: string;
  LMainSource: string;
  LOutputPath: string;
  LFormat: TSbomFormat;
  LName: string;
  LVersion: string;
  LWarning: string;
  LNote: string;
  LCraText: string;
  LErr: string;
  LWarn: string;
  LHasProject: Boolean;
  LRequiresFound: Boolean;
  LFilesComplete: Boolean;
  LFile: TLibrarySourceFile;
  LArtefact: TArtefactInfo;
  I: Integer;
  LManifest: TComponentManifest;
  LManifestJson: string;
  LManifestPath: string;
  LManifestError: string;
  LDormantWarnings: TArray<string>;
  LWarningIndex: Integer;
  LPrefixMode: string;
  LRuntimeJson: string;
begin
  Result := False;
  LManifest := Default(TComponentManifest);
  LManifestJson := '';
  LManifestPath := '';
  LProjectPath := Trim(AProjectPath);
  LHasProject := LProjectPath <> '';

  if LHasProject and TPath.IsRelativePath(LProjectPath) then
  begin
    try
      LProjectPath := TPath.GetFullPath(LProjectPath);
    except
      on EInOutArgumentException do
        LProjectPath := TPath.Combine(GetCurrentDir, LProjectPath);
    end;
  end;

  if (not LHasProject) and (Length(FConfig.SourceDirs) = 0) then
  begin
    DoProgress('Error: Library mode needs a project file or at least one source directory.', -1);
    Exit;
  end;

  if LHasProject then
  begin
    LExt := LowerCase(TPath.GetExtension(LProjectPath));
    if (LExt <> '.dproj') and (LExt <> '.dpk') and (LExt <> '.dpr') then
    begin
      DoProgress('Error: Library mode accepts a .dproj, a .dpk, or a .dpr: ' +
        LProjectPath, -1);
      Exit;
    end;
    if not TFile.Exists(LProjectPath) then
    begin
      DoProgress('Error: Project file not found: ' + LProjectPath, -1);
      Exit;
    end;
  end;

  LProjectInfo := Default(TProjectInfo);
  LBuildEvidence := Default(TBuildEvidence);
  LCompositionEvidence := Default(TCompositionEvidence);
  LReportedWarnings := nil;
  LArtefacts := nil;
  LCraWarnings := nil;
  FCraWarnings := nil;
  try
    LReportedWarnings := TList<string>.Create;
    LArtefacts := TArtefactList.Create;
    LBuildEvidence := TBuildEvidence.Create;
    LCompositionEvidence := TCompositionEvidence.Create;

    if LHasProject then
    begin
      DoProgress('Scanning project...', 10);
      try
        FProjectScanner.SetDelphi7Root(FConfig.Delphi7Root);
        FProjectScanner.SetBdsVersion(FConfig.BdsVersion);
        FProjectScanner.SetExplicitTargetRequest(FConfig.PlatformExplicit,
          FConfig.ConfigurationExplicit);
        LProjectInfo := FProjectScanner.Scan(LProjectPath, FConfig.Platform,
          FConfig.Configuration);
      except
        on E: Exception do
        begin
          // Scan frees the record it created before it raises.
          DoProgress('Error: Failed to read project file: ' + E.Message, -1);
          Exit;
        end;
      end;

      if Assigned(LProjectInfo.ProgressNotes) then
        for LNote in LProjectInfo.ProgressNotes do
          if Trim(LNote) <> '' then
            DoProgress(LNote, 11);
      ReportWarnings(LProjectInfo.Warnings, LReportedWarnings, 12);
    end
    else
      LProjectInfo := TProjectInfo.Create;

    SetLength(LSourceDirs, 0);
    for I := 0 to High(FConfig.SourceDirs) do
    begin
      LDir := Trim(FConfig.SourceDirs[I]);
      if LDir = '' then
        Continue;
      if TPath.IsRelativePath(LDir) then
      begin
        if LHasProject and (LProjectInfo.ProjectDir <> '') then
          LDir := TPath.Combine(LProjectInfo.ProjectDir, LDir)
        else
          LDir := TPath.Combine(GetCurrentDir, LDir);
      end;
      try
        LDir := TPath.GetFullPath(LDir);
      except
        on EInOutArgumentException do
          ;
      end;
      SetLength(LSourceDirs, Length(LSourceDirs) + 1);
      LSourceDirs[High(LSourceDirs)] := LDir;
    end;

    if LHasProject and (LProjectInfo.ProjectDir <> '') then
      LCommonRoot := LProjectInfo.ProjectDir
    else if Length(LSourceDirs) > 0 then
      LCommonRoot := LSourceDirs[0]
    else
      LCommonRoot := GetCurrentDir;

    if not LHasProject then
    begin
      LProjectInfo.ProjectDir := LCommonRoot;
      LProjectInfo.ProjectName :=
        ExtractFileName(ExcludeTrailingPathDelimiter(LCommonRoot));
      if LProjectInfo.ProjectName = '' then
        LProjectInfo.ProjectName := 'library';
    end;

    // The same manifest build mode reads. A bad file stops the run. A bad
    // cpe is a warning on the manifest and does not stop it.
    if Trim(FConfig.ManifestFile) <> '' then
    begin
      LManifestPath := ResolveManifestPath(LProjectInfo.ProjectDir, FConfig.ManifestFile);
      if not TryLoadComponentManifest(LManifestPath, LManifest, LManifestJson,
        LManifestError) then
      begin
        DoProgress('Error: Invalid component manifest "' + LManifestPath + '": ' +
          LManifestError, -1);
        Exit;
      end;
      // The in-memory copy carries the install root, so a later parse in a
      // writer applies the product-path veto. --match-prefixes and
      // matchPrefixes override the file for this run. An empty root (no
      // project, or a scan that found no install) leaves the veto idle.
      LPrefixMode := '';
      if Trim(FConfig.PrefixMatch) <> '' then
      begin
        if SameText(FConfig.PrefixMatch, 'legacy') or
          SameText(FConfig.PrefixMatch, 'corroborated') then
          LPrefixMode := LowerCase(Trim(FConfig.PrefixMatch))
        else
          DoProgress('Warning: match.prefixes "' + FConfig.PrefixMatch +
            '" is not corroborated or legacy. The components file is used.', 13);
      end;
      LRuntimeJson := ManifestJsonWithRuntimeContext(LManifestJson,
        LProjectInfo.Toolchain.RootDir, LPrefixMode);
      if LRuntimeJson <> LManifestJson then
      begin
        LManifestJson := LRuntimeJson;
        if not TryParseComponentManifest(LManifestJson, LManifestPath, LManifest,
          LManifestError) then
        begin
          DoProgress('Error: Invalid component manifest "' + LManifestPath + '": ' +
            LManifestError, -1);
          Exit;
        end;
      end;
      for LWarningIndex := 0 to High(LManifest.Warnings) do
        DoProgress('Warning: ' + LManifestPath + ': ' +
          LManifest.Warnings[LWarningIndex], 13);
    end;

    LMainSource := '';
    if LHasProject then
    begin
      LExt := LowerCase(TPath.GetExtension(LProjectPath));
      if LExt = '.dproj' then
      begin
        if (LProjectInfo.MainSourcePath <> '') and
           (SameText(TPath.GetExtension(LProjectInfo.MainSourcePath), '.dpk') or
            SameText(TPath.GetExtension(LProjectInfo.MainSourcePath), '.dpr')) then
          LMainSource := LProjectInfo.MainSourcePath;
      end
      else
        LMainSource := LProjectPath;
    end;

    DoProgress('Collecting library sources...', 30);
    LFiles := CollectLibrarySourceFiles(LMainSource, LSourceDirs, LCommonRoot,
      FConfig.IncludePatterns, FConfig.ExcludePatterns, LRequires, LRequiresFound,
      LCollectWarnings);
    for LWarning in LCollectWarnings do
      DoProgress('Warning: ' + LWarning, 32);

    LFilesComplete := True;
    for LFile in LFiles do
    begin
      LArtefact := Default(TArtefactInfo);
      LArtefact.FilePath := LFile.FullPath;
      LArtefact.RelativePath := LFile.RelativePath;
      LArtefact.ComponentName := LFile.RelativePath;
      LArtefact.ArtefactType := 'file';
      LArtefact.LibrarySourceFile := True;
      LArtefact.FileSize := -1;
      if TFile.Exists(LFile.FullPath) then
      begin
        try
          LArtefact.FileSize := TFile.GetSize(LFile.FullPath);
          LArtefact.Hash := FHashService.ComputeSha256(LFile.FullPath);
          LArtefact.HashSha512 := FHashService.ComputeSha512(LFile.FullPath);
        except
          LArtefact.FileSize := -1;
          LArtefact.Hash := '';
          LArtefact.HashSha512 := '';
        end;
      end;
      if (LArtefact.Hash = '') or (LArtefact.HashSha512 = '') then
        LFilesComplete := False;
      LArtefacts.Add(LArtefact);
    end;
    if Length(LFiles) = 0 then
      LFilesComplete := True;

    for LName in LRequires do
    begin
      LArtefact := Default(TArtefactInfo);
      LArtefact.ComponentName := LName;
      LArtefact.FileSize := -1;
      if IsDelphiFrameworkPackage(LName) then
        LArtefact.ArtefactType := 'framework'
      else
        LArtefact.ArtefactType := 'required-package';
      LArtefact.Version := Trim(LProjectInfo.Toolchain.Version);
      LArtefacts.Add(LArtefact);
    end;

    DoProgress(Format('Found %d library component(s)', [LArtefacts.Count]), 50);

    LOutputPath := ResolveConfiguredOutputPath(AOutputPath);
    if TPath.IsRelativePath(LOutputPath) then
    begin
      if LHasProject and (LProjectInfo.ProjectDir <> '') then
        LOutputPath := TPath.Combine(LProjectInfo.ProjectDir, LOutputPath)
      else if LCommonRoot <> '' then
        LOutputPath := TPath.Combine(LCommonRoot, LOutputPath)
      else
        LOutputPath := TPath.Combine(GetCurrentDir, LOutputPath);
    end;

    if AFormat <> sfCycloneDxJson then
      LFormat := AFormat
    else
      LFormat := FConfig.Format;

    LMetadata := Default(TSbomMetadata);
    LMetadata.ProductName := Trim(FConfig.ProductName);
    if LMetadata.ProductName = '' then
      LMetadata.ProductName := LProjectInfo.ProjectName;
    if LMetadata.ProductName = '' then
      LMetadata.ProductName := 'library';
    LMetadata.ProductVersion := Trim(FConfig.ProductVersion);
    if LMetadata.ProductVersion = '' then
      LMetadata.ProductVersion := LProjectInfo.Version;
    LMetadata.Supplier := Trim(FConfig.Supplier);
    if LMetadata.Supplier = '' then
      LMetadata.Supplier := LProjectInfo.CompanyName;
    LMetadata.SupplierUrl := Trim(FConfig.SupplierUrl);
    LMetadata.Licence := Trim(FConfig.Licence);
    LMetadata.SbomCreator := Trim(FConfig.SbomCreator);
    LMetadata.Timestamp := FormatUtcTimestamp('');
    LMetadata.ToolName := 'DX.Comply';
    LMetadata.ToolVersion := GetDxComplyToolVersion;
    LMetadata.ComponentType := 'library';
    LVersion := LMetadata.ProductVersion;
    // Every shipped file carries the release version. Unknown stays empty.
    for I := 0 to LArtefacts.Count - 1 do
      if LArtefacts[I].LibrarySourceFile then
      begin
        LArtefact := LArtefacts[I];
        LArtefact.Version := Trim(LVersion);
        LArtefacts[I] := LArtefact;
      end;
    if Trim(FConfig.Purl) <> '' then
      LMetadata.Purl := Trim(FConfig.Purl)
    else
      LMetadata.Purl := GithubPurlFromRepoUrl(FConfig.RepoUrl, LVersion);
    LMetadata.LibraryCompositions := True;
    LMetadata.LibraryFilesComplete := LFilesComplete;
    LMetadata.LibraryRequiresDeclared := LRequiresFound;
    SetLength(LMetadata.Properties, 1);
    LMetadata.Properties[0] := TSbomProperty.Create(
      'net.developer-experts.dx-comply:document.profile', 'library-source');

    if LManifest.Loaded then
    begin
      LDormantWarnings := DormantComponentWarnings(LManifest,
        BuildManifestPlan(LManifest, LArtefacts));
      for LWarningIndex := 0 to High(LDormantWarnings) do
        DoProgress('Warning: ' + LManifestPath + ': ' +
          LDormantWarnings[LWarningIndex], 68);
      for var LPrefixLine in RejectedPrefixLogLines(LManifest, LArtefacts) do
        DoProgress('Warning: ' + LManifestPath + ': ' + LPrefixLine, 68);
      for var LFolderLine in ProductFolderMatchLogLines(LManifest, LArtefacts) do
        DoProgress('Warning: ' + LManifestPath + ': ' + LFolderLine, 68);
      ApplyManifestPublisher(LManifest, LMetadata);
      LMetadata.ComponentManifestJson := LManifestJson;
    end;

    LCraWarnings := TList<string>.Create;
    for LCraText in BuildCraMetadataWarnings(FConfig, LMetadata, LProjectInfo,
      LArtefacts) do
      LCraWarnings.Add(LCraText);
    ReportWarnings(LCraWarnings, LReportedWarnings, 69);
    FCraWarnings := LCraWarnings.ToArray;

    DoProgress('Generating SBOM...', 70);
    FSbomWriter := CreateWriter(LFormat);
    Result := FSbomWriter.Write(LOutputPath, LMetadata, LArtefacts, LProjectInfo);
    if not Result then
    begin
      DoProgress('Error: Failed to write SBOM', -1);
      Exit;
    end;

    DoProgress('Running structural check...', 90);
    LValidation := ValidateSbom(LOutputPath);
    LReportData := BuildHumanReadableReportData(LOutputPath, LFormat, LMetadata,
      LProjectInfo, LBuildEvidence, LCompositionEvidence, LArtefacts,
      LReportedWarnings, Default(TDeepEvidenceBuildResult), LValidation);
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
      for LErr in LValidation.Errors do
        DoProgress('Structural check error: ' + LErr, -1);
      for LWarn in LValidation.Warnings do
        DoProgress('Structural check warning: ' + LWarn, 95);
    end;
  finally
    LCraWarnings.Free;
    LArtefacts.Free;
    LReportedWarnings.Free;
    LCompositionEvidence.Free;
    LBuildEvidence.Free;
    LProjectInfo.Free;
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
  LNote: string;
  LCraWarnings: TList<string>;
  LCraText: string;
  LDprojPath: string;
begin
  Result := False;

  if not IsAcceptableBsiCreator(FConfig.SbomCreator) then
  begin
    if FConfig.WarningContext = swcIde then
    begin
      DoProgress('Error: The SBOM creator must be an email address or an http(s) URL. ' +
        'Correct it in ' + cIdeSbomHeaderDialogPath + '.', -1);
    end
    else
    begin
      DoProgress('Error: sbomCreator must be an email address or an http(s) URL.', -1);
    end;
    Exit;
  end;

  // Library mode does not build, read a MAP file, or scan a binary.
  if FConfig.LibraryMode then
  begin
    Result := GenerateLibrary(AProjectPath, AOutputPath, AFormat);
    Exit;
  end;

  // A .dpr with a .dproj of the same name next to it is a Delphi 2007 or
  // later project. Use the .dproj, as Delphi does when it opens the .dpr.
  // A .dpr without a .dproj keeps the Delphi 7 path. Issue #75.
  LDprojPath := ResolveProjectPath(AProjectPath);
  if LDprojPath <> AProjectPath then
  begin
    Result := Generate(LDprojPath, AOutputPath, AFormat);
    Exit;
  end;

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
  FCraWarnings := nil;
  LManifestJson := '';
  try
    FProjectScanner.SetDelphi7Root(FConfig.Delphi7Root);
    FProjectScanner.SetBdsVersion(FConfig.BdsVersion);
    FProjectScanner.SetExplicitTargetRequest(FConfig.PlatformExplicit,
      FConfig.ConfigurationExplicit);
    LProjectInfo := FProjectScanner.Scan(AProjectPath, FConfig.Platform, FConfig.Configuration);

    // Apply MapFileDir override. The directory changes; the file name stays
    // the one this platform writes (Project.map, or libProject.so.map on
    // Android). Legacy projects look next to the output binary unless the
    // caller points at another directory.
    if FConfig.MapFileDir <> '' then
    begin
      LProjectInfo.MapFilePath := TPath.Combine(FConfig.MapFileDir,
        LProjectInfo.ExpectedMapFileName);
    end;
  except
    on E: Exception do
    begin
      DoProgress('Error: Failed to read project file: ' + E.Message, -1);
      LReportedWarnings.Free;
      Exit;
    end;
  end;

  try
    // Output-directory variant notes. Not warnings, so the CLI prints them
    // only with --verbose.
    if Assigned(LProjectInfo.ProgressNotes) then
      for LNote in LProjectInfo.ProgressNotes do
        if Trim(LNote) <> '' then
          DoProgress(LNote, 11);

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
      // The in-memory copy carries the install root, so a later parse in a
      // writer applies the product-path veto. --match-prefixes and
      // matchPrefixes override the file for this run.
      var LPrefixMode := '';
      if Trim(FConfig.PrefixMatch) <> '' then
      begin
        if SameText(FConfig.PrefixMatch, 'legacy') or
          SameText(FConfig.PrefixMatch, 'corroborated') then
          LPrefixMode := LowerCase(Trim(FConfig.PrefixMatch))
        else
          DoProgress('Warning: match.prefixes "' + FConfig.PrefixMatch +
            '" is not corroborated or legacy. The components file is used.', 13);
      end;
      var LRuntimeJson := ManifestJsonWithRuntimeContext(LManifestJson,
        LProjectInfo.Toolchain.RootDir, LPrefixMode);
      if LRuntimeJson <> LManifestJson then
      begin
        LManifestJson := LRuntimeJson;
        if not TryParseComponentManifest(LManifestJson, LManifestPath, LManifest,
          LManifestError) then
        begin
          DoProgress('Error: Invalid component manifest "' + LManifestPath + '": ' +
            LManifestError, -1);
          Exit(False);
        end;
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
        LDeepEvidenceBuildResult.MapFilePath := LProjectInfo.MapFilePath;
        LDeepEvidenceBuildResult.WorkingDirectory := LProjectInfo.ProjectDir;
        LDeepEvidenceBuildResult.Message := FormatDeepEvidenceFailureMessage(
          E.ClassName, E.Message, LProjectInfo.ProjectPath, LProjectInfo.MapFilePath,
          LProjectInfo.ProjectDir, '');
      end;
    end;
    if not LDeepEvidenceBuildResult.Success then
    begin
      var LDiagLog := WriteDeepEvidenceDiagnosticLog(LProjectInfo.ProjectDir,
        LDeepEvidenceBuildResult, LProjectInfo.ProjectPath);
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
        if LDeepEvidenceBuildResult.WorkingDirectory <> '' then
          DoProgress('Hint: Deep-Evidence working directory: ' +
            LDeepEvidenceBuildResult.WorkingDirectory, 18);
        if LDeepEvidenceBuildResult.MapFilePath <> '' then
          DoProgress('Hint: Expected MAP file: ' +
            LDeepEvidenceBuildResult.MapFilePath, 18);
        if LDeepEvidenceBuildResult.Output <> '' then
          DoProgress('Hint: Deep-Evidence build output: ' +
            LDeepEvidenceBuildResult.Output, 18);
        if LDiagLog <> '' then
          DoProgress('Hint: Deep-Evidence diagnostics written to: ' + LDiagLog, 18);
        DoProgress('Continuing SBOM generation with the existing MAP file (if any). ' +
          'See the log output above for details.', 18);
      end
      else
      begin
        DoProgress('Error: ' + LDeepEvidenceBuildResult.Message, -1);
        if LDeepEvidenceBuildResult.CommandLine <> '' then
          DoProgress('Command: ' + LDeepEvidenceBuildResult.CommandLine, -1);
        if LDeepEvidenceBuildResult.WorkingDirectory <> '' then
          DoProgress('Working directory: ' + LDeepEvidenceBuildResult.WorkingDirectory, -1);
        if LDeepEvidenceBuildResult.MapFilePath <> '' then
          DoProgress('Expected MAP: ' + LDeepEvidenceBuildResult.MapFilePath, -1);
        if LDeepEvidenceBuildResult.Output <> '' then
          DoProgress('Build output: ' + LDeepEvidenceBuildResult.Output, -1);
        if LDiagLog <> '' then
          DoProgress('Diagnostics: ' + LDiagLog, -1);
        Exit;
      end;
    end
    else if LDeepEvidenceBuildResult.Executed then
      DoProgress('MAP build completed.', 18)
    else
      DoProgress(LDeepEvidenceBuildResult.Message, 18);

    DoProgress('Preparing build evidence...', 20);
    LBuildEvidence := ReadBuildEvidence(LProjectInfo);
    DoProgress(Format('Collected %d build evidence item(s):',
      [LBuildEvidence.EvidenceItems.Count]), 25);
    // Unit rows from a detailed map can number in the thousands. They are
    // counted here. The lines below name the other evidence items so the
    // log is not only a total (issue #100).
    var LMapUnitCount := 0;
    for var LEvidenceItem in LBuildEvidence.EvidenceItems do
    begin
      if Trim(LEvidenceItem.UnitName) <> '' then
      begin
        Inc(LMapUnitCount);
        Continue;
      end;
      DoProgress('  ' + BuildEvidenceItemLogLine(LEvidenceItem), 25);
    end;
    if LMapUnitCount > 0 then
      DoProgress(Format('  Unit from map file: %d unit(s)', [LMapUnitCount]), 25);
    ReportWarnings(LBuildEvidence.Warnings, LReportedWarnings, 26);

    DoProgress('Resolving composition evidence...', 28);
    LCompositionEvidence := ResolveCompositionEvidence(LProjectInfo, LBuildEvidence);
    // units_exact and units_folder name the library even when the file sits
    // in the Delphi install. A units_prefix match does not reassign a unit
    // in an Embarcadero product path. Product units with no row keep the
    // resolver origin.
    if LManifest.Loaded then
      ApplyManifestOverInstallOrigin(LManifest, LProjectInfo.Toolchain.RootDir,
        LCompositionEvidence.Units);
    DoProgress(Format('Resolved %d composition unit(s)',
      [LCompositionEvidence.Units.Count]), 29);
    ReportWarnings(LCompositionEvidence.Warnings, LReportedWarnings, 29);
    if FConfig.WarnOnEmptyCompositionEvidence and (LCompositionEvidence.Units.Count = 0) then
      DoProgress('Warning: ' + BuildEmptyCompositionWarning(LProjectInfo, LBuildEvidence), 29);

    DoProgress('Scanning build output...', 30);

    LArtefacts := CollectBuildArtefacts(LProjectInfo);
    try
      DoProgress(Format('Found %d artefacts', [LArtefacts.Count]), 50);

      // Determine output path. A caller path wins. Otherwise a bare file
      // name is placed in outputDir when that directory is set.
      LOutputPath := ResolveConfiguredOutputPath(AOutputPath);

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
      AddExternalDllReferencesToArtefacts(LProjectInfo, LCompositionEvidence,
        LArtefacts);
      AddImportedBinariesToArtefacts(LProjectInfo, LArtefacts);

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

      // Files from the build output carry the product version, as files do
      // in library mode. The hash prefix is no longer used as a version.
      ApplyProductVersionToBuildFiles(LArtefacts, LMetadata.ProductVersion,
        LProjectInfo.OutputFilePath);

      if LManifest.Loaded then
      begin
        // A MAP unit with no file is still in the unit list. Add it when a
        // library row matches, so that row is not reported as having no units.
        if FConfig.IncludeCompositionEvidence and
          Assigned(LCompositionEvidence.Units) then
          for var LNameOnly in LCompositionEvidence.Units do
          begin
            if Trim(LNameOnly.ResolvedPath) = '' then
              TryAddNameOnlyLibraryUnit(LManifest, LNameOnly.UnitName,
                UnitOriginKindToString(LNameOnly.OriginKind),
                UnitEvidenceKindToString(LNameOnly.EvidenceKind),
                ResolutionConfidenceToString(LNameOnly.Confidence),
                LArtefacts);
          end;
        LDormantWarnings := DormantComponentWarnings(LManifest,
          BuildManifestPlan(LManifest, LArtefacts));
        for LWarningIndex := 0 to High(LDormantWarnings) do
          DoProgress('Warning: ' + LManifestPath + ': ' + LDormantWarnings[LWarningIndex], 68);
        for var LPrefixLine in RejectedPrefixLogLines(LManifest, LArtefacts) do
          DoProgress('Warning: ' + LManifestPath + ': ' + LPrefixLine, 68);
        for var LFolderLine in ProductFolderMatchLogLines(LManifest, LArtefacts) do
          DoProgress('Warning: ' + LManifestPath + ': ' + LFolderLine, 68);
        ApplyManifestPublisher(LManifest, LMetadata);
        LMetadata.ComponentManifestJson := LManifestJson;
      end;

      // Header gaps are warnings. The SBOM is still written.
      LCraWarnings := TList<string>.Create;
      try
        for LCraText in BuildCraMetadataWarnings(FConfig, LMetadata, LProjectInfo,
          LArtefacts) do
          LCraWarnings.Add(LCraText);
        // Issue #110: third-party units without supplier or licence. With
        // composition evidence switched off the units are not SBOM components,
        // but the program still links them. The check then runs on the
        // resolved units, so --strict does not pass because they are hidden.
        var LUnitArtefacts := ThirdPartyCheckArtefacts(LCompositionEvidence, LArtefacts);
        try
          for LCraText in BuildThirdPartyComponentWarnings(FConfig, LManifest, LUnitArtefacts) do
            LCraWarnings.Add(LCraText);
        finally
          LUnitArtefacts.Free;
        end;
        ReportWarnings(LCraWarnings, LReportedWarnings, 69);
        FCraWarnings := LCraWarnings.ToArray;
        // Issue #114: one-line count for the CLI and the IDE log.
        var LWithoutManifestLine := ThirdPartyWithoutManifestLine(LArtefacts, LMetadata.ComponentManifestJson);
        if LWithoutManifestLine <> '' then
          DoProgress('Info: ' + LWithoutManifestLine, 69);
      finally
        LCraWarnings.Free;
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
    ClearProjectBinaryIndex;
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
  if scoSupplierUrl in ACaller.ExplicitOverrides then
    Result.SupplierUrl := ACaller.SupplierUrl;
  if scoLicence in ACaller.ExplicitOverrides then
    Result.Licence := ACaller.Licence;
  if scoSbomCreator in ACaller.ExplicitOverrides then
    Result.SbomCreator := ACaller.SbomCreator;
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
  if scoLibraryMode in ACaller.ExplicitOverrides then
    Result.LibraryMode := ACaller.LibraryMode;
  if scoSourceDirs in ACaller.ExplicitOverrides then
    Result.SourceDirs := ACaller.SourceDirs;
  if scoPurl in ACaller.ExplicitOverrides then
    Result.Purl := ACaller.Purl;
  if scoRepoUrl in ACaller.ExplicitOverrides then
    Result.RepoUrl := ACaller.RepoUrl;
  if scoStrictMode in ACaller.ExplicitOverrides then
  begin
    Result.StrictMode := ACaller.StrictMode;
  end;
  if scoReportContent in ACaller.ExplicitOverrides then
  begin
    Result.HumanReadableReport.Content := ACaller.HumanReadableReport.Content;
  end;
  if scoReportGroupByFolder in ACaller.ExplicitOverrides then
  begin
    Result.HumanReadableReport.GroupByFolder := ACaller.HumanReadableReport.GroupByFolder;
  end;
  if scoSpdxVersion in ACaller.ExplicitOverrides then
  begin
    Result.SpdxVersion := ACaller.SpdxVersion;
  end;
  if scoPrefixMatch in ACaller.ExplicitOverrides then
    Result.PrefixMatch := ACaller.PrefixMatch;
  Result.Format := ApplySpdxVersion(Result.Format, Result.SpdxVersion);

  Result.IncludePlatformInOutput := ACaller.IncludePlatformInOutput;
  Result.ExplicitOverrides := ACaller.ExplicitOverrides;
  Result.WarningContext := ACaller.WarningContext;

  // Place a bare file name in outputDir before decoration, so the decorated
  // name stays in that directory. An explicit --output is left as a file path.
  if not (scoOutputPath in ACaller.ExplicitOverrides) then
    Result.OutputPath := TSbomConfig.ApplyOutputDirectory(
      Result.OutputPath, Result.OutputDir, False);

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
  if LCliConfig.BdsVersion <> '' then
  begin
    FConfig.BdsVersion := LCliConfig.BdsVersion;
  end;
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

function TDxComplyGenerator.ResolveProjectPath(const AProjectPath: string): string;
var
  LDprojPath: string;
begin
  Result := AProjectPath;
  if TryFindDprojForDpr(AProjectPath, LDprojPath) then
  begin
    DoProgress('Info: ' + DprojForDprMessage(AProjectPath, LDprojPath), 5);
    Result := LDprojPath;
  end;
end;

function TDxComplyGenerator.ValidateProject(const AProjectPath: string): Boolean;
begin
  Result := FProjectScanner.Validate(AProjectPath);
end;

function TDxComplyGenerator.ResolveConfiguredOutputPath(
  const AOutputPath: string): string;
begin
  // A path passed into Generate is the file to write. outputDir applies
  // only when the caller left the path empty. An explicit --output is
  // recorded on ExplicitOverrides and is not moved into the directory.
  if AOutputPath <> '' then
    Exit(AOutputPath);
  Result := TSbomConfig.ApplyOutputDirectory(FConfig.OutputPath, FConfig.OutputDir,
    scoOutputPath in FConfig.ExplicitOverrides);
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
