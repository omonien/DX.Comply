/// <summary>
/// DX.Comply.IDE.PathSupport
/// Shared repository and asset path helpers for the DX.Comply IDE package.
/// </summary>
///
/// <remarks>
/// These helpers centralize the logic that locates the repository root relative
/// to the loaded design package so dialogs, menu assets, and documentation views
/// stay aligned and avoid duplicating path traversal logic.
///
/// FindDXComplyRepositoryRoot uses the same order as tests/DX.Comply.Tests.Paths:
/// DXCOMPLY_REPO_ROOT, ancestors of the module, ancestors of the current
/// directory, dxcomply-repo-root.txt next to the module, then a single
/// sources/(checkout)/ match above the module. The test executable is not
/// always stored under build/(platform)/(config)/, and the IDE package is not
/// always stored inside the checkout.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.IDE.PathSupport;

interface

function GetDXComplyModuleFilePath: string;
function FindDXComplyRepositoryFile(const ARelativePath: string): string;
function FindDXComplyAssetFile(const AFileName: string): string;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.SysUtils,
  System.Types,
  Winapi.Windows;

function GetDXComplyModuleFilePath: string;
var
  LLength: Integer;
begin
  SetLength(Result, 1024);
  LLength := GetModuleFileName(HInstance, PChar(Result), Length(Result));
  if LLength <= 0 then
    Exit('');
  SetLength(Result, LLength);
end;

const
  cRepoRootEnvVar = 'DXCOMPLY_REPO_ROOT';
  cRepoRootHintFile = 'dxcomply-repo-root.txt';
  cEngineDprojRelative = 'src' + PathDelim + 'DX.Comply.Engine.dproj';
  cReadmeFileName = 'README.md';
  cSourcesDirectoryName = 'sources';

function IsRepoRoot(const ADirectory: string): Boolean;
begin
  Result := (ADirectory <> '') and
    TFile.Exists(TPath.Combine(ADirectory, cEngineDprojRelative)) and
    TFile.Exists(TPath.Combine(ADirectory, cReadmeFileName));
end;

function WalkUpForRepoRoot(const AStartDirectory: string): string;
var
  LCurrentDirectory: string;
  LParentDirectory: string;
begin
  Result := '';
  LCurrentDirectory := AStartDirectory;
  while LCurrentDirectory <> '' do
  begin
    if IsRepoRoot(LCurrentDirectory) then
      Exit(LCurrentDirectory);

    LParentDirectory := ExtractFileDir(LCurrentDirectory);
    if SameText(LParentDirectory, LCurrentDirectory) then
      Break;
    LCurrentDirectory := LParentDirectory;
  end;
end;

function UnquotePath(const AValue: string): string;
begin
  Result := Trim(AValue);
  if (Result <> '') and (Result[1] = #$FEFF) then
    Result := Trim(Copy(Result, 2, Length(Result) - 1));
  if (Length(Result) >= 2) and (Result[1] = '"') and (Result[Length(Result)] = '"') then
    Result := Trim(Copy(Result, 2, Length(Result) - 2));
end;

function ResolveUserPath(const ABaseDirectory, APath: string): string;
var
  LPath: string;
begin
  Result := '';
  LPath := UnquotePath(APath);
  if LPath = '' then
    Exit;

  try
    if TPath.IsRelativePath(LPath) then
      Result := TPath.GetFullPath(TPath.Combine(ABaseDirectory, LPath))
    else
      Result := TPath.GetFullPath(LPath);
  except
    on Exception do
      Result := '';
  end;
end;

function ReadHintLine(const AFilePath: string): string;
var
  LLines: TStringList;
begin
  Result := '';
  if not TFile.Exists(AFilePath) then
    Exit;

  LLines := TStringList.Create;
  try
    try
      LLines.LoadFromFile(AFilePath, TEncoding.UTF8);
    except
      on Exception do
        Exit;
    end;
    if LLines.Count > 0 then
      Result := UnquotePath(LLines[0]);
  finally
    LLines.Free;
  end;
end;

function TryHintFile(const AModuleDirectory: string): string;
var
  LHintPath: string;
  LResolved: string;
  LStart: string;
  LText: string;
begin
  Result := '';
  if Trim(AModuleDirectory) = '' then
    Exit;

  LHintPath := TPath.Combine(AModuleDirectory, cRepoRootHintFile);
  if not TFile.Exists(LHintPath) then
    Exit;

  LText := ReadHintLine(LHintPath);
  if LText = '' then
    Exit;

  LResolved := ResolveUserPath(AModuleDirectory, LText);
  if LResolved = '' then
    Exit;

  if TDirectory.Exists(LResolved) then
    LStart := LResolved
  else
    LStart := ExtractFileDir(LResolved);
  Result := WalkUpForRepoRoot(LStart);
end;

function TrySourcesLayout(const AModuleDirectory: string): string;
var
  LChild: string;
  LChildren: TStringDynArray;
  LCurrentDirectory: string;
  LDprojMatches: Integer;
  LIndex: Integer;
  LMatch: string;
  LParentDirectory: string;
  LSources: string;
begin
  Result := '';
  LCurrentDirectory := AModuleDirectory;
  while LCurrentDirectory <> '' do
  begin
    LSources := TPath.Combine(LCurrentDirectory, cSourcesDirectoryName);
    if TDirectory.Exists(LSources) then
    begin
      LDprojMatches := 0;
      LMatch := '';
      try
        LChildren := TDirectory.GetDirectories(LSources);
      except
        on Exception do
          Exit;
      end;

      for LIndex := 0 to High(LChildren) do
      begin
        LChild := LChildren[LIndex];
        if TFile.Exists(TPath.Combine(LChild, cEngineDprojRelative)) then
        begin
          Inc(LDprojMatches);
          LMatch := LChild;
        end;
      end;

      if (LDprojMatches = 1) and IsRepoRoot(LMatch) then
        Exit(LMatch);
      Exit;
    end;

    LParentDirectory := ExtractFileDir(LCurrentDirectory);
    if SameText(LParentDirectory, LCurrentDirectory) then
      Break;
    LCurrentDirectory := LParentDirectory;
  end;
end;

function FindDXComplyRepositoryRoot: string;
var
  LEnvValue: string;
  LModuleDirectory: string;
  LPath: string;
begin
  // Winapi.Windows also exports GetEnvironmentVariable, so qualify SysUtils.
  LEnvValue := System.SysUtils.GetEnvironmentVariable(cRepoRootEnvVar);
  LPath := ResolveUserPath(GetCurrentDir, LEnvValue);
  if (LPath <> '') and IsRepoRoot(LPath) then
    Exit(LPath);

  LModuleDirectory := ExtractFileDir(GetDXComplyModuleFilePath);
  Result := WalkUpForRepoRoot(LModuleDirectory);
  if Result <> '' then
    Exit;

  Result := WalkUpForRepoRoot(GetCurrentDir);
  if Result <> '' then
    Exit;

  Result := TryHintFile(LModuleDirectory);
  if Result <> '' then
    Exit;

  Result := TrySourcesLayout(LModuleDirectory);
end;

function FindDXComplyRepositoryFile(const ARelativePath: string): string;
var
  LRepositoryRoot: string;
begin
  Result := '';
  LRepositoryRoot := FindDXComplyRepositoryRoot;
  if LRepositoryRoot = '' then
    Exit;

  Result := TPath.Combine(LRepositoryRoot, ARelativePath);
  if not TFile.Exists(Result) then
    Result := '';
end;

function FindDXComplyAssetFile(const AFileName: string): string;
begin
  Result := FindDXComplyRepositoryFile(TPath.Combine('assets', AFileName));
end;

end.