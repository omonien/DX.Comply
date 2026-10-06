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
    /// <summary>
    /// How ScriptPath was chosen: override, bundled, or module-parents.
    /// Empty when no script was found.
    /// </summary>
    ScriptSource: string;
    /// <summary>
    /// Maximum time ExecutePlan waits for the build process, in milliseconds.
    /// Zero uses the built-in default (30 minutes).
    /// </summary>
    TimeoutMs: Cardinal;
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
      cBuildScriptFileName = 'DelphiBuildDPROJ.ps1';
      cScriptSourceOverride = 'override';
      cScriptSourceBundled = 'bundled';
      cScriptSourceModuleParents = 'module-parents';
      cDefaultBuildTimeoutMs = 30 * 60 * 1000;
    /// <summary>
    /// Returns the directory of the currently loaded module.
    /// </summary>
    function GetModuleDirectory: string;
    /// <summary>
    /// Searches for the shared Delphi build script from the supplied directory upward.
    /// </summary>
    function FindBuildScriptFromDirectory(const AStartDirectory: string): string;
    /// <summary>
    /// Returns the script installed next to the DX.Comply binary, if present.
    /// </summary>
    function FindBundledBuildScript: string;
    /// <summary>
    /// Resolves the effective build script path, honoring user overrides first.
    /// ASource receives override, bundled, or module-parents.
    /// </summary>
    function ResolveBuildScriptPath(const ABuildScriptPathOverride: string;
      out ASource: string): string;
    /// <summary>
    /// Quotes one command-line argument.
    /// </summary>
    function QuoteArgument(const AValue: string): string;
    /// <summary>
    /// True when AValue is one shell-safe token.
    /// </summary>
    function IsSafeBuildToken(const AValue: string): Boolean;
    /// <summary>
    /// Appends a quoted switch, or raises when a non-empty value is not a safe token.
    /// </summary>
    procedure AppendSafeTokenSwitch(var ACommandLine: string;
      const AName, ASwitch, AValue: string);
    /// <summary>
    /// Builds the PowerShell command line for the given plan.
    /// </summary>
    function BuildCommandLine(const APlan: TDeepEvidenceBuildPlan): string;
    /// <summary>
    /// Describes which script ExecutePlan is about to run.
    /// </summary>
    function ScriptExecutionNote(const APlan: TDeepEvidenceBuildPlan): string;
    /// <summary>
    /// Timeout used for one plan. Zero selects the default.
    /// </summary>
    function ResolveBuildTimeoutMs(const APlan: TDeepEvidenceBuildPlan): UInt64;
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

procedure TBuildOrchestrator.AppendSafeTokenSwitch(var ACommandLine: string;
  const AName, ASwitch, AValue: string);
begin
  if AValue = '' then
    Exit;
  if not IsSafeBuildToken(AValue) then
    raise EArgumentException.Create(AName +
      ' must be a single token of letters, digits, ".", "_", "+" or "-".');
  ACommandLine := ACommandLine + ' ' + ASwitch + ' ' + QuoteArgument(AValue);
end;

function TBuildOrchestrator.BuildCommandLine(const APlan: TDeepEvidenceBuildPlan): string;
var
  LMsBuildProperty: string;
begin
  // Names match DelphiBuildDPROJ.ps1. The script still accepts the previous
  // names (-ProjectPath, -Configuration, -AdditionalMSBuildProperties) as aliases.
  Result := 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File ' +
    QuoteArgument(APlan.ScriptPath) +
    ' -ProjectFile ' + QuoteArgument(APlan.ProjectPath);
  AppendSafeTokenSwitch(Result, 'Configuration', '-Config', APlan.Configuration);
  AppendSafeTokenSwitch(Result, 'Platform', '-Platform', APlan.Platform);

  if APlan.DelphiVersion > 0 then
    Result := Result + ' -DelphiVersion ' + QuoteArgument(IntToStr(APlan.DelphiVersion));

  for LMsBuildProperty in APlan.AdditionalMSBuildProperties do
    Result := Result + ' -ExtraProperty ' + QuoteArgument(LMsBuildProperty);
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
  Result.ScriptPath := ResolveBuildScriptPath(AOptions.BuildScriptPathOverride,
    Result.ScriptSource);
  Result.ProjectPath := AProjectInfo.ProjectPath;
  Result.Platform := AProjectInfo.Platform;
  Result.Configuration := AProjectInfo.Configuration;
  Result.DelphiVersion := AOptions.DelphiVersion;
  Result.ExpectedMapFilePath := AProjectInfo.MapFilePath;
  Result.AdditionalMSBuildProperties := [cDetailedMapProperty];
  Result.TimeoutMs := cDefaultBuildTimeoutMs;

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
    // TPath.GetDirectoryName returns an empty string for drive roots (e.g. 'C:\').
    // Without this guard the loop would continue with an empty LCurrentDirectory,
    // causing TPath.Combine to produce relative paths and potentially triggering
    // a Windows "filename is empty" error (issue #19).
    if (LParentDirectory = '') or SameText(LParentDirectory, LCurrentDirectory) then
      Break;

    LCurrentDirectory := LParentDirectory;
  end;
end;

function TBuildOrchestrator.ExecutePlan(const APlan: TDeepEvidenceBuildPlan): TDeepEvidenceBuildResult;
var
  LAvailable: DWORD;
  LBytesRead: Cardinal;
  LBuffer: TBytes;
  LCommandLine: string;
  LExitCode: Cardinal;
  LOutputBuilder: TStringBuilder;
  LPipeRead, LPipeWrite: THandle;
  LProcessInfo: TProcessInformation;
  LProcessStarted: Boolean;
  LSecurityAttributes: TSecurityAttributes;
  LStartTick: UInt64;
  LStartupInfo: TStartupInfo;
  LTimedOut: Boolean;
  LTimeoutMs: UInt64;
  LWorkDir: PChar;

  procedure AppendPipeText;
  begin
    if LBytesRead > 0 then
      LOutputBuilder.Append(TEncoding.UTF8.GetString(LBuffer, 0, LBytesRead));
  end;

  function DrainAvailableOutput: Boolean;
  begin
    Result := True;
    LAvailable := 0;
    while PeekNamedPipe(LPipeRead, nil, 0, nil, @LAvailable, nil) and (LAvailable > 0) do
    begin
      if not ReadFile(LPipeRead, LBuffer[0], Length(LBuffer), LBytesRead, nil) then
        Exit(False);
      AppendPipeText;
      if LBytesRead = 0 then
        Exit(False);
    end;
  end;

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
  LProcessStarted := False;
  FillChar(LProcessInfo, SizeOf(LProcessInfo), 0);
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

    LCommandLine := APlan.CommandLine;
    UniqueString(LCommandLine);
    if APlan.WorkingDirectory <> '' then
      LWorkDir := PChar(APlan.WorkingDirectory)
    else
      LWorkDir := nil;

    if not CreateProcess(nil, PChar(LCommandLine), nil, nil, True, CREATE_NO_WINDOW,
      nil, LWorkDir, LStartupInfo, LProcessInfo) then
    begin
      Result.Success := False;
      Result.Message := 'Failed to start build process: ' + GetEnglishSystemError(GetLastError);
      Exit;
    end;
    LProcessStarted := True;

    CloseHandle(LPipeWrite);
    LPipeWrite := 0;

    Result.Executed := True;
    Result.Message := ScriptExecutionNote(APlan);
    LTimedOut := False;
    LTimeoutMs := ResolveBuildTimeoutMs(APlan);
    LStartTick := GetTickCount64;
    LOutputBuilder := TStringBuilder.Create;
    try
      SetLength(LBuffer, 4096);
      while True do
      begin
        if (GetTickCount64 - LStartTick) >= LTimeoutMs then
        begin
          LTimedOut := True;
          TerminateProcess(LProcessInfo.hProcess, 1);
          WaitForSingleObject(LProcessInfo.hProcess, 5000);
          Break;
        end;

        if not DrainAvailableOutput then
          Break;

        if WaitForSingleObject(LProcessInfo.hProcess, 200) = WAIT_OBJECT_0 then
        begin
          DrainAvailableOutput;
          Break;
        end;
      end;
      Result.Output := Trim(LOutputBuilder.ToString);
    finally
      LOutputBuilder.Free;
    end;

    if not GetExitCodeProcess(LProcessInfo.hProcess, LExitCode) then
      LExitCode := Cardinal(-1);
    Result.ExitCode := Integer(LExitCode);

    if LTimedOut then
    begin
      Result.Success := False;
      Result.Message := 'Deep-Evidence build timed out after ' +
        IntToStr(LTimeoutMs div 1000) + ' seconds. ' + ScriptExecutionNote(APlan);
    end
    else
    begin
      Result.Success := Result.ExitCode = 0;

      if Result.Success and (APlan.ExpectedMapFilePath <> '') and
         not TFile.Exists(APlan.ExpectedMapFilePath) then
      begin
        Result.Success := False;
        Result.Message := 'Build succeeded but the expected map file was not generated: ' +
          APlan.ExpectedMapFilePath + ' ' + ScriptExecutionNote(APlan);
      end
      else if Result.Success then
        Result.Message := 'Deep-Evidence build completed successfully. ' + ScriptExecutionNote(APlan)
      else
        Result.Message := 'Deep-Evidence build failed with exit code ' +
          IntToStr(Result.ExitCode) + '. ' + ScriptExecutionNote(APlan);
    end;
  finally
    if LProcessStarted then
    begin
      if LProcessInfo.hThread <> 0 then
        CloseHandle(LProcessInfo.hThread);
      if LProcessInfo.hProcess <> 0 then
        CloseHandle(LProcessInfo.hProcess);
    end;
    if LPipeRead <> 0 then
      CloseHandle(LPipeRead);
    if LPipeWrite <> 0 then
      CloseHandle(LPipeWrite);
  end;
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

function TBuildOrchestrator.IsSafeBuildToken(const AValue: string): Boolean;
var
  I: Integer;
  LChar: Char;
begin
  Result := AValue <> '';
  if not Result then
    Exit;
  for I := 1 to Length(AValue) do
  begin
    LChar := AValue[I];
    if not CharInSet(LChar, ['A'..'Z', 'a'..'z', '0'..'9', '.', '_', '+', '-']) then
      Exit(False);
  end;
end;

function TBuildOrchestrator.QuoteArgument(const AValue: string): string;
begin
  Result := '"' + StringReplace(AValue, '"', '""', [rfReplaceAll]) + '"';
end;

function TBuildOrchestrator.ResolveBuildTimeoutMs(const APlan: TDeepEvidenceBuildPlan): UInt64;
begin
  if APlan.TimeoutMs = 0 then
    Result := cDefaultBuildTimeoutMs
  else
    Result := APlan.TimeoutMs;
end;

function TBuildOrchestrator.ScriptExecutionNote(const APlan: TDeepEvidenceBuildPlan): string;
begin
  Result := 'Build script: ' + APlan.ScriptPath;
  if APlan.ScriptSource = cScriptSourceOverride then
    Result := Result + ' (configured override)'
  else if APlan.ScriptSource = cScriptSourceBundled then
    Result := Result + ' (shipped beside the DX.Comply binary)'
  else if APlan.ScriptSource = cScriptSourceModuleParents then
    Result := Result + ' (found by searching parent directories of the DX.Comply module)';
end;

function TBuildOrchestrator.FindBundledBuildScript: string;
var
  LModuleDir: string;
  LCandidate: string;
begin
  Result := '';
  LModuleDir := GetModuleDirectory;
  if LModuleDir = '' then
    Exit;

  LCandidate := TPath.Combine(LModuleDir, cBuildScriptFileName);
  if TFile.Exists(LCandidate) then
    Exit(TPath.GetFullPath(LCandidate));

  // IDE package: {app}\bpl\DX.Comply.IDE*.bpl, script installed in {app}\bin.
  LCandidate := TPath.GetFullPath(TPath.Combine(LModuleDir, '..\bin\' + cBuildScriptFileName));
  if TFile.Exists(LCandidate) then
    Exit(LCandidate);
end;

function TBuildOrchestrator.ResolveBuildScriptPath(const ABuildScriptPathOverride: string;
  out ASource: string): string;
var
  LBundled: string;
begin
  ASource := '';
  if Trim(ABuildScriptPathOverride) <> '' then
  begin
    ASource := cScriptSourceOverride;
    Exit(TPath.GetFullPath(ABuildScriptPathOverride));
  end;

  // Prefer the copy shipped next to the binary. Do not walk the project
  // being scanned: that tree can supply a script which then runs with
  // -ExecutionPolicy Bypass.
  LBundled := FindBundledBuildScript;
  if LBundled <> '' then
  begin
    ASource := cScriptSourceBundled;
    Exit(LBundled);
  end;

  Result := FindBuildScriptFromDirectory(GetModuleDirectory);
  if Result <> '' then
    ASource := cScriptSourceModuleParents;
end;

end.