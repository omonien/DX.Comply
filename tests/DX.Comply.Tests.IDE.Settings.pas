/// <summary>
/// DX.Comply.Tests.IDE.Settings
/// DUnitX tests for DX.Comply IDE settings persistence.
/// </summary>
///
/// <remarks>
/// These tests keep the settings store ToolsAPI-free and ensure the IDE plugin can
/// reliably persist optional Deep-Evidence automation defaults.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.IDE.Settings;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>
  /// DUnitX fixture for global IDE settings persistence.
  /// </summary>
  [TestFixture]
  TIDESettingsTests = class
  public
    [Test]
    procedure Default_HasSafeAutomationDefaults;

    [Test]
    procedure LoadFromMissingFile_ReturnsDefaults;

    [Test]
    procedure SaveToFile_ThenLoadFromFile_RoundTripsAllFields;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  DX.Comply.IDE.Settings;

procedure TIDESettingsTests.Default_HasSafeAutomationDefaults;
var
  LSettings: TDXComplyIDESettings;
begin
  LSettings := TDXComplyIDESettings.Default;
  Assert.AreEqual(Ord(abmDisabled), Ord(LSettings.AutoBuildMode));
  Assert.IsTrue(LSettings.PromptBeforeBuild);
  Assert.IsTrue(LSettings.SaveAllModifiedFilesBeforeBuild);
  Assert.IsTrue(LSettings.UseActiveBuildConfiguration);
  Assert.IsTrue(LSettings.ContinueWithoutDeepEvidenceOnBuildFailure);
  Assert.IsTrue(LSettings.WarnWhenCompositionEvidenceIsEmpty);
  Assert.AreEqual(0, LSettings.DelphiVersionOverride);
end;

procedure TIDESettingsTests.LoadFromMissingFile_ReturnsDefaults;
var
  LFilePath: string;
  LSettings: TDXComplyIDESettings;
begin
  LFilePath := TPath.Combine(TPath.GetTempPath, TPath.GetRandomFileName + '.ini');
  LSettings := TDXComplyIDESettingsStore.LoadFromFile(LFilePath);
  Assert.AreEqual(Ord(abmDisabled), Ord(LSettings.AutoBuildMode));
  Assert.AreEqual('', LSettings.BuildScriptPath);
end;

procedure TIDESettingsTests.SaveToFile_ThenLoadFromFile_RoundTripsAllFields;
var
  LFilePath: string;
  LLoadedSettings: TDXComplyIDESettings;
  LSettings: TDXComplyIDESettings;
begin
  LFilePath := TPath.Combine(TPath.GetTempPath, TPath.GetRandomFileName + '.ini');
  try
    LSettings := TDXComplyIDESettings.Default;
    LSettings.AutoBuildMode := abmAlways;
    LSettings.PromptBeforeBuild := False;
    LSettings.SaveAllModifiedFilesBeforeBuild := False;
    LSettings.UseActiveBuildConfiguration := False;
    LSettings.ContinueWithoutDeepEvidenceOnBuildFailure := False;
    LSettings.WarnWhenCompositionEvidenceIsEmpty := False;
    LSettings.BuildScriptPath := 'C:\Tools\DelphiBuildDPROJ.ps1';
    LSettings.DelphiVersionOverride := 37;

    TDXComplyIDESettingsStore.SaveToFile(LFilePath, LSettings);
    LLoadedSettings := TDXComplyIDESettingsStore.LoadFromFile(LFilePath);

    Assert.AreEqual(Ord(abmAlways), Ord(LLoadedSettings.AutoBuildMode));
    Assert.IsFalse(LLoadedSettings.PromptBeforeBuild);
    Assert.IsFalse(LLoadedSettings.SaveAllModifiedFilesBeforeBuild);
    Assert.IsFalse(LLoadedSettings.UseActiveBuildConfiguration);
    Assert.IsFalse(LLoadedSettings.ContinueWithoutDeepEvidenceOnBuildFailure);
    Assert.IsFalse(LLoadedSettings.WarnWhenCompositionEvidenceIsEmpty);
    Assert.AreEqual(LSettings.BuildScriptPath, LLoadedSettings.BuildScriptPath);
    Assert.AreEqual(37, LLoadedSettings.DelphiVersionOverride);
  finally
    if TFile.Exists(LFilePath) then
      TFile.Delete(LFilePath);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TIDESettingsTests);

end.