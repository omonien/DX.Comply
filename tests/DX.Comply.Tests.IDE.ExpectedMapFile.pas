/// <summary>
/// DX.Comply.Tests.IDE.ExpectedMapFile
/// DUnitX tests for the IDE expected MAP file path.
/// </summary>
///
/// <remarks>
/// The confirmation dialog cannot be hosted in the console runner. These
/// tests lock the helper it calls when the configuration or platform
/// changes, including custom output directories and $(Platform) / $(Config).
/// The path must match TProjectScanner, which is what generation uses.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.IDE.ExpectedMapFile;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>
  /// DUnitX fixture for ResolveExpectedMapFileState (issue #153).
  /// </summary>
  [TestFixture]
  TIDEExpectedMapFileTests = class
  public
    [Test]
    procedure EmptyProjectPath_ReturnsEmptyState;

    [Test]
    procedure MacroOutput_ChangesWithConfigurationAndPlatform;

    [Test]
    procedure CustomOutputDir_FollowsConfiguration;

    [Test]
    procedure PlatformConfigOutputDir_FollowsSelectedTarget;

    [Test]
    procedure MissingFlag_FollowsSelectedTarget;
  end;

implementation

uses
  System.IOUtils,
  System.SysUtils,
  DX.Comply.Engine.Intf,
  DX.Comply.IDE.ExpectedMapFile,
  DX.Comply.ProjectScanner;

const
  cProjectName = 'ReadCom';

function SampleDproj(const ABaseExeOutput, ADebugOutput, AReleaseOutput,
  AReleaseWin32Output, AReleaseWin64Output: string): string;
  function Group(const ACondition, AOutput: string): string;
  begin
    if AOutput = '' then
      Exit('');
    Result :=
      '  <PropertyGroup Condition="' + ACondition + '">' + sLineBreak +
      '    <DCC_ExeOutput>' + AOutput + '</DCC_ExeOutput>' + sLineBreak +
      '  </PropertyGroup>' + sLineBreak;
  end;
begin
  Result :=
    '<?xml version="1.0" encoding="utf-8"?>' + sLineBreak +
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>ReadCom.dpr</MainSource>' + sLineBreak +
    '    <AppType>Application</AppType>' + sLineBreak +
    '    <ProjectGuid>{15300000-0000-0000-0000-000000000153}</ProjectGuid>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    Group('''$(Base)''!=''''', ABaseExeOutput) +
    Group('''$(Cfg_1)''!=''''', ADebugOutput) +
    Group('''$(Cfg_2)''!=''''', AReleaseOutput) +
    Group('''$(Cfg_2_Win32)''!=''''', AReleaseWin32Output) +
    Group('''$(Cfg_2_Win64)''!=''''', AReleaseWin64Output) +
    '  <ItemGroup>' + sLineBreak +
    '    <BuildConfiguration Include="Debug">' + sLineBreak +
    '      <Key>Cfg_1</Key>' + sLineBreak +
    '    </BuildConfiguration>' + sLineBreak +
    '    <BuildConfiguration Include="Release">' + sLineBreak +
    '      <Key>Cfg_2</Key>' + sLineBreak +
    '    </BuildConfiguration>' + sLineBreak +
    '  </ItemGroup>' + sLineBreak +
    '</Project>';
end;

function WriteProject(const ATempDir, AXml: string): string;
begin
  if TDirectory.Exists(ATempDir) then
    TDirectory.Delete(ATempDir, True);
  ForceDirectories(ATempDir);
  Result := TPath.Combine(ATempDir, cProjectName + '.dproj');
  TFile.WriteAllText(Result, AXml, TEncoding.UTF8);
end;

procedure AssertMatchesScanner(const AProjectPath, APlatform, AConfiguration: string;
  const AState: TExpectedMapFileState);
var
  LProjectInfo: TProjectInfo;
  LScanner: IProjectScanner;
begin
  LScanner := TProjectScanner.Create;
  LProjectInfo := LScanner.Scan(AProjectPath, APlatform, AConfiguration);
  try
    Assert.AreEqual(LProjectInfo.MapFilePath, AState.Path,
      APlatform + '/' + AConfiguration +
      ' must use the MAP path generation scans, but was: ' + AState.Path);
  finally
    LProjectInfo.Free;
  end;
end;

procedure TIDEExpectedMapFileTests.EmptyProjectPath_ReturnsEmptyState;
var
  LState: TExpectedMapFileState;
begin
  LState := ResolveExpectedMapFileState('', 'Win32', 'Release');
  Assert.AreEqual('', LState.Path);
  Assert.IsFalse(LState.Missing);
  Assert.AreEqual('', ExpectedMapFileMissingHint(LState));
end;

procedure TIDEExpectedMapFileTests.MacroOutput_ChangesWithConfigurationAndPlatform;
var
  LDebugWin32: TExpectedMapFileState;
  LProjectPath: string;
  LReleaseWin32: TExpectedMapFileState;
  LReleaseWin64: TExpectedMapFileState;
  LTempDir: string;
begin
  LTempDir := TPath.Combine(TPath.GetTempPath, 'DXComplyTest_ExpectedMap153_Macro');
  LProjectPath := WriteProject(LTempDir,
    SampleDproj('.\$(Platform)\$(Config)', '', '', '', ''));
  try
    LDebugWin32 := ResolveExpectedMapFileState(LProjectPath, 'Win32', 'Debug');
    LReleaseWin32 := ResolveExpectedMapFileState(LProjectPath, 'Win32', 'Release');
    LReleaseWin64 := ResolveExpectedMapFileState(LProjectPath, 'Win64', 'Release');

    AssertMatchesScanner(LProjectPath, 'Win32', 'Debug', LDebugWin32);
    AssertMatchesScanner(LProjectPath, 'Win32', 'Release', LReleaseWin32);
    AssertMatchesScanner(LProjectPath, 'Win64', 'Release', LReleaseWin64);

    Assert.IsTrue(LDebugWin32.Path.Contains(TPath.Combine('Win32', 'Debug')),
      'Debug/Win32 must keep the Debug segment, but was: ' + LDebugWin32.Path);
    Assert.IsTrue(LReleaseWin32.Path.Contains(TPath.Combine('Win32', 'Release')),
      'Release/Win32 must replace Debug with Release, but was: ' + LReleaseWin32.Path);
    Assert.IsFalse(LReleaseWin32.Path.Contains(TPath.Combine('Win32', 'Debug')),
      'Release/Win32 must not keep the Debug directory, but was: ' + LReleaseWin32.Path);
    Assert.IsTrue(LReleaseWin64.Path.Contains(TPath.Combine('Win64', 'Release')),
      'Release/Win64 must follow the platform, but was: ' + LReleaseWin64.Path);
    Assert.IsFalse(LReleaseWin64.Path.Contains(TPath.Combine('Win32', 'Release')),
      'Release/Win64 must not keep Win32, but was: ' + LReleaseWin64.Path);
    Assert.IsTrue(LReleaseWin32.Path.EndsWith(cProjectName + '.map'),
      'The file name stays the project MAP name');
  finally
    if TDirectory.Exists(LTempDir) then
      TDirectory.Delete(LTempDir, True);
  end;
end;

procedure TIDEExpectedMapFileTests.CustomOutputDir_FollowsConfiguration;
var
  LDebug: TExpectedMapFileState;
  LProjectPath: string;
  LRelease: TExpectedMapFileState;
  LTempDir: string;
begin
  // The base group still has $(Platform)\$(Config). The configuration group
  // replaces it, which is how a custom output directory is stored in a .dproj.
  LTempDir := TPath.Combine(TPath.GetTempPath, 'DXComplyTest_ExpectedMap153_Custom');
  LProjectPath := WriteProject(LTempDir,
    SampleDproj('.\$(Platform)\$(Config)', '.\out\debug', '.\out\release', '', ''));
  try
    LDebug := ResolveExpectedMapFileState(LProjectPath, 'Win32', 'Debug');
    LRelease := ResolveExpectedMapFileState(LProjectPath, 'Win32', 'Release');

    AssertMatchesScanner(LProjectPath, 'Win32', 'Debug', LDebug);
    AssertMatchesScanner(LProjectPath, 'Win32', 'Release', LRelease);

    Assert.IsTrue(LDebug.Path.Contains(TPath.Combine('out', 'debug')),
      'Debug must use its custom output directory, but was: ' + LDebug.Path);
    Assert.IsTrue(LRelease.Path.Contains(TPath.Combine('out', 'release')),
      'Release must use its custom output directory, but was: ' + LRelease.Path);
    Assert.IsFalse(LRelease.Path.Contains(TPath.Combine('Win32', 'Debug')),
      'A custom Release directory must not fall back to Win32\Debug, but was: ' +
      LRelease.Path);
    Assert.IsFalse(LDebug.Path.Contains(TPath.Combine('out', 'release')),
      'Debug must not pick up the Release directory, but was: ' + LDebug.Path);
  finally
    if TDirectory.Exists(LTempDir) then
      TDirectory.Delete(LTempDir, True);
  end;
end;

procedure TIDEExpectedMapFileTests.PlatformConfigOutputDir_FollowsSelectedTarget;
var
  LDebugWin32: TExpectedMapFileState;
  LProjectPath: string;
  LReleaseWin32: TExpectedMapFileState;
  LReleaseWin64: TExpectedMapFileState;
  LTempDir: string;
begin
  LTempDir := TPath.Combine(TPath.GetTempPath, 'DXComplyTest_ExpectedMap153_PlatCfg');
  LProjectPath := WriteProject(LTempDir,
    SampleDproj('.\$(Platform)\$(Config)', '', '',
      '.\custom\win32release', '.\custom\win64release'));
  try
    LDebugWin32 := ResolveExpectedMapFileState(LProjectPath, 'Win32', 'Debug');
    LReleaseWin32 := ResolveExpectedMapFileState(LProjectPath, 'Win32', 'Release');
    LReleaseWin64 := ResolveExpectedMapFileState(LProjectPath, 'Win64', 'Release');

    AssertMatchesScanner(LProjectPath, 'Win32', 'Debug', LDebugWin32);
    AssertMatchesScanner(LProjectPath, 'Win32', 'Release', LReleaseWin32);
    AssertMatchesScanner(LProjectPath, 'Win64', 'Release', LReleaseWin64);

    Assert.IsTrue(LDebugWin32.Path.Contains(TPath.Combine('Win32', 'Debug')),
      'Debug keeps the macro path when that configuration has no custom directory, but was: ' +
      LDebugWin32.Path);
    Assert.IsTrue(LReleaseWin32.Path.Contains(TPath.Combine('custom', 'win32release')),
      'Release/Win32 must use the platform+config output directory, but was: ' +
      LReleaseWin32.Path);
    Assert.IsTrue(LReleaseWin64.Path.Contains(TPath.Combine('custom', 'win64release')),
      'Release/Win64 must use its own platform+config output directory, but was: ' +
      LReleaseWin64.Path);
    Assert.IsFalse(LReleaseWin64.Path.Contains('win32release'),
      'Changing platform must leave the other platform directory, but was: ' +
      LReleaseWin64.Path);
  finally
    if TDirectory.Exists(LTempDir) then
      TDirectory.Delete(LTempDir, True);
  end;
end;

procedure TIDEExpectedMapFileTests.MissingFlag_FollowsSelectedTarget;
var
  LDebug: TExpectedMapFileState;
  LProjectPath: string;
  LRelease: TExpectedMapFileState;
  LTempDir: string;
begin
  LTempDir := TPath.Combine(TPath.GetTempPath, 'DXComplyTest_ExpectedMap153_Missing');
  LProjectPath := WriteProject(LTempDir,
    SampleDproj('.\$(Platform)\$(Config)', '', '', '', ''));
  try
    LDebug := ResolveExpectedMapFileState(LProjectPath, 'Win32', 'Debug');
    LRelease := ResolveExpectedMapFileState(LProjectPath, 'Win32', 'Release');
    Assert.IsTrue(LDebug.Missing, 'A Debug MAP that was not written is missing');
    Assert.IsTrue(LRelease.Missing, 'A Release MAP that was not written is missing');
    Assert.AreNotEqual(LDebug.Path, LRelease.Path,
      'The two configurations must not share one expected path');

    ForceDirectories(TPath.GetDirectoryName(LDebug.Path));
    TFile.WriteAllText(LDebug.Path, 'map', TEncoding.ASCII);

    LDebug := ResolveExpectedMapFileState(LProjectPath, 'Win32', 'Debug');
    LRelease := ResolveExpectedMapFileState(LProjectPath, 'Win32', 'Release');
    Assert.IsFalse(LDebug.Missing, 'The Debug MAP on disk clears the missing flag');
    Assert.IsTrue(LRelease.Missing,
      'A Debug MAP must not clear the missing flag for Release');
    Assert.AreEqual('', ExpectedMapFileMissingHint(LDebug));
    Assert.AreEqual(scExpectedMapFileMissing, ExpectedMapFileMissingHint(LRelease));
    Assert.IsFalse(LRelease.Path.Contains(TPath.Combine('Win32', 'Debug')),
      'The Release path must stay in its own directory when the Debug MAP exists, but was: ' +
      LRelease.Path);
  finally
    if TDirectory.Exists(LTempDir) then
      TDirectory.Delete(LTempDir, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TIDEExpectedMapFileTests);

end.
