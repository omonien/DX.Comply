/// <summary>
/// DX.Comply.LegacyProject
/// Reads Delphi 7 (and other pre-2007) project metadata from .dpr, .dpk,
/// .bdsproj, .dof, and .cfg files.
/// </summary>
///
/// <remarks>
/// DX.Comply does not compile these projects. It reads the project source
/// plus the sibling option files the user's own build already produced.
///
/// Precedence: when both a .dof and a .cfg define a value, the .dof wins.
/// The .cfg supplies a value only when the .dof does not define that key.
/// An empty .dof value still counts as defined, so it blocks the .cfg value.
///
/// Delphi 7 has one Win32 option set. There is no Debug/Release split in the
/// .dof. Library units are resolved from the Borland Delphi 7.0 registry
/// keys when that install is present. A missing install is not an error.
/// </remarks>
///
/// <copyright>
/// Copyright (c) 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.LegacyProject;

interface

uses
  System.Generics.Collections;

type
  /// <summary>
  /// Output kind taken from the program, library, or package header.
  /// </summary>
  TLegacyModuleKind = (
    lmkProgram,
    lmkLibrary,
    lmkPackage
  );

  /// <summary>
  /// Compiler settings read from one .dof or one .cfg.
  /// Has* is True when that file defines the value, including an empty value.
  /// </summary>
  TLegacyOptionSet = record
    HasOutputDir: Boolean;
    OutputDir: string;
    HasUnitOutputDir: Boolean;
    UnitOutputDir: string;
    HasPackageDllOutputDir: Boolean;
    PackageDllOutputDir: string;
    HasPackageDcpOutputDir: Boolean;
    PackageDcpOutputDir: string;
    HasSearchPath: Boolean;
    SearchPath: string;
    HasPackages: Boolean;
    Packages: string;
    HasConditionals: Boolean;
    Conditionals: string;
    HasUsePackages: Boolean;
    UsePackages: Boolean;
    HasMapFile: Boolean;
    MapFile: Integer;
    HasDetailedMap: Boolean;
    HasFileVersion: Boolean;
    FileVersion: string;
    HasCompanyName: Boolean;
    CompanyName: string;
    HasProductName: Boolean;
    ProductName: string;
    HasVersionNumbers: Boolean;
    MajorVer: string;
    MinorVer: string;
    Release: string;
    Build: string;
  end;

  /// <summary>
  /// Source file, option files, and header facts for one legacy project.
  /// </summary>
  TLegacySources = record
    ProjectPath: string;
    MainSourcePath: string;
    DofPath: string;
    CfgPath: string;
    ProjectName: string;
    ModuleKind: TLegacyModuleKind;
    LibSuffix: string;
  end;

/// <summary>
/// True for .dpr, .dpk, and .bdsproj. .dproj and .groupproj stay on the
/// MSBuild reader.
/// </summary>
function IsLegacyProjectFile(const AProjectPath: string): Boolean;

/// <summary>
/// Locates the main source, the sibling .dof and .cfg, and the module kind.
/// Missing option files leave DofPath or CfgPath empty. They are not an error.
/// </summary>
function ResolveLegacySources(const AProjectPath: string): TLegacySources;

/// <summary>
/// Reads a Delphi 7 .dof (INI). A missing file returns an empty option set.
/// </summary>
function ParseDofOptions(const AFilePath: string): TLegacyOptionSet;

/// <summary>
/// Reads a dcc32 .cfg response file. A missing file returns an empty option set.
/// </summary>
function ParseCfgOptions(const AFilePath: string): TLegacyOptionSet;

/// <summary>
/// Copies each defined value from APreferred, otherwise from AFallback.
/// </summary>
function MergeLegacyOptions(const APreferred, AFallback: TLegacyOptionSet): TLegacyOptionSet;

/// <summary>
/// True when the project links with runtime packages. A .dof UsePackages
/// value wins over -LU in the .cfg. When UsePackages is off, the package
/// list is cleared even if the .cfg names packages.
/// </summary>
function ResolveRuntimePackages(const ADof, ACfg: TLegacyOptionSet;
  out APackages: string): Boolean;

/// <summary>
/// FileVersion when present, otherwise Major.Minor.Release.Build, otherwise 1.0.0.0.
/// </summary>
function LegacyVersionText(const AOptions: TLegacyOptionSet): string;

/// <summary>
/// Output extension for the module kind: .exe, .dll, or .bpl.
/// </summary>
function ModuleKindOutputExtension(AKind: TLegacyModuleKind): string;

/// <summary>
/// Replaces $(DELPHI) and $(BDS) with ARoot. Other tokens are left in place.
/// </summary>
function ExpandLegacyMacros(const AValue, ARoot: string): string;

/// <summary>
/// Header keyword after comments are removed. The extension is the fallback
/// when the source has no program, library, or package keyword.
/// </summary>
function DetectModuleKind(const ASourceText, AExtension: string): TLegacyModuleKind;

/// <summary>
/// Reads {$LIBSUFFIX '...'} from package or library source. False when absent.
/// </summary>
function TryReadLibSuffix(const ASourceText: string; out ASuffix: string): Boolean;

/// <summary>
/// Warning text when the caller explicitly requested a platform or
/// configuration that a legacy project cannot select. Empty when neither
/// request was explicit, or when the explicit value is already Win32 / Default.
/// The built-in Release default must not produce a warning.
/// </summary>
function LegacyTargetMessage(const ARequestedPlatform,
  ARequestedConfiguration: string; APlatformExplicit,
  AConfigurationExplicit: Boolean): string;

/// <summary>
/// BPL directory when PackageDLLOutputDir is blank. The registry package
/// directory is used only when the Delphi 7 registry root was found and that
/// value is non-empty. Otherwise the project directory is used.
/// </summary>
function ResolveBlankPackageOutputDir(const AProjectDir,
  ARegistryPackageDir: string; ARegistryRootFound: Boolean): string;

/// <summary>
/// Error text used when the detailed MAP file is not next to the output binary.
/// </summary>
function LegacyMapFileMissingMessage(const AMapFilePath: string): string;

/// <summary>
/// Resolves a Delphi 7 installation root and the IDE library search path.
/// ARootOverride wins when that directory exists. Otherwise HKCU, then HKLM,
/// Software\Borland\Delphi\7.0, then the DELPHI environment variable.
/// ARegistryRoot is set only when that registry RootDir exists on disk.
/// APackageDplOutput is the Library value "Package DPL Output" in that case.
/// Returns False when no root directory exists. Never raises because Delphi 7
/// is absent.
/// </summary>
function TryResolveDelphi7Install(const ARootOverride: string;
  out ARootDir, ALibrarySearchPath, ARegistryRoot, APackageDplOutput: string;
  const AWarnings: TList<string>): Boolean;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.IOUtils,
  System.IniFiles,
  System.RegularExpressions,
  System.Win.Registry,
  Winapi.Windows;

const
  cDelphi7Key = '\SOFTWARE\Borland\Delphi\7.0';
  cDelphi7LibraryKey = '\SOFTWARE\Borland\Delphi\7.0\Library';

function IsLegacyProjectFile(const AProjectPath: string): Boolean;
var
  LExt: string;
begin
  LExt := LowerCase(TPath.GetExtension(AProjectPath));
  Result := (LExt = '.dpr') or (LExt = '.dpk') or (LExt = '.bdsproj');
end;

function StripQuotes(const AValue: string): string;
begin
  Result := Trim(AValue);
  if (Length(Result) >= 2) and
     ((Result[1] = '"') or (Result[1] = '''')) and
     (Result[Length(Result)] = Result[1]) then
    Result := Copy(Result, 2, Length(Result) - 2);
  Result := Trim(Result);
end;

function ReadLegacyText(const APath: string): string;
var
  LBytes: TBytes;
  LEncoding: TEncoding;
  LPreambleSize: Integer;
begin
  Result := '';
  if (Trim(APath) = '') or not TFile.Exists(APath) then
    Exit;

  // Delphi 7 writes project files as ANSI. A BOM, when present, wins.
  LBytes := TFile.ReadAllBytes(APath);
  LEncoding := nil;
  LPreambleSize := TEncoding.GetBufferEncoding(LBytes, LEncoding, TEncoding.ANSI);
  Result := LEncoding.GetString(LBytes, LPreambleSize, Length(LBytes) - LPreambleSize);
end;

function StripPascalComments(const AText: string): string;
begin
  Result := TRegEx.Replace(AText, '\(\*.*?\*\)', ' ', [roSingleLine]);
  Result := TRegEx.Replace(Result, '\{.*?\}', ' ', [roSingleLine]);
  Result := TRegEx.Replace(Result, '//.*$', ' ', [roMultiLine]);
end;

function DetectModuleKind(const ASourceText, AExtension: string): TLegacyModuleKind;
var
  LMatch: TMatch;
  LText: string;
begin
  if SameText(AExtension, '.dpk') then
    Result := lmkPackage
  else
    Result := lmkProgram;

  LText := StripPascalComments(ASourceText);
  LMatch := TRegEx.Match(LText, '\b(program|library|package)\b', [roIgnoreCase]);
  if not LMatch.Success then
    Exit;

  if SameText(LMatch.Groups[1].Value, 'library') then
    Exit(lmkLibrary);
  if SameText(LMatch.Groups[1].Value, 'package') then
    Exit(lmkPackage);
  Result := lmkProgram;
end;

function TryReadLibSuffix(const ASourceText: string; out ASuffix: string): Boolean;
var
  LMatch: TMatch;
begin
  ASuffix := '';
  LMatch := TRegEx.Match(ASourceText,
    '\{\$\s*LIBSUFFIX\s+(''([^'']*)''|"([^"]*)")\s*\}',
    [roIgnoreCase, roSingleLine]);
  Result := LMatch.Success;
  if not Result then
    Exit;

  if LMatch.Groups.Count >= 3 then
    ASuffix := LMatch.Groups[2].Value;
  if (ASuffix = '') and (LMatch.Groups.Count >= 4) then
    ASuffix := LMatch.Groups[3].Value;
end;

function ModuleKindOutputExtension(AKind: TLegacyModuleKind): string;
begin
  case AKind of
    lmkLibrary:
      Result := '.dll';
    lmkPackage:
      Result := '.bpl';
  else
    Result := '.exe';
  end;
end;

function ExpandLegacyMacros(const AValue, ARoot: string): string;
begin
  Result := AValue;
  if Trim(ARoot) = '' then
    Exit;

  Result := StringReplace(Result, '$(DELPHI)', ARoot, [rfIgnoreCase, rfReplaceAll]);
  Result := StringReplace(Result, '$(BDS)', ARoot, [rfIgnoreCase, rfReplaceAll]);
end;

function FirstExistingFile(const ACandidates: array of string): string;
var
  LCandidate: string;
begin
  Result := '';
  for LCandidate in ACandidates do
  begin
    if (Trim(LCandidate) <> '') and TFile.Exists(LCandidate) then
      Exit(LCandidate);
  end;
end;

function ChangeExtIfPresent(const APath, AExt: string): string;
begin
  if Trim(APath) = '' then
    Result := ''
  else
    Result := TPath.ChangeExtension(APath, AExt);
end;

function ExtractBdsprojMainSource(const AText: string): string;
var
  LMatch: TMatch;
begin
  Result := '';
  LMatch := TRegEx.Match(AText,
    '<Source\s+Name\s*=\s*"MainSource"\s*>\s*([^<]+?)\s*</Source>',
    [roIgnoreCase, roSingleLine]);
  if LMatch.Success then
    Result := Trim(LMatch.Groups[1].Value);
end;

function ResolveLegacySources(const AProjectPath: string): TLegacySources;
var
  LExtension: string;
  LMainText: string;
  LProjectDir: string;
  LSiblingDpr: string;
  LSiblingDpk: string;
begin
  Result := Default(TLegacySources);
  Result.ProjectPath := AProjectPath;
  Result.ModuleKind := lmkProgram;
  if Trim(AProjectPath) = '' then
    Exit;

  LProjectDir := TPath.GetDirectoryName(AProjectPath);
  LExtension := LowerCase(TPath.GetExtension(AProjectPath));

  if LExtension = '.bdsproj' then
  begin
    LMainText := ExtractBdsprojMainSource(ReadLegacyText(AProjectPath));
    if LMainText <> '' then
    begin
      if TPath.IsRelativePath(LMainText) then
        Result.MainSourcePath := TPath.Combine(LProjectDir, LMainText)
      else
        Result.MainSourcePath := LMainText;
      try
        Result.MainSourcePath := TPath.GetFullPath(Result.MainSourcePath);
      except
        // Keep the combined path when the name is not a valid filesystem path.
      end;
    end;

    if Result.MainSourcePath = '' then
    begin
      LSiblingDpr := TPath.ChangeExtension(AProjectPath, '.dpr');
      LSiblingDpk := TPath.ChangeExtension(AProjectPath, '.dpk');
      if TFile.Exists(LSiblingDpr) then
        Result.MainSourcePath := TPath.GetFullPath(LSiblingDpr)
      else if TFile.Exists(LSiblingDpk) then
        Result.MainSourcePath := TPath.GetFullPath(LSiblingDpk);
    end;
  end
  else
  begin
    try
      Result.MainSourcePath := TPath.GetFullPath(AProjectPath);
    except
      Result.MainSourcePath := AProjectPath;
    end;
  end;

  if Result.MainSourcePath <> '' then
    Result.ProjectName := TPath.GetFileNameWithoutExtension(Result.MainSourcePath)
  else
    Result.ProjectName := TPath.GetFileNameWithoutExtension(AProjectPath);

  LMainText := ReadLegacyText(Result.MainSourcePath);
  Result.ModuleKind := DetectModuleKind(LMainText,
    TPath.GetExtension(Result.MainSourcePath));
  if not TryReadLibSuffix(LMainText, Result.LibSuffix) then
    Result.LibSuffix := '';

  Result.DofPath := FirstExistingFile([
    ChangeExtIfPresent(AProjectPath, '.dof'),
    ChangeExtIfPresent(Result.MainSourcePath, '.dof')]);
  Result.CfgPath := FirstExistingFile([
    ChangeExtIfPresent(AProjectPath, '.cfg'),
    ChangeExtIfPresent(Result.MainSourcePath, '.cfg')]);
end;

procedure ReadIniText(const AIni: TMemIniFile; const ASection, AName: string;
  out AHasValue: Boolean; out AValue: string);
begin
  AHasValue := AIni.ValueExists(ASection, AName);
  if AHasValue then
    AValue := Trim(AIni.ReadString(ASection, AName, ''))
  else
    AValue := '';
end;

function ParseUsePackagesFlag(const AValue: string): Boolean;
var
  LValue: string;
begin
  LValue := LowerCase(Trim(AValue));
  Result := (LValue = '1') or (LValue = 'true') or (LValue = 'yes');
end;

function ParseDofOptions(const AFilePath: string): TLegacyOptionSet;
var
  LIni: TMemIniFile;
begin
  Result := Default(TLegacyOptionSet);
  if (Trim(AFilePath) = '') or not TFile.Exists(AFilePath) then
    Exit;

  LIni := TMemIniFile.Create(AFilePath, TEncoding.ANSI);
  try
    ReadIniText(LIni, 'Directories', 'OutputDir',
      Result.HasOutputDir, Result.OutputDir);
    ReadIniText(LIni, 'Directories', 'UnitOutputDir',
      Result.HasUnitOutputDir, Result.UnitOutputDir);
    ReadIniText(LIni, 'Directories', 'PackageDLLOutputDir',
      Result.HasPackageDllOutputDir, Result.PackageDllOutputDir);
    ReadIniText(LIni, 'Directories', 'PackageDCPOutputDir',
      Result.HasPackageDcpOutputDir, Result.PackageDcpOutputDir);
    ReadIniText(LIni, 'Directories', 'SearchPath',
      Result.HasSearchPath, Result.SearchPath);
    ReadIniText(LIni, 'Directories', 'Packages',
      Result.HasPackages, Result.Packages);
    ReadIniText(LIni, 'Directories', 'Conditionals',
      Result.HasConditionals, Result.Conditionals);

    if LIni.ValueExists('Directories', 'UsePackages') then
    begin
      Result.HasUsePackages := True;
      Result.UsePackages := ParseUsePackagesFlag(
        LIni.ReadString('Directories', 'UsePackages', '0'));
    end;

    if LIni.ValueExists('Linker', 'MapFile') then
    begin
      Result.HasMapFile := True;
      Result.MapFile := LIni.ReadInteger('Linker', 'MapFile', 0);
      Result.HasDetailedMap := Result.MapFile = 3;
    end;

    ReadIniText(LIni, 'Version Info Keys', 'FileVersion',
      Result.HasFileVersion, Result.FileVersion);
    ReadIniText(LIni, 'Version Info Keys', 'CompanyName',
      Result.HasCompanyName, Result.CompanyName);
    ReadIniText(LIni, 'Version Info Keys', 'ProductName',
      Result.HasProductName, Result.ProductName);

    if LIni.ValueExists('Version Info', 'MajorVer') or
       LIni.ValueExists('Version Info', 'MinorVer') or
       LIni.ValueExists('Version Info', 'Release') or
       LIni.ValueExists('Version Info', 'Build') then
    begin
      Result.HasVersionNumbers := True;
      Result.MajorVer := Trim(LIni.ReadString('Version Info', 'MajorVer', '0'));
      Result.MinorVer := Trim(LIni.ReadString('Version Info', 'MinorVer', '0'));
      Result.Release := Trim(LIni.ReadString('Version Info', 'Release', '0'));
      Result.Build := Trim(LIni.ReadString('Version Info', 'Build', '0'));
    end;
  finally
    LIni.Free;
  end;
end;

procedure TokenizeCfg(const AText: string; const ATokens: TList<string>);
var
  I: Integer;
  LChar: Char;
  LInQuote: Boolean;
  LQuote: Char;
  LToken: string;
begin
  LInQuote := False;
  LQuote := #0;
  LToken := '';
  I := 1;
  while I <= Length(AText) do
  begin
    LChar := AText[I];
    if LInQuote then
    begin
      LToken := LToken + LChar;
      if LChar = LQuote then
        LInQuote := False;
    end
    else if (LChar = '"') or (LChar = '''') then
    begin
      LInQuote := True;
      LQuote := LChar;
      LToken := LToken + LChar;
    end
    else if CharInSet(LChar, [' ', #9, #10, #13]) then
    begin
      if LToken <> '' then
      begin
        ATokens.Add(LToken);
        LToken := '';
      end;
    end
    else
      LToken := LToken + LChar;
    Inc(I);
  end;
  if LToken <> '' then
    ATokens.Add(LToken);
end;

procedure AppendListValue(var ATarget: string; const AValue: string);
begin
  if Trim(AValue) = '' then
    Exit;
  if ATarget = '' then
    ATarget := Trim(AValue)
  else
    ATarget := ATarget + ';' + Trim(AValue);
end;

function TrySplitCfgSwitch(const AToken, AName: string; out AInlineValue: string;
  out ANeedsNextToken: Boolean): Boolean;
var
  LPrefix: string;
begin
  AInlineValue := '';
  ANeedsNextToken := False;
  LPrefix := '-' + AName;
  if SameText(AToken, LPrefix) then
  begin
    ANeedsNextToken := True;
    Exit(True);
  end;

  if StartsText(LPrefix, AToken) and (Length(AToken) > Length(LPrefix)) then
  begin
    AInlineValue := StripQuotes(Copy(AToken, Length(LPrefix) + 1, MaxInt));
    Exit(True);
  end;

  Result := False;
end;

function NextCfgValue(const ATokens: TList<string>; var AIndex: Integer): string;
var
  LNext: string;
begin
  Result := '';
  if AIndex >= ATokens.Count then
    Exit;

  LNext := ATokens[AIndex];
  // Another real switch, not a compiler directive such as -$M.
  if StartsText('-', LNext) and not StartsText('-$', LNext) then
    Exit;

  Result := StripQuotes(LNext);
  Inc(AIndex);
end;

function ParseCfgOptions(const AFilePath: string): TLegacyOptionSet;
var
  LIndex: Integer;
  LInline: string;
  LNeedsNext: Boolean;
  LText: string;
  LToken: string;
  LTokens: TList<string>;
  LValue: string;
begin
  Result := Default(TLegacyOptionSet);
  if (Trim(AFilePath) = '') or not TFile.Exists(AFilePath) then
    Exit;

  LText := ReadLegacyText(AFilePath);
  LTokens := TList<string>.Create;
  try
    TokenizeCfg(LText, LTokens);
    LIndex := 0;
    while LIndex < LTokens.Count do
    begin
      LToken := LTokens[LIndex];
      Inc(LIndex);
      if not StartsText('-', LToken) or StartsText('-$', LToken) then
        Continue;

      if SameText(LToken, '-GD') then
      begin
        Result.HasDetailedMap := True;
        Continue;
      end;

      // Longer names first so -E does not consume -E from a different switch
      // and -N does not consume -N0 or -NS.
      if TrySplitCfgSwitch(LToken, 'LE', LInline, LNeedsNext) then
      begin
        if LNeedsNext then
          LValue := NextCfgValue(LTokens, LIndex)
        else
          LValue := LInline;
        Result.HasPackageDllOutputDir := True;
        Result.PackageDllOutputDir := LValue;
      end
      else if TrySplitCfgSwitch(LToken, 'LN', LInline, LNeedsNext) then
      begin
        if LNeedsNext then
          LValue := NextCfgValue(LTokens, LIndex)
        else
          LValue := LInline;
        Result.HasPackageDcpOutputDir := True;
        Result.PackageDcpOutputDir := LValue;
      end
      else if TrySplitCfgSwitch(LToken, 'LU', LInline, LNeedsNext) then
      begin
        if LNeedsNext then
          LValue := NextCfgValue(LTokens, LIndex)
        else
          LValue := LInline;
        Result.HasPackages := True;
        AppendListValue(Result.Packages, LValue);
      end
      else if TrySplitCfgSwitch(LToken, 'N0', LInline, LNeedsNext) then
      begin
        if LNeedsNext then
          LValue := NextCfgValue(LTokens, LIndex)
        else
          LValue := LInline;
        Result.HasUnitOutputDir := True;
        Result.UnitOutputDir := LValue;
      end
      else if TrySplitCfgSwitch(LToken, 'NS', LInline, LNeedsNext) then
      begin
        // Unit scopes are a later-Delphi switch. Delphi 7 does not use them.
        if LNeedsNext then
          NextCfgValue(LTokens, LIndex);
      end
      else if TrySplitCfgSwitch(LToken, 'E', LInline, LNeedsNext) then
      begin
        if LNeedsNext then
          LValue := NextCfgValue(LTokens, LIndex)
        else
          LValue := LInline;
        Result.HasOutputDir := True;
        Result.OutputDir := LValue;
      end
      else if TrySplitCfgSwitch(LToken, 'N', LInline, LNeedsNext) then
      begin
        if LNeedsNext then
          LValue := NextCfgValue(LTokens, LIndex)
        else
          LValue := LInline;
        Result.HasUnitOutputDir := True;
        Result.UnitOutputDir := LValue;
      end
      else if TrySplitCfgSwitch(LToken, 'U', LInline, LNeedsNext) then
      begin
        if LNeedsNext then
          LValue := NextCfgValue(LTokens, LIndex)
        else
          LValue := LInline;
        Result.HasSearchPath := True;
        AppendListValue(Result.SearchPath, LValue);
      end
      else if TrySplitCfgSwitch(LToken, 'D', LInline, LNeedsNext) then
      begin
        if LNeedsNext then
          LValue := NextCfgValue(LTokens, LIndex)
        else
          LValue := LInline;
        Result.HasConditionals := True;
        AppendListValue(Result.Conditionals, LValue);
      end;
    end;
  finally
    LTokens.Free;
  end;
end;

function PickOption(APreferredHas: Boolean; const APreferred: string;
  AFallbackHas: Boolean; const AFallback: string; out AHas: Boolean): string;
begin
  if APreferredHas then
  begin
    AHas := True;
    Exit(APreferred);
  end;
  AHas := AFallbackHas;
  Result := AFallback;
end;

function MergeLegacyOptions(const APreferred, AFallback: TLegacyOptionSet): TLegacyOptionSet;
begin
  Result := Default(TLegacyOptionSet);
  Result.OutputDir := PickOption(APreferred.HasOutputDir, APreferred.OutputDir,
    AFallback.HasOutputDir, AFallback.OutputDir, Result.HasOutputDir);
  Result.UnitOutputDir := PickOption(APreferred.HasUnitOutputDir, APreferred.UnitOutputDir,
    AFallback.HasUnitOutputDir, AFallback.UnitOutputDir, Result.HasUnitOutputDir);
  Result.PackageDllOutputDir := PickOption(APreferred.HasPackageDllOutputDir,
    APreferred.PackageDllOutputDir, AFallback.HasPackageDllOutputDir,
    AFallback.PackageDllOutputDir, Result.HasPackageDllOutputDir);
  Result.PackageDcpOutputDir := PickOption(APreferred.HasPackageDcpOutputDir,
    APreferred.PackageDcpOutputDir, AFallback.HasPackageDcpOutputDir,
    AFallback.PackageDcpOutputDir, Result.HasPackageDcpOutputDir);
  Result.SearchPath := PickOption(APreferred.HasSearchPath, APreferred.SearchPath,
    AFallback.HasSearchPath, AFallback.SearchPath, Result.HasSearchPath);
  Result.Packages := PickOption(APreferred.HasPackages, APreferred.Packages,
    AFallback.HasPackages, AFallback.Packages, Result.HasPackages);
  Result.Conditionals := PickOption(APreferred.HasConditionals, APreferred.Conditionals,
    AFallback.HasConditionals, AFallback.Conditionals, Result.HasConditionals);

  if APreferred.HasUsePackages then
  begin
    Result.HasUsePackages := True;
    Result.UsePackages := APreferred.UsePackages;
  end
  else if AFallback.HasUsePackages then
  begin
    Result.HasUsePackages := True;
    Result.UsePackages := AFallback.UsePackages;
  end;

  if APreferred.HasMapFile then
  begin
    Result.HasMapFile := True;
    Result.MapFile := APreferred.MapFile;
  end
  else if AFallback.HasMapFile then
  begin
    Result.HasMapFile := True;
    Result.MapFile := AFallback.MapFile;
  end;

  // MapFile in the .dof describes the whole map setting, so -GD in the .cfg
  // does not override MapFile=0, 1, or 2.
  if APreferred.HasMapFile or APreferred.HasDetailedMap then
    Result.HasDetailedMap := APreferred.HasDetailedMap or
      (APreferred.HasMapFile and (APreferred.MapFile = 3))
  else
    Result.HasDetailedMap := AFallback.HasDetailedMap or
      (AFallback.HasMapFile and (AFallback.MapFile = 3));

  Result.FileVersion := PickOption(APreferred.HasFileVersion, APreferred.FileVersion,
    AFallback.HasFileVersion, AFallback.FileVersion, Result.HasFileVersion);
  Result.CompanyName := PickOption(APreferred.HasCompanyName, APreferred.CompanyName,
    AFallback.HasCompanyName, AFallback.CompanyName, Result.HasCompanyName);
  Result.ProductName := PickOption(APreferred.HasProductName, APreferred.ProductName,
    AFallback.HasProductName, AFallback.ProductName, Result.HasProductName);

  if APreferred.HasVersionNumbers then
  begin
    Result.HasVersionNumbers := True;
    Result.MajorVer := APreferred.MajorVer;
    Result.MinorVer := APreferred.MinorVer;
    Result.Release := APreferred.Release;
    Result.Build := APreferred.Build;
  end
  else if AFallback.HasVersionNumbers then
  begin
    Result.HasVersionNumbers := True;
    Result.MajorVer := AFallback.MajorVer;
    Result.MinorVer := AFallback.MinorVer;
    Result.Release := AFallback.Release;
    Result.Build := AFallback.Build;
  end;
end;

function ResolveRuntimePackages(const ADof, ACfg: TLegacyOptionSet;
  out APackages: string): Boolean;
begin
  APackages := '';
  if ADof.HasUsePackages then
  begin
    Result := ADof.UsePackages;
    if not Result then
      Exit;
    if ADof.HasPackages then
      APackages := ADof.Packages
    else
      APackages := ACfg.Packages;
    Exit;
  end;

  if ACfg.HasPackages and (Trim(ACfg.Packages) <> '') then
  begin
    Result := True;
    APackages := ACfg.Packages;
    Exit;
  end;

  Result := False;
end;

function ValueOrDefault(const AValue, ADefault: string): string;
begin
  Result := Trim(AValue);
  if Result = '' then
    Result := ADefault;
end;

function LegacyVersionText(const AOptions: TLegacyOptionSet): string;
begin
  if AOptions.HasFileVersion and (Trim(AOptions.FileVersion) <> '') then
    Exit(Trim(AOptions.FileVersion));

  if AOptions.HasVersionNumbers then
    Exit(ValueOrDefault(AOptions.MajorVer, '0') + '.' +
      ValueOrDefault(AOptions.MinorVer, '0') + '.' +
      ValueOrDefault(AOptions.Release, '0') + '.' +
      ValueOrDefault(AOptions.Build, '0'));

  Result := '1.0.0.0';
end;

function LegacyTargetMessage(const ARequestedPlatform,
  ARequestedConfiguration: string; APlatformExplicit,
  AConfigurationExplicit: Boolean): string;
var
  LIgnored: string;
begin
  LIgnored := '';
  if APlatformExplicit and (Trim(ARequestedPlatform) <> '') and
     not SameText(ARequestedPlatform, 'Win32') then
    LIgnored := 'Ignoring requested platform "' + ARequestedPlatform + '".';
  if AConfigurationExplicit and (Trim(ARequestedConfiguration) <> '') and
     not SameText(ARequestedConfiguration, 'Default') then
  begin
    if LIgnored <> '' then
      LIgnored := LIgnored + ' ';
    LIgnored := LIgnored + 'Ignoring requested configuration "' +
      ARequestedConfiguration + '".';
  end;

  if LIgnored = '' then
    Exit('');

  Result := 'Legacy Delphi project: using the single Win32 option set from ' +
    'the sibling .dof and .cfg. ' + LIgnored;
end;

function ResolveBlankPackageOutputDir(const AProjectDir,
  ARegistryPackageDir: string; ARegistryRootFound: Boolean): string;
begin
  if ARegistryRootFound and (Trim(ARegistryPackageDir) <> '') then
    Result := Trim(ARegistryPackageDir)
  else
    Result := AProjectDir;
end;

function LegacyMapFileMissingMessage(const AMapFilePath: string): string;
begin
  Result := 'No detailed MAP file found next to the output binary';
  if Trim(AMapFilePath) <> '' then
    Result := Result + ': ' + AMapFilePath;
  Result := Result +
    '. In Delphi 7 open Project Options, Linker, and set Map file to Detailed,' +
    ' or add -GD to the .cfg, then rebuild.' +
    ' If the MAP file is in another directory, pass --map-dir.';
end;

procedure AddWarning(const AWarnings: TList<string>; const AMessage: string);
begin
  if Assigned(AWarnings) and (Trim(AMessage) <> '') and not AWarnings.Contains(AMessage) then
    AWarnings.Add(AMessage);
end;

function ReadRegistryString(ARootKey: HKEY; const AKeyPath, AValueName: string): string;
var
  LRegistry: TRegistry;

  procedure TryRead(const AAccess: REGSAM);
  begin
    if Result <> '' then
      Exit;

    LRegistry.Access := KEY_READ or AAccess;
    if not LRegistry.OpenKeyReadOnly(AKeyPath) then
      Exit;
    try
      if LRegistry.ValueExists(AValueName) then
        Result := Trim(LRegistry.ReadString(AValueName));
    finally
      LRegistry.CloseKey;
    end;
  end;

begin
  Result := '';
  LRegistry := TRegistry.Create;
  try
    LRegistry.RootKey := ARootKey;
    TryRead(KEY_WOW64_32KEY);
    TryRead(KEY_WOW64_64KEY);
  finally
    LRegistry.Free;
  end;
end;

function ReadDelphi7RegistryValue(const AKeyPath, AValueName: string): string;
begin
  Result := ReadRegistryString(HKEY_CURRENT_USER, AKeyPath, AValueName);
  if Result = '' then
    Result := ReadRegistryString(HKEY_LOCAL_MACHINE, AKeyPath, AValueName);
end;

function NormalizeExistingRoot(const APath: string): string;
begin
  Result := Trim(APath);
  if Result = '' then
    Exit;

  Result := ExcludeTrailingPathDelimiter(Result);
  if not TDirectory.Exists(Result) then
    Exit('');

  try
    Result := ExcludeTrailingPathDelimiter(TPath.GetFullPath(Result));
  except
    Result := ExcludeTrailingPathDelimiter(Result);
  end;
end;

function TryResolveDelphi7Install(const ARootOverride: string;
  out ARootDir, ALibrarySearchPath, ARegistryRoot, APackageDplOutput: string;
  const AWarnings: TList<string>): Boolean;
var
  LFromRegistry: string;
begin
  ARootDir := '';
  ALibrarySearchPath := '';
  ARegistryRoot := '';
  APackageDplOutput := '';
  Result := False;

  if Trim(ARootOverride) <> '' then
  begin
    ARootDir := NormalizeExistingRoot(ARootOverride);
    if ARootDir = '' then
      AddWarning(AWarnings, 'Delphi 7 root "' + ARootOverride +
        '" was not found. Library units will not be read from that path.');
  end;

  try
    LFromRegistry := ReadDelphi7RegistryValue(cDelphi7Key, 'RootDir');
    ARegistryRoot := NormalizeExistingRoot(LFromRegistry);
    if ARootDir = '' then
      ARootDir := ARegistryRoot;

    ALibrarySearchPath := ReadDelphi7RegistryValue(cDelphi7LibraryKey, 'Search Path');
    if ALibrarySearchPath = '' then
      ALibrarySearchPath := ReadDelphi7RegistryValue(cDelphi7LibraryKey, 'SearchPath');
    // The global BPL directory is an IDE setting. Use it only when the
    // registry install itself was found, not when the caller passed a root.
    if ARegistryRoot <> '' then
      APackageDplOutput := ReadDelphi7RegistryValue(cDelphi7LibraryKey,
        'Package DPL Output');
  except
    on E: Exception do
      AddWarning(AWarnings, 'Could not read the Delphi 7 registry key: ' + E.Message);
  end;

  if ARootDir = '' then
  begin
    ARootDir := NormalizeExistingRoot(GetEnvironmentVariable('DELPHI'));
  end;

  Result := ARootDir <> '';
  if not Result then
    AddWarning(AWarnings,
      'Delphi 7 is not installed on this machine (no HKCU or HKLM ' +
      'Software\Borland\Delphi\7.0 RootDir). Library units from the Delphi 7 ' +
      'installation will not be resolved. Set --delphi7-root or delphi7Root in ' +
      '.dxcomply.json to point at a Delphi 7 tree.');
end;

end.
