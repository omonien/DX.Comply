/// <summary>
/// DX.Comply.Tests.Report.HtmlWriter
/// DUnitX tests for the HTML compliance report writer.
/// </summary>
///
/// <remarks>
/// The HTML report targets human auditors, so these tests assert that the generated
/// document contains the expected semantic sections and status markers.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.Report.HtmlWriter;

interface

uses
  System.Generics.Collections,
  DUnitX.TestFramework,
  DX.Comply.BuildEvidence.Intf,
  DX.Comply.Engine.Intf,
  DX.Comply.Report.Intf;

type
  /// <summary>
  /// DUnitX fixture for HTML report rendering.
  /// </summary>
  [TestFixture]
  THtmlReportWriterTests = class
  private
    FArtefacts: TArtefactList;
    FBuildEvidence: TBuildEvidence;
    FCompositionEvidence: TCompositionEvidence;
    FData: TComplianceReportData;
    FOutputPath: string;
    FProjectInfo: TProjectInfo;
    FTempDir: string;
    FWarnings: TList<string>;
    procedure InitializeReportData;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure GetFormat_ReturnsHtml;

    [Test]
    procedure Write_CreatesReadableHtmlReport;
  end;

implementation

uses
  System.IOUtils,
  System.SysUtils,
  DX.Comply.Report.HtmlWriter,
  DX.Comply.Schema.Validator;

procedure THtmlReportWriterTests.GetFormat_ReturnsHtml;
var
  LWriter: IHumanReadableReportWriter;
begin
  LWriter := THtmlReportWriter.Create;
  Assert.AreEqual(NativeInt(Ord(hrfHtml)), NativeInt(Ord(LWriter.GetFormat)));
end;

procedure THtmlReportWriterTests.InitializeReportData;
var
  LArtefact: TArtefactInfo;
  LEvidenceItem: TBuildEvidenceItem;
  LResolvedUnit: TResolvedUnitInfo;
begin
  FProjectInfo := TProjectInfo.Create;
  FProjectInfo.ProjectName := 'Demo';
  FProjectInfo.ProjectPath := TPath.Combine(FTempDir, 'src', 'Demo.dproj');
  FProjectInfo.ProjectDir := TPath.GetDirectoryName(FProjectInfo.ProjectPath);
  FProjectInfo.Platform := 'Win32';
  FProjectInfo.Configuration := 'Debug';
  FProjectInfo.UsesDebugDCUs := True;
  FProjectInfo.Version := '2.0.0';
  FProjectInfo.Toolchain.ProductName := 'Embarcadero Delphi';
  FProjectInfo.Toolchain.Version := '37.0';
  FProjectInfo.Toolchain.BuildVersion := '37.0.57242.3601';
  FProjectInfo.Toolchain.RootDir := 'C:\Program Files (x86)\Embarcadero\Studio\37.0';

  FBuildEvidence := TBuildEvidence.Create;
  LEvidenceItem.SourceKind := besCompilerResponseFile;
  LEvidenceItem.DisplayName := 'dcc32.rsp';
  LEvidenceItem.FilePath := 'Y:\Build\dcc32.rsp';
  LEvidenceItem.UnitName := 'Demo.Html';
  LEvidenceItem.Detail := '-U search path';
  FBuildEvidence.EvidenceItems.Add(LEvidenceItem);

  FCompositionEvidence := TCompositionEvidence.Create;
  FCompositionEvidence.GeneratedAt := '2026-03-07T13:00:00Z';
  LResolvedUnit.UnitName := 'Demo.Html';
  LResolvedUnit.EvidenceKind := uekDcu;
  LResolvedUnit.OriginKind := uokThirdParty;
  LResolvedUnit.Confidence := rcStrong;
  LResolvedUnit.ContainerPath := 'Y:\Lib\Demo.Html.dcu';
  FCompositionEvidence.Units.Add(LResolvedUnit);

  FArtefacts := TArtefactList.Create;
  LArtefact.FilePath := 'Y:\Build\Demo.dll';
  LArtefact.RelativePath := 'build\Win32\Debug\Demo.dll';
  LArtefact.FileSize := 2048;
  LArtefact.Hash := '1234567890ABCDEF';
  LArtefact.ArtefactType := 'dll';
  FArtefacts.Add(LArtefact);

  FWarnings := TList<string>.Create;
  FWarnings.Add('One third-party unit was resolved heuristically.');

  FData := Default(TComplianceReportData);
  FData.SbomOutputPath := TPath.Combine(FTempDir, 'bom.json');
  FData.SbomFormat := sfCycloneDxJson;
  FData.Metadata.ProductName := 'Demo';
  FData.Metadata.ProductVersion := '2.0.0';
  FData.Metadata.Timestamp := '2026-03-07T13:00:00Z';
  FData.ProjectInfo := FProjectInfo;
  FData.BuildEvidence := FBuildEvidence;
  FData.CompositionEvidence := FCompositionEvidence;
  FData.Artefacts := FArtefacts;
  FData.Warnings := FWarnings;
  FData.DeepEvidenceRequested := True;
  FData.DeepEvidenceResult.Success := True;
  FData.DeepEvidenceResult.Executed := False;
  FData.DeepEvidenceResult.Message := 'Skipped because the expected MAP file already existed.';
  FData.ValidationResult := TValidationResult.CreateValid;
end;

procedure THtmlReportWriterTests.Setup;
var
  LGuid: TGUID;
begin
  CreateGUID(LGuid);
  FTempDir := TPath.Combine(TPath.GetTempPath, GUIDToString(LGuid).Trim(['{', '}']));
  TDirectory.CreateDirectory(FTempDir);
  FOutputPath := TPath.Combine(FTempDir, 'report.html');
  InitializeReportData;
end;

procedure THtmlReportWriterTests.TearDown;
begin
  FWarnings.Free;
  FArtefacts.Free;
  FCompositionEvidence.Free;
  FBuildEvidence.Free;
  FProjectInfo.Free;
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

procedure THtmlReportWriterTests.Write_CreatesReadableHtmlReport;
var
  LConfig: THumanReadableReportConfig;
  LContent: string;
  LWriter: IHumanReadableReportWriter;
begin
  LConfig := THumanReadableReportConfig.Default;
  LWriter := THtmlReportWriter.Create;

  Assert.IsTrue(LWriter.Write(FOutputPath, FData, LConfig));
  Assert.IsTrue(TFile.Exists(FOutputPath));

  LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('<!DOCTYPE html>', LContent) > 0);
  Assert.IsTrue(Pos('<h1>Software Release Assessment (SRA) and SBOM Compliance Report</h1>', LContent) > 0);
  Assert.IsTrue(Pos('This Software Release Assessment summarizes the generated Software Bill of Materials (SBOM)', LContent) > 0);
  Assert.IsTrue(Pos('Generated By', LContent) > 0);
  Assert.IsTrue(Pos('Repository / Project Root', LContent) > 0);
  Assert.IsTrue(Pos('Delphi Runtime Units', LContent) > 0);
  Assert.IsTrue(Pos('Debug DCUs', LContent) > 0);
  Assert.IsTrue(Pos('Unit Evidence', LContent) > 0);
  Assert.IsTrue(Pos('Demo.Html', LContent) > 0);
  Assert.IsTrue(Pos('37.0.57242.3601', LContent) > 0);
  Assert.IsTrue(Pos('Build Trace Records', LContent) > 0);
  Assert.IsTrue(Pos('Build Traceability', LContent) > 0);
  Assert.IsTrue(Pos('One third-party unit was resolved heuristically.', LContent) > 0);
end;

initialization
  TDUnitX.RegisterTestFixture(THtmlReportWriterTests);

end.