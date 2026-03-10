/// <summary>
/// DX.Comply.Tests.Report.MarkdownWriter
/// DUnitX tests for the Markdown compliance report writer.
/// </summary>
///
/// <remarks>
/// These tests verify the human-readable Markdown companion report independently from
/// the SBOM writers so layout regressions remain easy to diagnose.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Comply.Tests.Report.MarkdownWriter;

interface

uses
  System.Generics.Collections,
  DUnitX.TestFramework,
  DX.Comply.BuildEvidence.Intf,
  DX.Comply.Engine.Intf,
  DX.Comply.Report.Intf;

type
  /// <summary>
  /// DUnitX fixture for Markdown report rendering.
  /// </summary>
  [TestFixture]
  TMarkdownReportWriterTests = class
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
    procedure GetFormat_ReturnsMarkdown;

    [Test]
    procedure Write_CreatesReadableMarkdownReport;
  end;

implementation

uses
  System.IOUtils,
  System.SysUtils,
  DX.Comply.Report.MarkdownWriter,
  DX.Comply.Schema.Validator;

function CreateArtefact: TArtefactInfo;
begin
  Result.FilePath := 'Y:\Build\Demo.exe';
  Result.RelativePath := 'build\Win64\Release\Demo.exe';
  Result.FileSize := 1024;
  Result.Hash := 'ABCDEF0123456789';
  Result.ArtefactType := 'exe';
end;

function CreateEvidenceItem: TBuildEvidenceItem;
begin
  Result.SourceKind := besMapFile;
  Result.DisplayName := 'Unit from map file';
  Result.FilePath := 'Y:\Build\Demo.map';
  Result.UnitName := 'Demo.Main';
  Result.Detail := 'LineNumbersSection';
end;

function CreateResolvedUnit: TResolvedUnitInfo;
begin
  Result.UnitName := 'Demo.Main';
  Result.EvidenceKind := uekPas;
  Result.OriginKind := uokLocalProject;
  Result.Confidence := rcAuthoritative;
  Result.ResolvedPath := 'Y:\Source\Demo.Main.pas';
end;

procedure TMarkdownReportWriterTests.GetFormat_ReturnsMarkdown;
var
  LWriter: IHumanReadableReportWriter;
begin
  LWriter := TMarkdownReportWriter.Create;
  Assert.AreEqual(NativeInt(Ord(hrfMarkdown)), NativeInt(Ord(LWriter.GetFormat)));
end;

procedure TMarkdownReportWriterTests.InitializeReportData;
var
  LBuildSourceItem: TBuildEvidenceItem;
begin
  FProjectInfo := TProjectInfo.Create;
  FProjectInfo.ProjectName := 'Demo';
  FProjectInfo.ProjectPath := TPath.Combine(FTempDir, 'src', 'Demo.dproj');
  FProjectInfo.ProjectDir := TPath.GetDirectoryName(FProjectInfo.ProjectPath);
  FProjectInfo.Platform := 'Win64';
  FProjectInfo.Configuration := 'Release';
  FProjectInfo.UsesDebugDCUs := False;
  FProjectInfo.Version := '1.2.3';
  FProjectInfo.Toolchain.ProductName := 'Embarcadero Delphi';
  FProjectInfo.Toolchain.Version := '37.0';
  FProjectInfo.Toolchain.BuildVersion := '37.0.57242.3601';
  FProjectInfo.Toolchain.RootDir := 'C:\Program Files (x86)\Embarcadero\Studio\37.0';

  FBuildEvidence := TBuildEvidence.Create;
  FBuildEvidence.EvidenceItems.Add(CreateEvidenceItem);
  LBuildSourceItem := Default(TBuildEvidenceItem);
  LBuildSourceItem.SourceKind := besCompilerResponseFile;
  LBuildSourceItem.DisplayName := 'dcc64.rsp';
  LBuildSourceItem.FilePath := 'Y:\Build\dcc64.rsp';
  LBuildSourceItem.Detail := '-U src;lib';
  FBuildEvidence.EvidenceItems.Add(LBuildSourceItem);

  FCompositionEvidence := TCompositionEvidence.Create;
  FCompositionEvidence.GeneratedAt := '2026-03-07T12:00:00Z';
  FCompositionEvidence.Units.Add(CreateResolvedUnit);

  FArtefacts := TArtefactList.Create;
  FArtefacts.Add(CreateArtefact);

  FWarnings := TList<string>.Create;
  FWarnings.Add('The MAP file was reused from a previous build.');

  FData := Default(TComplianceReportData);
  FData.SbomOutputPath := TPath.Combine(FTempDir, 'bom.json');
  FData.SbomFormat := sfCycloneDxJson;
  FData.Metadata.ProductName := 'Demo';
  FData.Metadata.ProductVersion := '1.2.3';
  FData.Metadata.Timestamp := '2026-03-07T12:00:00Z';
  FData.ProjectInfo := FProjectInfo;
  FData.BuildEvidence := FBuildEvidence;
  FData.CompositionEvidence := FCompositionEvidence;
  FData.Artefacts := FArtefacts;
  FData.Warnings := FWarnings;
  FData.DeepEvidenceRequested := True;
  FData.DeepEvidenceResult.Success := True;
  FData.DeepEvidenceResult.Executed := True;
  FData.ValidationResult := TValidationResult.CreateValid;
end;

procedure TMarkdownReportWriterTests.Setup;
var
  LGuid: TGUID;
begin
  CreateGUID(LGuid);
  FTempDir := TPath.Combine(TPath.GetTempPath, GUIDToString(LGuid).Trim(['{', '}']));
  TDirectory.CreateDirectory(FTempDir);
  FOutputPath := TPath.Combine(FTempDir, 'report.md');
  InitializeReportData;
end;

procedure TMarkdownReportWriterTests.TearDown;
begin
  FWarnings.Free;
  FArtefacts.Free;
  FCompositionEvidence.Free;
  FBuildEvidence.Free;
  FProjectInfo.Free;
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

procedure TMarkdownReportWriterTests.Write_CreatesReadableMarkdownReport;
var
  LConfig: THumanReadableReportConfig;
  LContent: string;
  LWriter: IHumanReadableReportWriter;
begin
  LConfig := THumanReadableReportConfig.Default;
  LWriter := TMarkdownReportWriter.Create;

  Assert.IsTrue(LWriter.Write(FOutputPath, FData, LConfig));
  Assert.IsTrue(TFile.Exists(FOutputPath));

  LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('# DX.Comply Software Release Assessment (SRA) and SBOM Compliance Report', LContent) > 0);
  Assert.IsTrue(Pos('This DX.Comply Software Release Assessment summarizes the generated Software Bill of Materials (SBOM)', LContent) > 0);
  Assert.IsTrue(Pos('## Report Context', LContent) > 0);
  Assert.IsTrue(Pos('Generated By', LContent) > 0);
  Assert.IsTrue(Pos('[bom.json](bom.json)', LContent) > 0);
  Assert.IsTrue(Pos('Repository / Project Root', LContent) > 0);
  Assert.IsTrue(Pos('Delphi Runtime Units', LContent) > 0);
  Assert.IsTrue(Pos('Release DCUs', LContent) > 0);
  Assert.IsTrue(Pos('## Artefacts', LContent) > 0);
  Assert.IsTrue(Pos('## Unit Evidence', LContent) > 0);
  Assert.IsTrue(Pos('Demo.Main', LContent) > 0);
  Assert.IsTrue(Pos('37.0.57242.3601', LContent) > 0);
  Assert.AreEqual(0, Pos('Build Traceability', LContent));
  Assert.AreEqual(0, Pos('Build Trace Records', LContent));
  Assert.IsTrue(Pos('The MAP file was reused from a previous build.', LContent) > 0);
end;

initialization
  TDUnitX.RegisterTestFixture(TMarkdownReportWriterTests);

end.