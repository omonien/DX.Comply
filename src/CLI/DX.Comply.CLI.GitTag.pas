/// <summary>
/// DX.Comply.CLI.GitTag
/// Reads the product version from the latest git tag of a directory.
/// </summary>
///
/// <remarks>
/// Used by the --version-from-git-tag CLI option. The tag is the one
/// "git describe --tags --abbrev=0" reports for the checked-out commit, that
/// is the newest tag reachable from HEAD. A leading v or V is removed, so
/// v2.1.0 becomes 2.1.0. When git is not installed, the directory is not a
/// git work tree, or no tag exists, the caller keeps the version it already
/// had and prints the warning text returned here.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.CLI.GitTag;

interface

uses
  DX.Comply.Engine;

/// <summary>
/// Removes surrounding blanks and one leading v or V from ATag.
/// A tag that is only "v" is returned unchanged.
/// </summary>
function StripVersionTagPrefix(const ATag: string): string;

/// <summary>
/// Runs "git -C ADirectory AArguments" without a window and returns its
/// combined stdout and stderr. Returns False when git cannot be started.
/// </summary>
function RunGitCommand(const ADirectory, AArguments: string; out AOutput: string;
  out AExitCode: Cardinal): Boolean;

/// <summary>
/// Runs git in ADirectory and returns the newest tag reachable from HEAD.
/// Returns False with a reason in AError when git cannot be started, the
/// directory is not a git work tree, or no tag exists.
/// </summary>
function TryReadLatestGitTag(const ADirectory: string; out ATag: string;
  out AError: string): Boolean;

/// <summary>
/// Sets AConfig.ProductVersion from the latest git tag of ADirectory and
/// marks it as an explicit override, so a config file value does not replace
/// it. An explicit --version is left alone. Returns False with a warning in
/// AWarning when no tag could be read; AConfig is then unchanged.
/// </summary>
function ApplyVersionFromGitTag(var AConfig: TSbomConfig;
  const ADirectory: string; out AWarning: string): Boolean;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes;

function StripVersionTagPrefix(const ATag: string): string;
begin
  Result := Trim(ATag);
  if (Length(Result) > 1) and CharInSet(Result[1], ['v', 'V']) then
    Delete(Result, 1, 1);
end;

function RunGitCommand(const ADirectory, AArguments: string; out AOutput: string;
  out AExitCode: Cardinal): Boolean;
var
  LSecurity: TSecurityAttributes;
  LReadPipe, LWritePipe: THandle;
  LStartup: TStartupInfo;
  LProcess: TProcessInformation;
  LCommandLine: string;
  LBuffer: TBytes;
  LRead: DWORD;
  LStream: TBytesStream;
begin
  Result := False;
  AOutput := '';
  AExitCode := Cardinal(-1);

  FillChar(LSecurity, SizeOf(LSecurity), 0);
  LSecurity.nLength := SizeOf(LSecurity);
  LSecurity.bInheritHandle := True;
  if not CreatePipe(LReadPipe, LWritePipe, @LSecurity, 0) then
    Exit;
  try
    SetHandleInformation(LReadPipe, HANDLE_FLAG_INHERIT, 0);

    FillChar(LStartup, SizeOf(LStartup), 0);
    LStartup.cb := SizeOf(LStartup);
    LStartup.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    LStartup.wShowWindow := SW_HIDE;
    LStartup.hStdInput := 0;
    LStartup.hStdOutput := LWritePipe;
    LStartup.hStdError := LWritePipe;

    LCommandLine := 'git -C "' + ExcludeTrailingPathDelimiter(ADirectory) +
      '" ' + AArguments;
    UniqueString(LCommandLine);
    FillChar(LProcess, SizeOf(LProcess), 0);
    if not CreateProcess(nil, PChar(LCommandLine), nil, nil, True,
      CREATE_NO_WINDOW, nil, nil, LStartup, LProcess) then
      Exit;

    CloseHandle(LWritePipe);
    LWritePipe := 0;
    try
      LStream := TBytesStream.Create;
      try
        SetLength(LBuffer, 4096);
        while ReadFile(LReadPipe, LBuffer[0], Length(LBuffer), LRead, nil) and
          (LRead > 0) do
          LStream.WriteBuffer(LBuffer[0], LRead);
        WaitForSingleObject(LProcess.hProcess, 30000);
        GetExitCodeProcess(LProcess.hProcess, AExitCode);
        AOutput := Trim(TEncoding.UTF8.GetString(LStream.Bytes, 0, LStream.Size));
      finally
        LStream.Free;
      end;
    finally
      CloseHandle(LProcess.hThread);
      CloseHandle(LProcess.hProcess);
    end;
    Result := True;
  finally
    if LWritePipe <> 0 then
      CloseHandle(LWritePipe);
    CloseHandle(LReadPipe);
  end;
end;

function FirstLine(const AText: string): string;
var
  LPos: Integer;
begin
  Result := AText;
  LPos := Pos(#10, Result);
  if LPos > 0 then
    Result := Copy(Result, 1, LPos - 1);
  Result := Trim(Result);
end;

function TryReadLatestGitTag(const ADirectory: string; out ATag: string;
  out AError: string): Boolean;
var
  LOutput: string;
  LExitCode: Cardinal;
begin
  Result := False;
  ATag := '';
  AError := '';

  if (ADirectory = '') or not DirectoryExists(ADirectory) then
  begin
    AError := 'directory not found: ' + ADirectory;
    Exit;
  end;

  if not RunGitCommand(ADirectory, 'describe --tags --abbrev=0', LOutput, LExitCode) then
  begin
    AError := 'git could not be started. Is git installed and on PATH?';
    Exit;
  end;

  if LExitCode <> 0 then
  begin
    if LOutput = '' then
      AError := 'git describe failed with exit code ' + UIntToStr(LExitCode)
    else
      AError := FirstLine(LOutput);
    Exit;
  end;

  ATag := FirstLine(LOutput);
  if ATag = '' then
  begin
    AError := 'git describe returned no tag';
    Exit;
  end;
  Result := True;
end;

function ApplyVersionFromGitTag(var AConfig: TSbomConfig;
  const ADirectory: string; out AWarning: string): Boolean;
var
  LTag: string;
  LError: string;
  LVersion: string;
begin
  AWarning := '';
  if scoProductVersion in AConfig.ExplicitOverrides then
    Exit(False);

  if not TryReadLatestGitTag(ADirectory, LTag, LError) then
  begin
    AWarning := 'Warning: --version-from-git-tag: no git tag found in ' +
      ADirectory + ' (' + LError + '). The version from the config file or ' +
      'the project version info is used instead.';
    Exit(False);
  end;

  LVersion := StripVersionTagPrefix(LTag);
  AConfig.ProductVersion := LVersion;
  Include(AConfig.ExplicitOverrides, scoProductVersion);
  Result := True;
end;

end.
