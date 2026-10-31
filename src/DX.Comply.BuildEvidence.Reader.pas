/// <summary>
/// DX.Comply.BuildEvidence.Reader
/// First-pass implementation of normalized build evidence collection.
/// </summary>
///
/// <remarks>
/// Normalizes already-resolved project metadata and augments it with compiler
/// option files such as project-specific CFG files or nested response files.
/// The resulting evidence model gives later resolver stages a closer view of
/// the effective compiler search path order without needing to re-run Delphi.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.BuildEvidence.Reader;

interface

uses
  System.Generics.Collections,
  System.IOUtils,
  DX.Comply.Engine.Intf,
  DX.Comply.BuildEvidence.Intf,
  DX.Comply.LegacyProject,
  DX.Comply.MapFile.Reader;

type
  /// <summary>
  /// Implementation of IBuildEvidenceReader for the first evidence slice.
  /// </summary>
  TBuildEvidenceReader = class(TInterfacedObject, IBuildEvidenceReader)
  private
    /// <summary>
    /// Copies string list values into the target list without duplicates.
    /// </summary>
    procedure CopyUniqueValues(const ASource, ATarget: TList<string>);
    /// <summary>
    /// Adds a normalized evidence item.
    /// </summary>
    procedure AddEvidenceItem(var ABuildEvidence: TBuildEvidence;
      ASourceKind: TBuildEvidenceSourceKind; const ADisplayName, AFilePath,
      APackageName, AUnitName, ADetail: string);
    /// <summary>
    /// Adds semicolon-delimited compiler path values to the target list.
    /// </summary>
    procedure AddCompilerPaths(const AValue, ABaseDirectory: string;
      const AProjectInfo: TProjectInfo; const ATarget: TList<string>);
    /// <summary>
    /// Adds semicolon-delimited unit scope names to the target list.
    /// </summary>
    procedure AddCompilerUnitScopes(const AValue: string; const ATarget: TList<string>);
    /// <summary>
    /// Collects compiler option evidence from cfg/rsp files that affect the build.
    /// </summary>
    procedure CollectCompilerOptionEvidence(const AProjectInfo: TProjectInfo;
      var ABuildEvidence: TBuildEvidence);
    /// <summary>
    /// Expands common Delphi/MSBuild macros inside compiler option values.
    /// </summary>
    function ExpandCompilerOptionValue(const AValue: string;
      const AProjectInfo: TProjectInfo): string;
    /// <summary>
    /// Returns the platform-specific Delphi compiler cfg file name.
    /// </summary>
    function GetCompilerConfigFileName(const AProjectInfo: TProjectInfo): string;
    /// <summary>
    /// Parses one compiler option file and merges discovered paths/scopes.
    /// </summary>
    procedure ParseCompilerOptionFile(const AFilePath: string;
      const AProjectInfo: TProjectInfo; var ABuildEvidence: TBuildEvidence;
      const AVisitedFiles: TList<string>; const ASearchPaths,
      AUnitScopeNames: TList<string>);
    /// <summary>
    /// Splits compiler option content into whitespace-delimited tokens.
    /// </summary>
    function TokenizeCompilerOptions(const AContent: string): TArray<string>;
  public
    /// <summary>
    /// Reads normalized build evidence from the supplied project metadata.
    /// </summary>
    function Read(const AProjectInfo: TProjectInfo): TBuildEvidence;
  end;

/// <summary>
/// One log line for a build evidence item: display name, unit or package,
/// path, and detail. Unit rows are included. The engine summarises those.
/// </summary>
function BuildEvidenceItemLogLine(const AItem: TBuildEvidenceItem): string;

implementation

uses
  System.Classes,
  System.StrUtils,
  System.SysUtils;

function PlatformUsesMapFileArm(const APlatform: string): Boolean;
begin
  // Android and the iOS device linker expose "Map file ARM" (Off / On).
  // iOSSimARM64 uses that linker. The Windows "Map file > Detailed" list
  // is not on those pages.
  var LPlatform := Trim(APlatform);
  Result := StartsText('Android', LPlatform) or
    StartsText('iOSDevice', LPlatform) or
    SameText(LPlatform, 'iOSSimARM64');
end;

function MapFileArmEnableHint: string;
begin
  Result := 'Enable the map with Project Options > Linker > Map file ARM > On, then rebuild.';
end;

function ClassicDetailedMapHint: string;
begin
  Result :=
    'Enable detailed MAP output (Project Options > Linker > Map file > Detailed)' +
    ' or set DCC_MapFile=3 in the .dproj, then rebuild for full composition evidence.';
end;

function MapFileNoUnitsWarning(const AProjectInfo: TProjectInfo): string;
begin
  if AProjectInfo.IsLegacyProject then
    Exit('MAP file found but contains no unit information: ' +
      AProjectInfo.MapFilePath + '. ' +
      'In Delphi 7 open Project Options, Linker, and set Map file to Detailed, ' +
      'or add -GD to the .cfg, then rebuild.');

  if PlatformUsesMapFileArm(AProjectInfo.Platform) then
    Exit('MAP file found but contains no unit information DX.Comply can read: ' +
      AProjectInfo.MapFilePath + '. ' +
      'DX.Comply does not know how to read units from the ARM/LLVM map format ' +
      'and did not guess any. ' + MapFileArmEnableHint);

  if StartsText('Linux', Trim(AProjectInfo.Platform)) then
    Exit('MAP file found but contains no unit information DX.Comply can read: ' +
      AProjectInfo.MapFilePath + '. ' +
      'DX.Comply does not know how to read units from the Linux map format ' +
      'and did not guess any.');

  Result := 'MAP file found but contains no unit information: ' +
    AProjectInfo.MapFilePath + '. ' + ClassicDetailedMapHint;
end;

function MapFileMissingWarning(const AProjectInfo: TProjectInfo): string;
begin
  if AProjectInfo.IsLegacyProject then
    Exit(LegacyMapFileMissingMessage(AProjectInfo.MapFilePath));

  if PlatformUsesMapFileArm(AProjectInfo.Platform) then
    Exit('No MAP file found: ' + AProjectInfo.MapFilePath + '. ' + MapFileArmEnableHint);

  if StartsText('Linux', Trim(AProjectInfo.Platform)) then
    Exit('No MAP file found: ' + AProjectInfo.MapFilePath + '. ' +
      'DX.Comply does not know which IDE option writes a Linux map file.');

  Result := 'No detailed MAP file found: ' + AProjectInfo.MapFilePath;
end;

function BuildEvidenceItemLogLine(const AItem: TBuildEvidenceItem): string;
begin
  Result := Trim(AItem.DisplayName);
  if Result = '' then
    Result := 'Build evidence';

  if Trim(AItem.UnitName) <> '' then
    Result := Result + ': ' + Trim(AItem.UnitName)
  else if Trim(AItem.PackageName) <> '' then
    Result := Result + ': ' + Trim(AItem.PackageName);

  if Trim(AItem.FilePath) <> '' then
    Result := Result + ' - ' + Trim(AItem.FilePath);

  if Trim(AItem.Detail) <> '' then
    Result := Result + ' [' + Trim(AItem.Detail) + ']';
end;

procedure TBuildEvidenceReader.AddEvidenceItem(var ABuildEvidence: TBuildEvidence;
  ASourceKind: TBuildEvidenceSourceKind; const ADisplayName, AFilePath,
  APackageName, AUnitName, ADetail: string);
var
  LEvidenceItem: TBuildEvidenceItem;
begin
  LEvidenceItem := Default(TBuildEvidenceItem);
  LEvidenceItem.SourceKind := ASourceKind;
  LEvidenceItem.DisplayName := ADisplayName;
  LEvidenceItem.FilePath := AFilePath;
  LEvidenceItem.PackageName := APackageName;
  LEvidenceItem.UnitName := AUnitName;
  LEvidenceItem.Detail := ADetail;
  ABuildEvidence.EvidenceItems.Add(LEvidenceItem);
end;

procedure TBuildEvidenceReader.CopyUniqueValues(const ASource, ATarget: TList<string>);
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

procedure TBuildEvidenceReader.AddCompilerPaths(const AValue, ABaseDirectory: string;
  const AProjectInfo: TProjectInfo; const ATarget: TList<string>);
var
  LExpandedValue: string;
  LPath: string;
  LPathList: TStringList;
begin
  if not Assigned(ATarget) then
    Exit;

  LExpandedValue := ExpandCompilerOptionValue(AValue, AProjectInfo);
  if Trim(LExpandedValue) = '' then
    Exit;

  LPathList := TStringList.Create;
  try
    LPathList.StrictDelimiter := True;
    LPathList.Delimiter := ';';
    LPathList.DelimitedText := LExpandedValue;
    for LPath in LPathList do
    begin
      LExpandedValue := Trim(LPath);
      if LExpandedValue = '' then
        Continue;
      if (Length(LExpandedValue) > 0) and (LExpandedValue[1] = '"') then
        Delete(LExpandedValue, 1, 1);
      if (Length(LExpandedValue) > 0) and
        (LExpandedValue[Length(LExpandedValue)] = '"') then
        Delete(LExpandedValue, Length(LExpandedValue), 1);
      if not TPath.IsPathRooted(LExpandedValue) then
        LExpandedValue := TPath.GetFullPath(TPath.Combine(ABaseDirectory, LExpandedValue));
      if not ATarget.Contains(LExpandedValue) then
        ATarget.Add(LExpandedValue);
    end;
  finally
    LPathList.Free;
  end;
end;

procedure TBuildEvidenceReader.AddCompilerUnitScopes(const AValue: string;
  const ATarget: TList<string>);
var
  LNormalizedScope: string;
  LScope: string;
  LScopeList: TStringList;
begin
  if not Assigned(ATarget) or (Trim(AValue) = '') then
    Exit;

  LScopeList := TStringList.Create;
  try
    LScopeList.StrictDelimiter := True;
    LScopeList.Delimiter := ';';
    LScopeList.DelimitedText := AValue;
    for LScope in LScopeList do
    begin
      LNormalizedScope := Trim(LScope);
      if (LNormalizedScope <> '') and not ATarget.Contains(LNormalizedScope) then
        ATarget.Add(LNormalizedScope);
    end;
  finally
    LScopeList.Free;
  end;
end;

procedure TBuildEvidenceReader.CollectCompilerOptionEvidence(
  const AProjectInfo: TProjectInfo; var ABuildEvidence: TBuildEvidence);
var
  LCandidatePath: string;
  LCandidates: TList<string>;
  LCompilerConfigFileName: string;
  LSearchPaths: TList<string>;
  LUnitScopeNames: TList<string>;
  LVisitedFiles: TList<string>;

  procedure AddCandidate(const APath: string);
  var
    LFullPath: string;
  begin
    if Trim(APath) = '' then
      Exit;
    LFullPath := TPath.GetFullPath(APath);
    if TFile.Exists(LFullPath) and not LCandidates.Contains(LFullPath) then
      LCandidates.Add(LFullPath);
  end;
begin
  LCandidates := TList<string>.Create;
  LSearchPaths := TList<string>.Create;
  LUnitScopeNames := TList<string>.Create;
  LVisitedFiles := TList<string>.Create;
  try
    LCompilerConfigFileName := GetCompilerConfigFileName(AProjectInfo);

    if (Trim(AProjectInfo.Toolchain.RootDir) <> '') and (Trim(LCompilerConfigFileName) <> '') then
      AddCandidate(TPath.Combine(AProjectInfo.Toolchain.RootDir, 'bin\' + LCompilerConfigFileName));

    if (Trim(AProjectInfo.ProjectDir) <> '') and (Trim(LCompilerConfigFileName) <> '') then
      AddCandidate(TPath.Combine(AProjectInfo.ProjectDir, LCompilerConfigFileName));

    if Trim(AProjectInfo.ProjectPath) <> '' then
    begin
      AddCandidate(ChangeFileExt(AProjectInfo.ProjectPath, '.cfg'));
      AddCandidate(ChangeFileExt(AProjectInfo.ProjectPath, '.rsp'));
    end;

    if (Trim(AProjectInfo.OutputDir) <> '') and (Trim(AProjectInfo.ProjectName) <> '') then
    begin
      LCandidatePath := TPath.Combine(AProjectInfo.OutputDir, AProjectInfo.ProjectName + '.rsp');
      AddCandidate(LCandidatePath);
    end;

    for LCandidatePath in LCandidates do
      ParseCompilerOptionFile(LCandidatePath, AProjectInfo, ABuildEvidence,
        LVisitedFiles, LSearchPaths, LUnitScopeNames);

    CopyUniqueValues(LSearchPaths, ABuildEvidence.SearchPaths);
    CopyUniqueValues(LUnitScopeNames, ABuildEvidence.UnitScopeNames);
  finally
    LVisitedFiles.Free;
    LUnitScopeNames.Free;
    LSearchPaths.Free;
    LCandidates.Free;
  end;
end;

function TBuildEvidenceReader.ExpandCompilerOptionValue(const AValue: string;
  const AProjectInfo: TProjectInfo): string;
begin
  Result := Trim(AValue);
  if (Length(Result) >= 2) and (Result[1] = '"') and
    (Result[Length(Result)] = '"') then
    Result := Copy(Result, 2, Length(Result) - 2);

  Result := StringReplace(Result, '$(BDSLIB)',
    TPath.Combine(AProjectInfo.Toolchain.RootDir, 'lib'),
    [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '$(BDSROOT)', AProjectInfo.Toolchain.RootDir,
    [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '$(BDS)', AProjectInfo.Toolchain.RootDir,
    [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '$(PROJECTDIR)', AProjectInfo.ProjectDir,
    [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '$(PROJECTNAME)', AProjectInfo.ProjectName,
    [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '$(PLATFORM)', AProjectInfo.Platform,
    [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '$(CONFIG)', AProjectInfo.Configuration,
    [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '$(OUTPUTDIR)', AProjectInfo.OutputDir,
    [rfReplaceAll, rfIgnoreCase]);
end;

function TBuildEvidenceReader.GetCompilerConfigFileName(
  const AProjectInfo: TProjectInfo): string;
begin
  if SameText(AProjectInfo.Platform, 'Win64') then
    Exit('dcc64.cfg');
  Result := 'dcc32.cfg';
end;

procedure TBuildEvidenceReader.ParseCompilerOptionFile(const AFilePath: string;
  const AProjectInfo: TProjectInfo; var ABuildEvidence: TBuildEvidence;
  const AVisitedFiles: TList<string>; const ASearchPaths,
  AUnitScopeNames: TList<string>);
var
  LBaseDirectory: string;
  LContent: string;
  LCurrentToken: string;
  LNormalizedPath: string;
  LPendingOption: string;
  LToken: string;
  LTokens: TArray<string>;
  LTokenValue: string;
  LValue: string;
begin
  if not Assigned(AVisitedFiles) or not Assigned(ASearchPaths) or
    not Assigned(AUnitScopeNames) then
    Exit;

  LNormalizedPath := TPath.GetFullPath(AFilePath);
  if not TFile.Exists(LNormalizedPath) or AVisitedFiles.Contains(LNormalizedPath) then
    Exit;

  AVisitedFiles.Add(LNormalizedPath);
  AddEvidenceItem(ABuildEvidence, besCompilerResponseFile,
    TPath.GetFileName(LNormalizedPath), LNormalizedPath, '', '', 'CompilerOptionFile');

  LContent := TFile.ReadAllText(LNormalizedPath);
  LTokens := TokenizeCompilerOptions(LContent);
  LBaseDirectory := TPath.GetDirectoryName(LNormalizedPath);
  LPendingOption := '';

  for LToken in LTokens do
  begin
    LCurrentToken := Trim(LToken);
    if LCurrentToken = '' then
      Continue;

    if LPendingOption <> '' then
    begin
      LValue := LCurrentToken;
      LCurrentToken := LPendingOption;
      LPendingOption := '';
    end
    else
      LValue := '';

    if (LValue = '') and ((SameText(LCurrentToken, '-U')) or (SameText(LCurrentToken, '/U')) or
      (SameText(LCurrentToken, '-I')) or (SameText(LCurrentToken, '/I')) or
      (SameText(LCurrentToken, '-R')) or (SameText(LCurrentToken, '/R')) or
      (SameText(LCurrentToken, '-NS')) or (SameText(LCurrentToken, '/NS'))) then
    begin
      LPendingOption := LCurrentToken;
      Continue;
    end;

    if (LValue = '') and ((StartsText('-NS', LCurrentToken)) or (StartsText('/NS', LCurrentToken))) then
    begin
      LTokenValue := Copy(LCurrentToken, 4, MaxInt);
      AddCompilerUnitScopes(ExpandCompilerOptionValue(LTokenValue, AProjectInfo), AUnitScopeNames);
      Continue;
    end;

    if (LValue = '') and ((StartsText('-U', LCurrentToken)) or (StartsText('/U', LCurrentToken)) or
      (StartsText('-I', LCurrentToken)) or (StartsText('/I', LCurrentToken)) or
      (StartsText('-R', LCurrentToken)) or (StartsText('/R', LCurrentToken))) then
    begin
      LTokenValue := Copy(LCurrentToken, 3, MaxInt);
      AddCompilerPaths(LTokenValue, LBaseDirectory, AProjectInfo, ASearchPaths);
      Continue;
    end;

    if (LValue <> '') and ((SameText(LCurrentToken, '-NS')) or (SameText(LCurrentToken, '/NS'))) then
    begin
      AddCompilerUnitScopes(ExpandCompilerOptionValue(LValue, AProjectInfo), AUnitScopeNames);
      Continue;
    end;

    if (LValue <> '') and ((SameText(LCurrentToken, '-U')) or (SameText(LCurrentToken, '/U')) or
      (SameText(LCurrentToken, '-I')) or (SameText(LCurrentToken, '/I')) or
      (SameText(LCurrentToken, '-R')) or (SameText(LCurrentToken, '/R'))) then
    begin
      AddCompilerPaths(LValue, LBaseDirectory, AProjectInfo, ASearchPaths);
      Continue;
    end;

    if StartsText('@', LCurrentToken) then
    begin
      LTokenValue := ExpandCompilerOptionValue(Copy(LCurrentToken, 2, MaxInt), AProjectInfo);
      if not TPath.IsPathRooted(LTokenValue) then
        LTokenValue := TPath.GetFullPath(TPath.Combine(LBaseDirectory, LTokenValue));
      ParseCompilerOptionFile(LTokenValue, AProjectInfo, ABuildEvidence,
        AVisitedFiles, ASearchPaths, AUnitScopeNames);
      Continue;
    end;

    if SameText(LCurrentToken, '--no-config') then
      if not ABuildEvidence.Warnings.Contains('Compiler option file disables inherited config processing: ' +
        LNormalizedPath) then
        ABuildEvidence.Warnings.Add('Compiler option file disables inherited config processing: ' +
          LNormalizedPath);
  end;
end;

function TBuildEvidenceReader.TokenizeCompilerOptions(const AContent: string): TArray<string>;
var
  LBuilder: TStringBuilder;
  LChar: Char;
  LInQuotes: Boolean;
  LLine: string;
  LLines: TStringList;
  LTrimmedLine: string;
  LTokens: TList<string>;

  procedure FlushToken;
  var
    LToken: string;
  begin
    LToken := Trim(LBuilder.ToString);
    LBuilder.Clear;
    if LToken <> '' then
      LTokens.Add(LToken);
  end;
begin
  LTokens := TList<string>.Create;
  LLines := TStringList.Create;
  LBuilder := TStringBuilder.Create;
  try
    LLines.Text := AContent;
    for LLine in LLines do
    begin
      LTrimmedLine := Trim(LLine);
      if (LTrimmedLine = '') or StartsText(';', LTrimmedLine) or
        StartsText('//', LTrimmedLine) then
        Continue;

      LInQuotes := False;
      LBuilder.Clear;
      for LChar in LTrimmedLine do
      begin
        if LChar = '"' then
        begin
          LInQuotes := not LInQuotes;
          LBuilder.Append(LChar);
          Continue;
        end;

        if not LInQuotes and CharInSet(LChar, [' ', #9]) then
        begin
          FlushToken;
          Continue;
        end;

        LBuilder.Append(LChar);
      end;
      FlushToken;
    end;

    Result := LTokens.ToArray;
  finally
    LBuilder.Free;
    LLines.Free;
    LTokens.Free;
  end;
end;

function TBuildEvidenceReader.Read(const AProjectInfo: TProjectInfo): TBuildEvidence;
var
  LMapUnitName: string;
  LMapUnitNames: TArray<string>;
  LRsmFilePath: string;
  LRuntimePackage: string;
begin
  Result := TBuildEvidence.Create;
  Result.ProjectPath := AProjectInfo.ProjectPath;
  Result.Platform := AProjectInfo.Platform;
  Result.Configuration := AProjectInfo.Configuration;
  Result.Paths.OutputDir := AProjectInfo.OutputDir;
  Result.Paths.DcuOutputDir := AProjectInfo.DcuOutputDir;
  Result.Paths.DcpOutputDir := AProjectInfo.DcpOutputDir;
  Result.Paths.BplOutputDir := AProjectInfo.BplOutputDir;
  Result.Paths.MapFilePath := AProjectInfo.MapFilePath;

  CopyUniqueValues(AProjectInfo.ProjectSearchPaths, Result.SearchPaths);
  // Legacy scans already merged .dof over .cfg. Reading the .cfg again would
  // put the losing values back into the search path.
  if not AProjectInfo.IsLegacyProject then
    CollectCompilerOptionEvidence(AProjectInfo, Result);
  CopyUniqueValues(AProjectInfo.SearchPaths, Result.SearchPaths);
  CopyUniqueValues(AProjectInfo.GlobalSearchPaths, Result.SearchPaths);
  CopyUniqueValues(AProjectInfo.UnitScopeNames, Result.UnitScopeNames);
  CopyUniqueValues(AProjectInfo.RuntimePackages, Result.RuntimePackages);
  CopyUniqueValues(AProjectInfo.Warnings, Result.Warnings);

  AddEvidenceItem(Result, besProjectMetadata, 'Project metadata',
    AProjectInfo.ProjectPath, '', '',
    Format('%s|%s', [AProjectInfo.Platform, AProjectInfo.Configuration]));

  if AProjectInfo.OutputDir <> '' then
    AddEvidenceItem(Result, besProjectMetadata, 'Primary output directory',
      AProjectInfo.OutputDir, '', '', 'OutputDir');

  if AProjectInfo.DcuOutputDir <> '' then
    AddEvidenceItem(Result, besProjectMetadata, 'DCU output directory',
      AProjectInfo.DcuOutputDir, '', '', 'DcuOutputDir');

  if AProjectInfo.DcpOutputDir <> '' then
    AddEvidenceItem(Result, besProjectMetadata, 'DCP output directory',
      AProjectInfo.DcpOutputDir, '', '', 'DcpOutputDir');

  if AProjectInfo.BplOutputDir <> '' then
    AddEvidenceItem(Result, besProjectMetadata, 'BPL output directory',
      AProjectInfo.BplOutputDir, '', '', 'BplOutputDir');

  if AProjectInfo.MapFilePath <> '' then
  begin
    AddEvidenceItem(Result, besProjectMetadata, 'Expected map file',
      AProjectInfo.MapFilePath, '', '', 'MapFilePath');

    if TFile.Exists(AProjectInfo.MapFilePath) then
    begin
      AddEvidenceItem(Result, besMapFile, 'Map file',
        AProjectInfo.MapFilePath, '', '', 'MapFile');

      LMapUnitNames := TMapFileReader.ReadUnitNames(AProjectInfo.MapFilePath);
      for LMapUnitName in LMapUnitNames do
        AddEvidenceItem(Result, besMapFile, 'Unit from map file',
          AProjectInfo.MapFilePath, '', LMapUnitName, 'LineNumbersSection');

      // No classic unit sections. Windows and macOS are told to switch the
      // map to Detailed. Android, iOS device, and Linux are not: their map
      // layout is not parsed, and a guessed pattern would invent units.
      if Length(LMapUnitNames) = 0 then
        Result.Warnings.Add(MapFileNoUnitsWarning(AProjectInfo));
    end;

    if not TFile.Exists(AProjectInfo.MapFilePath) then
    begin
      Result.Warnings.Add(MapFileMissingWarning(AProjectInfo));

      LRsmFilePath := ChangeFileExt(AProjectInfo.MapFilePath, '.rsm');
      if TFile.Exists(LRsmFilePath) then
        Result.Warnings.Add('Found RSM file without matching MAP file: ' + LRsmFilePath +
          '. Deep-Evidence unit resolution currently requires a detailed MAP file.');
    end;
  end;

  for LRuntimePackage in Result.RuntimePackages do
    AddEvidenceItem(Result, besProjectMetadata, 'Runtime package', '',
      LRuntimePackage, '', 'RuntimePackages');
end;

end.