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
/// - .dproj, .groupproj, .dpk, .dpr, and .bdsproj file extensions
/// - MSBuild variable replacement ($(Platform), $(Config), $(ProductVersion), $(MSBuildProjectName))
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
  System.StrUtils,
  System.Classes,
  System.IOUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  System.Win.Registry,
  Winapi.Windows,
  DX.Comply.Engine.Intf,
  DX.Comply.LegacyProject;

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
      cValidExtensions: array[0..4] of string = (
        '.dproj', '.groupproj', '.dpk', '.dpr', '.bdsproj');
  private
    FXmlText: string;
    FCurrentPlatform: string;
    FCurrentConfig: string;
    FConfigKey: string;
    FWarnings: TList<string>;
    /// <summary>
    /// Optional Delphi 7 root passed in before Scan. Empty uses the registry.
    /// </summary>
    FDelphi7Root: string;
    /// <summary>
    /// BDS version used for $(ProductVersion), for example 37.0.
    /// Set at the start of each scan. Empty when no install is found.
    /// </summary>
    FBdsProductVersion: string;
    FPlatformExplicit: Boolean;
    FConfigurationExplicit: Boolean;
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
    /// Returns the content of the first PropertyGroup without a Condition attribute.
    /// Used for legacy Delphi 2007 projects where defaults live in unconditional blocks.
    /// </summary>
    function GetUnconditionalPropertyGroupContent: string;
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
    /// Extracts runtime packages from DCC_UsePackage when UsePackages is true.
    /// A readable PE output keeps only packages named in its import table.
    /// </summary>
    function ExtractRuntimePackages(const AOutputFilePath, ADllSuffix: string): TList<string>;
    /// <summary>
    /// True when UsePackages resolves to true for the active config and platform.
    /// </summary>
    function LinksWithRuntimePackages: Boolean;
    /// <summary>
    /// Replaces known MSBuild tokens, then environment variables.
    /// When AEmptyProductVersion is true, $(ProductVersion) and its aliases
    /// become empty instead of the detected BDS version.
    /// </summary>
    function ExpandMsBuildPath(const APath, AProjectName: string;
      AEmptyProductVersion: Boolean): string;
    /// <summary>
    /// Replaces MSBuild variable tokens with actual platform/config values.
    /// </summary>
    function NormalizePath(const APath, AProjectName: string): string;
    /// <summary>
    /// Resolves a configured build path to a normalized absolute path.
    /// </summary>
    function ResolveBuildPath(const ARawPath, AProjectDir, AProjectName: string): string;
    /// <summary>
    /// Resolves an output directory, preferring a candidate that exists on disk.
    /// ANotes receives one progress line when the raw path contains a token.
    /// </summary>
    function ResolveOutputDirectory(const ARawPath, AProjectDir, AProjectName,
      ALabel: string; const ANotes: TList<string>): string;
    /// <summary>
    /// Returns .exe, .dll, or .bpl for the project output the .dproj names.
    /// </summary>
    function DetectOutputExtension(const AMainSourcePath: string): string;
    /// <summary>
    /// Reads DllSuffix for the active configuration. Returns False when the
    /// value still contains an unresolved $(...) token.
    /// </summary>
    function TryResolveDllSuffix(const AProjectName: string; out ASuffix: string): Boolean;
    /// <summary>
    /// Fills ArtefactOutputDir and OutputFilePath from the active output
    /// directories, AppType, and DllSuffix.
    /// </summary>
    procedure ResolveOutputFile(var AProjectInfo: TProjectInfo);
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
    /// Builds global Delphi library/source search roots for the detected toolchain,
    /// including IDE Library Paths from the registry (third-party components).
    /// </summary>
    function BuildGlobalSearchPaths(const AToolchain: TDelphiToolchainInfo;
      AUsesDebugDCUs: Boolean): TList<string>;
    /// <summary>
    /// Reads the IDE Library Search Path from the Windows registry for the
    /// given BDS version and platform (contains third-party component paths).
    /// </summary>
    function ReadIdeLibrarySearchPath(const ABdsVersion, APlatform: string): string;
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
    /// Detects targeted platforms from two sources and merges them:
    /// (1) the TargetedPlatforms numeric bitmask, and
    /// (2) named &lt;Platform value="X"&gt;True&lt;/Platform&gt; entries in
    /// &lt;BorlandProject&gt;&lt;Platforms&gt; — used by LLVM/mobile targets.
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
    /// <summary>
    /// Resolves a legacy output or search directory. Empty input returns an
    /// empty string. A path that still contains $(...) falls back to the
    /// project directory when ARequired is True.
    /// </summary>
    function ResolveLegacyDirectory(const ARawPath, AProjectDir, AProjectName,
      ADelphiRoot: string; ARequired: Boolean): string;
    /// <summary>
    /// Fills AProjectInfo from a .dpr, .dpk, or .bdsproj and its sibling
    /// .dof/.cfg. .dof values win over .cfg values.
    /// </summary>
    procedure PopulateLegacyProject(var AProjectInfo: TProjectInfo;
      const APlatform, AConfiguration: string);
    /// <summary>
    /// Adds Delphi 7 Lib/Source directories and the IDE library search path.
    /// </summary>
    procedure AddDelphi7LibraryPaths(const AProjectInfo: TProjectInfo;
      const ARoot, ALibrarySearchPath, AProjectName: string);
  public
    constructor Create;
    destructor Destroy; override;
    // IProjectScanner
    function Scan(const AProjectPath, APlatform, AConfiguration: string): TProjectInfo;
    function Validate(const AProjectPath: string): Boolean;
    procedure SetDelphi7Root(const ARoot: string);
    procedure SetExplicitTargetRequest(APlatformExplicit,
      AConfigurationExplicit: Boolean);
  end;

/// <summary>
/// BDS version DX.Comply records for the detected Delphi install,
/// for example 37.0. Empty when no install is found.
/// $(ProductVersion), $(BDSVersion), and $(BDSVER) expand to this value.
/// </summary>
function DetectBdsProductVersion: string;

/// <summary>
/// Reads DLL names from a PE import directory (PE32 and PE32+).
/// Returns False when the file is missing, unreadable, or not a valid PE.
/// ANames is empty on failure. A valid PE with no imports returns True and
/// an empty list. Never raises.
/// </summary>
function TryReadPeImportNames(const AFilePath: string;
  out ANames: TArray<string>): Boolean;

implementation

function ReadLatestInstalledBdsVersion: string;
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

function DetectBdsProductVersion: string;
var
  LBdsPath: string;
begin
  Result := '';
  LBdsPath := Trim(GetEnvironmentVariable('BDS'));
  if (LBdsPath <> '') and TDirectory.Exists(LBdsPath) then
  begin
    Result := TPath.GetFileName(ExcludeTrailingPathDelimiter(
      TPath.GetFullPath(LBdsPath)));
    Exit;
  end;
  Result := ReadLatestInstalledBdsVersion;
end;

function TryReadU16At(AStream: TStream; AOffset: Int64; out AValue: Word): Boolean;
var
  LBytes: array[0..1] of Byte;
begin
  Result := False;
  AValue := 0;
  if (AStream = nil) or (AOffset < 0) or (AStream.Size < 2) or
     (AOffset > AStream.Size - 2) then
    Exit;
  try
    AStream.Position := AOffset;
    if AStream.Read(LBytes[0], 2) <> 2 then
      Exit;
  except
    Exit;
  end;
  AValue := Word(LBytes[0]) or (Word(LBytes[1]) shl 8);
  Result := True;
end;

function TryReadU32At(AStream: TStream; AOffset: Int64; out AValue: Cardinal): Boolean;
var
  LBytes: array[0..3] of Byte;
begin
  Result := False;
  AValue := 0;
  if (AStream = nil) or (AOffset < 0) or (AStream.Size < 4) or
     (AOffset > AStream.Size - 4) then
    Exit;
  try
    AStream.Position := AOffset;
    if AStream.Read(LBytes[0], 4) <> 4 then
      Exit;
  except
    Exit;
  end;
  AValue := Cardinal(LBytes[0]) or (Cardinal(LBytes[1]) shl 8) or
    (Cardinal(LBytes[2]) shl 16) or (Cardinal(LBytes[3]) shl 24);
  Result := True;
end;

function TryReadAsciiZ(AStream: TStream; AOffset: Int64; out AText: string): Boolean;
const
  cMaxNameLength = 512;
var
  LByte: Byte;
  LCount: Integer;
begin
  Result := False;
  AText := '';
  if (AStream = nil) or (AOffset < 0) or (AOffset >= AStream.Size) then
    Exit;

  LCount := 0;
  while LCount < cMaxNameLength do
  begin
    if AOffset + LCount >= AStream.Size then
      Exit;
    try
      AStream.Position := AOffset + LCount;
      if AStream.Read(LByte, 1) <> 1 then
        Exit;
    except
      Exit;
    end;
    if LByte = 0 then
    begin
      Result := True;
      Exit;
    end;
    // Import names are ANSI DLL file names. Anything else is not trusted.
    if (LByte < 32) or (LByte > 126) then
      Exit;
    AText := AText + Chr(LByte);
    Inc(LCount);
  end;
end;

type
  TPeSectionSpan = record
    VirtualAddress: Cardinal;
    SizeOfRawData: Cardinal;
    PointerToRawData: Cardinal;
  end;

function RvaToFileOffset(const ASections: TArray<TPeSectionSpan>; ARva: Cardinal;
  out AOffset: Int64): Boolean;
var
  LSection: TPeSectionSpan;
  LStart: Int64;
  LEnd: Int64;
begin
  Result := False;
  AOffset := 0;
  for LSection in ASections do
  begin
    if LSection.SizeOfRawData = 0 then
      Continue;
    LStart := Int64(LSection.VirtualAddress);
    LEnd := LStart + Int64(LSection.SizeOfRawData);
    if (Int64(ARva) >= LStart) and (Int64(ARva) < LEnd) then
    begin
      AOffset := Int64(LSection.PointerToRawData) + (Int64(ARva) - LStart);
      if AOffset < 0 then
        Exit;
      Result := True;
      Exit;
    end;
  end;
end;

function ReadPeImportNamesFromStream(AStream: TStream; out ANames: TArray<string>): Boolean;
const
  cDosMagic = $5A4D;
  cPeSignature = $00004550;
  cPe32Magic = $010B;
  cPe32PlusMagic = $020B;
  cMaxSections = 96;
  cMaxImports = 4096;
var
  LNames: TList<string>;
  LSections: TArray<TPeSectionSpan>;
  LMagic: Word;
  LOptMagic: Word;
  LSectionCount: Word;
  LOptSize: Word;
  LLfanew: Cardinal;
  LPeSig: Cardinal;
  LNumberOfRva: Cardinal;
  LImportRva: Cardinal;
  LImportSize: Cardinal;
  LNameRva: Cardinal;
  LOriginalFirstThunk: Cardinal;
  LFirstThunk: Cardinal;
  LSectionVa: Cardinal;
  LSectionRawSize: Cardinal;
  LSectionRawPtr: Cardinal;
  LCoff: Int64;
  LOpt: Int64;
  LSectionTable: Int64;
  LImportOffset: Int64;
  LNameOffset: Int64;
  LDescriptor: Int64;
  LNumberOffset: Integer;
  LDataOffset: Integer;
  LRemain: Cardinal;
  LGuard: Integer;
  I: Integer;
  LDllName: string;
begin
  Result := False;
  SetLength(ANames, 0);
  if AStream = nil then
    Exit;

  LNames := TList<string>.Create;
  try
    try
      if not TryReadU16At(AStream, 0, LMagic) or (LMagic <> cDosMagic) then
        Exit;
      if not TryReadU32At(AStream, $3C, LLfanew) then
        Exit;
      if (LLfanew < $40) or (Int64(LLfanew) > AStream.Size) then
        Exit;
      if not TryReadU32At(AStream, LLfanew, LPeSig) or (LPeSig <> cPeSignature) then
        Exit;

      LCoff := Int64(LLfanew) + 4;
      if not TryReadU16At(AStream, LCoff + 2, LSectionCount) then
        Exit;
      if not TryReadU16At(AStream, LCoff + 16, LOptSize) then
        Exit;
      if (LSectionCount > cMaxSections) or (LOptSize < 24) then
        Exit;

      LOpt := LCoff + 20;
      if not TryReadU16At(AStream, LOpt, LOptMagic) then
        Exit;
      if LOptMagic = cPe32Magic then
      begin
        LNumberOffset := 92;
        LDataOffset := 96;
      end
      else if LOptMagic = cPe32PlusMagic then
      begin
        LNumberOffset := 108;
        LDataOffset := 112;
      end
      else
        Exit;

      // The import entry is data directory index 1 (8 bytes at LDataOffset + 8).
      if LOptSize < LDataOffset + 16 then
        Exit;
      if not TryReadU32At(AStream, LOpt + LNumberOffset, LNumberOfRva) then
        Exit;
      if LNumberOfRva < 2 then
      begin
        Result := True;
        Exit;
      end;
      if not TryReadU32At(AStream, LOpt + LDataOffset + 8, LImportRva) then
        Exit;
      if not TryReadU32At(AStream, LOpt + LDataOffset + 12, LImportSize) then
        Exit;
      if (LImportRva = 0) or (LImportSize = 0) then
      begin
        Result := True;
        Exit;
      end;
      if LImportSize < 20 then
        Exit;

      LSectionTable := LOpt + LOptSize;
      SetLength(LSections, LSectionCount);
      for I := 0 to LSectionCount - 1 do
      begin
        if not TryReadU32At(AStream, LSectionTable + Int64(I) * 40 + 12, LSectionVa) then
          Exit;
        if not TryReadU32At(AStream, LSectionTable + Int64(I) * 40 + 16, LSectionRawSize) then
          Exit;
        if not TryReadU32At(AStream, LSectionTable + Int64(I) * 40 + 20, LSectionRawPtr) then
          Exit;
        LSections[I].VirtualAddress := LSectionVa;
        LSections[I].SizeOfRawData := LSectionRawSize;
        LSections[I].PointerToRawData := LSectionRawPtr;
      end;

      if not RvaToFileOffset(LSections, LImportRva, LImportOffset) then
        Exit;

      LRemain := LImportSize;
      LGuard := 0;
      LDescriptor := LImportOffset;
      while (LRemain >= 20) and (LGuard < cMaxImports) do
      begin
        if not TryReadU32At(AStream, LDescriptor, LOriginalFirstThunk) then
          Exit;
        if not TryReadU32At(AStream, LDescriptor + 12, LNameRva) then
          Exit;
        if not TryReadU32At(AStream, LDescriptor + 16, LFirstThunk) then
          Exit;
        if (LOriginalFirstThunk = 0) and (LNameRva = 0) and (LFirstThunk = 0) then
          Break;

        if LNameRva <> 0 then
        begin
          if not RvaToFileOffset(LSections, LNameRva, LNameOffset) then
            Exit;
          if not TryReadAsciiZ(AStream, LNameOffset, LDllName) then
            Exit;
          if (LDllName <> '') and not LNames.Contains(LDllName) then
            LNames.Add(LDllName);
        end;

        LDescriptor := LDescriptor + 20;
        Dec(LRemain, 20);
        Inc(LGuard);
      end;

      ANames := LNames.ToArray;
      Result := True;
    except
      Result := False;
      SetLength(ANames, 0);
    end;
  finally
    LNames.Free;
  end;
end;

function TryReadPeImportNames(const AFilePath: string; out ANames: TArray<string>): Boolean;
var
  LStream: TFileStream;
begin
  Result := False;
  SetLength(ANames, 0);
  if Trim(AFilePath) = '' then
    Exit;
  try
    if not TFile.Exists(AFilePath) then
      Exit;
    LStream := TFileStream.Create(AFilePath, fmOpenRead or fmShareDenyNone);
    try
      Result := ReadPeImportNamesFromStream(LStream, ANames);
      if not Result then
        SetLength(ANames, 0);
    finally
      LStream.Free;
    end;
  except
    Result := False;
    SetLength(ANames, 0);
  end;
end;

function IsDecimalSuffix(const AValue: string): Boolean;
var
  LChar: Char;
begin
  Result := AValue <> '';
  for LChar in AValue do
    if not CharInSet(LChar, ['0'..'9']) then
      Exit(False);
end;

function ImportDllBaseName(const AImport: string): string;
var
  LNormalized: string;
  LSep: Integer;
begin
  LNormalized := StringReplace(AImport, '/', '\', [rfReplaceAll]);
  LSep := LastDelimiter('\', LNormalized);
  Result := Copy(LNormalized, LSep + 1, MaxInt);
end;

function RuntimePackageImported(const APackageName, ADllSuffix: string;
  const AImports: TArray<string>): Boolean;
var
  LImport: string;
  LFileName: string;
  LPackage: string;
  LRest: string;
  LSuffix: string;
begin
  Result := False;
  LPackage := LowerCase(Trim(APackageName));
  if LPackage = '' then
    Exit;

  // An unresolved $(...) suffix is not a file-name suffix.
  LSuffix := Trim(ADllSuffix);
  if Pos('$', LSuffix) > 0 then
    LSuffix := '';
  LSuffix := LowerCase(LSuffix);

  for LImport in AImports do
  begin
    LFileName := LowerCase(ImportDllBaseName(LImport));
    if not LFileName.EndsWith('.bpl') then
      Continue;
    if not LFileName.StartsWith(LPackage) then
      Continue;
    // Delphi lists "rtl" and imports rtl370.bpl (or rtl.bpl). The digits are
    // the compiler package version. Delphi 12 uses 290 while its BDS version
    // is 23.0, so any numeric suffix is accepted, plus a resolved DllSuffix.
    LRest := Copy(LFileName, Length(LPackage) + 1,
      Length(LFileName) - Length(LPackage) - Length('.bpl'));
    if LRest = '' then
      Exit(True);
    if (LSuffix <> '') and (LRest = LSuffix) then
      Exit(True);
    if IsDecimalSuffix(LRest) then
      Exit(True);
  end;
end;

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
  FBdsProductVersion := '';
end;

destructor TProjectScanner.Destroy;
begin
  FWarnings.Free;
  inherited;
end;

procedure TProjectScanner.LoadProjectFile(const AProjectPath: string);
var
  LBytes: TBytes;
  LEncoding: TEncoding;
  LPreambleSize: Integer;
begin
  LBytes := TFile.ReadAllBytes(AProjectPath);

  // Detect BOM. Fall back to UTF-8 because .dproj files are XML and modern
  // Delphi versions save them as UTF-8 (with or without BOM). Legacy ANSI
  // project files that contain only ASCII will decode identically under UTF-8.
  LEncoding := nil;
  LPreambleSize := TEncoding.GetBufferEncoding(LBytes, LEncoding, TEncoding.UTF8);

  FXmlText := LEncoding.GetString(LBytes, LPreambleSize, Length(LBytes) - LPreambleSize);
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

function TProjectScanner.DetectToolchainInfo: TDelphiToolchainInfo;
var
  LBdsPath: string;
  LVersion: string;
begin
  Result := Default(TDelphiToolchainInfo);

  // Same version string $(ProductVersion) expands to.
  LVersion := DetectBdsProductVersion;
  LBdsPath := Trim(GetEnvironmentVariable('BDS'));
  if (LBdsPath <> '') and TDirectory.Exists(LBdsPath) then
    Result.RootDir := ExcludeTrailingPathDelimiter(TPath.GetFullPath(LBdsPath))
  else
    Result.RootDir := GetBdsRootDirForVersion(LVersion);
  Result.Version := LVersion;

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

  LContent := TFile.ReadAllText(AMainSourcePath);
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
  LIdeSearchPath: string;
  LPathEntry: string;
  LPreferredConfigDir: string;
  LResolvedPath: string;
begin
  Result := TList<string>.Create;
  if Trim(AToolchain.RootDir) = '' then
    Exit;

  // Delphi installation lib directories
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

  // IDE Library Search Path from registry (third-party components)
  LIdeSearchPath := ReadIdeLibrarySearchPath(AToolchain.Version, FCurrentPlatform);
  if LIdeSearchPath <> '' then
  begin
    for LPathEntry in LIdeSearchPath.Split([';']) do
    begin
      LResolvedPath := Trim(LPathEntry);
      if (LResolvedPath = '') or LResolvedPath.StartsWith('$') then
        Continue;
      AddExistingPath(LResolvedPath, Result);
    end;
  end;
end;

function TProjectScanner.ReadIdeLibrarySearchPath(
  const ABdsVersion, APlatform: string): string;
var
  LRegistry: TRegistry;
  LKeyPath: string;
  procedure TryRead(ARootKey: HKEY; const AAccess: REGSAM);
  begin
    if Result <> '' then
      Exit;

    LRegistry.RootKey := ARootKey;
    LRegistry.Access := KEY_READ or AAccess;
    if not LRegistry.OpenKeyReadOnly(LKeyPath) then
      Exit;
    try
      Result := Trim(LRegistry.ReadString('Search Path'));
    finally
      LRegistry.CloseKey;
    end;
  end;
begin
  Result := '';
  if (ABdsVersion = '') or (APlatform = '') then
    Exit;

  LKeyPath := '\SOFTWARE\Embarcadero\BDS\' + ABdsVersion + '\Library\' + APlatform;
  LRegistry := TRegistry.Create;
  try
    // IDE settings are typically stored in HKCU
    TryRead(HKEY_CURRENT_USER, KEY_WOW64_32KEY);
    TryRead(HKEY_CURRENT_USER, KEY_WOW64_64KEY);
    // Fallback to HKLM
    TryRead(HKEY_LOCAL_MACHINE, KEY_WOW64_32KEY);
    TryRead(HKEY_LOCAL_MACHINE, KEY_WOW64_64KEY);
  finally
    LRegistry.Free;
  end;
end;

function TProjectScanner.DetectTargetedPlatforms: TArray<string>;
var
  LValue: string;
  LBitmask: Integer;
  LPlatforms: TList<string>;
  LMatch: TMatch;
  LMatches: TMatchCollection;
  LPlatformName: string;
begin
  LPlatforms := TList<string>.Create;
  try
    // Primary source: TargetedPlatforms numeric bitmask
    // Delphi IDE writes this element for Win/Mac/desktop targets.
    LValue := GetElementValue(FXmlText, 'TargetedPlatforms');
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

    // Supplemental source: named <Platform value="X">True</Platform> entries
    // in the <BorlandProject><Platforms> section.  Mobile / LLVM-backend targets
    // (iOSDevice64, Android64, LinuxArm64, …) are often absent from the
    // TargetedPlatforms bitmask but listed here instead.  Add any platform
    // that is enabled (True) and not already present from the bitmask above.
    LMatches := TRegEx.Matches(FXmlText,
      '<Platform\s+value="([^"]+)"[^>]*>\s*(True|False)\s*</Platform>',
      [roIgnoreCase]);
    for LMatch in LMatches do
    begin
      if (LMatch.Groups.Count >= 3) and
         SameText(LMatch.Groups[2].Value, 'True') then
      begin
        LPlatformName := LMatch.Groups[1].Value;
        if (LPlatformName <> '') and not LPlatforms.Contains(LPlatformName) then
          LPlatforms.Add(LPlatformName);
      end;
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

function TProjectScanner.GetUnconditionalPropertyGroupContent: string;
var
  LPattern: string;
  LMatch: TMatch;
  LMatches: TMatchCollection;
begin
  Result := '';
  LPattern := '<PropertyGroup(?:\s[^>]*)?>.*?</PropertyGroup>';
  LMatches := TRegEx.Matches(FXmlText, LPattern, [roIgnoreCase, roSingleLine]);

  for LMatch in LMatches do
  begin
    // Skip groups that have a Condition attribute
    if TRegEx.IsMatch(LMatch.Value, 'Condition\s*=\s*"', [roIgnoreCase]) then
      Continue;
    // Skip the Project Extensions group
    if Pos('<ProjectExtensions', LMatch.Value) > 0 then
      Continue;
    Result := LMatch.Value;
    Exit;
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

  // 0. Unconditional PropertyGroup (no Condition attribute — Delphi 2007 default)
  LBlock := GetUnconditionalPropertyGroupContent;
  if LBlock <> '' then
  begin
    LValue := GetElementValue(LBlock, AName);
    if LValue <> '' then
      Result := LValue;
  end;

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
      LValue := GetElementValue(LBlocks[I], AName);
      if LValue <> '' then
        Result := LValue;
    end;
  end;

  // 3. Config-specific — use the detected Cfg_N key
  if FConfigKey <> '' then
  begin
    LBlocks := GetPropertyGroupContents('$(' + FConfigKey + ')');
    for I := 0 to High(LBlocks) do
    begin
      LValue := GetElementValue(LBlocks[I], AName);
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

  // 5. Legacy format (Delphi 2007): $(Configuration)|$(Platform) conditions
  //    e.g. Condition="'$(Configuration)|$(Platform)'=='Release|Win32'"
  if FCurrentConfig <> '' then
  begin
    if FCurrentPlatform <> '' then
    begin
      LBlock := GetPropertyGroupContent(FCurrentConfig + '|' + FCurrentPlatform);
      if LBlock <> '' then
      begin
        LValue := GetElementValue(LBlock, AName);
        if LValue <> '' then
          Result := LValue;
      end;
    end;
    // AnyCPU fallback — used by old .dproj files without platform-specific blocks
    LBlock := GetPropertyGroupContent(FCurrentConfig + '|AnyCPU');
    if LBlock <> '' then
    begin
      LValue := GetElementValue(LBlock, AName);
      if LValue <> '' then
        Result := LValue;
    end;
  end;
end;

function TProjectScanner.LinksWithRuntimePackages: Boolean;
var
  LValue: string;
begin
  // Missing UsePackages means the IDE default, which is false. The same
  // property precedence as DCC_ExeOutput applies (Base, platform, config).
  LValue := Trim(GetPropertyValue('UsePackages', ''));
  Result := SameText(LValue, 'true') or SameText(LValue, '1');
end;

function TProjectScanner.ExtractRuntimePackages(const AOutputFilePath,
  ADllSuffix: string): TList<string>;
var
  LPackages: TList<string>;
  LKept: TList<string>;
  LBlock, LPackageStr: string;
  LBlocks: TArray<string>;
  LPackageArray: TArray<string>;
  LImports: TArray<string>;
  LPlatformPackages: string;
  LPackageName: string;
  I: Integer;
begin
  LPackages := TList<string>.Create;

  // Delphi writes the default package list into every .dproj. Those packages
  // are linked only when UsePackages is true for this config and platform.
  if not LinksWithRuntimePackages then
    Exit(LPackages);

  // DCC_UsePackage in base PropertyGroup
  LBlock := GetPropertyGroupContent('$(Base)');
  LPackageStr := GetElementValue(LBlock, 'DCC_UsePackage');
  if LPackageStr = '' then
    LPackageStr := GetElementValue(FXmlText, 'RuntimePackage');

  // Also check platform-specific UsePackage
  if FCurrentPlatform <> '' then
  begin
    LBlocks := GetPropertyGroupContents('$(Base_' + FCurrentPlatform + ')');
    for I := 0 to High(LBlocks) do
    begin
      LPlatformPackages := GetElementValue(LBlocks[I], 'DCC_UsePackage');
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

  // A readable PE keeps only packages whose BPL is actually imported.
  // A missing or malformed file keeps the UsePackages list.
  if (AOutputFilePath = '') or not TFile.Exists(AOutputFilePath) then
    Exit(LPackages);
  if not TryReadPeImportNames(AOutputFilePath, LImports) then
    Exit(LPackages);

  LKept := TList<string>.Create;
  try
    for LPackageName in LPackages do
      if RuntimePackageImported(LPackageName, ADllSuffix, LImports) then
        LKept.Add(LPackageName);
    LPackages.Clear;
    for LPackageName in LKept do
      LPackages.Add(LPackageName);
  finally
    LKept.Free;
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

function TProjectScanner.ExpandMsBuildPath(const APath, AProjectName: string;
  AEmptyProductVersion: Boolean): string;
var
  LPath: string;
  LProductVersion: string;

  // Expands any remaining $(VarName) placeholders by consulting Windows
  // environment variables. Delphi's "User System Overrides" propagate to the
  // build via environment variables, so this resolves project-specific tokens
  // such as $(DVER). See issue #27.
  function ExpandEnvironmentTokens(const AInput: string): string;
  var
    LIdx, LStart, LEnd: Integer;
    LName, LValue: string;
  begin
    Result := AInput;
    LIdx := 1;
    while LIdx < Length(Result) do
    begin
      LStart := PosEx('$(', Result, LIdx);
      if LStart = 0 then
        Break;
      LEnd := PosEx(')', Result, LStart + 2);
      if LEnd = 0 then
        Break;
      LName := Copy(Result, LStart + 2, LEnd - LStart - 2);
      LValue := GetEnvironmentVariable(LName);
      // Limitation: GetEnvironmentVariable returns '' both for an undefined
      // variable AND for one that is defined but empty. We cannot
      // distinguish the two cases without the lower-level Win32 API.
      // Treating both as "leave the token intact" is the safer choice.
      // Substituting an empty string would silently collapse path
      // segments and produce invalid paths. See issue #27.
      if LValue <> '' then
      begin
        Result := Copy(Result, 1, LStart - 1) + LValue +
          Copy(Result, LEnd + 1, MaxInt);
        // Continue searching after the substituted value
        LIdx := LStart + Length(LValue);
      end
      else
        // Unknown or empty token. Leave it intact and advance past it.
        LIdx := LEnd + 1;
    end;
  end;

  function CollapseSeparators(const AInput: string): string;
  var
    LPrefix: string;
    LBody: string;
    LPrev: string;
  begin
    // A leading \\ is a UNC prefix and must survive collapsing.
    if AInput.StartsWith('\\') then
    begin
      LPrefix := '\\';
      LBody := Copy(AInput, 3, MaxInt);
    end
    else
    begin
      LPrefix := '';
      LBody := AInput;
    end;
    repeat
      LPrev := LBody;
      LBody := StringReplace(LBody, '\\', '\', [rfReplaceAll]);
    until LBody = LPrev;
    Result := LPrefix + LBody;
  end;

begin
  LPath := APath;
  // Standard MSBuild variables
  LPath := StringReplace(LPath, '$(Platform)', FCurrentPlatform, [rfIgnoreCase, rfReplaceAll]);
  LPath := StringReplace(LPath, '$(Config)', FCurrentConfig, [rfIgnoreCase, rfReplaceAll]);
  LPath := StringReplace(LPath, '$(Configuration)', FCurrentConfig, [rfIgnoreCase, rfReplaceAll]);
  LPath := StringReplace(LPath, '$(MSBuildProjectName)', AProjectName, [rfIgnoreCase, rfReplaceAll]);
  LPath := StringReplace(LPath, '$(ProjectName)', AProjectName, [rfIgnoreCase, rfReplaceAll]);
  // $(ProductVersion) is the BDS version the IDE substitutes (37.0 on Delphi 13).
  // A command-line build with no rsvars leaves it empty. BDSVER and BDSVersion
  // are the same value. Replace the longer alias before $(BDSVER).
  if AEmptyProductVersion or (FBdsProductVersion <> '') then
  begin
    if AEmptyProductVersion then
      LProductVersion := ''
    else
      LProductVersion := FBdsProductVersion;
    LPath := StringReplace(LPath, '$(ProductVersion)', LProductVersion, [rfIgnoreCase, rfReplaceAll]);
    LPath := StringReplace(LPath, '$(BDSVersion)', LProductVersion, [rfIgnoreCase, rfReplaceAll]);
    LPath := StringReplace(LPath, '$(BDSVER)', LProductVersion, [rfIgnoreCase, rfReplaceAll]);
  end;
  // Resolve user-defined $(VarName) placeholders against environment variables.
  if Pos('$(', LPath) > 0 then
    LPath := ExpandEnvironmentTokens(LPath);
  // Normalize path separators
  LPath := StringReplace(LPath, '/', '\', [rfReplaceAll]);
  LPath := CollapseSeparators(LPath);
  // Remove trailing backslash, but keep a drive root such as C:\
  if (Length(LPath) > 1) and (LPath[Length(LPath)] = '\') and
     not LPath.EndsWith(':\') then
    LPath := Copy(LPath, 1, Length(LPath) - 1);
  Result := LPath;
end;

function TProjectScanner.NormalizePath(const APath, AProjectName: string): string;
begin
  Result := ExpandMsBuildPath(APath, AProjectName, False);
end;

function ContainsProductVersionToken(const APath: string): Boolean;
var
  LUpper: string;
begin
  LUpper := UpperCase(APath);
  Result := (Pos('$(PRODUCTVERSION)', LUpper) > 0) or
    (Pos('$(BDSVERSION)', LUpper) > 0) or
    (Pos('$(BDSVER)', LUpper) > 0);
end;

function StripMsBuildTokens(const APath: string): string;
var
  LStart: Integer;
  LEnd: Integer;
begin
  Result := APath;
  LStart := Pos('$(', Result);
  while LStart > 0 do
  begin
    LEnd := PosEx(')', Result, LStart + 2);
    if LEnd = 0 then
      Break;
    Result := Copy(Result, 1, LStart - 1) + Copy(Result, LEnd + 1, MaxInt);
    LStart := PosEx('$(', Result, LStart);
  end;
end;

function TProjectScanner.ResolveOutputDirectory(const ARawPath, AProjectDir,
  AProjectName, ALabel: string; const ANotes: TList<string>): string;
var
  LRaw: string;
  LExpanded: string;
  LEmptyProduct: string;
  LStripped: string;
  LCandidateA: string;
  LCandidateB: string;
  LCandidateC: string;
  LFailedA: Boolean;
  LFailedB: Boolean;
  LFailedC: Boolean;
  LChosenFailed: Boolean;
  LHasProductToken: Boolean;
  LReason: string;

  function TryToAbsolute(const APath: string; out AFullPath: string): Boolean;
  var
    LPath: string;
  begin
    Result := True;
    LPath := APath;
    if (LPath <> '') and TPath.IsRelativePath(LPath) then
    begin
      try
        LPath := TPath.Combine(AProjectDir, LPath);
      except
        Result := False;
      end;
    end;
    try
      AFullPath := TPath.GetFullPath(LPath);
    except
      AFullPath := LPath;
      Result := False;
    end;
  end;

  function DirectoryExistsSafe(const APath: string): Boolean;
  begin
    Result := False;
    if Trim(APath) = '' then
      Exit;
    try
      Result := TDirectory.Exists(APath);
    except
      Result := False;
    end;
  end;

  function CleanStripped(const APath: string): string;
  var
    LPrefix: string;
    LBody: string;
    LPrev: string;
  begin
    Result := StringReplace(APath, '/', '\', [rfReplaceAll]);
    if Result.StartsWith('\\') then
    begin
      LPrefix := '\\';
      LBody := Copy(Result, 3, MaxInt);
    end
    else
    begin
      LPrefix := '';
      LBody := Result;
    end;
    repeat
      LPrev := LBody;
      LBody := StringReplace(LBody, '\\', '\', [rfReplaceAll]);
    until LBody = LPrev;
    Result := LPrefix + LBody;
    if (Length(Result) > 1) and (Result[Length(Result)] = '\') and
       not Result.EndsWith(':\') then
      Result := Copy(Result, 1, Length(Result) - 1);
  end;

begin
  Result := '';
  LRaw := Trim(ARawPath);
  if LRaw = '' then
    Exit;

  // A: known properties expanded, unknown tokens left.
  // B: A with every remaining $(...) token removed.
  // C: same as A, but $(ProductVersion) and its aliases are empty.
  // The first directory that exists wins. A, then B, then C. Otherwise A is kept.
  LExpanded := ExpandMsBuildPath(LRaw, AProjectName, False);
  LHasProductToken := ContainsProductVersionToken(LRaw) and (FBdsProductVersion <> '');
  if LHasProductToken then
    LEmptyProduct := ExpandMsBuildPath(LRaw, AProjectName, True)
  else
    LEmptyProduct := '';
  LStripped := CleanStripped(StripMsBuildTokens(LExpanded));

  LFailedA := not TryToAbsolute(LExpanded, LCandidateA);
  if LHasProductToken then
    LFailedC := not TryToAbsolute(LEmptyProduct, LCandidateC)
  else
  begin
    LFailedC := False;
    LCandidateC := '';
  end;
  LFailedB := not TryToAbsolute(LStripped, LCandidateB);

  if DirectoryExistsSafe(LCandidateA) then
  begin
    Result := LCandidateA;
    LChosenFailed := LFailedA;
    LReason := 'expanded properties; the directory exists';
  end
  else if DirectoryExistsSafe(LCandidateB) and not SameText(LCandidateB, LCandidateA) then
  begin
    Result := LCandidateB;
    LChosenFailed := LFailedB;
    LReason := 'unresolved $(...) removed; that directory exists';
  end
  else if LHasProductToken and DirectoryExistsSafe(LCandidateC) and
     not SameText(LCandidateC, LCandidateA) and
     not SameText(LCandidateC, LCandidateB) then
  begin
    Result := LCandidateC;
    LChosenFailed := LFailedC;
    LReason := '$(ProductVersion) left empty; that directory exists';
  end
  else
  begin
    Result := LCandidateA;
    LChosenFailed := LFailedA;
    LReason := 'expanded properties; no candidate directory exists';
  end;

  if LChosenFailed then
    FWarnings.Add('Could not resolve output path: ' + Result);

  // One line, and only when a product-version token or an unresolved token
  // was involved. Ordinary $(Platform) and $(Config) paths stay quiet.
  // The CLI prints the line only with --verbose.
  if Assigned(ANotes) and (ContainsProductVersionToken(LRaw) or
     (Pos('$(', LExpanded) > 0) or not SameText(Result, LCandidateA)) then
    ANotes.Add(ALabel + ' resolved to ' + Result + ' (' + LReason + ').');
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

function TProjectScanner.DetectOutputExtension(const AMainSourcePath: string): string;
var
  LAppType: string;
  LKeyword: string;
  LMatch: TMatch;
  LText: string;
begin
  LAppType := Trim(GetPropertyValue('AppType', ''));
  if SameText(LAppType, 'Library') then
    Exit('.dll');
  if SameText(LAppType, 'Package') then
    Exit('.bpl');
  if SameText(LAppType, 'Application') or SameText(LAppType, 'Console') then
    Exit('.exe');

  if SameText(TPath.GetExtension(AMainSourcePath), '.dpk') then
    Exit('.bpl');

  if (AMainSourcePath <> '') and TFile.Exists(AMainSourcePath) then
  begin
    try
      LText := TFile.ReadAllText(AMainSourcePath);
    except
      LText := '';
    end;
    // The first program/library/package keyword decides the output when the
    // .dproj does not say AppType. A leading comment or blank line is skipped
    // because ^ matches each line.
    LMatch := TRegEx.Match(LText, '^\s*(program|library|package)\b',
      [roIgnoreCase, roMultiLine]);
    if LMatch.Success then
    begin
      LKeyword := LowerCase(LMatch.Groups[1].Value);
      if LKeyword = 'library' then
        Exit('.dll');
      if LKeyword = 'package' then
        Exit('.bpl');
      Exit('.exe');
    end;
  end;

  Result := '.exe';
end;

function TProjectScanner.TryResolveDllSuffix(const AProjectName: string;
  out ASuffix: string): Boolean;
var
  LRaw: string;
begin
  ASuffix := '';
  LRaw := Trim(GetPropertyValue('DllSuffix', ''));
  if LRaw = '' then
    Exit(True);

  ASuffix := NormalizePath(LRaw, AProjectName);
  if Pos('$', ASuffix) > 0 then
  begin
    FWarnings.Add('Could not resolve DllSuffix "' + LRaw +
      '". The output file name was left unset; the output directory is still scanned.');
    ASuffix := '';
    Exit(False);
  end;
  Result := True;
end;

procedure TProjectScanner.ResolveOutputFile(var AProjectInfo: TProjectInfo);
var
  LDir: string;
  LExt: string;
  LFileName: string;
  LSuffix: string;
  LSuffixResolved: Boolean;
begin
  AProjectInfo.OutputFilePath := '';
  LExt := DetectOutputExtension(AProjectInfo.MainSourcePath);

  // Packages are written to the BPL output. Exe and dll use the exe output.
  // OutputDir prefers DCC_ExeOutput, so a package whose BPL folder differs
  // from that path must not be scanned from the exe folder (issue #38).
  LDir := '';
  if SameText(LExt, '.bpl') then
    LDir := AProjectInfo.BplOutputDir;
  if LDir = '' then
    LDir := AProjectInfo.OutputDir;
  AProjectInfo.ArtefactOutputDir := LDir;

  // DllSuffix is appended to dll and bpl names only. An application keeps
  // ProjectName.exe even when the .dproj still carries a suffix.
  LSuffix := '';
  if SameText(LExt, '.exe') then
    LSuffixResolved := True
  else
    LSuffixResolved := TryResolveDllSuffix(AProjectInfo.ProjectName, LSuffix);
  if not LSuffixResolved then
    Exit;
  if AProjectInfo.ProjectName = '' then
    Exit;

  if SameText(LExt, '.exe') then
    LFileName := AProjectInfo.ProjectName + LExt
  else
    LFileName := AProjectInfo.ProjectName + LSuffix + LExt;

  if LDir = '' then
    AProjectInfo.OutputFilePath := LFileName
  else
    AProjectInfo.OutputFilePath := TPath.Combine(LDir, LFileName);
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
var
  LMapFileName: string;
  LCandidate: string;
  LCandidateDirs: TArray<string>;
  LDir: string;
  LBuildDir: string;
begin
  Result := '';
  if AProjectInfo.ProjectName = '' then
    Exit;

  LMapFileName := AProjectInfo.ProjectName + AProjectInfo.EffectiveMapSuffix + '.map';

  // Build candidate directories in priority order:
  // 1. Configured output directory (from .dproj)
  // 2. Project directory (Delphi default when no output dir is configured)
  // 3. Standard build structure relative to project (../build/Platform/Config)
  // 4. BPL output directory (for packages)
  LCandidateDirs := [];
  if AProjectInfo.OutputDir <> '' then
    LCandidateDirs := LCandidateDirs + [AProjectInfo.OutputDir];
  if AProjectInfo.ProjectDir <> '' then
    LCandidateDirs := LCandidateDirs + [AProjectInfo.ProjectDir];
  if AProjectInfo.ProjectDir <> '' then
  begin
    LBuildDir := ResolveBuildPath('..\build\$(Platform)\$(Config)',
      AProjectInfo.ProjectDir, AProjectInfo.ProjectName);
    if LBuildDir <> '' then
      LCandidateDirs := LCandidateDirs + [LBuildDir];
  end;
  if (AProjectInfo.BplOutputDir <> '') and
     (AProjectInfo.BplOutputDir <> AProjectInfo.OutputDir) then
    LCandidateDirs := LCandidateDirs + [AProjectInfo.BplOutputDir];

  // Return the first candidate where the MAP file actually exists
  for LDir in LCandidateDirs do
  begin
    LCandidate := TPath.Combine(LDir, LMapFileName);
    if TFile.Exists(LCandidate) then
      Exit(LCandidate);
  end;

  // No existing MAP file found — return the best candidate path so the
  // Deep-Evidence build knows where to look after building
  if Length(LCandidateDirs) > 0 then
    Result := TPath.Combine(LCandidateDirs[0], LMapFileName);
end;

procedure TProjectScanner.SetDelphi7Root(const ARoot: string);
begin
  FDelphi7Root := Trim(ARoot);
end;

procedure TProjectScanner.SetExplicitTargetRequest(APlatformExplicit,
  AConfigurationExplicit: Boolean);
begin
  FPlatformExplicit := APlatformExplicit;
  FConfigurationExplicit := AConfigurationExplicit;
end;

function TProjectScanner.ResolveLegacyDirectory(const ARawPath, AProjectDir,
  AProjectName, ADelphiRoot: string; ARequired: Boolean): string;
var
  LPath: string;
begin
  Result := '';
  LPath := Trim(ARawPath);
  if LPath = '' then
  begin
    if ARequired then
      Result := AProjectDir;
    Exit;
  end;

  LPath := ExpandLegacyMacros(LPath, ADelphiRoot);
  if Pos('$(', LPath) > 0 then
  begin
    FWarnings.Add('Could not resolve path "' + ARawPath +
      '" because no Delphi 7 root was found.');
    if ARequired then
      Result := AProjectDir;
    Exit;
  end;

  Result := ResolveBuildPath(LPath, AProjectDir, AProjectName);
  if (Result = '') and ARequired then
    Result := AProjectDir;
end;

procedure TProjectScanner.AddDelphi7LibraryPaths(const AProjectInfo: TProjectInfo;
  const ARoot, ALibrarySearchPath, AProjectName: string);
var
  LExpanded: string;
  LItem: string;
begin
  if ARoot <> '' then
  begin
    AddExistingPath(TPath.Combine(ARoot, 'Lib'), AProjectInfo.GlobalSearchPaths);
    AddExistingPath(TPath.Combine(ARoot, 'Source'), AProjectInfo.GlobalSearchPaths);
    AddExistingPath(TPath.Combine(ARoot, 'Source\Rtl\Sys'), AProjectInfo.GlobalSearchPaths);
    AddExistingPath(TPath.Combine(ARoot, 'Source\Rtl\Common'), AProjectInfo.GlobalSearchPaths);
    AddExistingPath(TPath.Combine(ARoot, 'Source\Vcl'), AProjectInfo.GlobalSearchPaths);
  end;

  if Trim(ALibrarySearchPath) = '' then
    Exit;

  LExpanded := ExpandLegacyMacros(ALibrarySearchPath, ARoot);
  for LItem in LExpanded.Split([';']) do
  begin
    if (Trim(LItem) = '') or (Pos('$(', LItem) > 0) then
      Continue;
    AddExistingPath(ResolveLegacyDirectory(LItem, AProjectInfo.ProjectDir,
      AProjectName, ARoot, False), AProjectInfo.GlobalSearchPaths);
  end;
end;

procedure TProjectScanner.PopulateLegacyProject(var AProjectInfo: TProjectInfo;
  const APlatform, AConfiguration: string);
var
  LCfg: TLegacyOptionSet;
  LDof: TLegacyOptionSet;
  LExt: string;
  LLibrarySearchPath: string;
  LOptions: TLegacyOptionSet;
  LOutputDir: string;
  LPackageDplOutput: string;
  LPackageItem: string;
  LPackageList: string;
  LPackageName: string;
  LRegistryPackageDir: string;
  LRegistryRoot: string;
  LRoot: string;
  LTargetMessage: string;
  LSearchPath: string;
  LSources: TLegacySources;
  LUsesPackages: Boolean;
  LWarning: string;
begin
  FCurrentPlatform := 'Win32';
  FCurrentConfig := 'Default';
  AProjectInfo.IsLegacyProject := True;
  AProjectInfo.Platform := 'Win32';
  AProjectInfo.Configuration := 'Default';
  AProjectInfo.UsesDebugDCUs := False;
  LTargetMessage := LegacyTargetMessage(APlatform, AConfiguration,
    FPlatformExplicit, FConfigurationExplicit);
  if LTargetMessage <> '' then
    FWarnings.Add(LTargetMessage);

  LSources := ResolveLegacySources(AProjectInfo.ProjectPath);
  if LSources.ProjectName <> '' then
    AProjectInfo.ProjectName := LSources.ProjectName;
  AProjectInfo.MainSourcePath := LSources.MainSourcePath;
  AProjectInfo.DllSuffix := LSources.LibSuffix;

  if (LSources.DofPath = '') and (LSources.CfgPath = '') then
    FWarnings.Add('No .dof or .cfg found next to the project. ' +
      'Output paths, search paths, and version info fall back to Delphi 7 defaults ' +
      '(the binary is written in the project directory).');

  try
    LDof := ParseDofOptions(LSources.DofPath);
  except
    on E: Exception do
    begin
      LDof := Default(TLegacyOptionSet);
      FWarnings.Add('Could not read .dof: ' + E.Message);
    end;
  end;

  try
    LCfg := ParseCfgOptions(LSources.CfgPath);
  except
    on E: Exception do
    begin
      LCfg := Default(TLegacyOptionSet);
      FWarnings.Add('Could not read .cfg: ' + E.Message);
    end;
  end;

  LOptions := MergeLegacyOptions(LDof, LCfg);

  if not TryResolveDelphi7Install(FDelphi7Root, LRoot, LLibrarySearchPath,
    LRegistryRoot, LPackageDplOutput, FWarnings) then
    LRoot := '';

  if LRoot <> '' then
  begin
    AProjectInfo.Toolchain.ProductName := 'Borland Delphi';
    AProjectInfo.Toolchain.Version := '7.0';
    AProjectInfo.Toolchain.RootDir := LRoot;
    AProjectInfo.Toolchain.BuildVersion :=
      GetFileVersionText(TPath.Combine(LRoot, 'bin\dcc32.exe'));
  end;

  if LOptions.HasUnitOutputDir and (Trim(LOptions.UnitOutputDir) <> '') then
    AProjectInfo.DcuOutputDir := ResolveLegacyDirectory(LOptions.UnitOutputDir,
      AProjectInfo.ProjectDir, AProjectInfo.ProjectName, LRoot, False);
  if LOptions.HasPackageDcpOutputDir and (Trim(LOptions.PackageDcpOutputDir) <> '') then
    AProjectInfo.DcpOutputDir := ResolveLegacyDirectory(LOptions.PackageDcpOutputDir,
      AProjectInfo.ProjectDir, AProjectInfo.ProjectName, LRoot, False);
  if LOptions.HasPackageDllOutputDir and (Trim(LOptions.PackageDllOutputDir) <> '') then
    AProjectInfo.BplOutputDir := ResolveLegacyDirectory(LOptions.PackageDllOutputDir,
      AProjectInfo.ProjectDir, AProjectInfo.ProjectName, LRoot, False);

  LOutputDir := '';
  if LOptions.HasOutputDir and (Trim(LOptions.OutputDir) <> '') then
    LOutputDir := ResolveLegacyDirectory(LOptions.OutputDir,
      AProjectInfo.ProjectDir, AProjectInfo.ProjectName, LRoot, False);
  AProjectInfo.OutputDir := LOutputDir;

  LExt := ModuleKindOutputExtension(LSources.ModuleKind);
  // A package is written to PackageDLLOutputDir (-LE). OutputDir (-E) is the
  // exe/dll directory and is not a fallback for the BPL.
  if SameText(LExt, '.bpl') then
  begin
    if AProjectInfo.BplOutputDir <> '' then
      AProjectInfo.ArtefactOutputDir := AProjectInfo.BplOutputDir
    else
    begin
      // PackageDLLOutputDir / -LE was blank. Delphi 7 writes the BPL to the
      // IDE's global directory when that registry install was found.
      LRegistryPackageDir := '';
      if LRegistryRoot <> '' then
        LRegistryPackageDir := ResolveLegacyDirectory(LPackageDplOutput,
          LRegistryRoot, AProjectInfo.ProjectName, LRegistryRoot, False);
      AProjectInfo.BplOutputDir := ResolveBlankPackageOutputDir(
        AProjectInfo.ProjectDir, LRegistryPackageDir, LRegistryRoot <> '');
      AProjectInfo.ArtefactOutputDir := AProjectInfo.BplOutputDir;
      if LRegistryPackageDir = '' then
        FWarnings.Add('No package output directory in the .dof or .cfg, and no ' +
          'Delphi 7 Package DPL Output value was found. Using the project directory.');
    end;
  end
  else if LOutputDir <> '' then
    AProjectInfo.ArtefactOutputDir := LOutputDir
  else
  begin
    AProjectInfo.ArtefactOutputDir := AProjectInfo.ProjectDir;
    if not LOptions.HasOutputDir then
      FWarnings.Add('No output directory in the .dof or .cfg. Using the project directory.');
  end;

  if AProjectInfo.OutputDir = '' then
    AProjectInfo.OutputDir := AProjectInfo.ArtefactOutputDir;

  if AProjectInfo.ProjectName <> '' then
  begin
    if SameText(LExt, '.exe') then
      AProjectInfo.OutputFilePath := TPath.Combine(AProjectInfo.ArtefactOutputDir,
        AProjectInfo.ProjectName + LExt)
    else
      AProjectInfo.OutputFilePath := TPath.Combine(AProjectInfo.ArtefactOutputDir,
        AProjectInfo.ProjectName + AProjectInfo.DllSuffix + LExt);
    AProjectInfo.MapFilePath := TPath.ChangeExtension(AProjectInfo.OutputFilePath, '.map');
  end;

  if Assigned(AProjectInfo.ExplicitUnitReferences) then
  begin
    AProjectInfo.ExplicitUnitReferences.Free;
    AProjectInfo.ExplicitUnitReferences := nil;
  end;
  AProjectInfo.ExplicitUnitReferences := ExtractMainSourceUnitReferences(
    AProjectInfo.MainSourcePath, AProjectInfo.ProjectDir, AProjectInfo.ProjectName);

  LSearchPath := '';
  if LOptions.HasSearchPath then
    LSearchPath := ExpandLegacyMacros(LOptions.SearchPath, LRoot);
  if (LRoot = '') and (Pos('$(DELPHI)', UpperCase(LSearchPath)) > 0) then
    FWarnings.Add('A search path entry uses $(DELPHI), but no Delphi 7 root was found. ' +
      'That entry was skipped.');

  AddExistingPath(AProjectInfo.ProjectDir, AProjectInfo.ProjectSearchPaths);
  AddDelimitedValues(LSearchPath, AProjectInfo.ProjectSearchPaths,
    AProjectInfo.ProjectDir, AProjectInfo.ProjectName, True);

  AddDelphi7LibraryPaths(AProjectInfo, LRoot, LLibrarySearchPath, AProjectInfo.ProjectName);

  CopyUniqueValues(AProjectInfo.ProjectSearchPaths, AProjectInfo.SearchPaths);
  CopyUniqueValues(AProjectInfo.GlobalSearchPaths, AProjectInfo.SearchPaths);

  LUsesPackages := ResolveRuntimePackages(LDof, LCfg, LPackageList);
  if LUsesPackages then
    for LPackageItem in LPackageList.Split([';']) do
    begin
      LPackageName := Trim(LPackageItem);
      if (LPackageName = '') or (LPackageName[1] = '$') then
        Continue;
      if not AProjectInfo.RuntimePackages.Contains(LPackageName) then
        AProjectInfo.RuntimePackages.Add(LPackageName);
    end;

  AProjectInfo.ConditionalDefines := LOptions.Conditionals;
  AProjectInfo.Version := LegacyVersionText(LOptions);
  if LOptions.HasCompanyName then
    AProjectInfo.CompanyName := Trim(LOptions.CompanyName);

  for LWarning in FWarnings do
    AProjectInfo.Warnings.Add(LWarning);
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
    FBdsProductVersion := DetectBdsProductVersion;
    Result.ProjectPath := AProjectPath;
    // Resolve the project directory from an absolute path so it is never empty.
    // A project path without a directory part (e.g. "MyProj.dproj" passed on a
    // CI agent with a different working directory) would otherwise yield an
    // empty ProjectDir, which cascades into an empty OutputDir and crashes the
    // file scanner with EInOutArgumentException (issue #47).
    // TPath.GetFullPath itself raises on an empty or syntactically invalid path,
    // so guard it: fall back to the raw directory part rather than propagating
    // an exception out of Scan.
    try
      Result.ProjectDir := TPath.GetDirectoryName(TPath.GetFullPath(AProjectPath));
    except
      on EInOutArgumentException do
        Result.ProjectDir := TPath.GetDirectoryName(AProjectPath);
    end;
    Result.ProjectName := TPath.GetFileNameWithoutExtension(AProjectPath);

    if IsLegacyProjectFile(AProjectPath) then
    begin
      PopulateLegacyProject(Result, APlatform, AConfiguration);
      Exit;
    end;

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

    // Extract output directory. Try the expanded path, then the same path
    // with unknown tokens removed, then a path with $(ProductVersion) empty.
    LExeOutputDir := ResolveOutputDirectory(GetPropertyValue('DCC_ExeOutput', ''),
      Result.ProjectDir, Result.ProjectName, 'DCC_ExeOutput', Result.ProgressNotes);
    LBplOutputDir := ResolveOutputDirectory(GetPropertyValue('DCC_BplOutput', ''),
      Result.ProjectDir, Result.ProjectName, 'DCC_BplOutput', Result.ProgressNotes);
    LDcpOutputDir := ResolveOutputDirectory(GetPropertyValue('DCC_DcpOutput', ''),
      Result.ProjectDir, Result.ProjectName, 'DCC_DcpOutput', Result.ProgressNotes);
    LDcuOutputDir := ResolveOutputDirectory(GetPropertyValue('DCC_DcuOutput', ''),
      Result.ProjectDir, Result.ProjectName, 'DCC_DcuOutput', Result.ProgressNotes);

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
      // Delphi's default: output goes to the project directory when no
      // DCC_ExeOutput / DCC_BplOutput is specified in the .dproj.
      Result.OutputDir := Result.ProjectDir;
      FWarnings.Add('No output directory found in .dproj. Using project directory as default.');
    end;

    Result.DllSuffix := GetPropertyValue('DllSuffix', '');
    ResolveOutputFile(Result);
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

    // Extract runtime packages. UsePackages gates the list. A readable output
    // binary then keeps only packages named in the PE import directory.
    if Assigned(Result.RuntimePackages) then
      Result.RuntimePackages.Free;
    Result.RuntimePackages := ExtractRuntimePackages(Result.OutputFilePath,
      Result.DllSuffix);

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
