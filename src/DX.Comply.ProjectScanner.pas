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
  System.Win.Registry,
  Winapi.Windows,
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
    /// Builds the expected map file path for the selected project build.
    /// </summary>
    function BuildExpectedMapFilePath(const AProjectInfo: TProjectInfo): string;
    /// <summary>
    /// Adds semicolon-delimited values to a list, optionally normalizing them as paths.
    /// </summary>
    procedure AddDelimitedValues(const AValue: string; const AValues: TList<string>;
      const AProjectDir, AProjectName: string; ANormalizeAsPath: Boolean);
    /// <summary>
    /// Adds a path to the list only when it exists and is not already present.
    /// </summary>
    procedure AddExistingPath(const APath: string; const AValues: TList<string>);
    /// <summary>
    /// Adds a project unit reference if it is not already present.
    /// </summary>
    procedure AddProjectUnitReference(const AReference: TProjectUnitReference;
      const AReferences: TProjectUnitReferenceList);
    /// <summary>
    /// Copies unique string values from one list into another.
    /// </summary>
    procedure CopyUniqueValues(const ASource, ATarget: TList<string>);
    /// <summary>
    /// Builds global Delphi library/source search roots for the detected toolchain.
    /// </summary>
    function BuildGlobalSearchPaths(const AToolchain: TDelphiToolchainInfo;
      AUsesDebugDCUs: Boolean): TList<string>;
    /// <summary>
    /// Detects the latest installed Delphi version from the registry.
    /// </summary>
    function DetectLatestInstalledBdsVersion: string;
    /// <summary>
    /// Detects Delphi toolchain metadata for the current machine.
    /// </summary>
    function DetectToolchainInfo: TDelphiToolchainInfo;
    /// <summary>
    /// Extracts DCCReference include paths from the .dproj file.
    /// </summary>
    function ExtractDprojUnitReferences(const AProjectDir, AProjectName: string): TProjectUnitReferenceList;
    /// <summary>
    /// Extracts explicit unit references from all available project metadata sources.
    /// </summary>
    function ExtractExplicitUnitReferences(const AProjectPath, AProjectDir,
      AProjectName, AMainSourcePath: string): TProjectUnitReferenceList;
    /// <summary>
    /// Extracts explicit unit references from the main .dpr / .dpk source file.
    /// </summary>
    function ExtractMainSourceUnitReferences(const AMainSourcePath, AProjectDir,
      AProjectName: string): TProjectUnitReferenceList;
    /// <summary>
    /// Resolves the main source file of the project.
    /// </summary>
    function ExtractMainSourcePath(const AProjectPath, AProjectDir, AProjectName: string): string;
    /// <summary>
    /// Extracts the effective unit search paths for the current platform/configuration.
    /// </summary>
    function ExtractSearchPaths(const AProjectDir, AProjectName: string): TList<string>;
    /// <summary>
    /// Determines whether the selected build uses Delphi debug DCUs.
    /// </summary>
    function ExtractUseDebugDCUs: Boolean;
    /// <summary>
    /// Returns the root directory of the supplied Delphi version.
    /// </summary>
    function GetBdsRootDirForVersion(const AVersion: string): string;
    /// <summary>
    /// Extracts the effective unit scope names for the current platform/configuration.
    /// </summary>
    function ExtractUnitScopeNames: TList<string>;
    /// <summary>
    /// Reads the fixed file version of the specified executable.
    /// </summary>
    function GetFileVersionText(const AFilePath: string): string;
    /// <summary>
    /// Attempts to detect the TargetedPlatforms bitmask and returns
    /// a list of platform names (Win32, Win64, etc.).
    /// </summary>
    function DetectTargetedPlatforms: TArray<string>;
    /// <summary>
    /// Loads the .dproj file content, handling BOM and encoding correctly.
    /// </summary>
    procedure LoadProjectFile(const AProjectPath: string);
    /// <summary>
    /// Normalizes and resolves explicit project unit paths.
    /// </summary>
    function ResolveUnitReferencePath(const APath, AProjectDir, AProjectName: string): string;
  public
    constructor Create;
    destructor Destroy; override;
    // IProjectScanner
    function Scan(const AProjectPath, APlatform, AConfiguration: string): TProjectInfo;
    function Validate(const AProjectPath: string): Boolean;
  end;

implementation

{ TProjectScanner }

procedure TProjectScanner.AddExistingPath(const APath: string; const AValues: TList<string>);
var
  LResolvedPath: string;
begin
  if not Assigned(AValues) then
    Exit;

  LResolvedPath := Trim(APath);
  if (LResolvedPath = '') or not TDirectory.Exists(LResolvedPath) then
    Exit;

  if not AValues.Contains(LResolvedPath) then
    AValues.Add(LResolvedPath);
end;

procedure TProjectScanner.AddDelimitedValues(const AValue: string; const AValues: TList<string>;
  const AProjectDir, AProjectName: string; ANormalizeAsPath: Boolean);
var
  LItem: string;
  LResolvedItem: string;
  LItems: TArray<string>;
begin
  if not Assigned(AValues) then
    Exit;

  if Trim(AValue) = '' then
    Exit;

  LItems := AValue.Split([';']);
  for LItem in LItems do
  begin
    LResolvedItem := Trim(LItem);
    if LResolvedItem = '' then
      Continue;

    if LResolvedItem[1] = '$' then
      Continue;

    if ANormalizeAsPath then
    begin
      LResolvedItem := NormalizePath(LResolvedItem, AProjectName);
      if (LResolvedItem <> '') and TPath.IsRelativePath(LResolvedItem) then
        LResolvedItem := TPath.Combine(AProjectDir, LResolvedItem);

      try
        LResolvedItem := TPath.GetFullPath(LResolvedItem);
      except
        FWarnings.Add('Could not resolve search path: ' + LResolvedItem);
      end;
    end;

    if not AValues.Contains(LResolvedItem) then
      AValues.Add(LResolvedItem);
  end;
end;

procedure TProjectScanner.AddProjectUnitReference(const AReference: TProjectUnitReference;
  const AReferences: TProjectUnitReferenceList);
var
  LExistingReference: TProjectUnitReference;
begin
  if not Assigned(AReferences) or (Trim(AReference.UnitName) = '') then
    Exit;

  for LExistingReference in AReferences do
  begin
    if SameText(LExistingReference.UnitName, AReference.UnitName) and
       SameText(LExistingReference.FilePath, AReference.FilePath) then
      Exit;
  end;

  AReferences.Add(AReference);
end;

procedure TProjectScanner.CopyUniqueValues(const ASource, ATarget: TList<string>);
var
  LValue: string;
begin
  if not Assigned(ASource) or not Assigned(ATarget) then
    Exit;

  for LValue in ASource do
  begin
    if not ATarget.Contains(LValue) then
      ATarget.Add(LValue);
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

    // Detect BOM — fall back to system default (ANSI) for legacy .dproj files
    // that were saved without BOM by older Delphi versions.
    LEncoding := nil;
    TEncoding.GetBufferEncoding(LBytes, LEncoding, TEncoding.Default);

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

function TProjectScanner.DetectLatestInstalledBdsVersion: string;
var
  LMajor: Integer;
  LMaxMajor: Integer;
  LRegistry: TRegistry;
  LVersionName: string;
  LVersionNames: TStringList;
  procedure CollectVersions(const AAccess: REGSAM);
  begin
    LRegistry.Access := KEY_READ or AAccess;
    if not LRegistry.OpenKeyReadOnly('\SOFTWARE\Embarcadero\BDS') then
      Exit;
    try
      LRegistry.GetKeyNames(LVersionNames);
    finally
      LRegistry.CloseKey;
    end;
  end;
begin
  Result := '';
  LMaxMajor := -1;
  LRegistry := TRegistry.Create;
  LVersionNames := TStringList.Create;
  try
    LRegistry.RootKey := HKEY_LOCAL_MACHINE;
    CollectVersions(KEY_WOW64_32KEY);
    CollectVersions(KEY_WOW64_64KEY);

    for LVersionName in LVersionNames do
    begin
      LMajor := StrToIntDef(LVersionName.Split(['.'])[0], -1);
      if LMajor > LMaxMajor then
      begin
        LMaxMajor := LMajor;
        Result := LVersionName;
      end;
    end;
  finally
    LVersionNames.Free;
    LRegistry.Free;
  end;
end;

function TProjectScanner.DetectToolchainInfo: TDelphiToolchainInfo;
var
  LBdsPath: string;
  LVersion: string;
begin
  Result := Default(TDelphiToolchainInfo);

  LBdsPath := Trim(GetEnvironmentVariable('BDS'));
  if (LBdsPath <> '') and TDirectory.Exists(LBdsPath) then
  begin
    Result.RootDir := ExcludeTrailingPathDelimiter(TPath.GetFullPath(LBdsPath));
    Result.Version := TPath.GetFileName(Result.RootDir);
  end
  else
  begin
    LVersion := DetectLatestInstalledBdsVersion;
    Result.RootDir := GetBdsRootDirForVersion(LVersion);
    Result.Version := LVersion;
  end;

  if Result.RootDir = '' then
    Exit;

  if Result.Version = '' then
    Result.Version := TPath.GetFileName(Result.RootDir);

  Result.ProductName := 'Embarcadero Delphi';
  Result.BuildVersion := GetFileVersionText(TPath.Combine(Result.RootDir, 'bin\bds.exe'));
end;

function TProjectScanner.ExtractDprojUnitReferences(const AProjectDir,
  AProjectName: string): TProjectUnitReferenceList;
var
  LIncludePath: string;
  LMatch: TMatch;
  LMatches: TMatchCollection;
  LReference: TProjectUnitReference;
begin
  Result := TProjectUnitReferenceList.Create;
  LMatches := TRegEx.Matches(FXmlText,
    '<DCCReference\s+Include="([^"]+\.pas)"\s*/?>', [roIgnoreCase, roSingleLine]);
  for LMatch in LMatches do
  begin
    if LMatch.Groups.Count < 2 then
      Continue;

    LIncludePath := Trim(LMatch.Groups[1].Value);
    LReference := Default(TProjectUnitReference);
    LReference.UnitName := TPath.GetFileNameWithoutExtension(LIncludePath);
    LReference.FilePath := ResolveUnitReferencePath(LIncludePath, AProjectDir, AProjectName);
    LReference.Source := 'DPROJ';
    AddProjectUnitReference(LReference, Result);
  end;
end;

function TProjectScanner.ExtractExplicitUnitReferences(const AProjectPath, AProjectDir,
  AProjectName, AMainSourcePath: string): TProjectUnitReferenceList;
var
  LReference: TProjectUnitReference;
  LReferences: TProjectUnitReferenceList;
begin
  Result := TProjectUnitReferenceList.Create;

  if SameText(TPath.GetExtension(AProjectPath), '.dproj') then
  begin
    LReferences := ExtractDprojUnitReferences(AProjectDir, AProjectName);
    try
      for LReference in LReferences do
        AddProjectUnitReference(LReference, Result);
    finally
      LReferences.Free;
    end;
  end;

  LReferences := ExtractMainSourceUnitReferences(AMainSourcePath, AProjectDir, AProjectName);
  try
    for LReference in LReferences do
      AddProjectUnitReference(LReference, Result);
  finally
    LReferences.Free;
  end;
end;

function TProjectScanner.ExtractMainSourcePath(const AProjectPath, AProjectDir,
  AProjectName: string): string;
var
  LCandidatePath: string;
  LExtension: string;
begin
  Result := '';
  LExtension := LowerCase(TPath.GetExtension(AProjectPath));
  if (LExtension = '.dpr') or (LExtension = '.dpk') then
    Exit(TPath.GetFullPath(AProjectPath));

  LCandidatePath := GetElementValue(FXmlText, 'MainSource');
  if LCandidatePath <> '' then
    Result := ResolveUnitReferencePath(LCandidatePath, AProjectDir, AProjectName);

  if (Result <> '') and TFile.Exists(Result) then
    Exit;

  LCandidatePath := TPath.Combine(AProjectDir, AProjectName + '.dpr');
  if TFile.Exists(LCandidatePath) then
    Exit(TPath.GetFullPath(LCandidatePath));

  LCandidatePath := TPath.Combine(AProjectDir, AProjectName + '.dpk');
  if TFile.Exists(LCandidatePath) then
    Exit(TPath.GetFullPath(LCandidatePath));

  Result := '';
end;

function TProjectScanner.ExtractMainSourceUnitReferences(const AMainSourcePath,
  AProjectDir, AProjectName: string): TProjectUnitReferenceList;
var
  LContent: string;
  LMatch: TMatch;
  LMatches: TMatchCollection;
  LReference: TProjectUnitReference;
begin
  Result := TProjectUnitReferenceList.Create;
  if (Trim(AMainSourcePath) = '') or not TFile.Exists(AMainSourcePath) then
    Exit;

  LContent := TFile.ReadAllText(AMainSourcePath, TEncoding.UTF8);
  LMatches := TRegEx.Matches(LContent,
    '([A-Za-z0-9_.]+)\s+in\s+''([^'']+\.(?:pas|dcu|dcp|bpl))''',
    [roIgnoreCase, roSingleLine]);

  for LMatch in LMatches do
  begin
    if LMatch.Groups.Count < 3 then
      Continue;

    LReference := Default(TProjectUnitReference);
    LReference.UnitName := Trim(LMatch.Groups[1].Value);
    LReference.FilePath := ResolveUnitReferencePath(LMatch.Groups[2].Value,
      AProjectDir, AProjectName);
    LReference.Source := 'MainSource';
    AddProjectUnitReference(LReference, Result);
  end;
end;

function TProjectScanner.BuildGlobalSearchPaths(const AToolchain: TDelphiToolchainInfo;
  AUsesDebugDCUs: Boolean): TList<string>;
var
  LAlternateConfigDir: string;
  LBaseLibDir: string;
  LPreferredConfigDir: string;
begin
  Result := TList<string>.Create;
  if Trim(AToolchain.RootDir) = '' then
    Exit;

  LBaseLibDir := TPath.Combine(AToolchain.RootDir, 'lib\' + FCurrentPlatform);
  if AUsesDebugDCUs then
  begin
    LPreferredConfigDir := TPath.Combine(LBaseLibDir, 'debug');
    LAlternateConfigDir := TPath.Combine(LBaseLibDir, 'release');
  end
  else
  begin
    LPreferredConfigDir := TPath.Combine(LBaseLibDir, 'release');
    LAlternateConfigDir := TPath.Combine(LBaseLibDir, 'debug');
  end;

  AddExistingPath(LPreferredConfigDir, Result);
  AddExistingPath(LBaseLibDir, Result);
  AddExistingPath(LAlternateConfigDir, Result);
  AddExistingPath(TPath.Combine(AToolchain.RootDir, 'source'), Result);
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

function TProjectScanner.GetBdsRootDirForVersion(const AVersion: string): string;
var
  LRegistry: TRegistry;
  procedure TryOpen(const AAccess: REGSAM);
  begin
    if Result <> '' then
      Exit;

    LRegistry.Access := KEY_READ or AAccess;
    if not LRegistry.OpenKeyReadOnly('\SOFTWARE\Embarcadero\BDS\' + AVersion) then
      Exit;
    try
      Result := Trim(LRegistry.ReadString('RootDir'));
    finally
      LRegistry.CloseKey;
    end;
  end;
begin
  Result := '';
  if Trim(AVersion) = '' then
    Exit;

  LRegistry := TRegistry.Create;
  try
    LRegistry.RootKey := HKEY_LOCAL_MACHINE;
    TryOpen(KEY_WOW64_32KEY);
    TryOpen(KEY_WOW64_64KEY);
    if (Result <> '') and TDirectory.Exists(Result) then
      Result := ExcludeTrailingPathDelimiter(TPath.GetFullPath(Result))
    else
      Result := '';
  finally
    LRegistry.Free;
  end;
end;

function TProjectScanner.GetFileVersionText(const AFilePath: string): string;
var
  LDummyHandle: DWORD;
  LFixedInfo: PVSFixedFileInfo;
  LInfoSize: DWORD;
  LValueLength: UINT;
  LVersionBuffer: TBytes;
begin
  Result := '';
  if not TFile.Exists(AFilePath) then
    Exit;

  LDummyHandle := 0;
  LInfoSize := GetFileVersionInfoSize(PChar(AFilePath), LDummyHandle);
  if LInfoSize = 0 then
    Exit;

  SetLength(LVersionBuffer, LInfoSize);
  if not GetFileVersionInfo(PChar(AFilePath), 0, LInfoSize, @LVersionBuffer[0]) then
    Exit;

  if not VerQueryValue(@LVersionBuffer[0], '\', Pointer(LFixedInfo), LValueLength) then
    Exit;

  if LValueLength < SizeOf(TVSFixedFileInfo) then
    Exit;

  Result := Format('%d.%d.%d.%d', [
    HiWord(LFixedInfo.dwFileVersionMS),
    LoWord(LFixedInfo.dwFileVersionMS),
    HiWord(LFixedInfo.dwFileVersionLS),
    LoWord(LFixedInfo.dwFileVersionLS)]);
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
    LBlocks := GetPropertyGroupContents('$(Base_' + FCurrentPlatform + ')');
    for I := 0 to High(LBlocks) do
    begin
      LBlock := LBlocks[I];
      begin
        LValue := GetElementValue(LBlock, AName);
        if LValue <> '' then
          Result := LValue;
      end;
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
  AddExistingPath(AProjectDir, Result);
  LSearchPathValue := GetPropertyValue('DCC_UnitSearchPath', '');
  AddDelimitedValues(LSearchPathValue, Result, AProjectDir, AProjectName, True);
end;

function TProjectScanner.ExtractUseDebugDCUs: Boolean;
var
  LValue: string;
begin
  LValue := Trim(GetPropertyValue('DCC_DebugDCUs', ''));
  if LValue = '' then
    Exit(SameText(FCurrentConfig, 'Debug'));

  Result := SameText(LValue, 'true') or SameText(LValue, '1');
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

function TProjectScanner.ResolveUnitReferencePath(const APath, AProjectDir,
  AProjectName: string): string;
var
  LPath: string;
begin
  Result := '';
  if Trim(APath) = '' then
    Exit;

  LPath := NormalizePath(APath, AProjectName);
  if (LPath <> '') and TPath.IsRelativePath(LPath) then
    LPath := TPath.Combine(AProjectDir, LPath);

  try
    Result := TPath.GetFullPath(LPath);
  except
    Result := LPath;
    FWarnings.Add('Could not resolve explicit unit reference path: ' + LPath);
  end;
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

function TProjectScanner.BuildExpectedMapFilePath(const AProjectInfo: TProjectInfo): string;
begin
  Result := '';
  if (AProjectInfo.OutputDir = '') or (AProjectInfo.ProjectName = '') then
    Exit;

  Result := TPath.Combine(AProjectInfo.OutputDir,
    AProjectInfo.ProjectName + AProjectInfo.DllSuffix + '.map');
end;

function TProjectScanner.Scan(const AProjectPath, APlatform, AConfiguration: string): TProjectInfo;
var
  LBplOutputDir: string;
  LDetectedPlatform: string;
  LHasMatchingPlatform: Boolean;
  LDcpOutputDir: string;
  LDcuOutputDir: string;
  LExeOutputDir: string;
  LTargetedPlatforms: TArray<string>;
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
    Result.MainSourcePath := ExtractMainSourcePath(AProjectPath, Result.ProjectDir, Result.ProjectName);

    LTargetedPlatforms := DetectTargetedPlatforms;
    LHasMatchingPlatform := False;
    for LDetectedPlatform in LTargetedPlatforms do
    begin
      if SameText(LDetectedPlatform, Result.Platform) then
      begin
        LHasMatchingPlatform := True;
        Break;
      end;
    end;

    if not LHasMatchingPlatform then
      FWarnings.Add('Requested platform "' + Result.Platform +
        '" is not listed in TargetedPlatforms.');

    // Detect the Cfg_N key for the requested configuration
    FConfigKey := DetectConfigKey(FCurrentConfig);
    Result.UsesDebugDCUs := ExtractUseDebugDCUs;

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

    Result.DllSuffix := GetPropertyValue('DllSuffix', '');
    Result.MapFilePath := BuildExpectedMapFilePath(Result);

    // Extract explicit project unit references.
    if Assigned(Result.ExplicitUnitReferences) then
      Result.ExplicitUnitReferences.Free;
    Result.ExplicitUnitReferences := ExtractExplicitUnitReferences(
      AProjectPath, Result.ProjectDir, Result.ProjectName, Result.MainSourcePath);

    // Resolve project-local and toolchain-level search roots.
    if Assigned(Result.ProjectSearchPaths) then
      Result.ProjectSearchPaths.Free;
    Result.ProjectSearchPaths := ExtractSearchPaths(Result.ProjectDir, Result.ProjectName);

    Result.Toolchain := DetectToolchainInfo;

    if Assigned(Result.GlobalSearchPaths) then
      Result.GlobalSearchPaths.Free;
    Result.GlobalSearchPaths := BuildGlobalSearchPaths(Result.Toolchain,
      Result.UsesDebugDCUs);

    // Build the effective search path list in priority order: project first, toolchain second.
    if Assigned(Result.SearchPaths) then
      Result.SearchPaths.Free;
    Result.SearchPaths := TList<string>.Create;
    CopyUniqueValues(Result.ProjectSearchPaths, Result.SearchPaths);
    CopyUniqueValues(Result.GlobalSearchPaths, Result.SearchPaths);

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
