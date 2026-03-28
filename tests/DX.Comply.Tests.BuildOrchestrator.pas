/// <summary>
/// DX.Comply.Tests.BuildOrchestrator
/// DUnitX tests for TBuildOrchestrator.
/// </summary>
///
/// <remarks>
/// Covers deterministic Deep-Evidence build-plan construction without relying
/// on a local Delphi installation.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.BuildOrchestrator;

interface

uses
  DUnitX.TestFramework,
  DX.Comply.BuildOrchestrator,
  DX.Comply.Engine.Intf;

type
  /// <summary>
  /// DUnitX fixture for the Deep-Evidence build orchestrator.
  /// </summary>
  [TestFixture]
  TBuildOrchestratorTests = class
  private
    FBuildOrchestrator: IBuildOrchestrator;
    function BuildOptions(AMode: TDeepEvidenceBuildMode;
      const ABuildScriptPathOverride: string = ''; ADelphiVersion: Integer = 0): TDeepEvidenceBuildOptions;
  public
    [Setup]
    procedure Setup;

    /// <summary>
    /// A missing map file must produce a build plan that forces detailed map generation.
    /// </summary>
    [Test]
    procedure CreatePlan_MapMissing_ForcesDetailedMapBuild;

    /// <summary>
    /// An existing map file must prevent a redundant build execution.
    /// </summary>
    [Test]
    procedure CreatePlan_MapExists_SkipsExecution;

    /// <summary>
    /// An explicit build script override must be used verbatim.
    /// </summary>
    [Test]
    procedure CreatePlan_UsesBuildScriptOverride;

    /// <summary>
    /// An empty MapFilePath must suppress build execution to prevent
    /// EInOutArgumentException on empty path operations (regression #17).
    /// </summary>
    [Test]
    procedure CreatePlan_EmptyMapFilePath_SkipsExecution;

    /// <summary>
    /// ExecutePlan must fail gracefully when ScriptPath is empty instead
    /// of passing an empty string to TFile.Exists (regression #17).
    /// </summary>
    [Test]
    procedure ExecutePlan_EmptyScriptPath_FailsGracefully;

    /// <summary>
    /// CreatePlan must not raise an exception when the project directory is a
    /// drive root (e.g. C:\).  Previously the directory traversal inside
    /// FindBuildScriptFromDirectory produced an empty path after
    /// TPath.GetDirectoryName('C:\') returned '', causing a Windows
    /// "Dateiname ist leer" error (regression #19).
    /// </summary>
    [Test]
    procedure CreatePlan_ProjectAtDriveRoot_DoesNotCrash;

    /// <summary>
    /// When the project lives at a drive root and no build script is found
    /// anywhere, the plan must still be returned with an empty ScriptPath
    /// rather than raising an exception (regression #19).
    /// </summary>
    [Test]
    procedure CreatePlan_ProjectAtDriveRoot_ScriptPathEmpty;
  end;

implementation

uses
  System.IOUtils,
  System.SysUtils;

function TBuildOrchestratorTests.BuildOptions(AMode: TDeepEvidenceBuildMode;
  const ABuildScriptPathOverride: string; ADelphiVersion: Integer): TDeepEvidenceBuildOptions;
begin
  Result := TDeepEvidenceBuildOptions.Default;
  Result.Mode := AMode;
  Result.BuildScriptPathOverride := ABuildScriptPathOverride;
  Result.DelphiVersion := ADelphiVersion;
end;

procedure TBuildOrchestratorTests.Setup;
begin
  FBuildOrchestrator := TBuildOrchestrator.Create;
end;

procedure TBuildOrchestratorTests.CreatePlan_MapExists_SkipsExecution;
var
  LPlan: TDeepEvidenceBuildPlan;
  LMapFilePath: string;
  LProjectInfo: TProjectInfo;
begin
  LMapFilePath := TPath.GetTempFileName;
  try
    LProjectInfo := TProjectInfo.Create;
    try
      LProjectInfo.ProjectPath := 'C:\Repo\src\DX.Comply.Engine.dproj';
      LProjectInfo.ProjectDir := 'C:\Repo\src';
      LProjectInfo.Platform := 'Win32';
      LProjectInfo.Configuration := 'Debug';
      LProjectInfo.MapFilePath := LMapFilePath;

      LPlan := FBuildOrchestrator.CreatePlan(LProjectInfo, BuildOptions(debWhenMapMissing));

      Assert.IsFalse(LPlan.ShouldExecute,
        'An existing map file must suppress a redundant Deep-Evidence build');
    finally
      LProjectInfo.Free;
    end;
  finally
    if TFile.Exists(LMapFilePath) then
      TFile.Delete(LMapFilePath);
  end;
end;

procedure TBuildOrchestratorTests.CreatePlan_MapMissing_ForcesDetailedMapBuild;
var
  LPlan: TDeepEvidenceBuildPlan;
  LProjectInfo: TProjectInfo;
begin
  LProjectInfo := TProjectInfo.Create;
  try
    LProjectInfo.ProjectPath := 'C:\Repo\src\DX.Comply.Engine.dproj';
    LProjectInfo.ProjectDir := 'C:\Repo\src';
    LProjectInfo.Platform := 'Win64';
    LProjectInfo.Configuration := 'Release';
    LProjectInfo.MapFilePath := 'C:\Repo\build\Win64\Release\DX.Comply.Engine.map';

    LPlan := FBuildOrchestrator.CreatePlan(LProjectInfo,
      BuildOptions(debWhenMapMissing, '', 13));

    Assert.IsTrue(LPlan.ShouldExecute,
      'A missing map file must trigger a Deep-Evidence build plan');
    Assert.AreEqual(NativeInt(1), NativeInt(Length(LPlan.AdditionalMSBuildProperties)),
      'The plan must append one MSBuild property to force detailed map generation');
    Assert.AreEqual('DCC_MapFile=3', LPlan.AdditionalMSBuildProperties[0],
      'The build plan must force detailed map generation');
    Assert.IsTrue(Pos('-DelphiVersion 13', LPlan.CommandLine) > 0,
      'The requested Delphi version must be forwarded into the build command line');
    Assert.IsTrue(Pos('-AdditionalMSBuildProperties "DCC_MapFile=3"', LPlan.CommandLine) > 0,
      'The command line must forward the detailed map property to the build script');
  finally
    LProjectInfo.Free;
  end;
end;

procedure TBuildOrchestratorTests.CreatePlan_UsesBuildScriptOverride;
var
  LPlan: TDeepEvidenceBuildPlan;
  LProjectInfo: TProjectInfo;
  LScriptPath: string;
begin
  LProjectInfo := TProjectInfo.Create;
  try
    LProjectInfo.ProjectPath := 'C:\Repo\src\DX.Comply.Engine.dproj';
    LProjectInfo.ProjectDir := 'C:\Repo\src';
    LProjectInfo.Platform := 'Win64';
    LProjectInfo.Configuration := 'Release';
    LProjectInfo.MapFilePath := 'C:\Repo\build\Win64\Release\DX.Comply.Engine.map';
    LScriptPath := 'C:\Tools\DelphiBuildDPROJ.ps1';

    LPlan := FBuildOrchestrator.CreatePlan(LProjectInfo,
      BuildOptions(debAlways, LScriptPath, 37));

    Assert.AreEqual(TPath.GetFullPath(LScriptPath), LPlan.ScriptPath,
      'The explicit build script override must take precedence over automatic discovery');
    Assert.IsTrue(LPlan.ShouldExecute,
      'The Always mode must force an explicit Deep-Evidence build');
  finally
    LProjectInfo.Free;
  end;
end;

procedure TBuildOrchestratorTests.CreatePlan_EmptyMapFilePath_SkipsExecution;
var
  LPlan: TDeepEvidenceBuildPlan;
  LProjectInfo: TProjectInfo;
begin
  LProjectInfo := TProjectInfo.Create;
  try
    LProjectInfo.ProjectPath := 'C:\Repo\src\MyApp.dproj';
    LProjectInfo.ProjectDir := 'C:\Repo\src';
    LProjectInfo.Platform := 'Win32';
    LProjectInfo.Configuration := 'Debug';
    LProjectInfo.MapFilePath := '';

    LPlan := FBuildOrchestrator.CreatePlan(LProjectInfo, BuildOptions(debWhenMapMissing));

    Assert.IsFalse(LPlan.ShouldExecute,
      'An empty MapFilePath must suppress build execution because the result cannot be verified');
  finally
    LProjectInfo.Free;
  end;
end;

procedure TBuildOrchestratorTests.ExecutePlan_EmptyScriptPath_FailsGracefully;
var
  LPlan: TDeepEvidenceBuildPlan;
  LResult: TDeepEvidenceBuildResult;
begin
  LPlan := Default(TDeepEvidenceBuildPlan);
  LPlan.Enabled := True;
  LPlan.ShouldExecute := True;
  LPlan.ScriptPath := '';
  LPlan.ProjectPath := 'C:\Repo\src\MyApp.dproj';
  LPlan.Platform := 'Win32';
  LPlan.Configuration := 'Debug';
  LPlan.ExpectedMapFilePath := 'C:\Repo\build\Win32\Debug\MyApp.map';

  LResult := FBuildOrchestrator.ExecutePlan(LPlan);

  Assert.IsFalse(LResult.Success,
    'An empty ScriptPath must produce a failure result, not an exception');
  Assert.IsTrue(Pos('not found', LResult.Message) > 0,
    'The failure message must indicate the build script was not found');
end;

procedure TBuildOrchestratorTests.CreatePlan_ProjectAtDriveRoot_DoesNotCrash;
var
  LPlan: TDeepEvidenceBuildPlan;
  LProjectInfo: TProjectInfo;
begin
  // Projects located directly at a drive root (e.g. C:\MyApp.dproj) must not
  // cause any exception during plan creation.  The directory traversal inside
  // FindBuildScriptFromDirectory used to produce an empty path when
  // TPath.GetDirectoryName('C:\') returned '' (issue #19).
  LProjectInfo := TProjectInfo.Create;
  try
    LProjectInfo.ProjectPath := 'C:\MyApp.dproj';
    LProjectInfo.ProjectDir := 'C:\';
    LProjectInfo.Platform := 'Win32';
    LProjectInfo.Configuration := 'Release';
    LProjectInfo.MapFilePath := 'C:\build\Win32\Release\MyApp.map';

    Assert.WillNotRaise(
      procedure
      begin
        LPlan := FBuildOrchestrator.CreatePlan(LProjectInfo, BuildOptions(debAlways));
      end,
      Exception,
      'CreatePlan must not raise when the project is at a drive root');
  finally
    LProjectInfo.Free;
  end;
end;

procedure TBuildOrchestratorTests.CreatePlan_ProjectAtDriveRoot_ScriptPathEmpty;
var
  LPlan: TDeepEvidenceBuildPlan;
  LProjectInfo: TProjectInfo;
begin
  // When the project is at a drive root and no DelphiBuildDPROJ.ps1 is found,
  // the plan must be returned with an empty ScriptPath rather than a garbage
  // relative path produced by combining an empty parent directory (issue #19).
  LProjectInfo := TProjectInfo.Create;
  try
    LProjectInfo.ProjectPath := 'C:\MyApp.dproj';
    LProjectInfo.ProjectDir := 'C:\';
    LProjectInfo.Platform := 'Win32';
    LProjectInfo.Configuration := 'Release';
    LProjectInfo.MapFilePath := 'C:\build\Win32\Release\MyApp.map';

    LPlan := FBuildOrchestrator.CreatePlan(LProjectInfo,
      BuildOptions(debAlways, '', 0));

    // With no override and no script on disk the path must be empty (or a
    // properly absolute path if the script happens to be installed).
    if LPlan.ScriptPath <> '' then
      Assert.IsTrue(TPath.IsPathRooted(LPlan.ScriptPath),
        'ScriptPath must be an absolute path, not a relative fragment')
    else
      Assert.AreEqual('', LPlan.ScriptPath,
        'ScriptPath must be empty when no build script is found');
  finally
    LProjectInfo.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TBuildOrchestratorTests);

end.