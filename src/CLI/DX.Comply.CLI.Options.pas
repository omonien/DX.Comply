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
  DX.Comply.Engine.Intf;

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
    FConfiguration: string;
    FProductName: string;
    FProductVersion: string;
    FSupplier: string;
    FIncludePatterns: TArray<string>;
    FExcludePatterns: TArray<string>;
    FCiMode: Boolean;
    FConfigFile: string;
    FHelp: Boolean;
    FVerbose: Boolean;
    FNoPause: Boolean;
    FMapDir: string;
    FNoCompositionEvidence: Boolean;
    FParseError: string;
    /// <summary>
    /// Converts a format string token to the corresponding TSbomFormat enum
    /// value. Returns sfCycloneDxJson for unrecognised tokens.
    /// </summary>
    function ParseFormat(const AValue: string): TSbomFormat;
    /// <summary>Appends AValue to the given dynamic string array.</summary>
    procedure AppendPattern(var APatterns: TArray<string>; const AValue: string);
  public
    constructor Create;
    /// <summary>
    /// Parses the process ParamStr array and populates all properties.
    /// Returns True when parsing succeeded (or --help was requested).
    /// Returns False when a required argument is missing or an unknown flag
    /// is encountered; ParseError will contain the reason.
    /// </summary>
    function Parse: Boolean;
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
    property Verbose: Boolean read FVerbose;
    property NoPause: Boolean read FNoPause;
    property MapDir: string read FMapDir;
    property NoCompositionEvidence: Boolean read FNoCompositionEvidence;
    property ParseError: string read FParseError;
  end;

implementation

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
  I: Integer;
  LArg, LKey, LValue: string;
  LEqualsPos: Integer;
begin
  Result := True;
  FParseError := '';

  for I := 1 to ParamCount do
  begin
    LArg := ParamStr(I);

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
        FFormat := ParseFormat(LValue)
      else if LKey = 'output' then
        FOutput := LValue
      else if LKey = 'platform' then
        FPlatform := LValue
      else if LKey = 'config-name' then
        FConfiguration := LValue
      else if LKey = 'product' then
        FProductName := LValue
      else if LKey = 'version' then
        FProductVersion := LValue
      else if LKey = 'supplier' then
        FSupplier := LValue
      else if LKey = 'include' then
        AppendPattern(FIncludePatterns, LValue)
      else if LKey = 'exclude' then
        AppendPattern(FExcludePatterns, LValue)
      else if LKey = 'config' then
        FConfigFile := LValue
      else if LKey = 'map-dir' then
        FMapDir := LValue
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
  Writeln('  --project=<path>              Path to the .dproj file (required)');
  Writeln('  --format=<format>             Output format (default: cyclonedx-json)');
  Writeln('                                  cyclonedx-json | cyclonedx-xml | spdx-json');
  Writeln('  --output=<path>               Output file path (default: bom.json)');
  Writeln('  --platform=<Win32|Win64>      Target platform (default: Win32)');
  Writeln('  --config-name=<Debug|Release> Build configuration (default: Release)');
  Writeln('  --product=<name>              Product name override');
  Writeln('  --version=<version>           Product version override');
  Writeln('  --supplier=<name>             Supplier/company name');
  Writeln('  --include=<pattern>           File include pattern (repeatable)');
  Writeln('  --exclude=<pattern>           File exclude pattern (repeatable)');
  Writeln('  --map-dir=<path>              Directory containing the pre-built MAP file');
  Writeln('  --no-composition-evidence     Omit source/DCU units from SBOM (binary-only)');
  Writeln('  --ci                          CI mode: use .dxcomply.json config file');
  Writeln('  --config=<path>               Path to .dxcomply.json (default: .dxcomply.json)');
  Writeln('  --help, -h                    Show this help');
  Writeln('  --verbose                     Print all progress messages (default: errors only)');
  Writeln('  --no-pause                    Suppress "Press Enter to quit" prompt');
  Writeln;
  Writeln('Examples:');
  Writeln('  dxcomply --project=src\MyApp.dproj --format=cyclonedx-json --output=bom.json');
  Writeln('  dxcomply --project=src\MyApp.dproj --ci --config=.dxcomply.json --no-pause');
end;

procedure TCliOptions.PrintVersion;
begin
  Writeln('DX.Comply v1.3.0');
end;

// ---------------------------------------------------------------------------
// ToSbomConfig
// ---------------------------------------------------------------------------

function TCliOptions.ToSbomConfig: TSbomConfig;
begin
  Result := TSbomConfig.Default;
  Result.OutputPath      := FOutput;
  Result.Format          := FFormat;
  Result.Platform        := FPlatform;
  Result.Configuration   := FConfiguration;
  Result.ProductName     := FProductName;
  Result.ProductVersion  := FProductVersion;
  Result.Supplier        := FSupplier;
  Result.IncludePatterns             := FIncludePatterns;
  Result.ExcludePatterns             := FExcludePatterns;
  Result.MapFileDir                  := FMapDir;
  Result.IncludeCompositionEvidence  := not FNoCompositionEvidence;
end;

end.
