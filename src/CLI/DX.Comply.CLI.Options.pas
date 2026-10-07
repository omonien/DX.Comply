/// <summary>
/// DX.Comply.CLI.Options
/// Command-line argument parsing for the dxcomply CLI tool.
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

type
  /// <summary>
  /// Parses command-line arguments for the dxcomply CLI and exposes them as
  /// typed properties. Call Parse, check the result and ParseError, then read
  /// the properties or call ToSbomConfig.
  /// </summary>
  TCliOptions = class
  private
    FProject: string;
    FFormat: TSbomFormat;
    FOutput: string;
    FPlatform: string;
    FPlatformExplicit: Boolean;
    FConfiguration: string;
    FConfigurationExplicit: Boolean;
    FProductName: string;
    FProductVersion: string;
    FSupplier: string;
    FIncludePatterns: TArray<string>;
    FExcludePatterns: TArray<string>;
    FCiMode: Boolean;
    FConfigFile: string;
    FHelp: Boolean;
    FShowVersion: Boolean;
    FVerbose: Boolean;
    FNoPause: Boolean;
    FMapDir: string;
    FNoCompositionEvidence: Boolean;
    FIncludePlatformInOutput: Boolean;
    FOutputExplicit: Boolean;
    FReportEnabled: Boolean;
    FReportFormat: THumanReadableReportFormat;
    FExplicitOverrides: TSbomConfigOverrides;
    FScanDirs: TArray<string>;
    FScanTree: Boolean;
    FDelphi7Root: string;
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
    /// <summary>
    /// Reads the current executable's fixed file version from its VersionInfo
    /// resource. Exposed for tests so CLI output can share the same source of
    /// truth as release metadata.
    /// </summary>
    class function ReadExecutableFileVersion: string; static;
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
    /// <summary>Writes the usage text to stdout.</summary>
    procedure PrintHelp;
    /// <summary>Writes the tool version line to stdout.</summary>
    procedure PrintVersion;
    /// <summary>
    /// Builds a TSbomConfig record populated from the parsed options.
    /// Call only after a successful Parse.
    /// </summary>
    function ToSbomConfig: TSbomConfig;

    property Project: string read FProject;
    property Format: TSbomFormat read FFormat;
    property Output: string read FOutput;
    property Platform: string read FPlatform;
    property Configuration: string read FConfiguration;
    property ProductName: string read FProductName;
    property ProductVersion: string read FProductVersion;
    property Supplier: string read FSupplier;
    property IncludePatterns: TArray<string> read FIncludePatterns;
    property ExcludePatterns: TArray<string> read FExcludePatterns;
    property CiMode: Boolean read FCiMode;
    property ConfigFile: string read FConfigFile;
    property Help: Boolean read FHelp;
    property ShowVersion: Boolean read FShowVersion;
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
    /// <summary>Extra binary directories from repeatable --scan-dir.</summary>
    property ScanDirs: TArray<string> read FScanDirs;
    /// <summary>True when --scan-tree was requested. Deprecated.</summary>
    property ScanTree: Boolean read FScanTree;
    /// <summary>Delphi 7 installation directory from --delphi7-root.</summary>
    property Delphi7Root: string read FDelphi7Root;
    property ParseError: string read FParseError;
  end;

implementation

uses
  Winapi.Windows;

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

  for I := 0 to High(AArgs) do
  begin
    LArg := AArgs[I];

    if (LArg = '--help') or (LArg = '-h') then
    begin
      FHelp := True;
      Continue;
    end;

    if LArg = '--version' then
    begin
      FShowVersion := True;
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

    // Deprecated recursive walk of the output directory. Kept for one release.
    if LArg = '--scan-tree' then
    begin
      FScanTree := True;
      Include(FExplicitOverrides, scoScanTree);
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

  if FShowVersion then
    Exit(True);

  // In CI mode with an explicit --config the project path is still required,
  // but we allow the caller to handle that after Parse returns.
  if FProject = '' then
  begin
    FParseError := '--project is required.';
    Exit(False);
  end;
end;

// ---------------------------------------------------------------------------
// PrintHelp / PrintVersion
// ---------------------------------------------------------------------------

procedure TCliOptions.PrintHelp;
begin
  PrintVersion;
  Writeln;
  Writeln('Usage:');
  Writeln('  dxcomply --project=<path> [options]');
  Writeln;
  Writeln('Options:');
  Writeln('  --project=<path>              Project file (required): .dproj, .dpr,');
  Writeln('                                .dpk, .bdsproj, or .groupproj');
  Writeln('  --format=<format>             Output format (default: cyclonedx-json)');
  Writeln('                                  cyclonedx-json | cyclonedx-xml | spdx-json');
  Writeln('  --output=<path>               Output file path (default: bom.json)');
  Writeln('  --platform=<name>             Target platform (default: Win32)');
  Writeln('                                File key: platform');
  Writeln('  --config-name=<name>          Build configuration (default: Release)');
  Writeln('                                File key: configName');
  Writeln('                                For .dpr, .dpk, and .bdsproj, --platform');
  Writeln('                                and --config-name are not applied.');
  Writeln('                                The defaults are not reported. A value');
  Writeln('                                you set is reported and ignored.');
  Writeln('  --product=<name>              Product name override');
  Writeln('  --version=<version>           Product version override');
  Writeln('  --supplier=<name>             Supplier/company name');
  Writeln('  --include=<pattern>           File include pattern (repeatable)');
  Writeln('  --exclude=<pattern>           File exclude pattern (repeatable)');
  Writeln('  --scan-dir=<path>             Also scan this directory for binaries');
  Writeln('                                (repeatable). A plain path is not recursive.');
  Writeln('                                A path that contains ** walks subdirectories.');
  Writeln('  --scan-tree                   Deprecated: recursively scan the output');
  Writeln('                                directory, as older versions did.');
  Writeln('                                Kept for one release. Prefer --scan-dir.');
  Writeln('  --map-dir=<path>              Directory containing the pre-built MAP file');
  Writeln('  --delphi7-root=<path>         Delphi 7 install directory (RootDir).');
  Writeln('                                Optional. Used to resolve library units');
  Writeln('                                for .dpr, .dpk, and .bdsproj projects.');
  Writeln('  --no-composition-evidence     Omit source/DCU units from SBOM (binary-only)');
  Writeln('  --include-platform-in-output  Append <Platform>.<Config> to the default');
  Writeln('                                output filename (e.g. bom.Win64.Release.json)');
  Writeln('                                Ignored when --output is supplied');
  Writeln('  --report[=<format>]           Generate companion human-readable report');
  Writeln('                                  markdown | html | both (default) | none');
  Writeln('  --ci                          CI mode: use .dxcomply.json config file');
  Writeln('  --config=<path>               Path to .dxcomply.json (default: .dxcomply.json)');
  Writeln('  --help, -h                    Show this help');
  Writeln('  --version                     Show tool version');
  Writeln('  --verbose                     Print all progress messages (default: errors only)');
  Writeln('  --no-pause                    Suppress "Press Enter to quit" prompt');
  Writeln;
  Writeln('Config file (--ci, when the file exists):');
  Writeln('  Built-in defaults are filled in first, then .dxcomply.json, then any');
  Writeln('  option you actually pass. A passed option wins over the file. An');
  Writeln('  option you omit keeps the file value (the default does not override');
  Writeln('  the file). Without --ci the file is not read.');
  Writeln;
  Writeln('Examples:');
  Writeln('  dxcomply --project=src\MyApp.dproj --format=cyclonedx-json --output=bom.json');
  Writeln('  dxcomply --project=src\MyApp.dpr --delphi7-root=C:\Delphi7 --no-pause');
  Writeln('  dxcomply --project=src\MyApp.dproj --ci --config=.dxcomply.json --no-pause');
  Writeln('  dxcomply --project=src\MyApp.dproj --ci --config-name=Debug --no-pause');
end;

class function TCliOptions.ReadExecutableFileVersion: string;
var
  LDummyHandle: DWORD;
  LExePath: string;
  LVersionBuffer: TBytes;
  LVersionDataSize: DWORD;
  LVersionInfo: PVSFixedFileInfo;
  LVersionLength: UINT;
begin
  Result := '';
  LExePath := ParamStr(0);
  if LExePath = '' then
    Exit;

  LVersionDataSize := GetFileVersionInfoSize(PChar(LExePath), LDummyHandle);
  if LVersionDataSize = 0 then
    Exit;

  SetLength(LVersionBuffer, LVersionDataSize);
  if not GetFileVersionInfo(PChar(LExePath), 0, LVersionDataSize, @LVersionBuffer[0]) then
    Exit;

  if not VerQueryValue(@LVersionBuffer[0], '\', Pointer(LVersionInfo), LVersionLength) or
    (LVersionLength < SizeOf(VS_FIXEDFILEINFO)) then
    Exit;

  Result := Format('%d.%d.%d.%d', [
    HiWord(LVersionInfo^.dwFileVersionMS),
    LoWord(LVersionInfo^.dwFileVersionMS),
    HiWord(LVersionInfo^.dwFileVersionLS),
    LoWord(LVersionInfo^.dwFileVersionLS)]);
end;

procedure TCliOptions.PrintVersion;
var
  LVersion: string;
begin
  LVersion := ReadExecutableFileVersion;
  if LVersion = '' then
    LVersion := 'unknown';

  Writeln('DX.Comply v' + LVersion);
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

function TCliOptions.ToSbomConfig: TSbomConfig;
begin
  Result := TSbomConfig.Default;
  Result.OutputPath      := FOutput;
  Result.Format          := FFormat;
  Result.Platform        := FPlatform;
  Result.PlatformExplicit := FPlatformExplicit;
  Result.Configuration   := FConfiguration;
  Result.ConfigurationExplicit := FConfigurationExplicit;
  Result.ProductName     := FProductName;
  Result.ProductVersion  := FProductVersion;
  Result.Supplier        := FSupplier;
  Result.IncludePatterns             := FIncludePatterns;
  Result.ExcludePatterns             := FExcludePatterns;
  Result.ScanDirs                    := FScanDirs;
  Result.ScanTree                    := FScanTree;
  Result.MapFileDir                  := FMapDir;
  Result.Delphi7Root                 := FDelphi7Root;
  Result.IncludeCompositionEvidence  := not FNoCompositionEvidence;
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
end;

end.
