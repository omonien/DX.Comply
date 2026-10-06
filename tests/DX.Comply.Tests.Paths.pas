/// <summary>
/// DX.Comply.Tests.Paths
/// Locates the DX.Comply repository root for integration tests.
/// </summary>
///
/// <remarks>
/// RepoRoot resolves the repository root in this order and stops at the first
/// directory that contains both src\DX.Comply.Engine.dproj and README.md:
///
/// 1. Environment variable DXCOMPLY_REPO_ROOT, when it is set to that directory.
/// 2. Ancestor folders of the test executable (ExtractFilePath(ParamStr(0))).
/// 3. Ancestor folders of the process current directory (GetCurrentDir).
/// 4. The text file dxcomply-repo-root.txt next to the executable. The first
///    line is either the repository root or a path inside it, such as a .dproj.
///    A path inside the repository is walked upward to the root. Delphi cannot
///    embed the compiling source directory, so this file is how a build server
///    passes that path in.
/// 5. Sibling checkout layout. From the executable directory, walk upward to
///    the first folder that contains a sources directory. Use it only when
///    exactly one sources\*\src\DX.Comply.Engine.dproj match exists.
///
/// The build server compiles a git checkout under sources/(name)/ and runs
/// the test executable from builds/(id)/bin/. Step 2 does not find the
/// checkout from there. Step 3 works when the process current directory is the
/// checkout. Steps 4 and 5 cover the other layouts.
///
/// If nothing matches, RepoRoot raises and the message names each place that
/// was searched. DX.Comply.IDE.PathSupport uses the same order, starting from
/// the loaded module instead of ParamStr(0), so the README loader can find
/// README.md in those layouts as well.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.Paths;

interface

/// <summary>
/// Absolute path of the DX.Comply repository root.
/// Raises if the root cannot be located. See the unit remarks for the search order.
/// </summary>
function RepoRoot: string;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.SysUtils,
  System.Types;

const
  cRepoRootEnvVar = 'DXCOMPLY_REPO_ROOT';
  cRepoRootHintFile = 'dxcomply-repo-root.txt';
  cEngineDprojRelative = 'src' + PathDelim + 'DX.Comply.Engine.dproj';
  cReadmeFileName = 'README.md';
  cSourcesDirectoryName = 'sources';

var
  GRepoRoot: string;
  GRepoRootResolved: Boolean;

function IsRepoRoot(const ADirectory: string): Boolean;
begin
  Result := (ADirectory <> '') and
    TFile.Exists(TPath.Combine(ADirectory, cEngineDprojRelative)) and
    TFile.Exists(TPath.Combine(ADirectory, cReadmeFileName));
end;

function CanonicalRoot(const ADirectory: string): string;
begin
  Result := ADirectory;
  if Result = '' then
    Exit;

  try
    Result := TPath.GetFullPath(ADirectory);
  except
    on Exception do
      Exit(ADirectory);
  end;

  // Keep the trailing delimiter of a drive root such as C:\.
  if (Length(Result) > 3) and (Result[Length(Result)] = PathDelim) then
    Delete(Result, Length(Result), 1);
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

function TryEnvironmentRoot(const AEnvValue: string): string;
var
  LPath: string;
begin
  Result := '';
  if Trim(AEnvValue) = '' then
    Exit;

  LPath := ResolveUserPath(GetCurrentDir, AEnvValue);
  if (LPath <> '') and IsRepoRoot(LPath) then
    Result := LPath;
end;

function TryHintFile(const AExeDirectory: string; out AHintPath, ANote: string): string;
var
  LResolved: string;
  LStart: string;
  LText: string;
begin
  Result := '';
  ANote := '';
  if Trim(AExeDirectory) = '' then
  begin
    AHintPath := '';
    ANote := 'executable directory is empty';
    Exit;
  end;

  AHintPath := TPath.Combine(AExeDirectory, cRepoRootHintFile);
  if not TFile.Exists(AHintPath) then
  begin
    ANote := 'file not found';
    Exit;
  end;

  LText := ReadHintLine(AHintPath);
  if LText = '' then
  begin
    ANote := 'file is empty or could not be read';
    Exit;
  end;

  LResolved := ResolveUserPath(AExeDirectory, LText);
  if LResolved = '' then
  begin
    ANote := '"' + LText + '" could not be resolved';
    Exit;
  end;

  // A .dproj path, or any other file inside the checkout, is walked upward.
  if TDirectory.Exists(LResolved) then
    LStart := LResolved
  else
    LStart := ExtractFileDir(LResolved);

  Result := WalkUpForRepoRoot(LStart);
  if Result = '' then
    ANote := '"' + LText + '" is not inside a repository root';
end;

function TrySourcesLayout(const AExeDirectory: string; out ANote: string): string;
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
  ANote := '';
  LCurrentDirectory := AExeDirectory;
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
        on E: Exception do
        begin
          ANote := 'could not read ' + LSources + ' (' + E.ClassName + ': ' + E.Message + ')';
          Exit;
        end;
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

      if LDprojMatches = 1 then
      begin
        if IsRepoRoot(LMatch) then
          Exit(LMatch);
        ANote := LMatch + ' contains ' + cEngineDprojRelative + ' but not ' + cReadmeFileName;
        Exit;
      end;

      if LDprojMatches = 0 then
        ANote := 'no ' + cEngineDprojRelative + ' under ' + LSources
      else
        ANote := IntToStr(LDprojMatches) + ' copies of ' + cEngineDprojRelative +
          ' under ' + LSources + '; a single match is required';
      Exit;
    end;

    LParentDirectory := ExtractFileDir(LCurrentDirectory);
    if SameText(LParentDirectory, LCurrentDirectory) then
      Break;
    LCurrentDirectory := LParentDirectory;
  end;

  if Trim(AExeDirectory) = '' then
    ANote := 'executable directory is empty'
  else
    ANote := 'no ' + cSourcesDirectoryName + ' directory above ' + AExeDirectory;
end;

function FailureMessage(const AEnvValue, AExeDirectory, AHintPath, AHintNote,
  ASourcesNote: string): string;
var
  LEnvText: string;
  LExeText: string;
  LHintText: string;
begin
  if Trim(AEnvValue) = '' then
    LEnvText := 'not set'
  else
    LEnvText := 'set to "' + AEnvValue + '", which is not a repository root';

  if Trim(AExeDirectory) = '' then
    LExeText := 'not available'
  else
    LExeText := AExeDirectory;

  if AHintPath = '' then
    LHintText := AHintNote
  else
    LHintText := AHintPath + ' (' + AHintNote + ')';

  Result :=
    'Could not locate the DX.Comply repository root.' + sLineBreak +
    'A valid root contains ' + cEngineDprojRelative + ' and ' + cReadmeFileName + '.' + sLineBreak +
    'Searched:' + sLineBreak +
    '1. Environment variable ' + cRepoRootEnvVar + ': ' + LEnvText + sLineBreak +
    '2. Ancestor folders of the executable directory: ' + LExeText + sLineBreak +
    '3. Ancestor folders of the current directory: ' + GetCurrentDir + sLineBreak +
    '4. Hint file ' + cRepoRootHintFile + ' next to the executable: ' + LHintText + sLineBreak +
    '5. sources\* layout above the executable: ' + ASourcesNote;
end;

function RepoRoot: string;
var
  LEnvValue: string;
  LExeDirectory: string;
  LFound: string;
  LHintNote: string;
  LHintPath: string;
  LSourcesNote: string;
begin
  if GRepoRootResolved then
    Exit(GRepoRoot);

  LEnvValue := GetEnvironmentVariable(cRepoRootEnvVar);
  LExeDirectory := ExtractFilePath(ParamStr(0));
  LHintPath := '';
  LHintNote := '';
  LSourcesNote := '';

  LFound := TryEnvironmentRoot(LEnvValue);
  if LFound = '' then
    LFound := WalkUpForRepoRoot(LExeDirectory);
  if LFound = '' then
    LFound := WalkUpForRepoRoot(GetCurrentDir);
  if LFound = '' then
    LFound := TryHintFile(LExeDirectory, LHintPath, LHintNote);
  if LFound = '' then
    LFound := TrySourcesLayout(LExeDirectory, LSourcesNote);

  if LFound = '' then
    raise Exception.Create(FailureMessage(LEnvValue, LExeDirectory, LHintPath,
      LHintNote, LSourcesNote));

  GRepoRoot := CanonicalRoot(LFound);
  GRepoRootResolved := True;
  Result := GRepoRoot;
end;

end.
