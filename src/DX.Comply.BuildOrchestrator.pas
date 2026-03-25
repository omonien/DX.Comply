/// <summary>
/// DX.Comply.BuildOrchestrator
/// Orchestrates explicit Deep-Evidence builds for MAP-first analysis.
/// </summary>
///
/// <remarks>
/// The first implementation slice focuses on deterministic plan construction
/// and a minimal build execution path that invokes the shared
/// `DelphiBuildDPROJ.ps1` script with additional MSBuild properties.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.BuildOrchestrator;

interface

uses
  DX.Comply.Engine.Intf;

type
  /// <summary>
  /// Controls when a Deep-Evidence build should be executed.
  /// </summary>
  TDeepEvidenceBuildMode = (
    /// <summary>Execute only when the expected map file is missing (default).</summary>
    debWhenMapMissing,
    /// <summary>Always execute before SBOM generation.</summary>
    debAlways
  );

  /// <summary>
  /// Input options for Deep-Evidence build planning.
  /// </summary>
  TDeepEvidenceBuildOptions = record
    Mode: TDeepEvidenceBuildMode;
    DelphiVersion: Integer;
    BuildScriptPathOverride: string;
    class function Default: TDeepEvidenceBuildOptions; static;
  end;

  /// <summary>
  /// Deterministic plan for an explicit Deep-Evidence build.
  /// </summary>
  TDeepEvidenceBuildPlan = record
    Enabled: Boolean;
    ShouldExecute: Boolean;
    WorkingDirectory: string;
    ScriptPath: string;
    ProjectPath: string;
    Platform: string;
    Configuration: string;
    DelphiVersion: Integer;
    ExpectedMapFilePath: string;
    AdditionalMSBuildProperties: TArray<string>;
    CommandLine: string;
  end;

  /// <summary>
  /// Result of a Deep-Evidence build orchestration attempt.
  /// </summary>
  TDeepEvidenceBuildResult = record
    Success: Boolean;
    Executed: Boolean;
    ExitCode: Integer;
    Message: string;
    Output: string;
    CommandLine: string;
    MapFilePath: string;
  end;

  /// <summary>
  /// Orchestrates explicit build execution for Deep-Evidence collection.
  /// </summary>
  IBuildOrchestrator = interface
    ['{18BBA16E-313A-45E2-B793-0A1A8B985F42}']
    /// <summary>
    /// Creates a deterministic plan for a Deep-Evidence build.
    /// </summary>
    function CreatePlan(const AProjectInfo: TProjectInfo;
      const AOptions: TDeepEvidenceBuildOptions): TDeepEvidenceBuildPlan;
    /// <summary>
    /// Executes the specified Deep-Evidence build plan.
    /// </summary>
    function ExecutePlan(const APlan: TDeepEvidenceBuildPlan): TDeepEvidenceBuildResult;
    /// <summary>
    /// Ensures the requested Deep-Evidence build exists and produced a map file.
    /// </summary>
    function EnsureDeepEvidenceBuild(const AProjectInfo: TProjectInfo;
      const AOptions: TDeepEvidenceBuildOptions): TDeepEvidenceBuildResult;
  end;

  /// <summary>
  /// Implementation of IBuildOrchestrator.
  /// </summary>
  TBuildOrchestrator = class(TInterfacedObject, IBuildOrchestrator)
  private
    const
      cDetailedMapProperty = 'DCC_MapFile=3';
    /// <summary>
    /// Builds the expected repository root from the project metadata.
    /// </summary>
    function GetRepositoryRoot(const AProjectInfo: TProjectInfo): string;
    /// <summary>
    /// Returns the directory of the currently loaded module.
    /// </summary>
    function GetModuleDirectory: string;
    /// <summary>
    /// Searches for the shared Delphi build script from the supplied directory upward.
    /// </summary>
    function FindBuildScriptFromDirectory(const AStartDirectory: string): string;
    /// <summary>
    /// Resolves the effective build script path, honoring user overrides first.
    /// </summary>
    function ResolveBuildScriptPath(const AProjectInfo: TProjectInfo;
      const ABuildScriptPathOverride: string): string;
    /// <summary>
    /// Quotes one command-line argument.
    /// </summary>
    function QuoteArgument(const AValue: string): string;
    /// <summary>
    /// Builds the PowerShell command line for the given plan.
    /// </summary>
    function BuildCommandLine(const APlan: TDeepEvidenceBuildPlan): string;
  public
    function CreatePlan(const AProjectInfo: TProjectInfo;
      const AOptions: TDeepEvidenceBuildOptions): TDeepEvidenceBuildPlan;
    function ExecutePlan(const APlan: TDeepEvidenceBuildPlan): TDeepEvidenceBuildResult;
    function EnsureDeepEvidenceBuild(const AProjectInfo: TProjectInfo;
      const AOptions: TDeepEvidenceBuildOptions): TDeepEvidenceBuildResult;
  end;

implementation

uses
  System.IOUtils,
  System.SysUtils,
  Winapi.Windows;

// ---------------------------------------------------------------------------
// Local helper — always returns an English Windows system error description.
// SysErrorMessage() uses the system locale which is German on German Windows.
// FormatMessage with MAKELANGID(LANG_ENGLISH, SUBLANG_DEFAULT) forces English.
// Falls back to SysErrorMessage when no English message is available.
// ---------------------------------------------------------------------------

function GetEnglishSystemError(AErrorCode: DWORD): string;
const
  // MAKELANGID(LANG_ENGLISH=9, SUBLANG_DEFAULT=1) = 1033 ($0409)
  cEnglishLangId = 1033;
var
  LBuffer: array[0..1023] of Char;
  LLength: DWORD;
begin
  FillChar(LBuffer, SizeOf(LBuffer), 0);
  LLength := FormatMessage(
    FORMAT_MESSAGE_FROM_SYSTEM or FORMAT_MESSAGE_IGNORE_INSERTS,
    nil,
    AErrorCode,
    cEnglishLangId,
    LBuffer,
    Length(LBuffer),
    nil);
  if LLength > 0 then
    Result := Trim(string(LBuffer))
  else
    // English strings not available (e.g. stripped OS) — fall back to locale
    Result := SysErrorMessage(AErrorCode);
end;

{ TDeepEvidenceBuildOptions }

class function TDeepEvidenceBuildOptions.Default: TDeepEvidenceBuildOptions;
begin
  Result.Mode := debWhenMapMissing;
  Result.DelphiVersion := 0;
  Result.BuildScriptPathOverride := '';
end;

function TBuildOrchestrator.BuildCommandLine(const APlan: TDeepEvidenceBuildPlan): string;
var
  LMsBuildProperty: string;
begin
  Result := 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File ' +
    QuoteArgument(APlan.ScriptPath) +
    ' -ProjectPath ' + QuoteArgument(APlan.ProjectPath) +
    ' -Configuration ' + APlan.Configuration +
    ' -Platform ' + APlan.Platform;

  if APlan.DelphiVersion > 0 then
    Result := Result + ' -DelphiVersion ' + IntToStr(APlan.DelphiVersion);

  for LMsBuildProperty in APlan.AdditionalMSBuildProperties do
    Result := Result + ' -AdditionalMSBuildProperties ' + QuoteArgument(LMsBuildProperty);
end;

function TBuildOrchestrator.CreatePlan(const AProjectInfo: TProjectInfo;
  const AOptions: TDeepEvidenceBuildOptions): TDeepEvidenceBuildPlan;
var
  LProjectDirectory: string;
begin
  Result := Default(TDeepEvidenceBuildPlan);
  Result.Enabled := True;
  LProjectDirectory := AProjectInfo.ProjectDir;
  if (LProjectDirectory = '') and (AProjectInfo.ProjectPath <> '') then
    LProjectDirectory := TPath.GetDirectoryName(AProjectInfo.ProjectPath);
  Result.WorkingDirectory := LProjectDirectory;
  Result.ScriptPath := ResolveBuildScriptPath(AProjectInfo, AOptions.BuildScriptPathOverride);
  Result.ProjectPath := AProjectInfo.ProjectPath;
  Result.Platform := AProjectInfo.Platform;
  Result.Configuration := AProjectInfo.Configuration;
  Result.DelphiVersion := AOptions.DelphiVersion;
  Result.ExpectedMapFilePath := AProjectInfo.MapFilePath;
  Result.AdditionalMSBuildProperties := [cDetailedMapProperty];

  case AOptions.Mode of
    debAlways:
      Result.ShouldExecute := Result.Enabled;
    debWhenMapMissing:
      Result.ShouldExecute := Result.Enabled and
        (Result.ExpectedMapFilePath <> '') and not TFile.Exists(Result.ExpectedMapFilePath);
  else
    Result.ShouldExecute := False;
  end;

  Result.CommandLine := BuildCommandLine(Result);
end;

function TBuildOrchestrator.EnsureDeepEvidenceBuild(const AProjectInfo: TProjectInfo;
  const AOptions: TDeepEvidenceBuildOptions): TDeepEvidenceBuildResult;
var
  LPlan: TDeepEvidenceBuildPlan;
begin
  LPlan := CreatePlan(AProjectInfo, AOptions);
  Result := ExecutePlan(LPlan);
end;

function TBuildOrchestrator.FindBuildScriptFromDirectory(const AStartDirectory: string): string;
var
  LCandidate: string;
  LCurrentDirectory: string;
  LParentDirectory: string;
  LLevel: Integer;
begin
  Result := '';
  if AStartDirectory = '' then
    Exit;

  LCurrentDirectory := TPath.GetFullPath(AStartDirectory);
  for LLevel := 0 to 6 do
  begin
    LCandidate := TPath.Combine(LCurrentDirectory, 'DelphiBuildDPROJ.ps1');
    if TFile.Exists(LCandidate) then
      Exit(LCandidate);

    LCandidate := TPath.Combine(LCurrentDirectory, 'build\DelphiBuildDPROJ.ps1');
    if TFile.Exists(LCandidate) then
      Exit(LCandidate);

    LParentDirectory := TPath.GetDirectoryName(LCurrentDirectory);
    if SameText(LParentDirectory, LCurrentDirectory) then
      Break;

    LCurrentDirectory := LParentDirectory;
  end;
end;

function TBuildOrchestrator.ExecutePlan(const APlan: TDeepEvidenceBuildPlan): TDeepEvidenceBuildResult;
var
  LBytesRead: Cardinal;
  LBuffer: TBytes;
  LCommandLine: string;
  LExitCode: Cardinal;
  LOutputBuilder: TStringBuilder;
  LPipeRead, LPipeWrite: THandle;
  LProcessInfo: TProcessInformation;
  LSecurityAttributes: TSecurityAttributes;
  LStartupInfo: TStartupInfo;
begin
  Result := Default(TDeepEvidenceBuildResult);
  Result.Success := True;
  Result.CommandLine := APlan.CommandLine;
  Result.MapFilePath := APlan.ExpectedMapFilePath;

  if not APlan.ShouldExecute then
  begin
    Result.Message := 'Deep-Evidence build skipped because the expected map file already exists.';
    Exit;
  end;

  if (APlan.ScriptPath = '') or not TFile.Exists(APlan.ScriptPath) then
  begin
    Result.Success := False;
    Result.Message := 'Build script not found: ' + APlan.ScriptPath;
    Exit;
  end;

  LPipeRead := 0;
  LPipeWrite := 0;
  FillChar(LSecurityAttributes, SizeOf(LSecurityAttributes), 0);
  LSecurityAttributes.nLength := SizeOf(LSecurityAttributes);
  LSecurityAttributes.bInheritHandle := True;

  if not CreatePipe(LPipeRead, LPipeWrite, @LSecurityAttributes, 0) then
  begin
    Result.Success := False;
    Result.Message := 'Failed to create output pipe: ' + GetEnglishSystemError(GetLastError);
    Exit;
  end;

  try
    SetHandleInformation(LPipeRead, HANDLE_FLAG_INHERIT, 0);

    FillChar(LStartupInfo, SizeOf(LStartupInfo), 0);
    LStartupInfo.cb := SizeOf(LStartupInfo);
    LStartupInfo.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    LStartupInfo.wShowWindow := SW_HIDE;
    LStartupInfo.hStdOutput := LPipeWrite;
    LStartupInfo.hStdError := LPipeWrite;
    FillChar(LProcessInfo, SizeOf(LProcessInfo), 0);

    LCommandLine := APlan.CommandLine;
    UniqueString(LCommandLine);

    if not CreateProcess(nil, PChar(LCommandLine), nil, nil, True, CREATE_NO_WINDOW,
      nil, PChar(APlan.WorkingDirectory), LStartupInfo, LProcessInfo) then
    begin
      Result.Success := False;
      Result.Message := 'Failed to start build process: ' + GetEnglishSystemError(GetLastError);
      Exit;
    end;

    CloseHandle(LPipeWrite);
    LPipeWrite := 0;

    Result.Executed := True;
    LOutputBuilder := TStringBuilder.Create;
    try
      SetLength(LBuffer, 4096);
      while ReadFile(LPipeRead, LBuffer[0], Length(LBuffer), LBytesRead, nil) and (LBytesRead > 0) do
        LOutputBuilder.Append(TEncoding.UTF8.GetString(LBuffer, 0, LBytesRead));
      Result.Output := Trim(LOutputBuilder.ToString);
    finally
      LOutputBuilder.Free;
    end;

    WaitForSingleObject(LProcessInfo.hProcess, INFINITE);
    if not GetExitCodeProcess(LProcessInfo.hProcess, LExitCode) then
      LExitCode := Cardinal(-1);
    Result.ExitCode := Integer(LExitCode);
    Result.Success := Result.ExitCode = 0;

    if Result.Success and (APlan.ExpectedMapFilePath <> '') and
       not TFile.Exists(APlan.ExpectedMapFilePath) then
    begin
      Result.Success := False;
      Result.Message := 'Build succeeded but the expected map file was not generated: ' +
        APlan.ExpectedMapFilePath;
    end
    else if Result.Success then
      Result.Message := 'Deep-Evidence build completed successfully.'
    else
      Result.Message := 'Deep-Evidence build failed with exit code ' + IntToStr(Result.ExitCode) + '.';

    CloseHandle(LProcessInfo.hThread);
    CloseHandle(LProcessInfo.hProcess);
  finally
    if LPipeRead <> 0 then
      CloseHandle(LPipeRead);
    if LPipeWrite <> 0 then
      CloseHandle(LPipeWrite);
  end;
end;

function TBuildOrchestrator.GetRepositoryRoot(const AProjectInfo: TProjectInfo): string;
var
  LProjectDir: string;
begin
  LProjectDir := AProjectInfo.ProjectDir;
  if (LProjectDir = '') and (AProjectInfo.ProjectPath <> '') then
    LProjectDir := TPath.GetDirectoryName(AProjectInfo.ProjectPath);

  if LProjectDir = '' then
    Exit('');

  Result := TPath.GetFullPath(TPath.Combine(LProjectDir, '..'));
end;

function TBuildOrchestrator.GetModuleDirectory: string;
var
  LBuffer: array[0..MAX_PATH * 4] of Char;
  LLength: Cardinal;
begin
  Result := '';
  LLength := GetModuleFileName(HInstance, LBuffer, Length(LBuffer));
  if LLength > 0 then
    Result := TPath.GetDirectoryName(string(LBuffer));

  if (Result = '') and (ParamStr(0) <> '') then
    Result := TPath.GetDirectoryName(ParamStr(0));
end;

function TBuildOrchestrator.QuoteArgument(const AValue: string): string;
begin
  Result := '"' + StringReplace(AValue, '"', '""', [rfReplaceAll]) + '"';
end;

function TBuildOrchestrator.ResolveBuildScriptPath(const AProjectInfo: TProjectInfo;
  const ABuildScriptPathOverride: string): string;
var
  LProjectDirectory: string;
begin
  if Trim(ABuildScriptPathOverride) <> '' then
    Exit(TPath.GetFullPath(ABuildScriptPathOverride));

  Result := FindBuildScriptFromDirectory(GetModuleDirectory);
  if Result <> '' then
    Exit;

  LProjectDirectory := AProjectInfo.ProjectDir;
  if (LProjectDirectory = '') and (AProjectInfo.ProjectPath <> '') then
    LProjectDirectory := TPath.GetDirectoryName(AProjectInfo.ProjectPath);

  Result := FindBuildScriptFromDirectory(LProjectDirectory);
  if Result <> '' then
    Exit;

  Result := FindBuildScriptFromDirectory(GetRepositoryRoot(AProjectInfo));
end;

end.