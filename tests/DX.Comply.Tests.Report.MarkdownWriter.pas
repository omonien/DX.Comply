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

    /// <summary>
    /// EXE/DLL artefact versions (numeric file version or product version
    /// stored on the artefact) appear in the Artefacts table. Issue #90.
    /// </summary>
    [Test]
    procedure Write_ArtefactVersion_AppearsInArtefactsTable;

    /// <summary>
    /// SBOM header data (creator, supplier, supplier URL, licence, product)
    /// appears in Project Overview when set, and is omitted when empty.
    /// </summary>
    [Test]
    procedure Write_SbomHeaderData_AppearsInProjectOverview;
    /// <summary>A supplier URL that is not http(s) is shown as text, not as a link.</summary>
    [Test]
    procedure Write_SupplierUrlWithOtherScheme_IsNotALink;
    [Test]
    procedure Write_EmptySbomHeaderData_IsOmitted;
    [Test]
    procedure Write_Overview_ShowsOriginsLicencesAndUnitsWithoutManifest;
    /// <summary>
    /// The Unknown supplier row lists its units by prefix. A known supplier
    /// stays a count. Issue #176.
    /// </summary>
    [Test]
    procedure Write_UnknownSupplier_ListsUnitsByPrefix;
    /// <summary>
    /// An Android shared library with no version resource shows the product
    /// version in the licence table and in the artefacts table. A third-party
    /// DLL shows its own version in both tables and does not inherit the
    /// product version.
    /// </summary>
    [Test]
    procedure Write_DeliverableWithoutVersion_UsesProductVersion;
    /// <summary>Content overview writes the overview sections without the unit list. Issue #126.</summary>
    [Test]
    procedure Write_ContentOverview_OmitsUnitList;
    /// <summary>Content units writes the unit list without the overview sections. Issue #126.</summary>
    [Test]
    procedure Write_ContentUnits_OmitsOverview;
    /// <summary>
    /// The licence table has one row per component, sorted by name, with
    /// version and copyright columns. Issue #156.
    /// </summary>
    [Test]
    procedure Write_LicenceTable_OneRowPerComponent;
    /// <summary>
    /// The Markdown heading starts with the project name, matching the HTML
    /// title. The product name is used when the project name is empty.
    /// Issue #167.
    /// </summary>
    [Test]
    procedure Write_Heading_PrefixesProjectName;
    /// <summary>
    /// Prefix matches not applied is written when a prefix was refused,
    /// and left out when none was.
    /// </summary>
    [Test]
    procedure Write_PrefixMatchesNotApplied_Section;
    /// <summary>
    /// EXE and DLL files in the no-licence list show the version already
    /// stored for the artefacts table. The product stays the first row of
    /// its group. Issue #203.
    /// </summary>
    [Test]
    procedure Write_NoLicenceList_ShowsExeAndDllVersion;
    /// <summary>
    /// Generated At names UTC. An empty header time uses the composition
    /// time. A value that is not a timestamp is printed unchanged. Issue #208.
    /// </summary>
    [Test]
    procedure Write_GeneratedAt_ShowsUtcLabel;
  end;

implementation

uses
  System.IOUtils,
  System.SysUtils,
  DX.Comply.Report.MarkdownWriter,
  DX.Comply.Schema.Validator;

function CreateArtefact: TArtefactInfo;
begin
  Result := Default(TArtefactInfo);
  Result.FilePath := 'Y:\Build\Demo.exe';
  Result.RelativePath := 'build\Win64\Release\Demo.exe';
  Result.FileSize := 1024;
  Result.Hash := 'ABCDEF0123456789';
  Result.ArtefactType := 'application';
  Result.Version := '1.2.3.4';
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
  Assert.IsTrue(Pos('# Demo - DX.Comply SBOM Report', LContent) > 0);
  Assert.IsTrue(Pos('This report lists the units, packages and DLL names DX.Comply could see in the build', LContent) > 0);
  Assert.IsTrue(Pos('Internal structural check passed', LContent) > 0);
  Assert.IsTrue(Pos('## Report Context', LContent) > 0);
  Assert.IsTrue(Pos('Generated By', LContent) > 0);
  Assert.IsTrue(Pos('[bom.json](bom.json)', LContent) > 0);
  Assert.IsTrue(Pos('Repository / Project Root', LContent) > 0);
  Assert.IsTrue(Pos('Delphi Runtime Units', LContent) > 0);
  Assert.IsTrue(Pos('Release DCUs', LContent) > 0);
  Assert.IsTrue(Pos('## Artefacts', LContent) > 0);
  Assert.IsTrue(Pos('| Relative Path | Type | Version | Size | SHA-256 |', LContent) > 0);
  Assert.IsTrue(Pos('1.2.3.4', LContent) > 0, 'artefact PE/product version must appear');
  Assert.IsTrue(Pos('## Unit Evidence', LContent) > 0);
  Assert.IsTrue(Pos('Demo.Main', LContent) > 0);
  Assert.IsTrue(Pos('37.0.57242.3601', LContent) > 0);
  Assert.AreEqual(0, Pos('Build Traceability', LContent));
  Assert.AreEqual(0, Pos('Build Trace Records', LContent));
  Assert.IsTrue(Pos('The MAP file was reused from a previous build.', LContent) > 0);
end;

procedure TMarkdownReportWriterTests.Write_ArtefactVersion_AppearsInArtefactsTable;
var
  LArtefact: TArtefactInfo;
  LConfig: THumanReadableReportConfig;
  LContent: string;
  LWriter: IHumanReadableReportWriter;
begin
  LArtefact := Default(TArtefactInfo);
  LArtefact.RelativePath := 'vendor.dll';
  LArtefact.ArtefactType := 'library';
  LArtefact.FileSize := 4096;
  LArtefact.Hash := StringOfChar('b', 64);
  LArtefact.Version := '10.0.19041.1';
  FArtefacts.Add(LArtefact);

  LConfig := THumanReadableReportConfig.Default;
  LWriter := TMarkdownReportWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, LConfig));
  LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('| vendor.dll | library | 10.0.19041.1 | 4096 |', LContent) > 0,
    'DLL version from the PE/version resource must appear on the report line');
  Assert.IsTrue(Pos('| build\Win64\Release\Demo.exe | application | 1.2.3.4 | 1024 |', LContent) > 0,
    'application version already stored on the artefact must appear unchanged');
end;

procedure TMarkdownReportWriterTests.Write_SbomHeaderData_AppearsInProjectOverview;
begin
  FData.Metadata.SbomCreator := 'sbom@example.com';
  FData.Metadata.Supplier := 'Example & Co GmbH';
  FData.Metadata.SupplierUrl := 'https://example.com';
  FData.Metadata.Licence := 'Proprietary';
  var LWriter: IHumanReadableReportWriter := TMarkdownReportWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, THumanReadableReportConfig.Default));
  var LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('| SBOM Creator | sbom@example.com |', LContent) > 0);
  Assert.IsTrue(Pos('| Supplier | Example & Co GmbH |', LContent) > 0);
  Assert.IsTrue(Pos('| Supplier URL | [https://example.com](https://example.com) |', LContent) > 0);
  Assert.IsTrue(Pos('| Licence | Proprietary |', LContent) > 0);
  Assert.IsTrue(Pos('| Product |', LContent) > 0);
end;

procedure TMarkdownReportWriterTests.Write_SupplierUrlWithOtherScheme_IsNotALink;
begin
  FData.Metadata.SupplierUrl := 'javascript:alert(1)';
  var LWriter: IHumanReadableReportWriter := TMarkdownReportWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, THumanReadableReportConfig.Default));
  var LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('| Supplier URL | javascript:alert(1) |', LContent) > 0,
    'The value is still shown');
  Assert.AreEqual(0, Pos('](javascript:', LContent), 'It must not become a link');
end;

procedure TMarkdownReportWriterTests.Write_EmptySbomHeaderData_IsOmitted;
begin
  var LWriter: IHumanReadableReportWriter := TMarkdownReportWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, THumanReadableReportConfig.Default));
  var LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.AreEqual(0, Pos('SBOM Creator', LContent));
  Assert.AreEqual(0, Pos('| Supplier |', LContent));
  Assert.AreEqual(0, Pos('| Licence |', LContent));
end;

procedure TMarkdownReportWriterTests.Write_Overview_ShowsOriginsLicencesAndUnitsWithoutManifest;
begin
  var LUnit := Default(TArtefactInfo);
  LUnit.RelativePath := 'JvComponent.pas';
  LUnit.ArtefactType := 'unit-evidence';
  LUnit.Origin := 'Third party';
  FArtefacts.Add(LUnit);
  FData.Metadata.Licence := 'Proprietary';
  var LWriter: IHumanReadableReportWriter := TMarkdownReportWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, THumanReadableReportConfig.Default));
  var LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('## Origin summary', LContent) > 0);
  Assert.IsTrue(Pos('| [Third party](#third-party-units-without-manifest) | 1 |', LContent) > 0);
  Assert.IsTrue(Pos('| **Total SBOM components** | **2** |', LContent) > 0);
  Assert.IsTrue(Pos('## Licences', LContent) > 0);
  Assert.IsTrue(Pos('| Declared licence | Components | Name | Version | Copyright | Note |', LContent) > 0);
  Assert.AreEqual(0, Pos('| Declared licence | Components | Names | Note |', LContent));
  Assert.IsTrue(Pos('| Proprietary | 1 | Demo (product) | 1.2.3.4 |  |  |', LContent) > 0,
    'the product and Demo.exe are one row, with the binary version');
  Assert.AreEqual<Integer>(0, Pos('| | | Demo.exe |', LContent),
    'Demo.exe is not a second licence row');
  Assert.IsTrue(Pos('| No licence information | 1 | JvComponent |  |  |  |', LContent) > 0);
  Assert.IsTrue(Pos('## Third-party units without manifest', LContent) > 0);
  Assert.IsTrue(Pos('| Jv | 1 | supplier, version, licence | JvComponent |', LContent) > 0);
  Assert.IsTrue(Pos('## Origin summary', LContent) < Pos('## Artefacts', LContent),
    'the origin summary is near the top');
end;

procedure TMarkdownReportWriterTests.Write_UnknownSupplier_ListsUnitsByPrefix;
begin
  FData.Metadata.ComponentManifestJson :=
    '{"match":{"prefixes":"legacy"},"components":[{"name":"JVCL","version":"3.5","vendor":"Project JEDI",' +
    '"licence":"MPL-1.1","units_prefix":["Jv"]}]}';
  var LJv := Default(TArtefactInfo);
  LJv.RelativePath := 'JvComponent.pas';
  LJv.ArtefactType := 'unit-evidence';
  LJv.Origin := 'Third party';
  FArtefacts.Add(LJv);
  var LXyz := Default(TArtefactInfo);
  LXyz.RelativePath := 'XyzGrid.pas';
  LXyz.ArtefactType := 'unit-evidence';
  LXyz.Origin := 'Third party';
  FArtefacts.Add(LXyz);
  var LWriter: IHumanReadableReportWriter := TMarkdownReportWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, THumanReadableReportConfig.Default));
  var LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('| Unknown supplier<br>Xyz: 1 unit (XyzGrid) | 1 |', LContent) > 0, LContent);
  Assert.IsTrue(Pos('| Project JEDI | 1 |', LContent) > 0, LContent);
  Assert.AreEqual(0, Pos('Project JEDI<br>', LContent));
end;

procedure TMarkdownReportWriterTests.Write_DeliverableWithoutVersion_UsesProductVersion;
var
  LWriter: IHumanReadableReportWriter;
  LContent: string;
  LDll: TArtefactInfo;
begin
  FArtefacts.Clear;
  FData.ProjectInfo.ProjectName := 'WernigApp';
  FData.Metadata.ProductName := 'WernigApp';
  FData.Metadata.ProductVersion := '16.0.0.7';
  FData.Metadata.Licence := 'MIT';
  var LSo := Default(TArtefactInfo);
  LSo.RelativePath := 'Android\Release\libWernigApp.so';
  LSo.ArtefactType := 'file';
  LSo.FileSize := 4096;
  LSo.Hash := 'ABCDEF';
  FArtefacts.Add(LSo);
  LDll := Default(TArtefactInfo);
  LDll.RelativePath := 'vendor.dll';
  LDll.ArtefactType := 'library';
  LDll.Version := '9.9.9';
  LDll.FileSize := 2048;
  LDll.Hash := '123456';
  FArtefacts.Add(LDll);
  LWriter := TMarkdownReportWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, THumanReadableReportConfig.Default));
  LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('| libWernigApp.so | 16.0.0.7 |', LContent) > 0,
    'The licence table uses the product version for the deliverable');
  Assert.IsTrue(Pos('| vendor.dll | 9.9.9 |', LContent) > 0,
    'A third-party DLL shows its stored version in the licence table');
  Assert.AreEqual<Integer>(0, Pos('| vendor.dll | 16.0.0.7 |', LContent),
    'A third-party DLL does not inherit the product version in the licence table');
  Assert.IsTrue(Pos('| Android\Release\libWernigApp.so | file | 16.0.0.7 |', LContent) > 0,
    'The artefacts table uses the product version');
  Assert.IsTrue(Pos('| vendor.dll | library | 9.9.9 |', LContent) > 0,
    'The artefacts table keeps the third-party version');
end;

procedure TMarkdownReportWriterTests.Write_ContentOverview_OmitsUnitList;
begin
  var LConfig := THumanReadableReportConfig.Default;
  LConfig.Content := hrcOverview;
  var LWriter: IHumanReadableReportWriter := TMarkdownReportWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, LConfig));
  var LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('## Origin summary', LContent) > 0);
  Assert.IsTrue(Pos('## Licences', LContent) > 0);
  Assert.IsTrue(Pos('| Declared licence | Components | Name | Version | Copyright | Note |', LContent) > 0,
    'overview content still includes the licence table');
  Assert.AreEqual(0, Pos('## Unit Evidence', LContent));
  Assert.AreEqual(0, Pos('#unit-evidence', LContent), 'no link to a missing section');
  Assert.IsTrue(Pos('ABCDEF0123456789', LContent) > 0, 'the artefact hashes stay');
end;

procedure TMarkdownReportWriterTests.Write_ContentUnits_OmitsOverview;
begin
  var LConfig := THumanReadableReportConfig.Default;
  LConfig.Content := hrcUnits;
  var LWriter: IHumanReadableReportWriter := TMarkdownReportWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, LConfig));
  var LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('## Unit Evidence', LContent) > 0);
  Assert.IsTrue(Pos('Demo.Main', LContent) > 0);
  Assert.AreEqual(0, Pos('## Origin summary', LContent));
  Assert.AreEqual(0, Pos('## Licences', LContent));
  Assert.AreEqual(0, Pos('| Copyright |', LContent), 'units content has no licence table');
end;

procedure TMarkdownReportWriterTests.Write_LicenceTable_OneRowPerComponent;
const
  cRows = '{"match":{"prefixes":"legacy"},"components":[' +
    '{"name":"SVG Icon Image List","version":"4.8.1","licence":"Apache-2.0","units_prefix":["Svg"]},' +
    '{"name":"Logger Pro","version":"2.1.2","licence":"Apache-2.0","copyright":"2020 | 2021","units_prefix":["Logger"]},' +
    '{"name":"delphi Event Bus","version":"2.1","licence":"apache-2.0","copyright":"A & B","units_prefix":["Event"]},' +
    '{"name":"VSoft Command Line Parser","version":"0.1.9","licence":"Apache-2.0","copyright":"   ","units_prefix":["VSoft"]},' +
    '{"name":"NoVersion Lib","licence":"Apache-2.0","copyright":"1999","units_prefix":["NvLib"]},' +
    '{"name":"JVCL","version":"3.5","licence":"MPL-1.1","units_prefix":["Jv"]}]}';
  procedure AddUnit(const AName: string);
  var
    LUnit: TArtefactInfo;
  begin
    LUnit := Default(TArtefactInfo);
    LUnit.RelativePath := AName + '.pas';
    LUnit.ArtefactType := 'unit-evidence';
    LUnit.Origin := 'Third party';
    FArtefacts.Add(LUnit);
  end;
begin
  FData.Metadata.ComponentManifestJson := cRows;
  FData.Metadata.Licence := 'Proprietary';
  AddUnit('SvgIcons');
  AddUnit('LoggerMain');
  AddUnit('EventBus');
  AddUnit('VSoftParser');
  AddUnit('NvLibCore');
  AddUnit('JvComponent');
  var LWriter: IHumanReadableReportWriter := TMarkdownReportWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, THumanReadableReportConfig.Default));
  var LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('| Declared licence | Components | Name | Version | Copyright | Note |', LContent) > 0);
  Assert.AreEqual(0, Pos('Logger Pro 2.1.2', LContent), 'the version is not glued to the name');
  var LEvent := Pos('| Apache-2.0 | 5 | delphi Event Bus | 2.1 | A & B |  |', LContent);
  var LLogger := Pos('| | | Logger Pro | 2.1.2 | 2020 \| 2021 | |', LContent);
  var LNoVersion := Pos('| | | NoVersion Lib |  | 1999 | |', LContent);
  var LSvg := Pos('| | | SVG Icon Image List | 4.8.1 |  | |', LContent);
  var LVsoft := Pos('| | | VSoft Command Line Parser | 0.1.9 |  | |', LContent);
  Assert.IsTrue(LEvent > 0, 'first row of the group carries the licence and the count');
  Assert.IsTrue((LEvent < LLogger) and (LLogger < LNoVersion) and (LNoVersion < LSvg) and (LSvg < LVsoft),
    'components are sorted by name without regard to case');
  Assert.IsTrue(Pos('| MPL-1.1 | 1 | JVCL | 3.5 |  | Copyleft licence. Check its terms for distribution with this product. |',
    LContent) > 0, 'a one-component group keeps the review note on its row');
  Assert.IsTrue(Pos('| Proprietary | 1 | Demo (product) | 1.2.3.4 |  |  |', LContent) > 0,
    'the product and Demo.exe are one licence row');
  Assert.IsTrue(LVsoft < Pos('| MPL-1.1 | 1 | JVCL |', LContent), 'licence groups stay in title order');
end;

procedure TMarkdownReportWriterTests.Write_Heading_PrefixesProjectName;
var
  LWriter: IHumanReadableReportWriter;
  LContent: string;
begin
  FData.ProjectInfo.ProjectName := 'XmlConvert';
  FData.Metadata.ProductName := 'Ignored';
  LWriter := TMarkdownReportWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, THumanReadableReportConfig.Default));
  LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('# XmlConvert - DX.Comply SBOM Report', LContent) > 0);

  FData.ProjectInfo.ProjectName := '';
  FData.Metadata.ProductName := 'Catalog';
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, THumanReadableReportConfig.Default));
  LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('# Catalog - DX.Comply SBOM Report', LContent) > 0);

  FData.Metadata.ProductName := '';
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, THumanReadableReportConfig.Default));
  LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('# DX.Comply SBOM Report', LContent) > 0);
  Assert.AreEqual(0, Pos('#  - DX.Comply', LContent));
end;

procedure TMarkdownReportWriterTests.Write_PrefixMatchesNotApplied_Section;
var
  LArtefact: TArtefactInfo;
  LContent: string;
  LWriter: IHumanReadableReportWriter;
begin
  LWriter := TMarkdownReportWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, THumanReadableReportConfig.Default));
  LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.AreEqual(0, Pos('Prefix matches not applied', LContent));

  FData.Metadata.ComponentManifestJson :=
    '{"components":[{"name":"TMS VCL UI Pack","version":"1","vendor":"tmssoftware.com",' +
    '"licence":"Commercial","type":"library","units_prefix":["GDIP"]}]}';
  FData.ProjectInfo.Toolchain.RootDir := 'C:\DXProduct';
  LArtefact := Default(TArtefactInfo);
  LArtefact.UnitName := 'Winapi.GDIPAPI';
  LArtefact.RelativePath := 'Winapi.GDIPAPI.pas';
  LArtefact.SourcePath := 'C:\DXProduct\source\rtl\win\Winapi.GDIPAPI.pas';
  LArtefact.ArtefactType := 'unit-evidence';
  LArtefact.Origin := 'Embarcadero RTL';
  FArtefacts.Add(LArtefact);

  Assert.IsTrue(LWriter.Write(FOutputPath, FData, THumanReadableReportConfig.Default));
  LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('## Prefix matches not applied', LContent) > 0);
  Assert.IsTrue(Pos('| Unit | Prefix | Row | Kept origin |', LContent) > 0);
  Assert.IsTrue(Pos('| Winapi.GDIPAPI | GDIP | TMS VCL UI Pack | Embarcadero RTL |', LContent) > 0);
end;

procedure TMarkdownReportWriterTests.Write_NoLicenceList_ShowsExeAndDllVersion;

  procedure AddBinary(const APath, AType, AVersion: string; AFromFileDate: Boolean);
  var
    LArtefact: TArtefactInfo;
  begin
    LArtefact := Default(TArtefactInfo);
    LArtefact.RelativePath := APath;
    LArtefact.ArtefactType := AType;
    LArtefact.Version := AVersion;
    LArtefact.VersionFromFileDate := AFromFileDate;
    LArtefact.FileSize := 100;
    LArtefact.Hash := 'abc';
    FArtefacts.Add(LArtefact);
  end;

var
  LContent: string;
  LNone: Integer;
  LProduct: Integer;
  LWriter: IHumanReadableReportWriter;
begin
  FArtefacts.Clear;
  FData.ProjectInfo.ProjectName := 'Demo';
  FData.ProjectInfo.OutputFilePath := 'C:\Build\Demo.exe';
  FData.Metadata.ProductName := 'Demo';
  FData.Metadata.ProductVersion := '2.0.0';
  FData.Metadata.Licence := 'MIT';
  FData.Metadata.ComponentManifestJson :=
    '{"components":[],"own_code_units":["MainForm"]}';
  AddBinary('build\Demo.exe', 'application', '2.0.0.1', False);
  AddBinary('tools\Helper.EXE', 'file', '1.4.2', False);
  AddBinary('bin\Vendor.DLL', 'library', '10.0.19041.1', False);
  AddBinary('plugin.dll', 'library', '', False);
  AddBinary('old.dll', 'library', '2020-01-02T03:04:05Z', True);
  AddBinary('rtl290.bpl', 'runtime-package', '29.0.0', False);
  AddBinary('uastack.dll', 'external-reference', '1.2.3', False);
  AddBinary('src\notes.pas', 'file', '2.0.0', False);
  var LUnit := Default(TArtefactInfo);
  LUnit.RelativePath := 'MainForm.pas';
  LUnit.ArtefactType := 'unit-evidence';
  LUnit.Origin := 'Local project';
  LUnit.UnitName := 'MainForm';
  FArtefacts.Add(LUnit);

  LWriter := TMarkdownReportWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, THumanReadableReportConfig.Default));
  LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);

  Assert.IsTrue(Pos('| No licence information | 7 | Helper.EXE | 1.4.2 |  |  |', LContent) > 0,
    'the no-licence list starts with the EXE and its stored version');
  Assert.IsTrue(Pos('| | | Vendor.DLL | 10.0.19041.1 |  | |', LContent) > 0,
    'a DLL shows the version stored on the file');
  Assert.IsTrue(Pos('| | | plugin.dll |  |  | |', LContent) > 0,
    'a DLL with no stored version stays empty');
  Assert.IsTrue(Pos('| | | old.dll | 2020-01-02 03:04:05 UTC |  | |', LContent) > 0,
    'a file-date stand-in is shown with a UTC label');
  Assert.AreEqual<Integer>(0, Pos('2020-01-02T03:04:05Z', LContent),
    'the file-date stand-in is not left with a trailing Z');
  Assert.IsTrue(Pos('| old.dll | library | 2020-01-02 03:04:05 UTC |', LContent) > 0,
    'the artefacts table shows the same UTC label');
  Assert.IsTrue(Pos('| | | rtl290.bpl | 29.0.0 |  | |', LContent) > 0,
    'a BPL shows the version stored on the file');
  Assert.IsTrue(Pos('| | | uastack.dll | 1.2.3 |  | |', LContent) > 0,
    'an external DLL reference shows its stored version');
  Assert.IsTrue(Pos('| | | notes.pas |  |  | |', LContent) > 0,
    'a source file does not show a stored version');
  Assert.AreEqual<Integer>(0, Pos('| Vendor.DLL | 2.0.0 |', LContent),
    'a third-party DLL does not inherit the product version');
  Assert.IsTrue(Pos('| bin\Vendor.DLL | library | 10.0.19041.1 |', LContent) > 0,
    'the artefacts table still shows the same stored version');

  LProduct := Pos('| MIT | 2 | Demo (product) | 2.0.0.1 |  |  |', LContent);
  LNone := Pos('| No licence information | 7 | Helper.EXE | 1.4.2 |  |  |', LContent);
  Assert.IsTrue((LProduct > 0) and (LProduct < LNone),
    'the product licence stays ahead of the no-licence list');
  Assert.IsTrue(LProduct < Pos('| | | MainForm |  |  | |', LContent),
    'the product is the first row of its licence list');
  Assert.AreEqual<Integer>(0, Pos('| | | Demo.exe |', LContent),
    'Demo.exe is not a second licence row');
end;

procedure TMarkdownReportWriterTests.Write_GeneratedAt_ShowsUtcLabel;
var
  LContent: string;
  LWriter: IHumanReadableReportWriter;
begin
  LWriter := TMarkdownReportWriter.Create;
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, THumanReadableReportConfig.Default));
  LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('| Generated At | 2026-03-07 12:00:00 UTC |', LContent) > 0,
    'Generated At shows the UTC label');
  Assert.AreEqual<Integer>(0, Pos('2026-03-07T12:00:00Z', LContent),
    'the report does not leave the trailing Z');

  // Composition evidence is a record copied onto FData. The writer reads
  // that copy, so the fallback time has to be set there.
  FData.Metadata.Timestamp := '';
  FData.CompositionEvidence.GeneratedAt := '2026-11-20T21:11:57Z';
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, THumanReadableReportConfig.Default));
  LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('| Generated At | 2026-11-20 21:11:57 UTC |', LContent) > 0,
    'an empty header time uses the composition time, still labelled UTC');

  FData.Metadata.Timestamp := 'not a timestamp';
  Assert.IsTrue(LWriter.Write(FOutputPath, FData, THumanReadableReportConfig.Default));
  LContent := TFile.ReadAllText(FOutputPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('| Generated At | not a timestamp |', LContent) > 0,
    'a value that is not a UTC timestamp is printed unchanged');
  Assert.AreEqual<Integer>(0, Pos('| Generated At | not a timestamp UTC |', LContent),
    'an unparsed generation time is not labelled UTC');
end;

initialization
  TDUnitX.RegisterTestFixture(TMarkdownReportWriterTests);

end.