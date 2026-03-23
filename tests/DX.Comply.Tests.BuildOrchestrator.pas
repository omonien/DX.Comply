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

initialization
  TDUnitX.RegisterTestFixture(TBuildOrchestratorTests);

end.