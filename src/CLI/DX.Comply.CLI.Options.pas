/// <summary>
/// DX.Comply.CLI.Options
/// Command-line argument parsing for the DX.Comply CLI tool (dxcomply.exe).
/// </summary>
///
/// <remarks>
/// Parses the ParamStr array and exposes strongly-typed properties for each
/// supported flag. Unknown flags cause Parse to return False and populate
/// ParseError with a descriptive message. ToSbomConfig converts the parsed
/// options into a TSbomConfig record ready for the engine.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.CLI.Options;

interface

uses
  System.SysUtils,
  System.Classes,
  DX.Comply.Engine,
  DX.Comply.Engine.Intf,
  DX.Comply.Report.Intf;

const
  /// <summary>
  /// File name shown in help and hints when the running executable's own
  /// name cannot be determined.
  /// </summary>
  cDefaultExeName = 'dxcomply.exe';

type
  /// <summary>
  /// Result of looking up the config file for dxcomply.exe.
  /// </summary>
  TConfigPathResolution = record
    /// <summary>
    /// Absolute path of the file that exists. Empty when no file was found.
    /// An absolute input that exists is returned unchanged.
    /// </summary>
    Path: string;
    /// <summary>True when Path is a file that exists.</summary>
    Found: Boolean;
    /// <summary>
    /// Absolute paths that were checked, in lookup order.
    /// The --ci warning prints this list.
    /// </summary>
    Tried: TArray<string>;
  end;

  /// <summary>
  /// Parses command-line arguments for the DX.Comply CLI and exposes them as
  /// typed properties. Call Parse, check the result and ParseError, then read
  /// the properties or call ToSbomConfig.
  /// </summary>
  TCliOptions = class
  private
    FProject: string;
    FFormat: TSbomFormat;
    FSpdxVersion: string;
    FOutput: string;
    FPlatform: string;
    FPlatformExplicit: Boolean;
    FConfiguration: string;
    FConfigurationExplicit: Boolean;
    FProductName: string;
    FProductVersion: string;
    FSupplier: string;
    FSupplierUrl: string;
    FLicence: string;
    FIncludePatterns: TArray<string>;
    FExcludePatterns: TArray<string>;
    FCiMode: Boolean;
    FConfigFile: string;
    FHelp: Boolean;
    FVerbose: Boolean;
    FNoPause: Boolean;
    FMapDir: string;
    FNoCompositionEvidence: Boolean;
    FIncludePlatformInOutput: Boolean;
    FOutputExplicit: Boolean;
    FReportEnabled: Boolean;
    FReportFormat: THumanReadableReportFormat;
    FReportContent: THumanReadableReportContent;
    FReportGroupByFolder: Boolean;
    FExplicitOverrides: TSbomConfigOverrides;
    FScanDirs: TArray<string>;
    FScanTree: Boolean;
    FLibraryMode: Boolean;
    FStrictMode: Boolean;
    FSourceDirs: TArray<string>;
    FPurl: string;
    FRepoUrl: string;
    FDelphi7Root: string;
    FBdsVersion: string;
    FManifestFile: string;
    FManifestExplicit: Boolean;
    FSbomCreator: string;
    FVersionFromGitTag: Boolean;
    FParseError: string;
    /// <summary>
    /// Parses the --report value (markdown | html | both | none) and updates
    /// the report enable flag / format. Returns True on success.
    /// </summary>
    function TryParseReport(const AValue: string): Boolean;
    /// <summary>
    /// Accepts true/false, yes/no, and 1/0. Returns False for anything else.
    /// </summary>
    function TryParseBool(const AValue: string; out AFlag: Boolean): Boolean;
    /// <summary>
    /// Converts a format string token to the corresponding TSbomFormat enum
    /// value. Returns sfCycloneDxJson for unrecognised tokens.
    /// </summary>
    function ParseFormat(const AValue: string): TSbomFormat;
    /// <summary>Appends AValue to the given dynamic string array.</summary>
    procedure AppendPattern(var APatterns: TArray<string>; const AValue: string);
  public
    /// <summary>
    /// Strips characters that could enable path traversal or directory
    /// injection when a value is interpolated into a filename. Keeps only
    /// ASCII letters, digits, hyphen and underscore. Exposed for testing.
    /// </summary>
    class function SanitizeForFilename(const AValue: string): string; static;
    constructor Create;
    /// <summary>
    /// Parses the process ParamStr array and populates all properties.
    /// Returns True when parsing succeeded (or --help was requested).
    /// Returns False when a required argument is missing or an unknown flag
    /// is encountered; ParseError will contain the reason.
    /// </summary>
    function Parse: Boolean; overload;
    /// <summary>
    /// Parses AArgs as the command line (without the program name).
    /// Used by tests so parsing does not depend on ParamStr.
    /// </summary>
    function Parse(const AArgs: TArray<string>): Boolean; overload;
    /// <summary>
    /// File name of the running executable (ExtractFileName of AModulePath,
    /// or of ParamStr(0) when AModulePath is empty). Falls back to
    /// cDefaultExeName when no name can be determined, so help and hints
    /// show the name the user actually runs (normally dxcomply.exe, or
    /// whatever the file was renamed to).
    /// </summary>
    class function ExecutableName(const AModulePath: string = ''): string; static;
    /// <summary>
    /// The hint printed after a command-line error, e.g.
    /// 'Run dxcomply.exe --help for usage.'
    /// </summary>
    class function UsageHint(const AModulePath: string = ''): string; static;
    /// <summary>
    /// The version line, e.g. 'DX.Comply v2.1.0.0'. The number comes from the
    /// version resource of the running executable, so it always matches the
    /// VerInfo keys of the build and cannot drift from a hardcoded literal.
    /// </summary>
    class function VersionLine: string; static;
    /// <summary>Writes the usage text to stdout.</summary>
    procedure PrintHelp;
    /// <summary>
    /// The usage text PrintHelp writes, including the version line.
    /// Square brackets in the option list mark an optional value.
    /// </summary>
    class function HelpText: string; static;
    /// <summary>
    /// Resolves the config file dxcomply.exe will read.
    /// An absolute AConfigFile is used as given.
    /// A relative path, including the default .dxcomply.json, is checked in
    /// AWorkingDirectory first (the process directory when that argument is
    /// empty). When the file is not there and AProjectPath is set, the
    /// project folder is checked next. The folder of dxcomply.exe is not used.
    /// </summary>
    class function ResolveConfigPath(const AConfigFile, AProjectPath: string;
      const AWorkingDirectory: string = ''): TConfigPathResolution; static;
    /// <summary>
    /// Warning printed when ACiMode is set and ResolveConfigPath found no file.
    /// Empty when ACiMode is false or a file was found, so the caller prints
    /// nothing in those cases. The text is not a CRA/BSI warning. It does not
    /// by itself select exit code 3.
    /// </summary>
    class function ConfigFileWarning(const ACiMode: Boolean;
      const AResolution: TConfigPathResolution): string; static;
    /// <summary>Writes the tool version line to stdout.</summary>
    procedure PrintVersion;
    /// <summary>
    /// Builds a TSbomConfig record populated from the parsed options.
    /// Call only after a successful Parse.
    /// </summary>
    function ToSbomConfig: TSbomConfig;
    /// <summary>
    /// Directory whose latest git tag --version-from-git-tag reads: the
    /// folder of --project, else the first --source-dir, else the current
    /// directory.
    /// </summary>
    function GitTagDirectory: string;

    property Project: string read FProject;
    property Format: TSbomFormat read FFormat;
    property Output: string read FOutput;
    property Platform: string read FPlatform;
    property Configuration: string read FConfiguration;
    property ProductName: string read FProductName;
    property ProductVersion: string read FProductVersion;
    /// <summary>True when --version-from-git-tag was passed.</summary>
    property VersionFromGitTag: Boolean read FVersionFromGitTag;
    property Supplier: string read FSupplier;
    /// <summary>Supplier contact URL from --supplier-url.</summary>
    property SupplierUrl: string read FSupplierUrl;
    /// <summary>Distribution licence of the product from --licence.</summary>
    property Licence: string read FLicence;
    property IncludePatterns: TArray<string> read FIncludePatterns;
    property ExcludePatterns: TArray<string> read FExcludePatterns;
    property CiMode: Boolean read FCiMode;
    property ConfigFile: string read FConfigFile;
    property Help: Boolean read FHelp;
    property Verbose: Boolean read FVerbose;
    property NoPause: Boolean read FNoPause;
    property MapDir: string read FMapDir;
    property NoCompositionEvidence: Boolean read FNoCompositionEvidence;
    /// <summary>
    /// When True (and --output is not supplied), the default bom.json
    /// filename is decorated with the selected platform and configuration
    /// (e.g. bom.Win64.Release.json). See issue #25.
    /// </summary>
    property IncludePlatformInOutput: Boolean read FIncludePlatformInOutput;
    /// <summary>True when the user passed --report=... to enable companion reports (issue #30).</summary>
    property ReportEnabled: Boolean read FReportEnabled;
    /// <summary>Effective report format when ReportEnabled is True.</summary>
    property ReportFormat: THumanReadableReportFormat read FReportFormat;
    /// <summary>Report sections from --report-content (issue #126). Default all.</summary>
    property ReportContent: THumanReadableReportContent read FReportContent;
    /// <summary>--report-group-by-folder (issue #132). Default False.</summary>
    property ReportGroupByFolder: Boolean read FReportGroupByFolder;
    /// <summary>Extra binary directories from repeatable --scan-dir.</summary>
    property ScanDirs: TArray<string> read FScanDirs;
    /// <summary>True when --scan-tree was requested. Deprecated.</summary>
    property ScanTree: Boolean read FScanTree;
    /// <summary>True when --library was requested.</summary>
    property LibraryMode: Boolean read FLibraryMode;
    /// <summary>True when --strict was requested (issue #111).</summary>
    property StrictMode: Boolean read FStrictMode;
    /// <summary>SPDX version from --spdx-version (issue #108).</summary>
    property SpdxVersion: string read FSpdxVersion;
    /// <summary>Source directories from repeatable --source-dir.</summary>
    property SourceDirs: TArray<string> read FSourceDirs;
    /// <summary>Package URL from --purl.</summary>
    property Purl: string read FPurl;
    /// <summary>Repository URL from --repo-url.</summary>
    property RepoUrl: string read FRepoUrl;
    /// <summary>Delphi 7 installation directory from --delphi7-root.</summary>
    property Delphi7Root: string read FDelphi7Root;
    /// <summary>BDS version from --bds-version, for example 23.0.</summary>
    property BdsVersion: string read FBdsVersion;
    /// <summary>Path from --manifest. Empty when the flag was not passed.</summary>
    property ManifestFile: string read FManifestFile;
    /// <summary>True when --manifest was passed. That path wins over the config file.</summary>
    property ManifestExplicit: Boolean read FManifestExplicit;
    /// <summary>SBOM creator contact from --sbom-creator. Empty when the flag was not passed.</summary>
    property SbomCreator: string read FSbomCreator;
    property ParseError: string read FParseError;
  end;

implementation

uses
  System.IOUtils,
  DX.Comply.Spdx3.Writer,
  DX.Comply.VersionInfo;

{ TCliOptions }

constructor TCliOptions.Create;
begin
  inherited Create;
  // Apply defaults that mirror TSbomConfig.Default
  FFormat        := sfCycloneDxJson;
  FOutput        := 'bom.json';
  FPlatform      := 'Win32';
  FConfiguration := 'Release';
  FConfigFile    := '.dxcomply.json';
  FExplicitOverrides := [];
end;

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

function TCliOptions.ParseFormat(const AValue: string): TSbomFormat;
var
  LLower: string;
begin
  LLower := LowerCase(AValue);
  if LLower = 'cyclonedx-xml' then
    Result := sfCycloneDxXml
  else if LLower = 'spdx-json' then
    Result := sfSpdxJson
  else
    // 'cyclonedx-json' and anything unrecognised fall back to the default
    Result := sfCycloneDxJson;
end;

function TCliOptions.TryParseBool(const AValue: string; out AFlag: Boolean): Boolean;
var
  LValue: string;
begin
  LValue := LowerCase(Trim(AValue));
  if (LValue = 'true') or (LValue = 'yes') or (LValue = '1') then
  begin
    AFlag := True;
    Exit(True);
  end;
  if (LValue = 'false') or (LValue = 'no') or (LValue = '0') then
  begin
    AFlag := False;
    Exit(True);
  end;
  Result := False;
end;

function TCliOptions.TryParseReport(const AValue: string): Boolean;
var
  LLower: string;
begin
  Result := True;
  LLower := LowerCase(Trim(AValue));
  if LLower = 'none' then
    FReportEnabled := False
  else if LLower = 'markdown' then
  begin
    FReportEnabled := True;
    FReportFormat  := hrfMarkdown;
  end
  else if LLower = 'html' then
  begin
    FReportEnabled := True;
    FReportFormat  := hrfHtml;
  end
  else if (LLower = 'both') or (LLower = '') then
  begin
    FReportEnabled := True;
    FReportFormat  := hrfBoth;
  end
  else
    Result := False;
end;

procedure TCliOptions.AppendPattern(var APatterns: TArray<string>; const AValue: string);
var
  LLen: Integer;
begin
  LLen := Length(APatterns);
  SetLength(APatterns, LLen + 1);
  APatterns[LLen] := AValue;
end;

// ---------------------------------------------------------------------------
// Parse
// ---------------------------------------------------------------------------

function TCliOptions.Parse: Boolean;
var
  LArgs: TArray<string>;
  I: Integer;
begin
  SetLength(LArgs, ParamCount);
  for I := 1 to ParamCount do
    LArgs[I - 1] := ParamStr(I);
  Result := Parse(LArgs);
end;

function TCliOptions.Parse(const AArgs: TArray<string>): Boolean;
var
  I: Integer;
  LArg, LKey, LValue: string;
  LEqualsPos: Integer;
begin
  Result := True;
  FParseError := '';
  FExplicitOverrides := [];
  FOutputExplicit := False;
  FSpdxVersion := '';

  for I := 0 to High(AArgs) do
  begin
    LArg := AArgs[I];

    if (LArg = '--help') or (LArg = '-h') then
    begin
      FHelp := True;
      Continue;
    end;

    if LArg = '--verbose' then
    begin
      FVerbose := True;
      Continue;
    end;

    if LArg = '--no-pause' then
    begin
      FNoPause := True;
      Continue;
    end;

    if LArg = '--ci' then
    begin
      FCiMode := True;
      Continue;
    end;

    if LArg = '--no-composition-evidence' then
    begin
      FNoCompositionEvidence := True;
      Include(FExplicitOverrides, scoIncludeCompositionEvidence);
      Continue;
    end;

    if LArg = '--include-platform-in-output' then
    begin
      FIncludePlatformInOutput := True;
      Continue;
    end;

    // Deprecated recursive walk of the output directory.
    if LArg = '--scan-tree' then
    begin
      FScanTree := True;
      Include(FExplicitOverrides, scoScanTree);
      Continue;
    end;

    if LArg = '--version-from-git-tag' then
    begin
      FVersionFromGitTag := True;
      Continue;
    end;

    if LArg = '--report-group-by-folder' then
    begin
      FReportGroupByFolder := True;
      Include(FExplicitOverrides, scoReportGroupByFolder);
      Continue;
    end;

    if LArg = '--strict' then
    begin
      FStrictMode := True;
      Include(FExplicitOverrides, scoStrictMode);
      Continue;
    end;

    if LArg = '--library' then
    begin
      FLibraryMode := True;
      Include(FExplicitOverrides, scoLibraryMode);
      Continue;
    end;

    // Bare --report (no value) enables both markdown and html.
    if LArg = '--report' then
    begin
      TryParseReport('both');
      Include(FExplicitOverrides, scoReport);
      Continue;
    end;

    if LArg.StartsWith('--') then
    begin
      // Split into key and value at the first '='
      LEqualsPos := LArg.IndexOf('=');
      if LEqualsPos < 0 then
      begin
        // Boolean flags that were not handled above are unknown
        FParseError := 'Unknown option: ' + LArg;
        Exit(False);
      end;

      LKey   := LowerCase(LArg.Substring(2, LEqualsPos - 2));
      LValue := LArg.Substring(LEqualsPos + 1);

      if LKey = 'project' then
        FProject := LValue
      else if LKey = 'format' then
      begin
        FFormat := ParseFormat(LValue);
        Include(FExplicitOverrides, scoFormat);
      end
      else if LKey = 'output' then
      begin
        FOutput := LValue;
        FOutputExplicit := True;
        Include(FExplicitOverrides, scoOutputPath);
      end
      else if LKey = 'platform' then
      begin
        FPlatform := LValue;
        FPlatformExplicit := True;
        Include(FExplicitOverrides, scoPlatform);
      end
      else if LKey = 'config-name' then
      begin
        FConfiguration := LValue;
        FConfigurationExplicit := True;
        Include(FExplicitOverrides, scoConfiguration);
      end
      else if LKey = 'product' then
      begin
        FProductName := LValue;
        Include(FExplicitOverrides, scoProductName);
      end
      else if LKey = 'version' then
      begin
        FProductVersion := LValue;
        Include(FExplicitOverrides, scoProductVersion);
      end
      else if LKey = 'supplier' then
      begin
        FSupplier := LValue;
        Include(FExplicitOverrides, scoSupplier);
      end
      else if LKey = 'supplier-url' then
      begin
        FSupplierUrl := Trim(LValue);
        Include(FExplicitOverrides, scoSupplierUrl);
      end
      else if LKey = 'licence' then
      begin
        FLicence := Trim(LValue);
        Include(FExplicitOverrides, scoLicence);
      end
      else if LKey = 'include' then
      begin
        AppendPattern(FIncludePatterns, LValue);
        Include(FExplicitOverrides, scoIncludePatterns);
      end
      else if LKey = 'exclude' then
      begin
        AppendPattern(FExcludePatterns, LValue);
        Include(FExplicitOverrides, scoExcludePatterns);
      end
      else if LKey = 'config' then
        FConfigFile := LValue
      else if LKey = 'map-dir' then
      begin
        FMapDir := LValue;
        Include(FExplicitOverrides, scoMapFileDir);
      end
      else if LKey = 'delphi7-root' then
        FDelphi7Root := LValue
      else if (LKey = 'bds-version') or (LKey = 'delphi-version') then
        FBdsVersion := LValue
      else if LKey = 'report' then
      begin
        if not TryParseReport(LValue) then
        begin
          FParseError := 'Invalid value for --report: ' + LValue +
            ' (expected markdown, html, both, or none)';
          Exit(False);
        end;
        Include(FExplicitOverrides, scoReport);
      end
      else if LKey = 'scan-dir' then
      begin
        AppendPattern(FScanDirs, LValue);
        Include(FExplicitOverrides, scoScanDirs);
      end
      else if LKey = 'scan-tree' then
      begin
        if not TryParseBool(LValue, FScanTree) then
        begin
          FParseError := 'Invalid value for --scan-tree: ' + LValue +
            ' (expected true or false)';
          Exit(False);
        end;
        Include(FExplicitOverrides, scoScanTree);
      end
      else if LKey = 'report-content' then
      begin
        if not TryParseReportContent(LValue, FReportContent) then
        begin
          FParseError := 'Invalid value for --report-content: ' + LValue +
            ' (expected all, overview, or units)';
          Exit(False);
        end;
        Include(FExplicitOverrides, scoReportContent);
      end
      else if LKey = 'report-group-by-folder' then
      begin
        if not TryParseBool(LValue, FReportGroupByFolder) then
        begin
          FParseError := 'Invalid value for --report-group-by-folder: ' + LValue +
            ' (expected true or false)';
          Exit(False);
        end;
        Include(FExplicitOverrides, scoReportGroupByFolder);
      end
      else if LKey = 'strict' then
      begin
        if not TryParseBool(LValue, FStrictMode) then
        begin
          FParseError := 'Invalid value for --strict: ' + LValue + ' (expected true or false)';
          Exit(False);
        end;
        Include(FExplicitOverrides, scoStrictMode);
      end
      else if LKey = 'spdx-version' then
      begin
        if not IsSupportedSpdxVersion(LValue) then
        begin
          FParseError := 'Invalid value for --spdx-version: ' + LValue + ' (expected 2.3 or 3.0.1)';
          Exit(False);
        end;
        FSpdxVersion := Trim(LValue);
        Include(FExplicitOverrides, scoSpdxVersion);
      end
      else if LKey = 'library' then
      begin
        if not TryParseBool(LValue, FLibraryMode) then
        begin
          FParseError := 'Invalid value for --library: ' + LValue +
            ' (expected true or false)';
          Exit(False);
        end;
        Include(FExplicitOverrides, scoLibraryMode);
      end
      else if LKey = 'source-dir' then
      begin
        if Trim(LValue) = '' then
        begin
          FParseError := 'Invalid value for --source-dir: path is empty.';
          Exit(False);
        end;
        AppendPattern(FSourceDirs, Trim(LValue));
        Include(FExplicitOverrides, scoSourceDirs);
      end
      else if LKey = 'purl' then
      begin
        FPurl := Trim(LValue);
        Include(FExplicitOverrides, scoPurl);
      end
      else if LKey = 'repo-url' then
      begin
        FRepoUrl := Trim(LValue);
        Include(FExplicitOverrides, scoRepoUrl);
      end
      else if LKey = 'manifest' then
      begin
        if Trim(LValue) = '' then
        begin
          FParseError := 'Invalid value for --manifest: path is empty.';
          Exit(False);
        end;
        FManifestFile := LValue;
        FManifestExplicit := True;
      end
      else if LKey = 'sbom-creator' then
      begin
        if Trim(LValue) = '' then
        begin
          FParseError := 'Invalid value for --sbom-creator: value is empty.';
          Exit(False);
        end;
        if BsiCreatorKind(LValue) = '' then
        begin
          FParseError := 'Invalid value for --sbom-creator: expected an email address or an http(s) URL.';
          Exit(False);
        end;
        FSbomCreator := Trim(LValue);
        Include(FExplicitOverrides, scoSbomCreator);
      end
      else
      begin
        FParseError := 'Unknown option: --' + LKey;
        Exit(False);
      end;
    end
    else
    begin
      // Positional argument: treat as the project path when not yet set
      if FProject = '' then
        FProject := LArg
      else
      begin
        FParseError := 'Unexpected positional argument: ' + LArg;
        Exit(False);
      end;
    end;
  end;

  // Validate required arguments (skip when --help is requested)
  if FHelp then
    Exit(True);

  // Build mode needs a project. Library mode does not when at least one
  // source directory was given. With --ci those keys may live only in the
  // config file, which is read after Parse, so an empty project is left
  // for the caller to accept or reject.
  if FProject = '' then
  begin
    if FLibraryMode and (Length(FSourceDirs) > 0) then
      Exit(True);
    if FCiMode then
      Exit(True);
    FParseError := '--project is required.';
    Exit(False);
  end;
end;

// ---------------------------------------------------------------------------
// PrintHelp / PrintVersion
// ---------------------------------------------------------------------------

class function TCliOptions.ExecutableName(const AModulePath: string): string;
var
  LPath: string;
begin
  LPath := AModulePath;
  if LPath = '' then
    LPath := ParamStr(0);
  Result := ExtractFileName(LPath);
  if Result = '' then
    Result := cDefaultExeName;
end;

class function TCliOptions.UsageHint(const AModulePath: string): string;
begin
  Result := 'Run ' + ExecutableName(AModulePath) + ' --help for usage.';
end;

// ---------------------------------------------------------------------------
// Config file lookup
// ---------------------------------------------------------------------------

class function TCliOptions.ResolveConfigPath(const AConfigFile, AProjectPath,
  AWorkingDirectory: string): TConfigPathResolution;
var
  LConfigFile: string;
  LWorkingDirectory: string;
  LCandidate: string;
  LProjectDirectory: string;
  LProjectPath: string;

  procedure AddTried(const APath: string);
  var
    I: Integer;
  begin
    if APath = '' then
      Exit;
    for I := 0 to High(Result.Tried) do
      if SameText(Result.Tried[I], APath) then
        Exit;
    SetLength(Result.Tried, Length(Result.Tried) + 1);
    Result.Tried[High(Result.Tried)] := APath;
  end;

  function Normalize(const APath: string): string;
  begin
    Result := APath;
    try
      Result := TPath.GetFullPath(APath);
    except
      on EInOutArgumentException do
        ;
    end;
  end;

begin
  Result.Path := '';
  Result.Found := False;
  SetLength(Result.Tried, 0);

  LConfigFile := Trim(AConfigFile);
  // Parse stores this name when --config is omitted. An empty argument
  // uses the same default so the lookup still has a file name.
  if LConfigFile = '' then
    LConfigFile := '.dxcomply.json';

  LWorkingDirectory := Trim(AWorkingDirectory);
  if LWorkingDirectory = '' then
    LWorkingDirectory := GetCurrentDir;

  // An absolute path is the file the caller named. It is not combined with
  // the working directory, the project folder, or the folder of dxcomply.exe.
  if not TPath.IsRelativePath(LConfigFile) then
  begin
    AddTried(LConfigFile);
    if TFile.Exists(LConfigFile) then
    begin
      Result.Path := LConfigFile;
      Result.Found := True;
    end;
    Exit;
  end;

  LCandidate := Normalize(TPath.Combine(LWorkingDirectory, LConfigFile));
  AddTried(LCandidate);
  if TFile.Exists(LCandidate) then
  begin
    Result.Path := LCandidate;
    Result.Found := True;
    Exit;
  end;

  LProjectPath := Trim(AProjectPath);
  if LProjectPath = '' then
    Exit;

  if TPath.IsRelativePath(LProjectPath) then
    LProjectPath := TPath.Combine(LWorkingDirectory, LProjectPath);
  LProjectPath := Normalize(LProjectPath);
  LProjectDirectory := TPath.GetDirectoryName(LProjectPath);
  if LProjectDirectory = '' then
    Exit;

  LCandidate := Normalize(TPath.Combine(LProjectDirectory, LConfigFile));
  AddTried(LCandidate);
  if TFile.Exists(LCandidate) then
  begin
    Result.Path := LCandidate;
    Result.Found := True;
  end;
end;

class function TCliOptions.ConfigFileWarning(const ACiMode: Boolean;
  const AResolution: TConfigPathResolution): string;
var
  LPath: string;
begin
  Result := '';
  if (not ACiMode) or AResolution.Found then
    Exit;

  Result := '[WARN ] No config file was found for --ci. dxcomply.exe continues without it.';
  Result := Result + sLineBreak + '        Paths tried:';
  for LPath in AResolution.Tried do
    Result := Result + sLineBreak + '        ' + LPath;
end;

procedure TCliOptions.PrintHelp;
var
  LLines: TStringList;
  I: Integer;
begin
  LLines := TStringList.Create;
  try
    LLines.Text := HelpText;
    for I := 0 to LLines.Count - 1 do
      Writeln(LLines[I]);
  finally
    LLines.Free;
  end;
end;

class function TCliOptions.HelpText: string;
var
  LLines: TStringList;
  LExe: string;
  procedure Line(const AText: string);
  begin
    LLines.Add(AText);
  end;
begin
  LLines := TStringList.Create;
  try
    LExe := ExecutableName;
    Line(VersionLine);
    Line('');
    Line('Usage:');
    Line('  ' + LExe + ' --project=<path> [options]');
    Line('  ' + LExe + ' --library --source-dir=<dir> [options]');
    Line('');
    Line('Square brackets mark an optional value, so --report equals --report=both');
    Line('and --library equals --library=true.');
    Line('');
    Line('Options:');
    Line('  --project=<path>              Project file. Required in build mode:');
    Line('                                .dproj, .dpr, .dpk, .bdsproj, or .groupproj.');
    Line('                                Optional in library mode when at least');
    Line('                                one --source-dir is set. Library mode');
    Line('                                accepts .dproj, .dpk, or .dpr.');
    Line('  --format=<format>             Output format (default: cyclonedx-json)');
    Line('                                  cyclonedx-json (1.6) | cyclonedx-xml (1.6) | spdx-json');
    Line('  --spdx-version=<version>      SPDX version for spdx-json: 2.3 (default) | 3.0.1');
    Line('                                File key: spdxVersion');
    Line('  --output=<path>               Output file path (default: bom.json).');
    Line('                                A relative path uses the project');
    Line('                                directory. This flag wins over outputDir.');
    Line('                                File key output is the file path.');
    Line('                                File key outputDir is a directory.');
    Line('                                A bare output name is written there.');
    Line('                                Reports with no report.output follow it.');
    Line('  --platform=<name>             Target platform (default: Win32)');
    Line('                                File key: platform');
    Line('                                Android 32-bit is the platform Android.');
    Line('                                The binary and the map are in');
    Line('                                Android\<Config>, for example');
    Line('                                Android\Release\libMyApp.so. Android32');
    Line('                                is accepted and mapped to that folder.');
    Line('                                Android64 stays Android64.');
    Line('  --config-name=<name>          Build configuration (default: Release)');
    Line('                                File key: configName');
    Line('                                For .dpr, .dpk, and .bdsproj, --platform');
    Line('                                and --config-name are not applied.');
    Line('                                The defaults are not reported. A value');
    Line('                                you set is reported and ignored.');
    Line('  --product=<name>              Product name override');
    Line('  --version=<version>           Product version override');
    Line('  --version-from-git-tag        Product version from the latest git tag');
    Line('                                of the project folder. A leading v or V');
    Line('                                is removed. --version wins when both');
    Line('                                are set. Without git or a tag, a warning');
    Line('                                is printed and the usual version is used.');
    Line('  --supplier=<name>             Supplier/company name');
    Line('  --supplier-url=<url>          Supplier contact URL.');
    Line('                                Used when the supplier is not an email.');
    Line('                                File key: product.supplierUrl');
    Line('  --licence=<SPDX expression>   Distribution licence of the product.');
    Line('                                SPDX identifier, expression, or a name.');
    Line('                                File key: product.licence');
    Line('  --sbom-creator=<email-or-url> SBOM creator contact (BSI TR-03183-2).');
    Line('                                An email address or an http(s) URL.');
    Line('                                Omitted when you do not set it.');
    Line('                                File key: sbomCreator');
    Line('  --include=<pattern>           File include pattern (repeatable)');
    Line('  --exclude=<pattern>           File exclude pattern (repeatable)');
    Line('  --scan-dir=<path>             Also scan this directory for binaries');
    Line('                                (repeatable). A plain path is not recursive.');
    Line('                                A path that contains ** walks subdirectories.');
    Line('  --scan-tree                   Deprecated: recursively scan the output');
    Line('                                directory, as older versions did.');
    Line('                                Will be removed in the next release.');
    Line('                                Prefer --scan-dir.');
    Line('  --library[=true|false]        SBOM for a source release, not a build.');
    Line('                                No build, no MAP file, no binary scan.');
    Line('                                File key: library');
    Line('  --source-dir=<dir>            Source directory, walked recursively');
    Line('                                (repeatable). Relative to the project');
    Line('                                directory, or the current directory');
    Line('                                when --project is omitted.');
    Line('                                File key: sourceDirs');
    Line('  --purl=<purl>                 Package URL of the root component.');
    Line('                                File key: product.purl');
    Line('  --repo-url=<url>              Repository URL. When --purl is empty');
    Line('                                and this is https://github.com/owner/repo');
    Line('                                (optional trailing .git or /), the purl');
    Line('                                is pkg:github/owner/repo@version when a');
    Line('                                version is known. Without a version,');
    Line('                                no purl is written.');
    Line('                                File key: product.repoUrl');
    Line('  --manifest=<file>             Component manifest (components.json)');
    Line('                                Groups third-party units into libraries');
    Line('                                with supplier, licence, version, type');
    Line('                                and PURL. Relative to the project directory.');
    Line('                                Overrides the manifest key in .dxcomply.json');
    Line('  --map-dir=<path>              Directory containing the pre-built MAP file');
    Line('  --delphi7-root=<path>         Delphi 7 install directory (RootDir).');
    Line('  --bds-version=<ver>           Delphi install to use, for example 23.0');
    Line('                                or 23. Default: the BDS environment');
    Line('                                variable, then the newest installed');
    Line('                                Delphi. That version sets');
    Line('                                $(ProductVersion), the library paths,');
    Line('                                and the IDE environment variable');
    Line('                                overrides. The run prints which');
    Line('                                version was used and where it came');
    Line('                                from. File key: bdsVersion');
    Line('  --no-composition-evidence     Omit source/DCU units from SBOM (binary-only)');
    Line('  --include-platform-in-output  Append <Platform>.<Config> to the default');
    Line('                                output filename (e.g. bom.Win64.Release.json).');
    Line('                                The file stays in outputDir when that');
    Line('                                directory is set. Ignored when --output');
    Line('                                is supplied');
    Line('  --report[=<format>]           Generate companion human-readable report');
    Line('                                  markdown | html | both (default) | none');
    Line('  --report-content=<content>    Sections of the report (not of the SBOM):');
    Line('                                  all (default) | overview | units');
    Line('                                overview: origin summary, licences and');
    Line('                                third-party units without manifest.');
    Line('                                units: the unit list with SHA-256 hashes.');
    Line('                                File key: report.content');
    Line('  --report-group-by-folder[=true|false]');
    Line('                                Group third-party units without manifest');
    Line('                                by unit prefix and source folder.');
    Line('                                File key: report.groupByFolder');
    Line('  --ci                          CI mode: use .dxcomply.json config file');
    Line('  --strict[=true|false]         Write the SBOM, then exit with code 3 when');
    Line('                                any CRA/BSI warning was raised.');
    Line('                                File key: strict');
    Line('  --config=<path>               Path to .dxcomply.json (default: .dxcomply.json).');
    Line('                                An absolute path is used as given.');
    Line('                                A relative path is checked in the current');
    Line('                                directory, then in the project folder');
    Line('                                when --project is set.');
    Line('  --help, -h                    Show this help');
    Line('  --verbose                     Print all progress messages (default: errors only)');
    Line('  --no-pause                    Suppress "Press Enter to quit" prompt');
    Line('');
    Line('Config file (--ci, when the file exists):');
    Line('  Built-in defaults are filled in first, then .dxcomply.json, then any');
    Line('  option you actually pass. A passed option wins over the file. An');
    Line('  option you omit keeps the file value (the default does not override');
    Line('  the file). Without --ci the file is not read. With --ci, a missing');
    Line('  file is reported with the paths that were checked, and the run');
    Line('  continues.');
    Line('');
    Line('Exit codes:');
    Line('  0  SBOM generated');
    Line('  1  Generation failed');
    Line('  2  Invalid arguments');
    Line('  3  SBOM generated, but --strict and at least one CRA/BSI warning');
    Line('');
    Line('Examples:');
    Line('  ' + LExe + ' --project=src\MyApp.dproj --format=cyclonedx-json --output=bom.json');
    Line('  ' + LExe + ' --project=src\MyApp.dproj --manifest=components.json --no-pause');
    Line('  ' + LExe + ' --project=src\MyApp.dproj --sbom-creator=sbom@example.com --no-pause');
    Line('  ' + LExe + ' --project=src\MyApp.dpr --delphi7-root=C:\Delphi7 --no-pause');
    Line('  ' + LExe + ' --project=src\MyApp.dproj --ci --config=.dxcomply.json --no-pause');
    Line('  ' + LExe + ' --project=src\MyApp.dproj --ci --config-name=Debug --no-pause');
    Line('  ' + LExe + ' --library --project=Source\DEC60.dproj --source-dir=Source --licence=Apache-2.0 --no-pause');
    Result := LLines.Text;
    if (Result <> '') and Result.EndsWith(sLineBreak) then
      SetLength(Result, Length(Result) - Length(sLineBreak));
  finally
    LLines.Free;
  end;
end;

class function TCliOptions.VersionLine: string;
begin
  Result := 'DX.Comply v' + GetDxComplyToolVersion;
end;

procedure TCliOptions.PrintVersion;
begin
  Writeln(VersionLine);
end;

// ---------------------------------------------------------------------------
// ToSbomConfig
// ---------------------------------------------------------------------------

class function TCliOptions.SanitizeForFilename(const AValue: string): string;
var
  LChar: Char;
begin
  Result := '';
  for LChar in AValue do
    if CharInSet(LChar, ['A'..'Z', 'a'..'z', '0'..'9', '-', '_']) then
      Result := Result + LChar;
end;

function TCliOptions.GitTagDirectory: string;
begin
  if FProject <> '' then
    Result := ExtractFileDir(ExpandFileName(FProject))
  else if Length(FSourceDirs) > 0 then
    Result := ExpandFileName(FSourceDirs[0])
  else
    Result := GetCurrentDir;
end;

function TCliOptions.ToSbomConfig: TSbomConfig;
begin
  Result := TSbomConfig.Default;
  Result.OutputPath      := FOutput;
  Result.SpdxVersion     := FSpdxVersion;
  Result.Format          := ApplySpdxVersion(FFormat, FSpdxVersion);
  Result.Platform        := FPlatform;
  Result.PlatformExplicit := FPlatformExplicit;
  Result.Configuration   := FConfiguration;
  Result.ConfigurationExplicit := FConfigurationExplicit;
  Result.ProductName     := FProductName;
  Result.ProductVersion  := FProductVersion;
  Result.Supplier        := FSupplier;
  Result.SupplierUrl     := FSupplierUrl;
  Result.Licence         := FLicence;
  Result.SbomCreator     := FSbomCreator;
  Result.IncludePatterns             := FIncludePatterns;
  Result.ExcludePatterns             := FExcludePatterns;
  Result.ScanDirs                    := FScanDirs;
  Result.ScanTree                    := FScanTree;
  Result.LibraryMode                 := FLibraryMode;
  Result.StrictMode                  := FStrictMode;
  Result.SourceDirs                  := FSourceDirs;
  Result.Purl                        := FPurl;
  Result.RepoUrl                     := FRepoUrl;
  Result.MapFileDir                  := FMapDir;
  Result.Delphi7Root                 := FDelphi7Root;
  Result.BdsVersion                  := FBdsVersion;
  Result.IncludeCompositionEvidence  := not FNoCompositionEvidence;
  Result.ManifestFile                := FManifestFile;
  Result.ManifestFileExplicit        := FManifestExplicit;
  Result.ExplicitOverrides           := FExplicitOverrides;
  Result.IncludePlatformInOutput     := FIncludePlatformInOutput;

  // When --include-platform-in-output is set and --output was not supplied,
  // decorate the filename with the selected platform/config so that
  // multi-platform builds do not overwrite one another. Issue #25.
  //
  // Platform and configuration are sanitized inside DecorateOutputFileName.
  // GenerateFromConfig applies the same decoration after the config file is
  // merged, using the file's output path when --output was not passed.
  if FIncludePlatformInOutput and not FOutputExplicit and (Result.OutputPath <> '') then
    Result.OutputPath := TSbomConfig.DecorateOutputFileName(
      Result.OutputPath, Result.Platform, Result.Configuration);

  // Enable companion human-readable reports on demand. Issue #30.
  // README documented HTML/Markdown as output formats but they live in the
  // optional HumanReadableReport block, not in TSbomFormat. The CLI exposes
  // them via --report so users can turn them on without a config file.
  // When the flag was passed, including --report=none, it overrides the file.
  if scoReport in FExplicitOverrides then
  begin
    Result.HumanReadableReport.Enabled := FReportEnabled;
    Result.HumanReadableReport.Format  := FReportFormat;
  end;
  // Issue #126: report sections. Does not turn reports on by itself.
  if scoReportContent in FExplicitOverrides then
    Result.HumanReadableReport.Content := FReportContent;
  // Issue #132: folder grouping. Does not turn reports on by itself.
  if scoReportGroupByFolder in FExplicitOverrides then
    Result.HumanReadableReport.GroupByFolder := FReportGroupByFolder;
end;

end.
