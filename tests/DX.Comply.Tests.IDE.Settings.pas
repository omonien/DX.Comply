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
    procedure OptionsPageCaption_UsesSingleTreeNodeCaption;

    [Test]
    procedure ScaleDesignValue_ScalesLinearlyByTargetPPI;

    [Test]
    procedure SaveToFile_ThenLoadFromFile_RoundTripsAllFields;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  DX.Comply.IDE.Settings,
  DX.Comply.Report.Intf;

procedure TIDESettingsTests.Default_HasSafeAutomationDefaults;
var
  LSettings: TDXComplyIDESettings;
begin
  LSettings := TDXComplyIDESettings.Default;
  Assert.AreEqual(Ord(abmAlways), Ord(LSettings.AutoBuildMode));
  Assert.IsTrue(LSettings.PromptBeforeBuild);
  Assert.IsTrue(LSettings.SaveAllModifiedFilesBeforeBuild);
  Assert.IsTrue(LSettings.UseActiveBuildConfiguration);
  Assert.IsFalse(LSettings.ContinueWithoutDeepEvidenceOnBuildFailure);
  Assert.IsTrue(LSettings.OpenHtmlReportAfterGenerate);
  Assert.IsTrue(LSettings.WarnWhenCompositionEvidenceIsEmpty);
  Assert.AreEqual(0, LSettings.DelphiVersionOverride);
  Assert.IsTrue(LSettings.HumanReadableReport.Enabled);
  Assert.AreEqual(NativeInt(Ord(hrfBoth)), NativeInt(Ord(LSettings.HumanReadableReport.Format)));
end;

procedure TIDESettingsTests.LoadFromMissingFile_ReturnsDefaults;
var
  LFilePath: string;
  LSettings: TDXComplyIDESettings;
begin
  LFilePath := TPath.Combine(TPath.GetTempPath, TPath.GetRandomFileName + '.ini');
  LSettings := TDXComplyIDESettingsStore.LoadFromFile(LFilePath);
  Assert.AreEqual(Ord(abmAlways), Ord(LSettings.AutoBuildMode));
  Assert.AreEqual('', LSettings.BuildScriptPath);
  Assert.AreEqual('', LSettings.HumanReadableReport.OutputBasePath);
end;

procedure TIDESettingsTests.OptionsPageCaption_UsesSingleTreeNodeCaption;
begin
  Assert.AreEqual('DX' + #$2024 + 'Comply', DXComplyOptionsPageCaption);
  Assert.IsFalse(DXComplyOptionsPageCaption.Contains('.'));
end;

procedure TIDESettingsTests.ScaleDesignValue_ScalesLinearlyByTargetPPI;
begin
  Assert.AreEqual(16, DXComplyScaleDesignValue(16, 96));
  Assert.AreEqual(32, DXComplyScaleDesignValue(16, 192));
  Assert.AreEqual(16, DXComplyScaleDesignValue(16, 0));
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
    LSettings.OpenHtmlReportAfterGenerate := False;
    LSettings.WarnWhenCompositionEvidenceIsEmpty := False;
    LSettings.BuildScriptPath := 'C:\Tools\DelphiBuildDPROJ.ps1';
    LSettings.DelphiVersionOverride := 37;
    LSettings.HumanReadableReport.Enabled := True;
    LSettings.HumanReadableReport.Format := hrfBoth;
    LSettings.HumanReadableReport.OutputBasePath := 'C:\Reports\demo.report';
    LSettings.HumanReadableReport.IncludeWarnings := False;
    LSettings.HumanReadableReport.IncludeCompositionEvidence := False;
    LSettings.HumanReadableReport.IncludeBuildEvidence := False;

    TDXComplyIDESettingsStore.SaveToFile(LFilePath, LSettings);
    LLoadedSettings := TDXComplyIDESettingsStore.LoadFromFile(LFilePath);

    Assert.AreEqual(Ord(abmAlways), Ord(LLoadedSettings.AutoBuildMode));
    Assert.IsFalse(LLoadedSettings.PromptBeforeBuild);
    Assert.IsFalse(LLoadedSettings.SaveAllModifiedFilesBeforeBuild);
    Assert.IsFalse(LLoadedSettings.UseActiveBuildConfiguration);
    Assert.IsFalse(LLoadedSettings.ContinueWithoutDeepEvidenceOnBuildFailure);
    Assert.IsFalse(LLoadedSettings.OpenHtmlReportAfterGenerate);
    Assert.IsFalse(LLoadedSettings.WarnWhenCompositionEvidenceIsEmpty);
    Assert.AreEqual(LSettings.BuildScriptPath, LLoadedSettings.BuildScriptPath);
    Assert.AreEqual(37, LLoadedSettings.DelphiVersionOverride);
    Assert.IsTrue(LLoadedSettings.HumanReadableReport.Enabled);
    Assert.AreEqual(NativeInt(Ord(hrfBoth)), NativeInt(Ord(LLoadedSettings.HumanReadableReport.Format)));
    Assert.AreEqual(LSettings.HumanReadableReport.OutputBasePath,
      LLoadedSettings.HumanReadableReport.OutputBasePath);
    Assert.IsFalse(LLoadedSettings.HumanReadableReport.IncludeWarnings);
    Assert.IsFalse(LLoadedSettings.HumanReadableReport.IncludeCompositionEvidence);
    Assert.IsFalse(LLoadedSettings.HumanReadableReport.IncludeBuildEvidence);
  finally
    if TFile.Exists(LFilePath) then
      TFile.Delete(LFilePath);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TIDESettingsTests);

end.