/// <summary>
/// DX.Comply.ProjectScanner
/// Scans and parses Delphi .dproj project files.
/// </summary>
///
/// <remarks>
/// This unit provides TProjectScanner which extracts metadata from .dproj files:
/// - Project name and version
/// - Platform and configuration settings
/// - Output directories
/// - Runtime package dependencies
///
/// Uses a lightweight regex-based XML reader that works in all environments
/// (IDE, CLI, test runners) without requiring MSXML or COM registration.
///
/// Edge cases handled:
/// - UTF-8 BOM in .dproj files
/// - Multi-platform projects (Win32, Win64, macOS, etc.)
/// - Config hierarchy mapping (Debug/Release to Cfg_N)
/// - Both .dproj and .dpk file extensions
/// - MSBuild variable replacement ($(Platform), $(Config), $(MSBuildProjectName))
/// - Missing/empty PropertyGroups with defensive fallbacks
/// - Forward/backslash normalization
/// </remarks>
///
/// <copyright>
/// Copyright (c) 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.ProjectScanner;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  DX.Comply.Engine.Intf;

type
  /// <summary>
  /// Implementation of IProjectScanner for scanning .dproj files.
  /// Uses regex-based parsing — no MSXML or COM dependencies.
  /// </summary>
  TProjectScanner = class(TInterfacedObject, IProjectScanner)
  private
    const
      cDefaultPlatform = 'Win32';
      cDefaultConfig = 'Debug';
      /// <summary>Valid Delphi project file extensions.</summary>
      cValidExtensions: array[0..2] of string = ('.dproj', '.dpk', '.groupproj');
  private
    FXmlText: string;
    FCurrentPlatform: string;
    FCurrentConfig: string;
    FConfigKey: string;
    FWarnings: TList<string>;
    /// <summary>
    /// Detects the Cfg_N key that corresponds to the requested configuration
    /// name (e.g. Debug -> Cfg_1, Release -> Cfg_2) by inspecting
    /// BuildConfiguration items.
    /// </summary>
    function DetectConfigKey(const AConfigName: string): string;
    /// <summary>
    /// Returns all PropertyGroup blocks whose Condition attribute contains
    /// ACondition (case-insensitive). If ACondition is empty, returns the first
    /// unconditional PropertyGroup. Returns all matches (not just the first).
    /// </summary>
    function GetPropertyGroupContents(const ACondition: string): TArray<string>;
    /// <summary>
    /// Returns the text content of the first PropertyGroup whose Condition
    /// attribute contains ACondition (case-insensitive). Empty string = any.
    /// </summary>
    function GetPropertyGroupContent(const ACondition: string): string;
    /// <summary>
    /// Reads the text content of element AName from AXmlBlock.
    /// </summary>
    function GetElementValue(const AXmlBlock, AName: string): string;
    /// <summary>
    /// Reads AName from property groups matching Base, platform, and config
    /// (later groups override earlier ones).
    /// </summary>
    function GetPropertyValue(const AName: string; const ADefault: string = ''): string;
    /// <summary>
    /// Extracts runtime packages from the DCC_UsePackage / RuntimePackage element.
    /// </summary>
    function ExtractRuntimePackages: TList<string>;
    /// <summary>
    /// Replaces MSBuild variable tokens with actual platform/config values.
    /// </summary>
    function NormalizePath(const APath, AProjectName: string): string;
    /// <summary>
    /// Resolves a configured build path to a normalized absolute path.
    /// </summary>
    function ResolveBuildPath(const ARawPath, AProjectDir, AProjectName: string): string;
    /// <summary>
    /// Adds semicolon-delimited values to a list, optionally normalizing them as paths.
    /// </summary>
    procedure AddDelimitedValues(const AValue: string; const AValues: TList<string>;
      const AProjectDir, AProjectName: string; ANormalizeAsPath: Boolean);
    /// <summary>
    /// Extracts the effective unit search paths for the current platform/configuration.
    /// </summary>
    function ExtractSearchPaths(const AProjectDir, AProjectName: string): TList<string>;
    /// <summary>
    /// Extracts the effective unit scope names for the current platform/configuration.
    /// </summary>
    function ExtractUnitScopeNames: TList<string>;
    /// <summary>
    /// Attempts to detect the TargetedPlatforms bitmask and returns
    /// a list of platform names (Win32, Win64, etc.).
    /// </summary>
    function DetectTargetedPlatforms: TArray<string>;
    /// <summary>
    /// Loads the .dproj file content, handling BOM and encoding correctly.
    /// </summary>
    procedure LoadProjectFile(const AProjectPath: string);
  public
    constructor Create;
    destructor Destroy; override;
    // IProjectScanner
    function Scan(const AProjectPath, APlatform, AConfiguration: string): TProjectInfo;
    function Validate(const AProjectPath: string): Boolean;
  end;

implementation

{ TProjectScanner }

procedure TProjectScanner.AddDelimitedValues(const AValue: string; const AValues: TList<string>;
  const AProjectDir, AProjectName: string; ANormalizeAsPath: Boolean);
var
  LItem: string;
  LItems: TArray<string>;
begin
  if not Assigned(AValues) then
    Exit;

  if Trim(AValue) = '' then
    Exit;

  LItems := AValue.Split([';']);
  for LItem in LItems do
  begin
    LItem := Trim(LItem);
    if LItem = '' then
      Continue;

    if LItem[1] = '$' then
      Continue;

    if ANormalizeAsPath then
    begin
      LItem := NormalizePath(LItem, AProjectName);
      if (LItem <> '') and TPath.IsRelativePath(LItem) then
        LItem := TPath.Combine(AProjectDir, LItem);

      try
        LItem := TPath.GetFullPath(LItem);
      except
        FWarnings.Add('Could not resolve search path: ' + LItem);
      end;
    end;

    if not AValues.Contains(LItem) then
      AValues.Add(LItem);
  end;
end;

constructor TProjectScanner.Create;
begin
  inherited Create;
  FWarnings := TList<string>.Create;
end;

destructor TProjectScanner.Destroy;
begin
  FWarnings.Free;
  inherited;
end;

procedure TProjectScanner.LoadProjectFile(const AProjectPath: string);
var
  LContent: TStringList;
  LBytes: TBytes;
  LEncoding: TEncoding;
begin
  // Try loading with automatic BOM detection first
  LContent := TStringList.Create;
  try
    // Read raw bytes to detect encoding
    LBytes := TFile.ReadAllBytes(AProjectPath);

    // Detect BOM
    LEncoding := nil;
    TEncoding.GetBufferEncoding(LBytes, LEncoding, TEncoding.UTF8);

    LContent.LoadFromFile(AProjectPath, LEncoding);
    FXmlText := LContent.Text;

    // Remove BOM character if still present at the start
    if (Length(FXmlText) > 0) and (Ord(FXmlText[1]) = $FEFF) then
      FXmlText := FXmlText.Substring(1);
  finally
    LContent.Free;
  end;
end;

function TProjectScanner.DetectConfigKey(const AConfigName: string): string;
var
  LPattern: string;
  LMatches: TMatchCollection;
  LMatch: TMatch;
  LInclude, LKey: string;
begin
  // Default mapping: Debug = Cfg_1, Release = Cfg_2
  Result := '';
  if SameText(AConfigName, 'Debug') then
    Result := 'Cfg_1'
  else if SameText(AConfigName, 'Release') then
    Result := 'Cfg_2';

  // Try to find the actual mapping from BuildConfiguration items
  // Pattern: <BuildConfiguration Include="Debug"><Key>Cfg_1</Key>
  LPattern := '<BuildConfiguration\s+Include="([^"]*)"[^>]*>.*?<Key>([^<]*)</Key>.*?</BuildConfiguration>';
  LMatches := TRegEx.Matches(FXmlText, LPattern, [roIgnoreCase, roSingleLine]);

  for LMatch in LMatches do
  begin
    if LMatch.Groups.Count >= 3 then
    begin
      LInclude := LMatch.Groups[1].Value;
      LKey := LMatch.Groups[2].Value;
      if SameText(LInclude, AConfigName) then
      begin
        Result := LKey;
        Exit;
      end;
    end;
  end;

  // If config name not found in BuildConfiguration, check if it's a custom config
  if Result = '' then
  begin
    FWarnings.Add('Configuration "' + AConfigName +
      '" not found in BuildConfiguration items. Using heuristic mapping.');
    // Fall back to searching for properties with the config name in conditions
    Result := AConfigName;
  end;
end;

function TProjectScanner.DetectTargetedPlatforms: TArray<string>;
var
  LValue: string;
  LBitmask: Integer;
  LPlatforms: TList<string>;
begin
  LValue := GetElementValue(FXmlText, 'TargetedPlatforms');
  LPlatforms := TList<string>.Create;
  try
    if LValue <> '' then
    begin
      LBitmask := StrToIntDef(LValue, 1);
      if (LBitmask and 1) <> 0 then LPlatforms.Add('Win32');
      if (LBitmask and 2) <> 0 then LPlatforms.Add('Win64');
      if (LBitmask and 4) <> 0 then LPlatforms.Add('OSX32');
      if (LBitmask and 8) <> 0 then LPlatforms.Add('iOSSimulator');
      if (LBitmask and 16) <> 0 then LPlatforms.Add('iOSDevice32');
      if (LBitmask and 32) <> 0 then LPlatforms.Add('Android32');
      if (LBitmask and 64) <> 0 then LPlatforms.Add('Linux64');
      if (LBitmask and 128) <> 0 then LPlatforms.Add('iOSDevice64');
      if (LBitmask and 256) <> 0 then LPlatforms.Add('Android64');
      if (LBitmask and 512) <> 0 then LPlatforms.Add('OSX64');
      if (LBitmask and 1024) <> 0 then LPlatforms.Add('OSXARM64');
    end;

    if LPlatforms.Count = 0 then
      LPlatforms.Add('Win32'); // Default fallback

    Result := LPlatforms.ToArray;
  finally
    LPlatforms.Free;
  end;
end;

function TProjectScanner.GetPropertyGroupContents(const ACondition: string): TArray<string>;
var
  LPattern: string;
  LMatch: TMatch;
  LConditionMatch: TMatch;
  LMatches: TMatchCollection;
  LResult: TList<string>;
begin
  LResult := TList<string>.Create;
  try
    LPattern := '<PropertyGroup(?:\s[^>]*)?>.*?</PropertyGroup>';
    LMatches := TRegEx.Matches(FXmlText, LPattern, [roIgnoreCase, roSingleLine]);

    for LMatch in LMatches do
    begin
      if ACondition = '' then
      begin
        // Return first unconditional PropertyGroup
        LConditionMatch := TRegEx.Match(LMatch.Value, 'Condition\s*=\s*"', [roIgnoreCase]);
        if not LConditionMatch.Success then
        begin
          LResult.Add(LMatch.Value);
          Break;
        end;
        Continue;
      end;

      LConditionMatch := TRegEx.Match(LMatch.Value,
        'Condition\s*=\s*"([^"]*)"', [roIgnoreCase]);
      if LConditionMatch.Success then
      begin
        if Pos(UpperCase(ACondition), UpperCase(LConditionMatch.Groups[1].Value)) > 0 then
          LResult.Add(LMatch.Value);
      end;
    end;

    Result := LResult.ToArray;
  finally
    LResult.Free;
  end;
end;

function TProjectScanner.GetPropertyGroupContent(const ACondition: string): string;
var
  LPattern: string;
  LMatch: TMatch;
  LConditionMatch: TMatch;
  LMatches: TMatchCollection;
begin
  Result := '';
  LPattern := '<PropertyGroup(?:\s[^>]*)?>.*?</PropertyGroup>';
  LMatches := TRegEx.Matches(FXmlText, LPattern, [roIgnoreCase, roSingleLine]);

  for LMatch in LMatches do
  begin
    if ACondition = '' then
    begin
      Result := LMatch.Value;
      Exit;
    end;

    LConditionMatch := TRegEx.Match(LMatch.Value,
      'Condition\s*=\s*"([^"]*)"', [roIgnoreCase]);
    if LConditionMatch.Success then
    begin
      if Pos(UpperCase(ACondition), UpperCase(LConditionMatch.Groups[1].Value)) > 0 then
      begin
        Result := LMatch.Value;
        Exit;
      end;
    end;
  end;
end;

function TProjectScanner.GetElementValue(const AXmlBlock, AName: string): string;
var
  LPattern: string;
  LMatch: TMatch;
begin
  Result := '';
  if AXmlBlock = '' then
    Exit;

  // Match <Name>value</Name> — handles optional namespace prefix and attributes
  LPattern := '<(?:\w+:)?' + TRegEx.Escape(AName) +
              '(?:\s[^>]*)?>([^<]*)</(?:\w+:)?' + TRegEx.Escape(AName) + '>';
  LMatch := TRegEx.Match(AXmlBlock, LPattern, [roIgnoreCase]);
  if LMatch.Success then
    Result := Trim(LMatch.Groups[1].Value);
end;

function TProjectScanner.GetPropertyValue(const AName, ADefault: string): string;
var
  LBlock, LValue: string;
  LBlocks: TArray<string>;
  I: Integer;
begin
  Result := ADefault;

  // 1. Base PropertyGroup (Condition contains '$(Base)')
  LBlocks := GetPropertyGroupContents('$(Base)');
  for I := 0 to High(LBlocks) do
  begin
    LBlock := LBlocks[I];
    // Skip Base_ groups (Base_Win32 etc.) — they are handled in step 2
    if (Pos('Base_', LBlock) > 0) and (Pos('''$(Base)''!=''''', LBlock) = 0) then
      Continue;
    LValue := GetElementValue(LBlock, AName);
    if LValue <> '' then
      Result := LValue;
  end;

  // 2. Platform-specific (Condition contains '$(Base_Win32)' etc.)
  if FCurrentPlatform <> '' then
  begin
    LBlock := GetPropertyGroupContent('$(Base_' + FCurrentPlatform + ')');
    if LBlock <> '' then
    begin
      LValue := GetElementValue(LBlock, AName);
      if LValue <> '' then
        Result := LValue;
    end;
  end;

  // 3. Config-specific — use the detected Cfg_N key
  if FConfigKey <> '' then
  begin
    LBlock := GetPropertyGroupContent('$(' + FConfigKey + ')');
    if LBlock <> '' then
    begin
      LValue := GetElementValue(LBlock, AName);
      if LValue <> '' then
        Result := LValue;
    end;
  end;

  // 4. Platform+Config specific (e.g., Base_Win32 + Cfg_1)
  if (FCurrentPlatform <> '') and (FConfigKey <> '') then
  begin
    LBlocks := GetPropertyGroupContents(FConfigKey + '_' + FCurrentPlatform);
    for I := 0 to High(LBlocks) do
    begin
      LValue := GetElementValue(LBlocks[I], AName);
      if LValue <> '' then
        Result := LValue;
    end;
  end;
end;

function TProjectScanner.ExtractRuntimePackages: TList<string>;
var
  LPackages: TList<string>;
  LBlock, LPackageStr: string;
  LPackageArray: TArray<string>;
  I: Integer;
begin
  LPackages := TList<string>.Create;

  // DCC_UsePackage in base PropertyGroup
  LBlock := GetPropertyGroupContent('$(Base)');
  LPackageStr := GetElementValue(LBlock, 'DCC_UsePackage');
  if LPackageStr = '' then
    LPackageStr := GetElementValue(FXmlText, 'RuntimePackage');

  // Also check platform-specific UsePackage
  if FCurrentPlatform <> '' then
  begin
    LBlock := GetPropertyGroupContent('$(Base_' + FCurrentPlatform + ')');
    if LBlock <> '' then
    begin
      var LPlatformPackages := GetElementValue(LBlock, 'DCC_UsePackage');
      if LPlatformPackages <> '' then
      begin
        if LPackageStr <> '' then
          LPackageStr := LPackageStr + ';' + LPlatformPackages
        else
          LPackageStr := LPlatformPackages;
      end;
    end;
  end;

  if LPackageStr <> '' then
  begin
    LPackageArray := LPackageStr.Split([';']);
    for I := 0 to High(LPackageArray) do
    begin
      LPackageStr := Trim(LPackageArray[I]);
      // Strip MSBuild variable references like $(DCC_UsePackage)
      if (LPackageStr <> '') and (LPackageStr[1] <> '$') then
      begin
        // Avoid duplicates
        if not LPackages.Contains(LPackageStr) then
          LPackages.Add(LPackageStr);
      end;
    end;
  end;

  Result := LPackages;
end;

function TProjectScanner.ExtractSearchPaths(const AProjectDir, AProjectName: string): TList<string>;
var
  LSearchPathValue: string;
begin
  Result := TList<string>.Create;
  LSearchPathValue := GetPropertyValue('DCC_UnitSearchPath', '');
  AddDelimitedValues(LSearchPathValue, Result, AProjectDir, AProjectName, True);
end;

function TProjectScanner.ExtractUnitScopeNames: TList<string>;
var
  LNamespaceValue: string;
begin
  Result := TList<string>.Create;
  LNamespaceValue := GetPropertyValue('DCC_Namespace', '');
  AddDelimitedValues(LNamespaceValue, Result, '', '', False);
end;

function TProjectScanner.NormalizePath(const APath, AProjectName: string): string;
var
  LPath: string;
begin
  LPath := APath;
  // Standard MSBuild variables
  LPath := StringReplace(LPath, '$(Platform)', FCurrentPlatform, [rfIgnoreCase, rfReplaceAll]);
  LPath := StringReplace(LPath, '$(Config)', FCurrentConfig, [rfIgnoreCase, rfReplaceAll]);
  LPath := StringReplace(LPath, '$(Configuration)', FCurrentConfig, [rfIgnoreCase, rfReplaceAll]);
  LPath := StringReplace(LPath, '$(MSBuildProjectName)', AProjectName, [rfIgnoreCase, rfReplaceAll]);
  LPath := StringReplace(LPath, '$(ProjectName)', AProjectName, [rfIgnoreCase, rfReplaceAll]);
  // Normalize path separators
  LPath := StringReplace(LPath, '/', '\', [rfReplaceAll]);
  // Remove trailing backslash
  if (LPath <> '') and (LPath[Length(LPath)] = '\') then
    LPath := Copy(LPath, 1, Length(LPath) - 1);
  Result := LPath;
end;

function TProjectScanner.ResolveBuildPath(const ARawPath, AProjectDir, AProjectName: string): string;
var
  LPath: string;
begin
  Result := '';
  if Trim(ARawPath) = '' then
    Exit;

  LPath := NormalizePath(ARawPath, AProjectName);
  if (LPath <> '') and TPath.IsRelativePath(LPath) then
    LPath := TPath.Combine(AProjectDir, LPath);

  try
    Result := TPath.GetFullPath(LPath);
  except
    Result := LPath;
    FWarnings.Add('Could not resolve output path: ' + LPath);
  end;
end;

function TProjectScanner.Scan(const AProjectPath, APlatform, AConfiguration: string): TProjectInfo;
var
  LBplOutputDir: string;
  LDcpOutputDir: string;
  LDcuOutputDir: string;
  LExeOutputDir: string;
  LVersionStr: string;
  LMajor, LMinor, LRelease, LBuild: string;
  LWarning: string;
begin
  FWarnings.Clear;
  Result := TProjectInfo.Create;
  try
    Result.ProjectPath := AProjectPath;
    Result.ProjectDir := TPath.GetDirectoryName(AProjectPath);
    Result.ProjectName := TPath.GetFileNameWithoutExtension(AProjectPath);

    if APlatform <> '' then
      FCurrentPlatform := APlatform
    else
      FCurrentPlatform := cDefaultPlatform;

    if AConfiguration <> '' then
      FCurrentConfig := AConfiguration
    else
      FCurrentConfig := cDefaultConfig;

    Result.Platform := FCurrentPlatform;
    Result.Configuration := FCurrentConfig;

    // Load the .dproj file with BOM-aware encoding detection
    LoadProjectFile(AProjectPath);

    // Detect the Cfg_N key for the requested configuration
    FConfigKey := DetectConfigKey(FCurrentConfig);

    // Extract version — try VerInfo_MajorVer first (newer format), then MajorVer
    LMajor := GetPropertyValue('VerInfo_MajorVer', '');
    if LMajor = '' then
      LMajor := GetPropertyValue('MajorVer', '1');

    LMinor := GetPropertyValue('VerInfo_MinorVer', '');
    if LMinor = '' then
      LMinor := GetPropertyValue('MinorVer', '0');

    LRelease := GetPropertyValue('VerInfo_Release', '');
    if LRelease = '' then
      LRelease := GetPropertyValue('Release', '0');

    LBuild := GetPropertyValue('VerInfo_Build', '');
    if LBuild = '' then
      LBuild := GetPropertyValue('Build', '0');

    Result.Version := LMajor + '.' + LMinor + '.' + LRelease + '.' + LBuild;

    // Also try FileVersion directly (some projects specify it as a single string)
    LVersionStr := GetPropertyValue('FileVersion', '');
    if (LVersionStr <> '') and (Pos('.', LVersionStr) > 0) then
      Result.Version := LVersionStr;

    // Extract output directory — try multiple common elements
    LExeOutputDir := ResolveBuildPath(GetPropertyValue('DCC_ExeOutput', ''),
      Result.ProjectDir, Result.ProjectName);
    LBplOutputDir := ResolveBuildPath(GetPropertyValue('DCC_BplOutput', ''),
      Result.ProjectDir, Result.ProjectName);
    LDcpOutputDir := ResolveBuildPath(GetPropertyValue('DCC_DcpOutput', ''),
      Result.ProjectDir, Result.ProjectName);
    LDcuOutputDir := ResolveBuildPath(GetPropertyValue('DCC_DcuOutput', ''),
      Result.ProjectDir, Result.ProjectName);

    Result.BplOutputDir := LBplOutputDir;
    Result.DcpOutputDir := LDcpOutputDir;
    Result.DcuOutputDir := LDcuOutputDir;

    Result.OutputDir := LExeOutputDir;
    if Result.OutputDir = '' then
      Result.OutputDir := Result.BplOutputDir;
    if Result.OutputDir = '' then
      Result.OutputDir := Result.DcpOutputDir;
    if Result.OutputDir = '' then
      Result.OutputDir := Result.DcuOutputDir;

    if Result.OutputDir = '' then
    begin
      // Fallback to standard project structure
      Result.OutputDir := ResolveBuildPath('..\build\$(Platform)\$(Config)',
        Result.ProjectDir, Result.ProjectName);
      FWarnings.Add('No output directory found in .dproj. Using default: ..\build\$(Platform)\$(Config)');
    end;

    // Extract search paths and namespace scopes
    if Assigned(Result.SearchPaths) then
      Result.SearchPaths.Free;
    Result.SearchPaths := ExtractSearchPaths(Result.ProjectDir, Result.ProjectName);

    if Assigned(Result.UnitScopeNames) then
      Result.UnitScopeNames.Free;
    Result.UnitScopeNames := ExtractUnitScopeNames;

    // Extract runtime packages
    if Assigned(Result.RuntimePackages) then
      Result.RuntimePackages.Free;
    Result.RuntimePackages := ExtractRuntimePackages;

    for LWarning in FWarnings do
      Result.Warnings.Add(LWarning);
  except
    on E: Exception do
    begin
      Result.Free;
      raise;
    end;
  end;
end;

function TProjectScanner.Validate(const AProjectPath: string): Boolean;
var
  LExt: string;
  I: Integer;
  LIsValidExt: Boolean;
begin
  Result := False;
  if not TFile.Exists(AProjectPath) then
    Exit;

  LExt := LowerCase(TPath.GetExtension(AProjectPath));
  LIsValidExt := False;
  for I := 0 to High(cValidExtensions) do
  begin
    if LExt = cValidExtensions[I] then
    begin
      LIsValidExt := True;
      Break;
    end;
  end;

  Result := LIsValidExt;
end;

end.
